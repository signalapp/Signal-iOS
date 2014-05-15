#import "YapDatabaseSearchResultsViewTransaction.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseFullTextSearchPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
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

#define ExtKey_superclassVersion  @"viewClassVersion"
#define ExtKey_subclassVersion    @"searchResultViewClassVersion"
#define ExtKey_persistent         @"persistent"
#define ExtKey_versionTag         @"versionTag"
#define ExtKey_query              @"query"


@implementation YapDatabaseSearchResultsViewTransaction
{
	YapRowidSet *ftsRowids;
	NSMutableDictionary *snippets;
}

- (id)initWithViewConnection:(YapDatabaseViewConnection *)inViewConnection
         databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super initWithViewConnection:inViewConnection databaseTransaction:inDatabaseTransaction]))
	{
		ftsRowids = YapRowidSetCreate(0);
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
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)(viewConnection->view);
	
	int superclassVersion = YAP_DATABASE_VIEW_CLASS_VERSION;
	int subclassVersion = YAP_DATABASE_SEARCH_RESULTS_VIEW_CLASS_VERSION;
	
	NSString *versionTag = searchResultsView->versionTag;
	
	BOOL isPersistent = [self isPersistentView];
	
	// We need to check several things:
	// - do we need to delete the old table(s) ?
	// - do we need to create the table(s) ?
	// - do we need to (re)populate the table(s) ?
	
	BOOL needsCreateTables = NO;
	
	int oldSuperclassVersion;
	BOOL hasOldSuperclassVersion;
	
	int oldSubclassVersion;
	BOOL hasOldSubclassVersion;
	
	BOOL oldIsPersistent = NO;
	BOOL hasOldIsPersistent = NO;
	
	NSString *oldVersionTag = nil;
	
	// Check classVersion (the internal version number of view implementation)
	
	oldSuperclassVersion = 0;
	hasOldSuperclassVersion = [self getIntValue:&oldSuperclassVersion forExtensionKey:ExtKey_superclassVersion];
	
	oldSubclassVersion = 0;
	hasOldSubclassVersion = [self getIntValue:&oldSubclassVersion forExtensionKey:ExtKey_subclassVersion];
	
	if (!hasOldSuperclassVersion || !hasOldSuperclassVersion)
	{
		needsCreateTables = YES;
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
	}
	
	// Check persistence.
	// Need to properly transition from persistent to non-persistent, and vice-versa.
	
	if (!needsCreateTables)
	{
		hasOldIsPersistent = [self getBoolValue:&oldIsPersistent forExtensionKey:ExtKey_persistent];
		
		if (hasOldIsPersistent && oldIsPersistent && !isPersistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[[searchResultsView class] dropTablesForRegisteredName:[self registeredName]
			                                       withTransaction:rwDatabaseTransaction];
		}
		
		if (!hasOldIsPersistent || (oldIsPersistent != isPersistent))
		{
			needsCreateTables = YES;
		}
		else if (!isPersistent)
		{
			// We always have to create & populate the tables for non-persistent views.
			// Even when re-registering from previous app launch.
			needsCreateTables = YES;
			
			oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag];
		}
	}
	
	// Create or re-populate if needed
	
	if (needsCreateTables)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self populateView]) return NO;
		
		if (!hasOldSuperclassVersion || (oldSuperclassVersion != superclassVersion)) {
			[self setIntValue:superclassVersion forExtensionKey:ExtKey_superclassVersion];
		}
		
		if (!hasOldSubclassVersion || (oldSubclassVersion != subclassVersion)) {
			[self setIntValue:subclassVersion forExtensionKey:ExtKey_subclassVersion];
		}
		
		if (!hasOldIsPersistent || (oldIsPersistent != isPersistent)) {
			[self setBoolValue:isPersistent forExtensionKey:ExtKey_persistent];
		}
		
		if (![oldVersionTag isEqualToString:versionTag]) {
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag];
		}
	}
	else
	{
		// Check versionTag.
		// We need to re-populate the database if it changed.
		
		oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag];
		
		if (![oldVersionTag isEqualToString:versionTag])
		{
			if (![self populateView]) return NO;
			
			[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag];
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
	
	BOOL result = [super prepareIfNeeded];
	if (result)
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		NSString *query = [self stringValueForExtensionKey:ExtKey_query];
		[searchResultsConnection setQuery:query isChange:NO];
	}
	
	return result;
}

