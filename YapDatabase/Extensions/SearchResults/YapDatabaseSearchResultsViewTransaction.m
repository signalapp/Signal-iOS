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

static NSString *const ext_key_superclassVersion = @"viewClassVersion";
static NSString *const ext_key_subclassVersion   = @"searchResultViewClassVersion";
static NSString *const ext_key_query             = @"query";


@implementation YapDatabaseSearchResultsViewTransaction
{
	YapRowidSet *ftsRowids;
	NSMutableDictionary *snippets;
	
	YapDatabaseSearchQueue *searchQueue;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)inViewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super initWithViewConnection:inViewConnection databaseTransaction:inDatabaseTransaction]))
	{
		if (viewConnection->view->options.isPersistent == NO)
		{
			snippetTableTransaction = [databaseTransaction memoryTableTransaction:[self snippetTableName]];
		}
	}
	return self;
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
	
	if (![self isPersistentView])
	{
		// We're registering an In-Memory-Only View (non-persistent) (not stored in the database).
		// So we can skip all the checks because we know we need to create the memory tables.
		
		if (![self createTables]) return NO;
		if (![self populateView]) return NO;
		
		// If there was a previously registered persistent view with this name,
		// then we should drop those tables from the database.
		
		BOOL dropPersistentTables = [self getIntValue:NULL forExtensionKey:ext_key_superclassVersion persistent:YES];
		if (dropPersistentTables)
		{
			[[viewConnection->view class]
			  dropTablesForRegisteredName:[self registeredName]
			              withTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
			                wasPersistent:YES];
		}
		
		return YES;
	}
	else
	{
		int superclassVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
		int subclassVersion = YAP_DATABASE_SEARCH_RESULTS_VIEW_CLASS_VERSION;
		
		NSString *versionTag = [viewConnection->view versionTag]; // MUST get init value from view
		
		// Figure out what steps we need to take in order to register the view
		//
		// We need to check several things:
		// - do we need to delete the old table(s) ?
		// - do we need to create the table(s) ?
		// - do we need to (re)populate the table(s) ?
		
		BOOL needsCreateTables = NO;
		BOOL needsPopulateView = NO;
		
		// Check classVersion (the internal version number of view implementation)
		
		int oldSuperclassVersion = 0;
		BOOL hasOldSuperclassVersion = [self getIntValue:&oldSuperclassVersion
		                                 forExtensionKey:ext_key_superclassVersion
		                                      persistent:YES];
		
		int oldSubclassVersion = 0;
		BOOL hasOldSubclassVersion = [self getIntValue:&oldSubclassVersion
		                               forExtensionKey:ext_key_subclassVersion
		                                    persistent:YES];
		
		if (!hasOldSuperclassVersion || !hasOldSuperclassVersion)
		{
			needsCreateTables = YES;
			needsPopulateView = YES;
		}
		else if ((oldSuperclassVersion != superclassVersion) ||
		         (oldSubclassVersion != subclassVersion))
		{
			if (oldSuperclassVersion != superclassVersion) {
				[self dropTablesForOldClassVersion:oldSuperclassVersion];
			}
			if (oldSubclassVersion != subclassVersion) {
				[self dropTablesForOldSubclassVersion:oldSubclassVersion];
			}
			
			needsCreateTables = YES;
			needsPopulateView = YES;
		}
		
		// Create the database tables (if needed)
		
		if (needsCreateTables)
		{
			if (![self createTables]) return NO;
		}
		
		// Check other variables (if needed)
		
		NSString *oldVersionTag = nil;
		
		if (!hasOldSuperclassVersion || !hasOldSuperclassVersion)
		{
			// If there wasn't classVersion info in the table,
			// then there won't be other values either.
		}
		else
		{
			// Check versionTag.
			// We need to re-populate the database if it changed.
			
			oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
			
			if (![oldVersionTag isEqualToString:versionTag])
			{
				needsPopulateView = YES;
			}
		}
		
		// Repopulate table (if needed)
		
		if (needsPopulateView)
		{
			if (![self populateView]) return NO;
		}
		
		// Update yap2 table values (if needed)
		
		if (!hasOldSuperclassVersion || (oldSuperclassVersion != superclassVersion)) {
			[self setIntValue:superclassVersion forExtensionKey:ext_key_superclassVersion persistent:YES];
		}
		
		if (!hasOldSubclassVersion || (oldSubclassVersion != subclassVersion)) {
			[self setIntValue:subclassVersion forExtensionKey:ext_key_subclassVersion persistent:YES];
		}
		
		if (![oldVersionTag isEqualToString:versionTag]) {
			[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
		}
		
		return YES;
	}
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
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	if ([searchResultsConnection query] == nil)
	{
		NSString *query = [self stringValueForExtensionKey:ext_key_query persistent:[self isPersistentView]];
		[searchResultsConnection setQuery:query isChange:NO];
	}
	
	return YES;
}

