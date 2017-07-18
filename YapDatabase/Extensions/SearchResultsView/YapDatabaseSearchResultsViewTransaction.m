#import "YapDatabaseSearchResultsViewTransaction.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabaseFullTextSearchPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseSearchQueuePrivate.h"
#import "YapRowidSet.h"
#import "YapCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

static NSString *const ext_key_subclassVersion = @"searchResultViewClassVersion";
static NSString *const ext_key_query           = @"query";


@implementation YapDatabaseSearchResultsViewTransaction
{
	YapRowidSet *ftsRowids;
	
	YapDatabaseSearchQueue *searchQueue;
}

- (void)dealloc
{
	if (ftsRowids) {
		YapRowidSetRelease(ftsRowids);
		ftsRowids = NULL;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to create any necessary tables (if needed),
 * as well as populate the view (if needed) by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{
	YDBLogAutoTrace();
	
	if (![super createIfNeeded]) return NO;
	
	if ([self isPersistentView])
	{
		int oldSubclassVersion = 0;
		BOOL hasOldSubclassVersion = [self getIntValue:&oldSubclassVersion
		                               forExtensionKey:ext_key_subclassVersion
		                                    persistent:YES];
		
		if (hasOldSubclassVersion)
		{
			[self dropTablesForOldSubclassVersion:oldSubclassVersion];
			[self removeValueForExtensionKey:ext_key_subclassVersion persistent:YES];
		}
	}
	
	return YES;
}

/**
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	YDBLogAutoTrace();
	
	if (![super prepareIfNeeded]) return NO;
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
	  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
	if ([searchResultsConnection query] == nil)
	{
		NSString *query = [self stringValueForExtensionKey:ext_key_query persistent:[self isPersistentView]];
		[searchResultsConnection setQuery:query isChange:NO];
	}
	
	return YES;
}

/**
 * Codebase upgrade helper.
**/
- (void)dropTablesForOldSubclassVersion:(int __unused)oldSubclassVersion
{
	// In YapDatabase v3.0 we dropped the snippets table.
	//
	// It's faster to generate the snippets on the fly,
	// rather than trying to store them in the database.
	
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *snippetTableName = [NSString stringWithFormat:@"view_%@_snippet", self.registeredName];
	
	NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", snippetTableName];
	
	int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping snippet table (%@): %d %s",
		            THIS_METHOD, snippetTableName, status, sqlite3_errmsg(db));
	}
}