/**
 * Standard upgrade hook
**/
- (void)dropTablesForOldSubclassVersion:(int)oldSubclassVersion
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
	
	if (options.snippetOptions)
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
			
			if (![databaseTransaction->connection registerTable:snippetTable withName:snippetTableName])
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
	
	// Initialize ivars
	
	if (viewConnection->group_pagesMetadata_dict == nil)
		viewConnection->group_pagesMetadata_dict = [[NSMutableDictionary alloc] init];
	
	if (viewConnection->pageKey_group_dict == nil)
		viewConnection->pageKey_group_dict = [[NSMutableDictionary alloc] init];
	
	// Perform search (if needed)
	
	YapRowidSetRemoveAll(ftsRowids);
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  (YapDatabaseFullTextSearchTransaction *)[databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	if (searchResultsOptions.snippetOptions)
	{
		// Need to get matching rowids and related snippets.
		
		if (snippets == nil)
			snippets = [[NSMutableDictionary alloc] init];
		else
			[snippets removeAllObjects];
		
		[ftsTransaction enumerateRowidsMatching:[self query]
		                     withSnippetOptions:searchResultsOptions.snippetOptions
		                             usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
		{
			YapRowidSetAdd(ftsRowids, rowid);
			
			if (snippet)
				[snippets setObject:snippet forKey:@(rowid)];
			else
				[snippets setObject:[NSNull null] forKey:@(rowid)];
		 }];
	}
	else
	{
		// No snippets. Just get the matching rowids.
		
		[ftsTransaction enumerateRowidsMatching:[self query] usingBlock:^(int64_t rowid, BOOL *stop) {
			
			YapRowidSetAdd(ftsRowids, rowid);
		}];
	}
	
	if (YapRowidSetCount(ftsRowids) > 0)
	{
		if (searchResultsView->parentViewName)
			[self updateViewFromParent];
		else
			[self updateViewUsingBlocks];
	}

	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Repopulate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	
	__unsafe_unretained YapDatabaseView *parentView = parentViewTransaction->viewConnection->view;
	
	searchResultsView->groupingBlock = parentView->groupingBlock;
	searchResultsView->groupingBlockType = parentView->groupingBlockType;
	
	searchResultsView->sortingBlock = parentView->sortingBlock;
	searchResultsView->sortingBlockType = parentView->sortingBlockType;
	
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
	// - And then run the normal populate routine, with one exceptione handled by the isRepopulate flag.
	//
	// The changeset mechanism will automatically consolidate all changes to the minimum.
	
	for (NSString *group in viewConnection->group_pagesMetadata_dict)
	{
		// We must add the changes in reverse order.
		// Either that, or the change index of each item would have to be zero,
		// because a YapDatabaseViewRowChange records the index at the moment the change happens.
		
		[self enumerateRowidsInGroup:group
		                 withOptions:NSEnumerationReverse // <- required
		                  usingBlock:^(int64_t rowid, NSUInteger index, BOOL *stop)
		{
			YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
			 
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange deleteKey:collectionKey inGroup:group atIndex:index]];
		}];
		
		[viewConnection->changes addObject:[YapDatabaseViewSectionChange deleteGroup:group]];
	}
	
	isRepopulate = YES;
	{
		// No need to redo the search. That is, no need to re-populate the ftsRowids ivar.
		// Instead, just run the pre & post-search code.
		//
		// [self populateView]; <- Nope. We want a subset of this method.
		
		[self removeAllRowids];
		
		if (YapRowidSetCount(ftsRowids) > 0)
		{
			[self updateViewFromParent];
		}
		
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
	
	NSMutableArray *groupsInSelf = [[self allGroups] mutableCopy];
	id <NSFastEnumeration> groupsInParent;
	
	if (searchResultsOptions.allowedGroups)
	{
		NSMutableSet *groupsInParentSet = [NSMutableSet setWithArray:[parentViewTransaction allGroups]];
		[groupsInParentSet intersectSet:searchResultsOptions.allowedGroups];
		
		groupsInParent = groupsInParentSet;
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
		                                   usingBlock:^(int64_t rowid, NSUInteger parentIndex, BOOL *stop)
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
					
					if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil)) {
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
			// Todo: This could be optimized...
			
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:existingRowid];
			[self removeRowid:existingRowid collectionKey:ck atIndex:index inGroup:group];
			
			existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
		}
		
		NSUInteger groupIndex = [groupsInSelf indexOfObject:group];
		if (groupIndex != NSNotFound)
		{
			[groupsInSelf removeObjectAtIndex:groupIndex];
		}
	}
	
	// Check to see if there are any groups that have been completely removed.
	
	for (NSString *group in groupsInSelf)
	{
		[self removeAllRowidsInGroup:group];
	}
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
#pragma mark Subclass Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked whenver a item is added to our view.
**/
- (void)didInsertRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	id snippet = [snippets objectForKey:@(rowid)];
	if (snippet == nil) return;
	
	if ([self isPersistentView])
	{
		__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsConnection =
		  (YapDatabaseSearchResultsViewConnection *)viewConnection;
		
		if (snippet == [NSNull null])
		{
			sqlite3_stmt *statement = [searchResultsConnection snippetTable_removeForRowidStatement];
			if (statement == NULL) return;
			
			// DELETE FROM "snippetTable" WHERE "rowid" = ?;
			
			sqlite3_bind_int64(statement, 1, rowid);
			
			int status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'snippetTable_removeForRowidStatement': %d %s, collectionKey(%@)",
				            status, sqlite3_errmsg(databaseTransaction->connection->db), collectionKey);
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
		else
		{
			sqlite3_stmt *statement = [searchResultsConnection snippetTable_setForRowidStatement];
			if (statement == NULL) return;
			
			// INSERT OR REPLACE INTO "snippetTable" ("rowid", "snippet") VALUES (?, ?);
			
			sqlite3_bind_int64(statement, 1, rowid);
			
			YapDatabaseString _snippet; MakeYapDatabaseString(&_snippet, snippet);
			sqlite3_bind_text(statement, 2, _snippet.str, _snippet.length, SQLITE_STATIC);
			
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
		if (snippet == [NSNull null])
		{
			[snippetTableTransaction removeObjectForKey:@(rowid)];
		}
		else
		{
			[snippetTableTransaction setObject:snippet forKey:@(rowid)];
		}
	}
}