/**
 * Standard upgrade hook
**/
- (void)dropTablesForOldSubclassVersion:(int __unused)oldSubclassVersion
{
	// Placeholder method.
	// To be used if we have a major upgrade to this class.
}

/**
 * Overrides createTables method in superclass in order to create extra snippet table (if needed).
**/
- (BOOL)createTables
{
	YDBLogAutoTrace();
	
	// Create the main tables for the view
	if (![super createTables]) return NO;
	
	// Check to see if we need to create the snippet table
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *options =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions = options.snippetOptions_NoCopy;
	
	if (snippetOptions)
	{
		// Need to create the snippet table
		
		NSString *snippetTableName = [self snippetTableName];
		
		if ([self isPersistentView])
		{
			sqlite3 *db = databaseTransaction->connection->db;
			
			YDBLogVerbose(@"Creating view table for registeredName(%@): %@", [self registeredName], snippetTableName);
			
			NSString *createSnippetTable = [NSString stringWithFormat:
			    @"CREATE TABLE IF NOT EXISTS \"%@\""
			    @" (\"rowid\" INTEGER PRIMARY KEY,"
			    @"  \"snippet\" CHAR"
			    @" );", snippetTableName];
			
			int status = sqlite3_exec(db, [createSnippetTable UTF8String], NULL, NULL, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"%@ - Failed creating snippet table (%@): %d %s",
				            THIS_METHOD, snippetTableName, status, sqlite3_errmsg(db));
				return NO;
			}
		}
		else // if (isNonPersistentView)
		{
			YapMemoryTable *snippetTable = [[YapMemoryTable alloc] initWithKeyClass:[NSNumber class]];
			
			if (![databaseTransaction->connection registerMemoryTable:snippetTable withName:snippetTableName])
			{
				YDBLogError(@"%@ - Failed registering snippet memory table", THIS_METHOD);
				return NO;
			}
			
			snippetTableTransaction = [databaseTransaction memoryTableTransaction:snippetTableName];
		}
	}
	
	return YES;
}