/**
 * Overrides populateView method in superclass in order to provide its own independent implementation.
**/
- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Perform search
	
	[self repopulateFtsRowids];
	
	// Update the view using search results
	
	if (YapRowidSetCount(ftsRowids) > 0)
	{
		__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
		  (YapDatabaseSearchResultsView *)parentConnection->parent;
		
		if (searchResultsView->parentViewName)
			[self updateViewFromParent];
		else
			[self updateViewUsingBlocks];
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseFullTextSearchHandler *)searchHandler
{
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  [databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	__unsafe_unretained YapDatabaseFullTextSearch *fts =
	  (YapDatabaseFullTextSearch *)ftsTransaction.extensionConnection.extension;
	
	return fts.handler;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Repopulate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Executes the FTS query, and populates the ftsRowids & snippets ivars.
**/
- (void)repopulateFtsRowids
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  (YapDatabaseFullTextSearchTransaction *)[databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	// Prepare ftsRowids ivar
	
	if (ftsRowids)
		YapRowidSetRemoveAll(ftsRowids);
	else
		ftsRowids = YapRowidSetCreate(0);
	
	// Perform search
	
	__block int processed = 0;
	
	[ftsTransaction enumerateRowidsMatching:[self query] usingBlock:^(int64_t rowid, BOOL *stop) {
		
		YapRowidSetAdd(ftsRowids, rowid);
		
		if (++processed == 2500)
		{
			processed = 0;
			if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
				*stop = YES;
			}
		}
	}];
}

/**
 * This method is invoked if:
 *
 * - Our parentView had its groupingBlock and/or sortingBlock changed.
 * - A parentView of our parentView had its groupingBlock and/or sortingBlock changed.
**/
- (void)repopulateViewDueToParentGroupingSortingChange
{
	YDBLogAutoTrace();
	
	// Code overview:
	//
	// We could simply run the usual algorithm.
	// That is, enumerate over every item in the database, and run pretty much the same code as
	// in the didUpdateObject:forCollectionKey:withMetadata:rowid:.
	// However, this causes a potential issue where the sortingBlock will be invoked with items that
	// no longer exist in the given group.
	//
	// Instead we're going to find a way around this.
	// That way the sortingBlock works in a manner we're used to.
	//
	// Here's the algorithm overview:
	//
	// - Insert remove ops for every row & group
	// - Remove all items from the database tables
	// - Flush the group_pagesMetadata_dict (and related ivars)
	// - Set the reset flag (for internal notification creation)
	// - And then run the normal populate routine, with one exception handled by the isRepopulate flag.
	//
	// The changeset mechanism will automatically consolidate all changes to the minimum.
	
	[self enumerateGroupsUsingBlock:^(NSString *group, BOOL __unused *outerStop) {
		
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse // <- required
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL __unused *innerStop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			 
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[parentConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
	}];
	
	isRepopulate = YES;
	{
		[self populateView];
	}
	isRepopulate = NO;
}

/**
 * This method is invoked if:
 *
 * - Our parentView is a filteredView, and its filteringBlock was changed.
 * - A parentView of our parentView is a filteredView, and its filteringBlock was changed.
**/
- (void)repopulateViewDueToParentFilteringChange
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)parentConnection->parent)->parentViewName != nil,
	         @"Logic error: method requires parentView");
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:searchResultsView->parentViewName];
	
	// The parentView is a filteredView, and its filteringBlock changed
	//
	// - in the parentView, the groups may have changed
	// - in the parentView, the items within each group may have changed
	// - in the parentView, the order of items within each group is the same (important!)
	//
	// So we can run an algorithm like this:
	//
	//    Our View : A C D E G
	// Parent View : A B C E F
	//
	// We start by comparing 'A' and 'A'. They match, so our view remains the same.
	// Then we compare 'C' and 'B'. They don't match, so we want to determine if we should remove 'C'.
	// To find out we check to see if 'C' exists in the parentView.
	// We discover that it does, so we can keep the "cursor" on C, and then determine if we should insert 'B'.
	// Then we compare 'C' and 'C' and get a match.
	// Then we compare 'D' and 'E'. They don't match, so we want to determine if we should remove 'D'.
	// To find out we check to see if 'D' exists in the parentView.
	// We discover it does not, so we remove 'D'. And our "cursor" moves forward.
	// Then we compare 'E' and 'E' ...
	
	// Run the FTS search to get our list of valid rowids
	
	[self repopulateFtsRowids];
	
	// Get the list of allowed groups
	
	NSMutableArray *groupsInSelf = [[self allGroups] mutableCopy];
	id <NSFastEnumeration> groupsInParent;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
	if (allowedGroups)
	{
		NSArray *allGroups = [parentViewTransaction allGroups];
		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:[allGroups count]];
		
		for (NSString *group in allGroups)
		{
			if ([allowedGroups isAllowed:group]) {
				[groups addObject:group];
			}
		}
		
		groupsInParent = groups;
	}
	else
	{
		groupsInParent = [parentViewTransaction allGroups];
	}
	
	for (NSString *group in groupsInParent)
	{
		__block BOOL existing = NO;
		__block BOOL existingKnownValid = NO;
		__block int64_t existingRowid = 0;
		
		existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
		
		__block NSUInteger index = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group usingBlock:
			^(int64_t rowid, NSUInteger __unused parentIndex, BOOL __unused *stop)
		{
			if (existing && ((existingRowid == rowid)))
			{
				// Shortcut #1
				//
				// The row was previously in the view (allowed by previous parentFilter + our filter),
				// and is still in the view (allowed by new parentFilter + our filter).
				
				index++;
				existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				existingKnownValid = NO;
				
				return; // from block (continue)
			}
			
			if (existing && !existingKnownValid)
			{
				// Is the existingRowid still contained within the parentView?
				do
				{
					if ([parentViewTransaction containsRowid:existingRowid])
					{
						// Yes it is
						existingKnownValid = YES;
					}
					else
					{
						// No it's not.
						// Remove it, and check the next rowid in the list.
						
						YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:existingRowid];
						[self removeRowid:existingRowid collectionKey:ck atIndex:index inGroup:group];
						
						existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
					}
					
				} while (existing && !existingKnownValid);
					
				if (existing && (existingRowid == rowid))
				{
					// Shortcut #2
					//
					// The row was previously in the view (allowed by previous parentFilter + our filter),
					// and is still in the view (allowed by new parentFilter + our filter).
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
					existingKnownValid = NO;
					
					return; // from block (continue)
				}
			}
			
			{ // otherwise
				
				// The row was not previously in our view.
				// This could be because it was just inserted into the parentView,
				// or because it doesn't match our search.
				//
				// Either way we have to check.
				
				if (YapRowidSetContains(ftsRowids, rowid))
				{
					// The row was not previously in our view (not previously in parent view),
					// but is now in the view (added to parent view, and matches our search).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					[self insertRowid:rowid collectionKey:ck
					                              inGroup:group
							                      atIndex:index];
					
					index++;
				}
				else
				{
					// The row was not previously in our view (filtered, or not previously in parent view),
					// and is still not in our view (filtered).
				}
			}
		}];
		
		while (existing)
		{
			// Todo: This could be further optimized.
			
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:existingRowid];
			[self removeRowid:existingRowid collectionKey:ck atIndex:index inGroup:group];
			
			existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
		}
		
		NSUInteger groupIndex = [groupsInSelf indexOfObject:group];
		if (groupIndex != NSNotFound)
		{
			[groupsInSelf removeObjectAtIndex:groupIndex];
		}
	
	} // end for (NSString *group in groupsInParent)
	
	// Check to see if there are any groups that have been completely removed.
	
	for (NSString *group in groupsInSelf)
	{
		[self removeAllRowidsInGroup:group];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should write any last changes to their database table(s) if needed,
 * and should perform any needed cleanup before the changeset is requested.
 *
 * Remember, the changeset is requested immediately after this method is invoked.
**/
- (void)flushPendingChangesToExtensionTables
{
	YDBLogAutoTrace();
	
	// If the query was changed, then we need to write it to the yap table.
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
	NSString *query = nil;
	BOOL queryChanged = NO;
	[searchResultsViewConnection getQuery:&query wasChanged:&queryChanged];
	
	if (queryChanged)
	{
		[self setStringValue:query forExtensionKey:ext_key_query persistent:[self isPersistentView]];
	}
	
	// This must be done LAST.
	[super flushPendingChangesToExtensionTables];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Use this method after it has been determined that the key should be inserted into the given group.
 * 
 * This method will use parentView to calculate the proper index for the rowid.
 * It will attempt to optimize this operation as best as possible using a variety of techniques.
**/
- (void)insertRowid:(int64_t)rowid
      collectionKey:(YapCollectionKey *)collectionKey
            inGroup:(NSString *)group
        withChanges:(YapDatabaseViewChangesBitMask)flags
              isNew:(BOOL)isGuaranteedNew
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	(YapDatabaseSearchResultsView *)parentConnection->parent;
	
	NSAssert((searchResultsView->parentViewName != nil), @"Improper method invocation!");
	
	// Is the key already in the group?
	// If so:
	// - its index within the group may or may not have changed.
	// - we can use its existing position as an optimization.
	
	BOOL tryExistingIndexInGroup = NO;
	
	YapDatabaseViewLocator *existingLocator = isGuaranteedNew ? nil : [self locatorForRowid:rowid];
	if (existingLocator)
	{
		// The key is already in the view.
		// Has it changed groups?
		
		if ([group isEqualToString:existingLocator.group])
		{
			// The key is already in the group.
			//
			// Possible optimization:
			// Object or metadata was updated, but doesn't affect the position of the row within the view.
			
			tryExistingIndexInGroup = YES;
		}
		else
		{
			// The item has changed groups.
			// Remove it from previous group.
			
			[self removeRowid:rowid collectionKey:collectionKey withLocator:existingLocator];
		}
	}
	
	// Is this a new group ?
	// Or the first item in an empty group ?
	
	NSUInteger count = [self numberOfItemsInGroup:group];
	
	if (count == 0)
	{
		// First object added to group.
		
		[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:0];
		return;
	}
	
	// Figure out where the rowid is within the parentView.
	
	YapDatabaseViewTransaction *parentViewTransaction = [databaseTransaction ext:searchResultsView->parentViewName];
	
	YapDatabaseViewLocator *locator = [parentViewTransaction locatorForRowid:rowid];
	
	// Optimization:
	//
	// Check the existing position in-case the index didn't change.
	
	if (tryExistingIndexInGroup)
	{
		// Edge case: existing key is the only key in the group
		//
		// (existingIndex == 0) && (count == 1)
		
		NSUInteger existingIndexInGroup = existingLocator.index;
		BOOL useExistingIndexInGroup = YES;
		
		if (existingIndexInGroup > 0)
		{
			NSUInteger prevIndexInGroup = existingIndexInGroup - 1;
			
			int64_t prevRowid = 0;
			[self getRowid:&prevRowid atIndex:prevIndexInGroup inGroup:group];
			
			YapDatabaseViewLocator *prevLocator = [parentViewTransaction locatorForRowid:prevRowid];
			
			useExistingIndexInGroup = (prevLocator.index < locator.index);
		}
		
		if ((existingIndexInGroup + 1) < count && useExistingIndexInGroup)
		{
			NSUInteger nextIndexInGroup = existingIndexInGroup + 1;
			
			int64_t nextRowid = 0;
			[self getRowid:&nextRowid atIndex:nextIndexInGroup inGroup:group];
			
			YapDatabaseViewLocator *nextLocator = [parentViewTransaction locatorForRowid:nextRowid];
			
			useExistingIndexInGroup = (nextLocator.index > locator.index);
		}
		
		if (useExistingIndexInGroup)
		{
			// The item didn't change position.
			
			YDBLogVerbose(@"Updated key(%@) in group(%@) maintains current index", collectionKey.key, group);
			
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:group
			                                        atIndex:existingIndexInGroup
			                                    withChanges:flags]];
			return;
		}
		else
		{
			// The item has changed position within its group.
			// Remove it from previous position (and don't forget to decrement count).
			
			[self removeRowid:rowid collectionKey:collectionKey withLocator:existingLocator];
			count--;
		}
	}
	
	// Calculate where the rowid should go
	// We do this by searching the parentView for a rowid that's in our filtered list.
	//
	// Algorithm:
	// - start with the rowids immediately (index-1, index+1) next to the rowid in the parentView
	// - look for those rowids in our list
	// - if found, we know where to place the rowid within our filtered list
	// - otherwise try the rowids further out (index-2, index+2) until we find a match
	
	NSUInteger offset = 1;
	
	NSUInteger parentIndex = locator.index;
	NSUInteger parentCount = [parentViewTransaction numberOfItemsInGroup:group];
	
	NSUInteger index = 0;
	do {
		
		if (parentIndex >= offset)
		{
			NSUInteger prevIndex = parentIndex - offset;
			
			int64_t prevRowid = 0;
			[parentViewTransaction getRowid:&prevRowid atIndex:prevIndex inGroup:group];
			
			YapDatabaseViewLocator *prevLocator = [self locatorForRowid:prevRowid];
			if (prevLocator)
			{
				index = prevLocator.index + 1;
				break;
			}
		}
		
		if ((parentIndex + offset) < parentCount)
		{
			NSUInteger nextIndex = parentIndex + offset;
			
			int64_t nextRowid = 0;
			[parentViewTransaction getRowid:&nextRowid atIndex:nextIndex inGroup:group];
			
			YapDatabaseViewLocator *nextLocator = [self locatorForRowid:nextRowid];
			if (nextLocator)
			{
				index = nextLocator.index;
				break;
			}
		}
		
		offset++;
		
	} while (YES);
	
	[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:index];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is modeled after YapDatabaseFilteredViewTransaction's version,
 * with the addition of checking 'matchesQuery'.