/**
 * This method is invoked whenver a single item is removed from our view.
**/
- (void)didRemoveRowid:(int64_t)rowid collectionKey:(YapCollectionKey *)collectionKey
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions == nil) {
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
			
		sqlite3_bind_int64(statement, 1, rowid);
		
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
- (void)didRemoveRowids:(NSArray *)rowids collectionKeys:(NSArray *)collectionKeys
{
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)viewConnection->view->options;
	
	if (searchResultsOptions.snippetOptions == nil) {
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
					[query appendFormat:@"?"];
				else
					[query appendFormat:@", ?"];
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
				sqlite3_bind_int64(statement, (int)(i+1), rowid);
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
	
	if (searchResultsOptions.snippetOptions == nil) {
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
			YDBLogError(@"%@ (%@): Error in snippetStatement: %d %s",
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

- (void)commitTransaction
{
	YDBLogAutoTrace();
	
	// If the query was changed, then we need to write it to the yap table.
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	NSString *query = nil;
	BOOL queryChanged = NO;
	[searchResultsViewConnection getQuery:&query wasChanged:&queryChanged];
	
	if (queryChanged)
	{
		[self setStringValue:query forExtensionKey:ExtKey_query];
	}
	
	// This must be done LAST.
	[super commitTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtensionTransaction_Hooks
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
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = parentViewTransaction->lastHandledGroup;
		
		if (group)
		{
			NSSet *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups containsObject:group])
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
		
		NSSet *allowedCollections = searchResultsOptions.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:collection])
		{
			if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object, metadata);
			}
		}
	}
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
	}
	
	if (matchesQuery)
	{
		// Add to view.
		// This was an insert operation, so we know it wasn't already in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group withChanges:flags isNew:YES];
		
		lastHandledGroup = group;
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// This was an insert operation, so we know it wasn't already in the view.
		
		lastHandledGroup = nil;
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
	
	NSString *group = nil;
	
	if (searchResultsView->parentViewName)
	{
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		group = parentViewTransaction->lastHandledGroup;
		
		if (group)
		{
			NSSet *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups containsObject:group])
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
		
		NSSet *allowedCollections = searchResultsOptions.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:collection])
		{
			if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object);
			}
			else if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
				
				group = groupingBlock(collection, key, object, metadata);
			}
		}
	}
	
	BOOL matchesQuery = NO;
	
	if (group)
	{
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
	}
	
	if (matchesQuery)
	{
		// Add key to view (or update position).
		// This was an update operation, so the key may have previously been in the view.
		
		int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
		
		[self insertRowid:rowid
		    collectionKey:collectionKey
		           object:object
		         metadata:metadata
		          inGroup:group
		      withChanges:flags
		            isNew:NO];
		
		lastHandledGroup = group;
	}
	else
	{
		// Not in view (not in parentView, or groupingBlock said NO, or doesn't match query).
		// Remove from view (if needed).
		// This was an update operation, so it may have previously been in the view.
		
		[self removeRowid:rowid collectionKey:collectionKey];
		lastHandledGroup = nil;
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
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                           searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject;
		
		BOOL sortMayHaveChanged = searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                          searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject;
		
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = parentViewTransaction->lastHandledGroup;
		
		if (group)
		{
			NSSet *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups containsObject:group])
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
			
			lastHandledGroup = nil;
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = fts->blockType == YapDatabaseFullTextSearchBlockTypeWithRow ||
		                            fts->blockType == YapDatabaseFullTextSearchBlockTypeWithObject;
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			int flags = YapDatabaseViewChangedObject;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			[viewConnection->changes addObject:
			 [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			
			lastHandledGroup = group;
			return;
		}
		
		BOOL matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		
		if (matchesQuery)
		{
			// Add to view (or update position).
			// This was an update operation, so it may have previously been in the view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id metadata = nil;
			if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
			    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
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
			
			lastHandledGroup = group;
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so it may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
			lastHandledGroup = nil;
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id metadata = nil;
		NSString *group = nil;
		
		if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey ||
			searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
		{
			// Grouping is based on the key or metadata.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [self groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// It wasn't previously in the view, and still isn't in the view.
			}
			else if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
			         searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				int flags = YapDatabaseViewChangedObject;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			}
			else
			{
				// Sorting is based on the object, which has changed.
				// So the sort order may possibly have changed.
				
				// From previous if statement (above) we know:
				// sortingBlockType is object or row (object+metadata)
				
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedObject;
				
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
			
			NSSet *allowedCollections = searchResultsOptions.allowedCollections;
			
			if (!allowedCollections || [allowedCollections containsObject:collection])
			{
				if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			          (YapDatabaseViewGroupingWithObjectBlock)searchResultsView->groupingBlock;
					
					group = groupingBlock(collection, key, object);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
					
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(collection, key, object, metadata);
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
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
				    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
				{
					// Sorting is based on the key or metadata, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [self groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change,
						// and the sort order cannot change (because the key/metadata didn't change).
						
						int flags = YapDatabaseViewChangedObject;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateKey:collectionKey
						                              changes:flags
						                              inGroup:group
						                              atIndex:existingIndex]];
						
						lastHandledGroup = group;
						return;
					}
				}
				
				if (metadata == nil && (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
				                        searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata))
				{
					// Need the metadata for the sorting block
					metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedObject;
				
				[self insertRowid:rowid
				    collectionKey:collectionKey
				           object:object
				         metadata:metadata
				          inGroup:group withChanges:flags isNew:NO];
			}
		}
		
		lastHandledGroup = group;
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
	
	if (searchResultsView->parentViewName)
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseFilteredViewTransaction.
		
		BOOL groupMayHaveChanged = searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                           searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata;
		
		BOOL sortMayHaveChanged = searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
		                          searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata;
		
		// Instead of going to the groupingBlock,
		// just ask the parentViewTransaction what the last group was.
		
		__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
		  [databaseTransaction ext:searchResultsView->parentViewName];
		
		NSString *group = parentViewTransaction->lastHandledGroup;
		
		if (group)
		{
			NSSet *allowedGroups = searchResultsOptions.allowedGroups;
			if (allowedGroups && ![allowedGroups containsObject:group])
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
			
			lastHandledGroup = nil;
			return;
		}
		
		__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
		  [databaseTransaction ext:searchResultsView->fullTextSearchName];
		
		__unsafe_unretained YapDatabaseFullTextSearch *fts =
		  (YapDatabaseFullTextSearch *)[[ftsTransaction extensionConnection] extension];
		
		BOOL searchMayHaveChanged = fts->blockType == YapDatabaseFullTextSearchBlockTypeWithRow ||
		                            fts->blockType == YapDatabaseFullTextSearchBlockTypeWithObject;
		
		if (!groupMayHaveChanged && !sortMayHaveChanged && !searchMayHaveChanged)
		{
			// Nothing has changed that could possibly affect the view.
			// Just note the touch.
			
			int flags = YapDatabaseViewChangedMetadata;
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
			
			[viewConnection->changes addObject:
			  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			
			lastHandledGroup = group;
			return;
		}
		
		BOOL matchesQuery = [ftsTransaction rowid:rowid matches:[self query]];
		
		if (matchesQuery)
		{
			// Add key to view (or update position).
			// This was an update operation, so the key may have previously been in the view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			id object= nil;
			if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
			    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
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
			
			lastHandledGroup = group;
		}
		else
		{
			// Filtered from this view.
			// Remove key from view (if needed).
			// This was an update operation, so the key may have previously been in the view.
			
			[self removeRowid:rowid collectionKey:collectionKey];
			lastHandledGroup = nil;
		}
	}
	else
	{
		// Implementation Note:
		// This code is modeled after that in YapDatabaseViewTransaction.
		
		id object = nil;
		NSString *group = nil;
		
		if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithKey ||
		    searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
		{
			// Grouping is based on the key or object.
			// Neither have changed, and thus the group hasn't changed.
			
			NSString *pageKey = [self pageKeyForRowid:rowid];
			group = [self groupForPageKey:pageKey];
			
			if (group == nil)
			{
				// Nothing to do.
				// The key wasn't previously in the view, and still isn't in the view.
			}
			else if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
			         searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				// Nothing has moved because the group hasn't changed and
				// nothing has changed that relates to sorting.
				
				int flags = YapDatabaseViewChangedMetadata;
				NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:pageKey];
				
				[viewConnection->changes addObject:
				  [YapDatabaseViewRowChange updateKey:collectionKey changes:flags inGroup:group atIndex:existingIndex]];
			}
			else
			{
				// Sorting is based on the metadata, which has changed.
				// So the sort order may possibly have changed.
				
				// From previous if statement (above) we know:
				// sortingBlockType is metadata or objectAndMetadata
				
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedMetadata;
				
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
			
			NSSet *allowedCollections = searchResultsOptions.allowedCollections;
			
			if (!allowedCollections || [allowedCollections containsObject:collection])
			{
				if (searchResultsView->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
				{
					__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			          (YapDatabaseViewGroupingWithMetadataBlock)searchResultsView->groupingBlock;
					
					group = groupingBlock(collection, key, metadata);
				}
				else
				{
					__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			          (YapDatabaseViewGroupingWithRowBlock)searchResultsView->groupingBlock;
					
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
					group = groupingBlock(collection, key, object, metadata);
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
				if (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithKey ||
				    searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
				{
					// Sorting is based on the key or object, neither of which has changed.
					// So if the group hasn't changed, then the sort order hasn't changed.
					
					NSString *existingPageKey = [self pageKeyForRowid:rowid];
					NSString *existingGroup = [self groupForPageKey:existingPageKey];
					
					if ([group isEqualToString:existingGroup])
					{
						// Nothing left to do.
						// The group didn't change,
						// and the sort order cannot change (because the key/object didn't change).
						
						int flags = YapDatabaseViewChangedMetadata;
						NSUInteger existingIndex = [self indexForRowid:rowid inGroup:group withPageKey:existingPageKey];
						
						[viewConnection->changes addObject:
						  [YapDatabaseViewRowChange updateKey:collectionKey
						                              changes:flags
						                              inGroup:group
						                              atIndex:existingIndex]];
						
						lastHandledGroup = group;
						return;
					}
				}
				
				if (object == nil && (searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithRow ||
				                      searchResultsView->sortingBlockType == YapDatabaseViewBlockTypeWithObject))
				{
					// Need the object for the sorting block
					object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
				}
				
				int flags = YapDatabaseViewChangedMetadata;
				
				[self insertRowid:rowid
					collectionKey:collectionKey
						   object:object
						 metadata:metadata
						  inGroup:group withChanges:flags isNew:NO];
			}
		}
		
		lastHandledGroup = group;
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
	
	[extensionDependencies enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
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

- (void)setGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
       groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
            sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
        sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
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
		[super setGroupingBlock:inGroupingBlock
		      groupingBlockType:inGroupingBlockType
		           sortingBlock:inSortingBlock
		       sortingBlockType:inSortingBlockType
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
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseViewTransaction *parentViewTransaction =
	  (YapDatabaseViewTransaction *)[databaseTransaction ext:searchResultsView->parentViewName];
	
	BOOL wasEmpty = [self isEmpty];
	
	id <NSFastEnumeration> groupsToEnumerate = nil;
	
	if (searchResultsOptions.allowedGroups) {
		groupsToEnumerate = searchResultsOptions.allowedGroups;
	}
	else {
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
				if (existing && (existingRowid == rowid))
				{
					// The row was previously in the view (in old search results),
					// and is still in the view (in new search results).
					
					index++;
					existing = [self getRowid:&existingRowid atIndex:index inGroup:group];
				}
				else
				{
					// The row was not previously in the view (not in old search results),
					// but is now in the view (in new search results).
					
					YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
					
					if (index == 0 && ([viewConnection->group_pagesMetadata_dict objectForKey:group] == nil)) {
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
		}];
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
	
	// Create a copy of the ftsRowids set.
	// As we enumerate the existing rowids in our view, we're going to
	YapRowidSet *ftsRowidsLeft = YapRowidSetCopy(ftsRowids);
	
	for (NSString *group in [self allGroups])
	{
		__block NSUInteger groupCount = [self numberOfKeysInGroup:group];
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
			}];
			
		} while (!done);
		
	} // end for (NSString *group in [self allGroups])
	
	
	// Now enumerate any items in ftsRowidsLeft
	
	__unsafe_unretained YapDatabaseView *view = viewConnection->view;
	
	YapRowidSetEnumerate(ftsRowidsLeft, ^(int64_t rowid, BOOL *stop) { @autoreleasepool {
		
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		
		id object = nil;
		id metadata = nil;
		
		// Invoke the grouping block to find out if the object should be included in the view.
		
		NSString *group = nil;
		NSSet *allowedCollections = view->options.allowedCollections;
		
		if (!allowedCollections || [allowedCollections containsObject:ck.collection])
		{
			if (view->groupingBlockType == YapDatabaseViewBlockTypeWithKey)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithKeyBlock groupingBlock =
			      (YapDatabaseViewGroupingWithKeyBlock)view->groupingBlock;
				
				group = groupingBlock(ck.collection, ck.key);
			}
			else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithObjectBlock groupingBlock =
			      (YapDatabaseViewGroupingWithObjectBlock)view->groupingBlock;
				
				object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, object);
			}
			else if (view->groupingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				__unsafe_unretained YapDatabaseViewGroupingWithMetadataBlock groupingBlock =
			      (YapDatabaseViewGroupingWithMetadataBlock)view->groupingBlock;
				
				metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, metadata);
			}
			else
			{
				__unsafe_unretained YapDatabaseViewGroupingWithRowBlock groupingBlock =
			      (YapDatabaseViewGroupingWithRowBlock)view->groupingBlock;
				
				[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
				
				group = groupingBlock(ck.collection, ck.key, object, metadata);
			}
		}
		
		if (group)
		{
			// Add to view.
			
			int flags = (YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata);
			
			if (view->sortingBlockType == YapDatabaseViewBlockTypeWithObject)
			{
				if (object == nil)
					object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithMetadata)
			{
				if (metadata == nil)
					metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			}
			else if (view->sortingBlockType == YapDatabaseViewBlockTypeWithRow)
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
	}});
	
	// Dealloc the temporary c++ set
	if (ftsRowidsLeft) {
		YapRowidSetRelease(ftsRowidsLeft);
	}
}