/**
 * Overrides populateView method in superclass in order to provide its own independent implementation.
**/
- (BOOL)populateView
{
	YDBLogAutoTrace();
	
	// Remove everything from the database
	
	[self removeAllRowids];
	
	// Initialize ivars (if needed)
	
	if (viewConnection->state == nil)
		viewConnection->state = [[YapDatabaseViewState alloc] init];
	
	// Perform search
	
	snippets = [[NSMutableDictionary alloc] init];
	[self repopulateFtsRowidsAndSnippets];
	
	// Update the view using search results
	
	if (YapRowidSetCount(ftsRowids) > 0)
	{
		__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
		  (YapDatabaseSearchResultsView *)viewConnection->view;
		
		if (searchResultsView->parentViewName)
			[self updateViewFromParent];
		else
			[self updateViewUsingBlocks];
	}
	
	// Clear temp variable(s)
	
	snippets = nil;
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Repopulate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Executes the FTS query, and populates the ftsRowids & snippets ivars.
**/
- (void)repopulateFtsRowidsAndSnippets
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  (YapDatabaseFullTextSearchTransaction *)[databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	// Prepare ftsRowids ivar
	
	if (ftsRowids)
		YapRowidSetRemoveAll(ftsRowids);
	else
		ftsRowids = YapRowidSetCreate(0);
	
	// Perform search
	
	__block int processed = 0;
	
	if (snippetOptions)
	{
		// Need to get matching rowids and related snippets.
		
		NSAssert(snippets != nil, @"Forgot to initialize snippets variable !");
		
		[ftsTransaction enumerateRowidsMatching:[self query]
		                     withSnippetOptions:snippetOptions
		                             usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
		{
			YapRowidSetAdd(ftsRowids, rowid);
			
			if (snippet) {
				[snippets setObject:snippet forKey:@(rowid)];
			}
			
			if (++processed == 2500)
			{
				processed = 0;
				if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
					*stop = YES;
				}
			}
		 }];
	}
	else
	{
		// No snippets. Just get the matching rowids.
		
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
}

/**
 * This method is invoked if:
 *
 * - Our parentView had its groupingBlock and/or sortingBlock changed.
 * - A parentView of our parentView had its groupingBlock and/or sortingBlock changed.
**/
- (void)repopulateViewDueToParentGroupingBlockChange
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)viewConnection->view)->parentViewName != nil,
	         @"Logic error: method requires parentView");
	
	// Update our groupingBlock & sortingBlock to match the changed parent
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	YapDatabaseViewTransaction *parentViewTransaction =
	  [databaseTransaction ext:searchResultsView->parentViewName];
	
	__unsafe_unretained YapDatabaseViewConnection *parentViewConnection = parentViewTransaction->viewConnection;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[parentViewConnection getGrouping:&grouping
	                          sorting:&sorting];
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	[searchViewConnection setGrouping:grouping
	                          sorting:sorting];
	
	// Code overview:
	//
	// We could simply run the usual algorithm.
	// That is, enumerate over every item in the database, and run pretty much the same code as
	// in the handleUpdateObject:forCollectionKey:withMetadata:rowid:.
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
	
	[viewConnection->state enumerateGroupsWithBlock:^(NSString *group, BOOL __unused *outerStop) {
		
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse // <- required
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL __unused *innerStop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			 
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteCollectionKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[viewConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
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
- (void)repopulateViewDueToParentFilteringBlockChange
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)viewConnection->view)->parentViewName != nil,
	         @"Logic error: method requires parentView");
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
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
	
	snippets = [[NSMutableDictionary alloc] init];
	[self repopulateFtsRowidsAndSnippets];
	
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
		
		[parentViewTransaction enumerateRowidsInGroup:group
		                                   usingBlock:^(int64_t rowid, NSUInteger __unused parentIndex, BOOL __unused *stop)
		{
			if (existing && ((existingRowid == rowid)))
			{
				// Shortcut #1
				//
				// The row was previously in the view (allowed by previous parentFilter + our filter),
				// and is still in the view (allowed by new parentFilter + our filter).
				
				if (snippetOptions)
				{
					NSString *snippet = [snippets objectForKey:@(rowid)];
					[self updateSnippet:snippet forRowid:rowid];
					
					YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
					
					[viewConnection->changes addObject:
					  [YapDatabaseViewRowChange updateCollectionKey:nil
					                                        inGroup:group
					                                        atIndex:index
					                                    withChanges:flags]];
				}
				
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
					
					if (snippetOptions)
					{
						NSString *snippet = [snippets objectForKey:@(rowid)];
						[self updateSnippet:snippet forRowid:rowid];
						
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateCollectionKey:nil
						                                        inGroup:group
						                                        atIndex:index
						                                    withChanges:flags]];
					}
					
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
					
					if (index == 0 && ([viewConnection->state pagesMetadataForGroup:group] == nil)) {
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					}
					else {
						[self insertRowid:rowid collectionKey:ck
						                              inGroup:group
								                      atIndex:index
						                  withExistingPageKey:nil];
					}
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
	
	// Clear temp variable(s)
	
	snippets = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)snippetTableName
{
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)(viewConnection->view);
	
	return [searchResultsView snippetTableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateSnippet:(NSString *)snippet forRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	if ([self isPersistentView])
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		if (snippet == nil)
		{
			sqlite3_stmt *statement = [searchResultsConnection snippetTable_removeForRowidStatement];
			if (statement == NULL) return;
			
			// DELETE FROM "snippetTable" WHERE "rowid" = ?;
			
			int const bind_idx_rowid = SQLITE_BIND_START;
			
			sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'snippetTable_removeForRowidStatement': %d %s",
				            status, sqlite3_errmsg(databaseTransaction->connection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
		else
		{
			sqlite3_stmt *statement = [searchResultsConnection snippetTable_setForRowidStatement];
			if (statement == NULL) return;
			
			// INSERT OR REPLACE INTO "snippetTable" ("rowid", "snippet") VALUES (?, ?);
			
			int const bind_idx_rowid   = SQLITE_BIND_START + 0;
			int const bind_idx_snippet = SQLITE_BIND_START + 1;
			
			sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
			
			YapDatabaseString _snippet; MakeYapDatabaseString(&_snippet, (NSString *)snippet);
			sqlite3_bind_text(statement, bind_idx_snippet, _snippet.str, _snippet.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'snippetTable_setForRowidStatement': %d %s",
				            status, sqlite3_errmsg(databaseTransaction->connection->db));
			}
			
			FreeYapDatabaseString(&_snippet);
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
	}
	else // if (isNonPersistentView)
	{
		if (snippet == nil)
		{
			[snippetTableTransaction removeObjectForKey:@(rowid)];
		}
		else
		{
			[snippetTableTransaction setObject:snippet forKey:@(rowid)];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Subclass Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked whenver a item is added to our view.
**/
- (void)didInsertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;

	if (searchResultsOptions.snippetOptions_NoCopy == nil) {
		// Ignore - snippets not being used
		return;
	}
	
	if (snippets)
	{
		NSString *snippet = [snippets objectForKey:@(rowid)];
		[self updateSnippet:snippet forRowid:rowid];
	}
}

/**
 * This method is invoked whenver a single item is removed from our view.
**/
- (void)didRemoveRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions_NoCopy == nil) {
		// Ignore - snippets not being used
		return;
	}
	
	if ([self isPersistentView])
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		sqlite3_stmt *statement = [searchResultsConnection snippetTable_removeForRowidStatement];
		if (statement == NULL) return;
		
		// DELETE FROM "snippetTable" WHERE "rowid" = ?;
		
		int const bind_idx_rowid = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'snippetTable_removeForRowidStatement': %d %s, collectionKey(%@)",
			            status, sqlite3_errmsg(databaseTransaction->connection->db), collectionKey);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else // if (isNonPersistentView)
	{
		[snippetTableTransaction removeObjectForKey:@(rowid)];
	}
}