**/
- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
            blockInvokeBitMask:(YapDatabaseBlockInvoke)blockInvokeBitMask
                changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	NSAssert((searchResultsView->parentViewName != nil), @"Improper method invocation!");
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collectionKey.collection])
	{
		return;
	}
	
	// Ask the parentViewTransaction for the group (which is cached info).
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:searchResultsView->parentViewName];
	
	NSString *group = [parentViewTransaction groupForRowid:rowid];
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
	}
	
	if (matchesQuery)
	{
		// Add row to the view or update its position.
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		          inGroup:group
		      withChanges:changesBitMask
		            isNew:isInsert];
	}
	else
	{
		// Not in view (not in parentView, or doesn't match query).
		// Remove from view (if needed).
		
		if (!isInsert) {
			[self removeRowid:rowid collectionKey:collectionKey];
		}
	}
}

/**
 * This method is modeleed after YapDatabaseAutoViewTransaction's version,
 *	with the addition of checking 'matchesQuery'.
**/
- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)collectionKey
                        object:(id)object
                      metadata:(id)metadata
                      grouping:(YapDatabaseViewGrouping *)grouping
                       sorting:(YapDatabaseViewSorting *)sorting
                     searching:(YapDatabaseFullTextSearchHandler *)searching
            blockInvokeBitMask:(YapDatabaseBlockInvoke)blockInvokeBitMask
                changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
                      isInsert:(BOOL)isInsert
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	NSAssert((searchResultsView->parentViewName == nil), @"Improper method invocation!");
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Determine if the grouping may have changed
	
	BOOL groupingMayHaveChanged;
	BOOL sortingMayHaveChanged;
	BOOL searchingMayHaveChanged;
	
	if (isInsert)
	{
		groupingMayHaveChanged  = YES;
		sortingMayHaveChanged   = YES;
		searchingMayHaveChanged = YES;
	}
	else
	{
		groupingMayHaveChanged  = (grouping->blockInvokeOptions  & blockInvokeBitMask);
		sortingMayHaveChanged   = (sorting->blockInvokeOptions   & blockInvokeBitMask);
		searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
	}
	
	if (!groupingMayHaveChanged && !sortingMayHaveChanged && !searchingMayHaveChanged)
	{
		// Nothing left to do.
		
		YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
		if (locator)
		{
			[parentConnection->changes addObject:
			  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
			                                        inGroup:locator.group
			                                        atIndex:locator.index
			                                    withChanges:changesBitMask]];
		}
		
		return;
	}
	
	// Invoke the grouping block to find out if the row should be included in the view.
	
	NSString *group = nil;
	
	if (groupingMayHaveChanged)
	{
		if (grouping->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			    (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			    (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object);
			group = [group copy]; // mutable string protection
		}
		else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			    (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, metadata);
			group = [group copy]; // mutable string protection
		}
		else
		{
			__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			    (YapDatabaseViewGroupingWithRowBlock)grouping->block;
			
			group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			group = [group copy]; // mutable string protection
		}
	}
	else
	{
		// Grouping hasn't changed.
		// Fetch the current group.
		
		YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
		group = locator.group;
	}
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		if (groupingMayHaveChanged || searchingMayHaveChanged)
		{
			__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
			  [databaseTransaction ext:searchResultsView->fullTextSearchName];
			
			matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		}
		else
		{
			matchesQuery = YES;
		}
	}
	
	if (matchesQuery)
	{
		// Add row to the view or update its position.
	
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:changesBitMask
		            isNew:isInsert];
	}
	else
	{
		// Not in view (groupingBlock returned nil, or doesn't match query).
		// Remove from view (if needed).
		
		if (!isInsert) {
			[self removeRowid:rowid collectionKey:collectionKey];
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeOnInsertOnly;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:YES];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
		
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:YES];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
		
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
		
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		BOOL groupingMayHaveChanged  = (grouping->blockInvokeOptions  & blockInvokeBitMask);
		BOOL sortingMayHaveChanged   = (sorting->blockInvokeOptions   & blockInvokeBitMask);
		BOOL searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
		
		BOOL groupingNeedsMetadata  = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
		BOOL sortingNeedsMetadata   = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
		
		id metadata = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsMetadata || sortingNeedsMetadata))
		{
			metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		}
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataModified;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
		
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		BOOL groupingMayHaveChanged  = (grouping->blockInvokeOptions & blockInvokeBitMask);
		BOOL sortingMayHaveChanged   = (sorting->blockInvokeOptions  & blockInvokeBitMask);
		BOOL searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
		
		BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
		BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
		
		id object = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsObject || sortingNeedsObject))
		{
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
		}
	
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfObjectTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		BOOL groupingMayHaveChanged  = (grouping->blockInvokeOptions & blockInvokeBitMask);
		BOOL sortingMayHaveChanged   = (sorting->blockInvokeOptions  & blockInvokeBitMask);
		BOOL searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
		
		BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
		BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
		
		BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
		BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
		
		id object = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsObject || sortingNeedsObject))
		{
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
		}
		
		id metadata = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsMetadata || sortingNeedsMetadata))
		{
			metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		}
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
		
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		BOOL groupingMayHaveChanged  = (grouping->blockInvokeOptions & blockInvokeBitMask);
		BOOL sortingMayHaveChanged   = (sorting->blockInvokeOptions  & blockInvokeBitMask);
		BOOL searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
		
		BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
		BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
		
		BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
		BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
		
		id object = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsObject || sortingNeedsObject))
		{
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
		}
		
		id metadata = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsMetadata || sortingNeedsMetadata))
		{
			metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		}
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	YapDatabaseBlockInvoke blockInvokeBitMask =
	  YapDatabaseBlockInvokeIfObjectTouched | YapDatabaseBlockInvokeIfMetadataTouched;
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	if (searchResultsView->parentViewName)
	{
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
	else
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
		  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
		YapDatabaseViewGrouping *grouping = nil;
		YapDatabaseViewSorting *sorting = nil;
		
		[searchResultsViewConnection getGrouping:&grouping sorting:&sorting];
		
		YapDatabaseFullTextSearchHandler *searching = [self searchHandler];
		
		BOOL groupingMayHaveChanged  = (grouping->blockInvokeOptions & blockInvokeBitMask);
		BOOL sortingMayHaveChanged   = (sorting->blockInvokeOptions  & blockInvokeBitMask);
		BOOL searchingMayHaveChanged = (searching->blockInvokeOptions & blockInvokeBitMask);
		
		BOOL groupingNeedsObject = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
		BOOL sortingNeedsObject  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
		
		BOOL groupingNeedsMetadata = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
		BOOL sortingNeedsMetadata  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
		
		id object = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsObject || sortingNeedsObject))
		{
			object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
		}
		
		id metadata = nil;
		if ((groupingMayHaveChanged || sortingMayHaveChanged || searchingMayHaveChanged)
		    && (groupingNeedsMetadata || sortingNeedsMetadata))
		{
			metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
		}
		
		[self _handleChangeWithRowid:rowid
		               collectionKey:collectionKey
		                      object:object
		                    metadata:metadata
		                    grouping:grouping
		                     sorting:sorting
		                   searching:searching
		          blockInvokeBitMask:blockInvokeBitMask
		              changesBitMask:changesBitMask
		                    isInsert:NO];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseViewDependency Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked if our parentView repopulates.
 * For example:
 *
 * - The parentView is a YapDatabaseView, and the groupingBlock and/or sortingBlock was changed.
 * - The parentView is a YapDatabaseFilteredView, and the filterBlock was changed.
 * - The parentView of the parentView was changed...
 * 
 * When this happens, there has likely been a significant change in the content of the parentView,
 * and a full repopulate is required on our part.