- (void)performSearchFor:(NSString *)query
{
	YDBLogAutoTrace();
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return;
	}
	
	YapRowidSetRemoveAll(ftsRowids);
	
	__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView =
	  (YapDatabaseSearchResultsView *)viewConnection->view;
	
	__unsafe_unretained YapDatabaseSearchResultsViewOptions *searchResultsOptions =
	  (YapDatabaseSearchResultsViewOptions *)searchResultsView->options;
	
	__unsafe_unretained YapDatabaseFullTextSearchTransaction *ftsTransaction =
	  (YapDatabaseFullTextSearchTransaction *)[databaseTransaction ext:searchResultsView->fullTextSearchName];
	
	if (searchResultsOptions.snippetOptions)
	{
		// Need to get matching rowids and related snippets.
		
		if (snippets == nil)
			snippets = [[NSMutableDictionary alloc] init];
		else
			[snippets removeAllObjects];
		
		[ftsTransaction enumerateRowidsMatching:query
		                     withSnippetOptions:searchResultsOptions.snippetOptions
		                             usingBlock:^(NSString *snippet, int64_t rowid, BOOL *stop)
		{
			YapRowidSetAdd(ftsRowids, rowid);
			
			if (snippet)
				[snippets setObject:snippet forKey:@(rowid)];
			else
				[snippets setObject:[NSNull null] forKey:@(rowid)];
		}];
	}
	else
	{
		// No snippets. Just get the matching rowids.
		
		[ftsTransaction enumerateRowidsMatching:query usingBlock:^(int64_t rowid, BOOL *stop) {
			
			YapRowidSetAdd(ftsRowids, rowid);
		}];
	}
	
	if (searchResultsView->parentViewName)
		[self updateViewFromParent];
	else
		[self updateViewUsingBlocks];
	
	__unsafe_unretained YapDatabaseSearchResultsViewConnection *searchResultsViewConnection =
	  (YapDatabaseSearchResultsViewConnection *)viewConnection;
	
	[searchResultsViewConnection setQuery:query isChange:YES];
}

- (void)performSearchWithQueue:(YapDatabaseSearchQueue *)queue
{
	// TODO: Implement me
}

@end