/**
 * This method is invoked whenever a batch of items are removed from our view.
**/
- (void)didRemoveRowids:(NSArray *)rowids collectionKeys:(NSArray __unused *)collectionKeys
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions_NoCopy == nil) {
		// Ignore - snippets not being used
		return;
	}
	
	if ([self isPersistentView])
	{
		// Important:
		// The given rowids array is unbounded.
		// That is, normally hook methods are limited by SQLITE_LIMIT_VARIABLE_NUMBER.
		// But that is ** NOT ** the case here.
		// So we're required to check for this, and split the queries accordingly.
		
		sqlite3 *db = databaseTransaction->connection->db;
		
		NSUInteger maxHostParams = (NSUInteger)sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
		
		NSUInteger rowidsCount = [rowids count];
		NSUInteger offset = 0;
		
		do
		{
			NSUInteger left = rowidsCount - offset;
			NSUInteger numParams = MIN(left, maxHostParams);
			
			// DELETE FROM "snippetTable" WHERE "rowid" (?, ?, ...);
			
			NSUInteger capacity = 100 + (numParams * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendFormat:@"DELETE FROM \"%@\" WHERE \"rowid\" IN (", [self snippetTableName]];
			
			for (NSUInteger i = 0; i < numParams; i++)
			{
				if (i == 0)
					[query appendString:@"?"];
				else
					[query appendString:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating removeSnippets statement: %d %s", status, sqlite3_errmsg(db));
				return;
			}
			
			for (NSUInteger i = 0; i < numParams; i++)
			{
				int64_t rowid = [[rowids objectAtIndex:(offset + i)] unsignedLongLongValue];
				sqlite3_bind_int64(statement, (int)(SQLITE_BIND_START + i), rowid);
			}
			
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing removeSnippets statement: %d %s", status, sqlite3_errmsg(db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
			
			offset += numParams;
			
		} while(offset < rowidsCount);
		
	}
	else // if (isNonPersistentView)
	{
		[snippetTableTransaction removeObjectsForKeys:rowids];
	}
}