**/
- (void)view:(NSString *)parentViewName didRepopulateWithFlags:(int)flags
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	if (![parentViewName isEqualToString:searchResultsView->parentViewName])
	{
		YDBLogWarn(@"%@ - Method inappropriately invoked. Doesn't match parentViewName.", THIS_METHOD);
		return;
	}
	
	// The parentView has significantly changed.
	// We need to repopulate.
	
	BOOL groupingMayHaveChanged = (flags & YDB_GroupingMayHaveChanged) ? YES : NO;
	BOOL sortingMayHaveChanged  = (flags & YDB_SortingMayHaveChanged) ? YES : NO;
	
	if (groupingMayHaveChanged || sortingMayHaveChanged)
	{
		[self repopulateViewDueToParentGroupingSortingChange];
	}
	else
	{
		[self repopulateViewDueToParentFilteringChange];
	}
	
	// Propogate the notification onward to any extensions dependent upon this one.
	
	__unsafe_unretained NSString *registeredName = [self registeredName];
	__unsafe_unretained NSDictionary *extensionDependencies = databaseTransaction->connection->extensionDependencies;
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop){
		
		__unsafe_unretained NSString *extName = (NSString *)key;
		__unsafe_unretained NSSet *extDependencies = (NSSet *)obj;
		
		if ([extDependencies containsObject:registeredName])
		{
			YapDatabaseExtensionTransaction *extTransaction = [databaseTransaction ext:extName];
			
			if ([extTransaction respondsToSelector:@selector(view:didRepopulateWithFlags:)])
			{
				[(id <YapDatabaseViewDependency>)extTransaction view:registeredName didRepopulateWithFlags:flags];
			}
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ReadWrite
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setGrouping:(YapDatabaseViewGrouping *)inGrouping
            sorting:(YapDatabaseViewSorting *)inSorting
         versionTag:(NSString *)inVersionTag
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	if (searchResultsView->parentViewName)
	{
		NSString *reason = @"Method not available.";
		
		NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
		  @"YapDatabaseSearchResultsView is configured to use a parentView."
		  @" You may change the groupingBlock/sortingBlock of the parentView,"
		  @" but you cannot change the configuration of the YapDatabaseSearchResultsView like this."};
		
		@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
		return;
	}
	else
	{
		[super setGrouping:inGrouping
		           sorting:inSorting
		        versionTag:inVersionTag];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Searching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)query
{
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
	return [searchResultsViewConnection query];
}

/**
 * This method updates the view by using the updated ftsRowids set.
 * Only use this method if parentViewName is non-nil.
 * 
 * Note: You must update ftsRowids before invoking this method.
**/
- (void)updateViewFromParent
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)parentConnection->parent)->parentViewName != nil,
	         @"Logic error: method requires parentView");
	
	if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
		return;
	}
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
	  (YapDatabaseViewTransaction *)[databaseTransaction ext:searchResultsView->parentViewName];
	
	BOOL wasEmpty = [self isEmpty];
	BOOL hasSnippetOptions = (searchResultsOptions.snippetOptions != nil);
	
	id <NSFastEnumeration> groupsToEnumerate = nil;
	
	__unsafe_unretained YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
	if (allowedGroups)
	{
		NSArray *allGroups = [parentViewTransaction allGroups];
		NSMutableArray *groups = [NSMutableArray arrayWithCapacity:[allGroups count]];
		
		for (NSString *group in allGroups)
		{
			if ([allowedGroups isAllowed:group]) {
				[groups addObject:group];
			}
		}
		
		groupsToEnumerate = groups;
	}
	else
	{
		groupsToEnumerate = [parentViewTransaction allGroups];
	}
	
	for (NSString *group in groupsToEnumerate)
	{
		__block BOOL existing = NO;
		__block int64_t existingRowid = 0;
		
		if (wasEmpty)
			existing = NO;
		else
			existing = [self getRowid:&existingRowid atIndex:0 inGroup:group];
		
		__block NSUInteger index = 0;
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
		{
			if (YapRowidSetContains(ftsRowids, rowid))
			{
				// The item matches the FTS query (should be in view)
				
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (in old search results),
					// and is still in the view (in new search results).
					
					if (hasSnippetOptions)
					{
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
						
						[parentConnection->changes addObject:
						  [YapDatabaseViewRowChange updateCollectionKey:nil
						                                        inGroup:group
						                                        atIndex:index
						                                    withChanges:flags]];
					}
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (not in old search results),
					// but is now in the view (in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					[self insertRowid:rowid collectionKey:ck
					                              inGroup:group
					                              atIndex:index];
					
					index++;
				}
			}
			else
			{
				// The item does not match the FTS query (should not be in view)
				
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (in old search results),
					// but is no longer in the view (not in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					[self removeRowid:rowid collectionKey:ck atIndex:index inGroup:group];
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (not in old search results),
					// and is still not in the view (not in new search results).
				}
			}
			
			if ((parentIndex % 500) == 0)
			{
				if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
					*stop = YES;
				}
			}
		}];
		
		if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
			return;
		}
	}
}