/**
 * This method is invoked whenever all items are removed from our view.
**/
- (void)didRemoveAllRowids
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions_NoCopy == nil) {
		// Ignore - snippets not being used
		return;
	}
	
	if ([self isPersistentView])
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		sqlite3_stmt *snippetStatement = [searchResultsConnection snippetTable_removeAllStatement];
		if (snippetStatement == NULL) return;
		
		// DELETE FROM "snippetTableName";
		
		YDBLogVerbose(@"DELETE FROM '%@';", [self snippetTableName]);
		
		int status = sqlite3_step(snippetStatement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error in snippetTable_removeAllStatement: %d %s",
			            THIS_METHOD, [self registeredName],
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_reset(snippetStatement);
	}
	else // if (isNonPersistentView)
	{
		[snippetTableTransaction removeAllObjects];
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
	
	if (![self isPersistentView])
	{
		[snippetTableTransaction commit];
	}
	
	// If the query was changed, then we need to write it to the yap table.
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
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

- (void)didRollbackTransaction
{
	YDBLogAutoTrace();
	
	if (![self isPersistentView])
	{
		[snippetTableTransaction rollback];
	}
	
	// This must be done LAST.
	[super didRollbackTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Since our groupingBlock is the same as the parent's groupingBlock,
		// just ask the parentViewTransaction for the group (which is cached info).
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = [parentViewTransaction groupForRowid:rowid];
		
		if (group)
		{
			YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups isAllowed:group])
			{
				group = nil;
			}
		}
	}
	else
	{
		// Invoke the grouping block to find out if the object should be included in the view.
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
		
		if (!allowedCollections || [allowedCollections isAllowed:collection])
		{
			YapDatabaseViewGrouping *grouping;
			
			[viewConnection getGrouping:&grouping];
			
			if (grouping->blockType == YapDatabaseBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, object);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			}
		}
	}
	
	NSString *snippet = nil;
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		if (snippetOptions)
		{
			snippet = [ftsTransaction rowid:rowid matches:[self query] withSnippetOptions:snippetOptions];
			matchesQuery = (snippet != nil);
		}
		else
		{
			matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		}
	}
	
	if (matchesQuery)
	{
		// Add to view.
		// This was an insert operation, so we know it wasn't already in the view.
		
		if (snippetOptions)
		{
			[self updateSnippet:snippet forRowid:rowid];
		}
		
		YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group withChanges:flags isNew:YES];
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// This was an insert operation, so we know it wasn't already in the view.
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Since our groupingBlock is the same as the parent's groupingBlock,
		// just ask the parentViewTransaction for the group (which is cached info).
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = [parentViewTransaction groupForRowid:rowid];
		
		if (group)
		{
			YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups isAllowed:group])
			{
				group = nil;
			}
		}
	}
	else
	{
		// Invoke the grouping block to find out if the object should be included in the view.
		
		__unsafe_unretained NSString *collection = collectionKey.collection;
		__unsafe_unretained NSString *key = collectionKey.key;
		
		YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
		
		if (!allowedCollections || [allowedCollections isAllowed:collection])
		{
			YapDatabaseViewGrouping *grouping;
			
			[viewConnection getGrouping:&grouping];
			
			if (grouping->blockType == YapDatabaseBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, object);
			}
			else if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)grouping->block;
				
				group = groupingBlock(databaseTransaction, collection, key, object, metadata);
			}
		}
	}
	
	NSString *snippet = nil;
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		if (snippetOptions)
		{
			snippet = [ftsTransaction rowid:rowid matches:[self query] withSnippetOptions:snippetOptions];
			matchesQuery = (snippet != nil);
		}
		else
		{
			matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		}
	}
	
	if (matchesQuery)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		if (snippetOptions)
		{
			[self updateSnippet:snippet forRowid:rowid];
		}
		
		YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:NO];
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// Remove from view (if needed).
		// This was an update operation, so it may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
 * This method overrides the version in YapDatabaseViewTransaction.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[viewConnection getGrouping:&grouping
	                    sorting:&sorting];
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = (grouping->blockType & YapDatabaseBlockType_ObjectFlag);
		BOOL sortMayHaveChanged  = (sorting->blockType  & YapDatabaseBlockType_ObjectFlag);
		
		// Since our groupingBlock is the same as the parent's groupingBlock,
		// just ask the parentViewTransaction for the group (which is cached info).
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = [parentViewTransaction groupForRowid:rowid];
		
		if (group)
		{
			YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups isAllowed:group])
			{
				group = nil;
			}
		}
		
		if (group == nil)
		{
			// Not included in parentView (or not in allowedGroups)
			
			if (groupMayHaveChanged)
			{
				// Remove from view (if needed).
				// This was an update operation, so it may have previously been in the view.
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				// The group hasn't changed.
				// Thus it wasn't previously in view, and still isn't in the view.
			}
			
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = (fts->handler->blockType & YapDatabaseBlockType_ObjectFlag);
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			if (pageKey == nil)
			{
				// Was previously filtered from this view.
				// And still filtered from this view.
			}
			else
			{
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:group
				                                        atIndex:existingIndex
				                                    withChanges:flags]];
			}
			
			return;
		}
		
		NSString *snippet = nil;
		BOOL matchesQuery = NO;
		
		if (snippetOptions)
		{
			snippet = [ftsTransaction rowid:rowid matches:[self query] withSnippetOptions:snippetOptions];
			matchesQuery = (snippet != nil);
		}
		else
		{
			matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		}
		
		if (matchesQuery)
		{
			// Add to view (or update position).
			// This was an update operation, so it may have previously been in the view.
			
			if (snippetOptions)
			{
				[self updateSnippet:snippet forRowid:rowid];
			}
			
			YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id metadata = nil;
			if (sorting->blockType & YapDatabaseBlockType_MetadataFlag)
			{
				metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
			}
			
			[self insertRowid:rowid
			    collectionKey:collectionKey
			           object:object
			         metadata:metadata
			          inGroup:group
			      withChanges:flags
			            isNew:NO];
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so it may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id metadata = nil;
		NSString *group = nil;
		
		if (grouping->blockType == YapDatabaseBlockTypeWithKey ||
			grouping->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			// Grouping is based on the key or metadata.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [viewConnection->state groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// It wasn't previously in the view, and still isn't in the view.
			}
			else if (sorting->blockType == YapDatabaseBlockTypeWithKey ||
			         sorting->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:group
				                                        atIndex:existingIndex
				                                    withChanges:flags]];
			}
			else
			{
				// Sorting is based on the object, which has changed.
				// So the sort order may possibly have changed.
				
				if (sorting->blockType & YapDatabaseBlockType_MetadataFlag)
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
				
				[self insertRowid:rowid
					collectionKey:collectionKey
						   object:object
						 metadata:metadata
						  inGroup:group withChanges:flags isNew:NO];
			}
		}
		else
		{
			// Grouping is based on object or row (object+metadata).
			// Invoke groupingBlock to see what the new group is.
			
			__unsafe_unretained NSString *collection = collectionKey.collection;
			__unsafe_unretained NSString *key = collectionKey.key;
			
			YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
			
			if (!allowedCollections || [allowedCollections isAllowed:collection])
			{
				if (grouping->blockType == YapDatabaseBlockTypeWithObject)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			          (YapDatabaseViewGroupingWithObjectBlock)grouping->block;
					
					group = groupingBlock(databaseTransaction, collection, key, object);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)grouping->block;
					
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(databaseTransaction, collection, key, object, metadata);
				}
			}
			
			if (group == nil)
			{
				// The key is not included in the view.
				// Remove key from view (if needed).
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				if (sorting->blockType == YapDatabaseBlockTypeWithKey ||
				    sorting->blockType == YapDatabaseBlockTypeWithMetadata)
				{
					// Sorting is based on the key or metadata, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [viewConnection->state groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change,
						// and the sort order cannot change (because the key/metadata didn't change).
						
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
						                                        inGroup:group
						                                        atIndex:existingIndex
						                                    withChanges:flags]];
						
						return;
					}
				}
				
				if (metadata == nil && (sorting->blockType & YapDatabaseBlockType_MetadataFlag))
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:NO];
			}
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchSnippetOptions *snippetOptions =
	  searchResultsOptions.snippetOptions_NoCopy;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[viewConnection getGrouping:&grouping
	                    sorting:&sorting];
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = (grouping->blockType & YapDatabaseBlockType_MetadataFlag);
		BOOL sortMayHaveChanged  = (sorting->blockType  & YapDatabaseBlockType_MetadataFlag);
		
		// Since our groupingBlock is the same as the parent's groupingBlock,
		// just ask the parentViewTransaction for the group (which is cached info).
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = [parentViewTransaction groupForRowid:rowid];
		
		if (group)
		{
			YapWhitelistBlacklist *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups isAllowed:group])
			{
				group = nil;
			}
		}
		
		if (group == nil)
		{
			// Not included in parentView.
			
			if (groupMayHaveChanged)
			{
				// Remove key from view (if needed).
				// This was an update operation, so the key may have previously been in the view.
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				// The group hasn't changed.
				// Thus it wasn't previously in view, and still isn't in the view.
			}
			
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = (fts->handler->blockType & YapDatabaseBlockType_MetadataFlag);
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedMetadata;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			if (pageKey == nil)
			{
				// Was previously filtered from this view.
				// And still filtered from this view.
			}
			else
			{
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:group
				                                        atIndex:existingIndex
				                                    withChanges:flags]];
			}
			
			return;
		}
		
		NSString *snippet = nil;
		BOOL matchesQuery = NO;
		
		if (snippetOptions)
		{
			snippet = [ftsTransaction rowid:rowid matches:[self query] withSnippetOptions:snippetOptions];
			matchesQuery = (snippet != nil);
		}
		else
		{
			matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		}
		
		if (matchesQuery)
		{
			// Add key to view (or update position).
			// This was an update operation, so the key may have previously been in the view.
			
			if (snippetOptions)
			{
				[self updateSnippet:snippet forRowid:rowid];
			}
			
			YapDatabaseViewChangesBitMask flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id object= nil;
			if (sorting->blockType & YapDatabaseBlockType_ObjectFlag)
			{
				object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
			}
			
			[self insertRowid:rowid
			    collectionKey:collectionKey
			           object:object
			         metadata:metadata
			          inGroup:group
			      withChanges:flags
			            isNew:NO];
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so the key may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id object = nil;
		NSString *group = nil;
		
		if (grouping->blockType == YapDatabaseBlockTypeWithKey ||
		    grouping->blockType == YapDatabaseBlockTypeWithObject)
		{
			// Grouping is based on the key or object.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [viewConnection->state groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// The key wasn't previously in the view, and still isn't in the view.
			}
			else if (sorting->blockType == YapDatabaseBlockTypeWithKey ||
			         sorting->blockType == YapDatabaseBlockTypeWithObject)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedMetadata;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
				                                        inGroup:group
				                                        atIndex:existingIndex
				                                    withChanges:flags]];
			}
			else
			{
				// Sorting is based on the metadata, which has changed.
				// So the sort order may possibly have changed.
				
				if (sorting->blockType & YapDatabaseBlockType_ObjectFlag)
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedMetadata;
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:NO];
			}
		}
		else
		{
			// Grouping is based on metadata or objectAndMetadata.
			// Invoke groupingBlock to see what the new group is.
			
			__unsafe_unretained NSString *collection = collectionKey.collection;
			__unsafe_unretained NSString *key = collectionKey.key;
			
			YapWhitelistBlacklist *allowedCollections = searchResultsOptions.allowedCollections;
			
			if (!allowedCollections || [allowedCollections isAllowed:collection])
			{
				if (grouping->blockType == YapDatabaseBlockTypeWithMetadata)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			          (YapDatabaseViewGroupingWithMetadataBlock)grouping->block;
					
					group = groupingBlock(databaseTransaction, collection, key, metadata);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)grouping->block;
					
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(databaseTransaction, collection, key, object, metadata);
				}
			}
			
			if (group == nil)
			{
				// The key is not included in the view.
				// Remove key from view (if needed).
				
				[self removeRowid:rowid collectionKey:collectionKey];
			}
			else
			{
				if (sorting->blockType == YapDatabaseBlockTypeWithKey ||
				    sorting->blockType == YapDatabaseBlockTypeWithObject)
				{
					// Sorting is based on the key or object, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [viewConnection->state groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change,
						// and the sort order cannot change (because the key/object didn't change).
						
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedMetadata;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
						                                        inGroup:group
						                                        atIndex:existingIndex
						                                    withChanges:flags]];
						
						return;
					}
				}
				
				if (object == nil && (sorting->blockType & YapDatabaseBlockType_ObjectFlag))
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedMetadata;
				
				[self insertRowid:rowid
					collectionKey:collectionKey
						   object:object
						 metadata:metadata
						  inGroup:group withChanges:flags isNew:NO];
			}
		}
	}
}