/**
 * This method updates the view by using the updated ftsRowids set.
 * Only use this method if parentViewName is nil.
 * 
 * Note: You must update ftsRowids before invoking this method.
**/
- (void)updateViewUsingBlocks
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)parentConnection->parent)->parentViewName == nil,
	         @"Logic error: method requires nil parentView");
	
	if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
		return;
	}
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)parentConnection->parent->options;
	
	BOOL hasSnippetOptions = (searchResultsOptions.snippetOptions != nil);
	
	// Create a copy of the ftsRowids set.
	// As we enumerate the existing rowids in our view, we're going to
	YapRowidSet *ftsRowidsLeft = YapRowidSetCopy(ftsRowids);
	
	NSArray *allGroups = [self allGroups];
	__block int processed = 0;
	
	for (NSString *group in allGroups)
	{
		__block NSUInteger groupCount = [self numberOfItemsInGroup:group];
		__block NSRange range = NSMakeRange(0, groupCount);
		__block BOOL done;
		do
		{
			done = YES;
			
			[self enumerateRowidsInGroup:group
			                 withOptions:0
			                       range:range
			                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
			{
				if (YapRowidSetContains(ftsRowidsLeft, rowid))
				{
					// The row was previously in the view (in old search results),
					// and is still in the view (in new search results).
					
					if (hasSnippetOptions)
					{
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
						
						[parentConnection->changes addObject:
						  [YapDatabaseViewRowChange updateCollectionKey:nil
						                                        inGroup:group
						                                        atIndex:index
						                                    withChanges:flags]];
					}
					
					// Removes from ftsRowidsLeft set
					YapRowidSetRemove(ftsRowidsLeft, rowid);
				}
				else
				{
					// The row was previously in the view (in old search results),
					// but is no longer in the view (not in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					[self removeRowid:rowid collectionKey:ck atIndex:index inGroup:group];
					*stop = YES;
					
					groupCount--;
					
					range.location = index;
					range.length = groupCount - index;
					
					if (range.length > 0){
						done = NO;
					}
				}
				
				if (++processed == 500)
				{
					processed = 0;
					if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
						*stop = YES;
						done = YES;
					}
				}
			}];
			
		} while (!done);
		
		if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
			return;
		}
		
	} // end for (NSString *group in [self allGroups])
	
	
	// Now enumerate any items in ftsRowidsLeft
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
	YapDatabaseViewGroupingBlock groupingBlock_generic = NULL;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[searchResultsViewConnection getGrouping:&grouping
	                                 sorting:&sorting];
	
	YapRowidSetEnumerate(ftsRowidsLeft, ^(int64_t rowid, BOOL *stop) { @autoreleasepool {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		id object = nil;
		id metadata = nil;
		
		// Invoke the grouping block to find out if the object should be included in the view.
		
		NSString *group = nil;
		YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
		
		if (!allowedCollections || [allowedCollections isAllowed:ck.collection])
		{
			if (grouping->blockType == YapDatabaseBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, ck.collection, ck.key);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
				
				object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(databaseTransaction, ck.collection, ck.key, object);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
				
				metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(databaseTransaction, ck.collection, ck.key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)groupingBlock_generic;
				
				[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(databaseTransaction, ck.collection, ck.key, object, metadata);
			}
		}
		
		if (group)
		{
			// Add to view.
			
			YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			if (sorting->blockType == YapDatabaseBlockTypeWithObject)
			{
				if (object == nil)
					object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			}
			else if (sorting->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				if (metadata == nil)
					metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			}
			else if (sorting->blockType == YapDatabaseBlockTypeWithRow)
			{
				if (object == nil) {
					if (metadata == nil)
						[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
					else
						object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
				}
				else if (metadata == nil) {
					metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
				}
			}
			
			[self insertRowid:rowid
			    collectionKey:ck
			           object:object
			         metadata:metadata
			          inGroup:group withChanges:flags isNew:YES];
		}
		
		if (++processed == 500)
		{
			processed = 0;
			if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
				*stop = YES;
			}
		}
	}});
	
	// Dealloc the temporary c++ set
	if (ftsRowidsLeft) {
		YapRowidSetRelease(ftsRowidsLeft);
	}
}

/**
 * Updates the view to include search results for the given query.
 *
 * This method will run the given query on the parent FTS extension,
 * and then properly pipe the results into the view.
 *
 * @see performSearchWithQueue:
**/
- (void)performSearchFor:(NSString *)query
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	// Update stored query
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)parentConnection;
	
	[searchResultsViewConnection setQuery:query isChange:YES];
	
	// Run the query against the FTS extension, and populate the ftsRowids & snippets ivars
	
	[self repopulateFtsRowids];
	
	// Update the view (using FTS results stored in ftsRowids)
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	if (searchResultsView->parentViewName)
		[self updateViewFromParent];
	else
		[self updateViewUsingBlocks];
}

/**
 * This method works similar to performSearchFor:,
 * but allows you to use a special search "queue" that gives you more control over how the search progresses.
 *
 * With a search queue, the transaction will skip intermediate queries,
 * and always perform the most recent query in the queue.
 *
 * A search queue can also be used to abort an in-progress search.
**/
- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)inSearchQueue
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	searchQueue = inSearchQueue;
	
	NSString *query = [searchQueue flushQueue];
	if (query)
	{
		[self performSearchFor:query];
		
		BOOL rollback = NO;
		BOOL abort = [searchQueue shouldAbortSearchInProgressAndRollback:&rollback];
		if (abort && rollback)
		{
			[databaseTransaction rollbackTransaction];
		}
	}
	
	searchQueue = nil;
}

- (NSString *)snippetForKey:(NSString *)key inCollection:(NSString *)collection
{
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)parentConnection->parent;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	if (snippetOptions == nil) {
		// Ignore - snippets not being used
		return nil;
	}
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection]) {
		return nil;
	}
	
	YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  [databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	NSString *snippet = [ftsTransaction rowid:rowid matches:[self query] withSnippetOptions:snippetOptions];
	
	return snippet;
}

@end