///
/// All other hook methods are handled by superclass (YapDatabaseViewTransaction).
///

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
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	if (![parentViewName isEqualToString:searchResultsView->parentViewName])
	{
		YDBLogWarn(@"%@ - Method inappropriately invoked. Doesn't match parentViewName.", THIS_METHOD);
		return;
	}
	
	// The parentView has significantly changed.
	// We need to repopulate.
	
	BOOL groupingBlockChanged = (flags & YDB_GroupingBlockChanged) ? YES : NO;
	BOOL sortingBlockChanged = (flags & YDB_SortingBlockChanged) ? YES : NO;
	
	if (groupingBlockChanged || sortingBlockChanged)
	{
		[self repopulateViewDueToParentGroupingBlockChange];
	}
	else
	{
		[self repopulateViewDueToParentFilteringBlockChange];
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
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
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
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	return [searchResultsViewConnection query];
}

//- (void)updateSnippet:(NSString *)snippet for

/**
 * This method updates the view by using the updated ftsRowids set.
 * Only use this method if parentViewName is non-nil.
 * 
 * Note: You must update ftsRowids before invoking this method.
**/
- (void)updateViewFromParent
{
	YDBLogAutoTrace();
	
	NSAssert(((YapDatabaseSearchResultsView *)viewConnection->view)->parentViewName != nil,
	         @"Logic error: method requires parentView");
	
	if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
		return;
	}
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
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
						NSString *snippet = [snippets objectForKey:@(rowid)];
						[self updateSnippet:snippet forRowid:rowid];
						
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
						
						[viewConnection->changes addObject:
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
					
					if (index == 0 && ([viewConnection->state pagesMetadataForGroup:group] == nil)) {
						[self insertRowid:rowid collectionKey:ck inNewGroup:group];
					}
					else {
						[self insertRowid:rowid collectionKey:ck
						                              inGroup:group
						                              atIndex:index
						                  withExistingPageKey:nil];
					}
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
	
	NSAssert(((YapDatabaseSearchResultsView *)viewConnection->view)->parentViewName == nil,
	         @"Logic error: method requires nil parentView");
	
	if ([searchQueue shouldAbortSearchInProgressAndRollback:NULL]) {
		return;
	}
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
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
						NSString *snippet = [snippets objectForKey:@(rowid)];
						[self updateSnippet:snippet forRowid:rowid];
						
						YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedSnippets;
						
						[viewConnection->changes addObject:
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
	
	YapDatabaseViewGroupingBlock groupingBlock_generic = NULL;
	
	YapDatabaseViewGrouping *grouping = nil;
	YapDatabaseViewSorting  *sorting  = nil;
	
	[viewConnection getGrouping:&grouping
	                    sorting:&sorting];
	
	YapRowidSetEnumerate(ftsRowidsLeft, ^(int64_t rowid, BOOL *stop) { @autoreleasepool {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		id object = nil;
		id metadata = nil;
		
		// Invoke the grouping block to find out if the object should be included in the view.
		
		NSString *group = nil;
		YapWhitelistBlacklist *allowedCollections = viewConnection->view->options.allowedCollections;
		
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
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	[searchResultsViewConnection setQuery:query isChange:YES];
	
	// Run the query against the FTS extension, and populate the ftsRowids & snippets ivars
	
	snippets = [[NSMutableDictionary alloc] init];
	[self repopulateFtsRowidsAndSnippets];
	
	// Update the view (using FTS results stored in ftsRowids)
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	if (searchResultsView->parentViewName)
		[self updateViewFromParent];
	else
		[self updateViewUsingBlocks];
	
	// Clear temp variable(s)
	
	snippets = nil;
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
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	(YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions == nil) {
		// Ignore - snippets not being used
		return nil;
	}
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection]) {
		return nil;
	}
	
	NSString *snippet = nil;
	
	if ([self isPersistentView])
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		sqlite3_stmt *statement = [searchResultsConnection snippetTable_getForRowidStatement];
		if (statement == NULL) return nil;
		
		// SELECT "snippet" FROM "snippetTable" WHERE "rowid" = ?;
		
		int const column_idx_snippet = SQLITE_COLUMN_START;
		int const bind_idx_rowid     = SQLITE_BIND_START;
		
		sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_snippet);
			int textSize = sqlite3_column_bytes(statement, column_idx_snippet);
			
			snippet = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'snippetTable_getForRowidStatement': %d %s",
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else
	{
		snippet = [snippetTableTransaction objectForKey:@(rowid)];
	}
	
	return snippet;
}

@end
