#import "YapCollectionsDatabaseViewConnection.h"
#import "YapCollectionsDatabaseViewPrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapCollectionKey.h"
#import "YapCache.h"
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


@implementation YapCollectionsDatabaseViewConnection
{
	sqlite3_stmt *keyTable_getPageKeyForCollectionKeyStatement;
	sqlite3_stmt *keyTable_setPageKeyForCollectionKeyStatement;
	sqlite3_stmt *keyTable_enumerateForCollectionStatement;
	sqlite3_stmt *keyTable_removeForCollectionKeyStatement;
	sqlite3_stmt *keyTable_removeForCollectionStatement;
	sqlite3_stmt *keyTable_removeAllStatement;
	
	sqlite3_stmt *pageTable_getDataForPageKeyStatement;
	sqlite3_stmt *pageTable_setAllForPageKeyStatement;
	sqlite3_stmt *pageTable_setMetadataForPageKeyStatement;
	sqlite3_stmt *pageTable_removeForPageKeyStatement;
	sqlite3_stmt *pageTable_removeAllStatement;
}

@synthesize view = view;

- (id)initWithView:(YapCollectionsDatabaseView *)inView databaseConnection:(YapCollectionsDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		view = inView;
		databaseConnection = inDbC;
		
		keyCache = [[YapCache alloc] initWithKeyClass:[YapCollectionKey class]];
		pageCache = [[YapCache alloc] initWithKeyClass:[NSString class]];
	}
	return self;
}

- (void)dealloc
{
	sqlite_finalize_null(&keyTable_getPageKeyForCollectionKeyStatement);
	sqlite_finalize_null(&keyTable_setPageKeyForCollectionKeyStatement);
	sqlite_finalize_null(&keyTable_enumerateForCollectionStatement);
	sqlite_finalize_null(&keyTable_removeForCollectionKeyStatement);
	sqlite_finalize_null(&keyTable_removeForCollectionStatement);
	sqlite_finalize_null(&keyTable_removeAllStatement);
	
	sqlite_finalize_null(&pageTable_getDataForPageKeyStatement);
	sqlite_finalize_null(&pageTable_setAllForPageKeyStatement);
	sqlite_finalize_null(&pageTable_setMetadataForPageKeyStatement);
	sqlite_finalize_null(&pageTable_removeForPageKeyStatement);
	sqlite_finalize_null(&pageTable_removeAllStatement);
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection
**/
- (void)_flushMemoryWithLevel:(int)level
{
	if (level >= YapDatabaseConnectionFlushMemoryLevelMild)
	{
		[keyCache removeAllObjects];
		[pageCache removeAllObjects];
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&keyTable_setPageKeyForCollectionKeyStatement);
		sqlite_finalize_null(&keyTable_enumerateForCollectionStatement);
		sqlite_finalize_null(&keyTable_removeForCollectionKeyStatement);
		sqlite_finalize_null(&keyTable_removeForCollectionStatement);
		sqlite_finalize_null(&keyTable_removeAllStatement);
		
		sqlite_finalize_null(&pageTable_setAllForPageKeyStatement);
		sqlite_finalize_null(&pageTable_setMetadataForPageKeyStatement);
		sqlite_finalize_null(&pageTable_removeForPageKeyStatement);
		sqlite_finalize_null(&pageTable_removeAllStatement);
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
		sqlite_finalize_null(&keyTable_getPageKeyForCollectionKeyStatement);
		
		sqlite_finalize_null(&pageTable_getDataForPageKeyStatement);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapAbstractDatabaseExtension *)extension
{
	return view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	YapCollectionsDatabaseViewTransaction *transaction =
	    [[YapCollectionsDatabaseViewTransaction alloc] initWithViewConnection:self
	             databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	YapCollectionsDatabaseViewTransaction *transaction =
	    [[YapCollectionsDatabaseViewTransaction alloc] initWithViewConnection:self
	             databaseTransaction:(YapCollectionsDatabaseReadTransaction *)databaseTransaction];
	
	if (dirtyKeys == nil)
		dirtyKeys = [[NSMutableDictionary alloc] init];
	if (dirtyPages == nil)
		dirtyPages = [[NSMutableDictionary alloc] init];
	if (dirtyMetadata == nil)
		dirtyMetadata = [[NSMutableDictionary alloc] init];
	if (changes == nil)
		changes = [[NSMutableArray alloc] init];
	if (mutatedGroups == nil)
		mutatedGroups = [[NSMutableSet alloc] init];
	
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableDictionary *)group_pagesMetadata_dict_deepCopy:(NSDictionary *)in_group_pagesMetadata_dict
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[in_group_pagesMetadata_dict count]];
	
	[in_group_pagesMetadata_dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSString *group = (NSString *)key;
		__unsafe_unretained NSMutableArray *pagesMetadata = (NSMutableArray *)obj;
		
		// We need a mutable copy of the pages array,
		// and we need a copy of each YapDatabaseViewPageMetadata object within the pages array.
		
		NSMutableArray *pagesMetadataDeepCopy = [[NSMutableArray alloc] initWithArray:pagesMetadata copyItems:YES];
		
		[deepCopy setObject:pagesMetadataDeepCopy forKey:group];
	}];
	
	return deepCopy;
}

- (NSMutableDictionary *)dirtyPagesDeepCopy:(NSDictionary *)inDirtyPages
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[inDirtyPages count]];
	
	[inDirtyPages enumerateKeysAndObjectsUsingBlock:^(id pageKeyObj, id pageObj, BOOL *stop) {
		
		__unsafe_unretained NSString *pageKey = (NSString *)pageKeyObj;
		__unsafe_unretained NSMutableArray *page = (NSMutableArray *)pageObj;
		
		// We need a mutable copy of the page array,
		// but we don't have to copy all the immutable collectionKeys within the page.
		
		NSMutableArray *pageDeepCopy = [[NSMutableArray alloc] initWithArray:page copyItems:NO];
		
		[deepCopy setObject:pageDeepCopy forKey:pageKey];
	}];
	
	return deepCopy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapAbstractDatabaseConnection
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	group_pagesMetadata_dict = nil;
	pageKey_group_dict = nil;
	
	[keyCache removeAllObjects];
	[pageCache removeAllObjects];
	
	[dirtyKeys removeAllObjects];
	[dirtyPages removeAllObjects];
	[dirtyMetadata removeAllObjects];
	reset = NO;
	
	[changes removeAllObjects];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
 * This code is best understood alongside the getExternalChangeset:internalChangeset: method (below).
**/
- (void)postCommitCleanup
{
	// Both dirtyKeys & dirtyPages are sent in the internalChangeset.
	// So we need completely new versions of them.
	
	if ([dirtyKeys count] > 0)
		dirtyKeys = nil;
	
	if ([dirtyPages count] > 0)
		dirtyPages = nil;
	
	// dirtyMetadata isn't part of the changeset.
	// So it's safe to simply reset.
	
	[dirtyMetadata removeAllObjects];
	
	// The changes log is copied into the external changeset.
	// So it's safe to simply reset.
	
	[changes removeAllObjects];
	[mutatedGroups removeAllObjects];
	
	reset = NO;
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	
	if ([dirtyKeys count] || [dirtyPages count] || [dirtyMetadata count] || reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithCapacity:5];
		
		if ([dirtyKeys count] > 0)
		{
			[internalChangeset setObject:dirtyKeys forKey:@"dirtyKeys"];
		}
		if ([dirtyPages count] > 0)
		{
			[internalChangeset setObject:dirtyPages forKey:@"dirtyPages"];
		}
		
		if (reset)
		{
			[internalChangeset setObject:@(reset) forKey:@"reset"];
		}
		
		NSMutableDictionary *group_pagesMetadata_dict_copy;
		NSMutableDictionary *pageKey_group_dict_copy;
		
		group_pagesMetadata_dict_copy = [self group_pagesMetadata_dict_deepCopy:group_pagesMetadata_dict];
		pageKey_group_dict_copy = [pageKey_group_dict mutableCopy];
		
		[internalChangeset setObject:group_pagesMetadata_dict_copy forKey:@"group_pagesMetadata_dict"];
		[internalChangeset setObject:pageKey_group_dict_copy       forKey:@"pageKey_group_dict"];
	}
	
	if ([changes count])
	{
		externalChangeset = [NSMutableDictionary dictionaryWithCapacity:1];
		
  		[externalChangeset setObject:[changes copy] forKey:@"changes"];
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *changeset_group_pagesMetadata_dict = [changeset objectForKey:@"group_pagesMetadata_dict"];
	NSMutableDictionary *changeset_pageKey_group_dict = [changeset objectForKey:@"pageKey_group_dict"];
	
	NSDictionary *changeset_dirtyKeys = [changeset objectForKey:@"dirtyKeys"];
	NSDictionary *changeset_dirtyPages = [changeset objectForKey:@"dirtyPages"];
	
	BOOL changeset_reset = [[changeset objectForKey:@"reset"] boolValue];
	
	// Process new top level objects
	
	group_pagesMetadata_dict = [self group_pagesMetadata_dict_deepCopy:changeset_group_pagesMetadata_dict];
	pageKey_group_dict = [changeset_pageKey_group_dict mutableCopy];
	
	// Update keyCache
	
	if (changeset_reset && ([changeset_dirtyKeys count] == 0))
	{
		[keyCache removeAllObjects];
	}
	else if ([changeset_dirtyKeys count])
	{
		NSUInteger removeCapacity = [keyCache count];
		NSUInteger updateCapacity = MIN([keyCache count], [changeset_dirtyKeys count]);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[keyCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_dirtyKeys objectForKey:key])
				[keysToUpdate addObject:key];
			else if (changeset_reset)
				[keysToRemove addObject:key];
		}];
		
		[keyCache removeObjectsForKeys:keysToRemove];
		
		NSNull *nsnull = [NSNull null];
		
		for (NSString *key in keysToUpdate)
		{
			id pageKey = [changeset_dirtyKeys objectForKey:key];
			
			if (pageKey == nsnull)
				[keyCache removeObjectForKey:key];
			else
				[keyCache setObject:pageKey forKey:key];
		}
	}
	
	// Update pageCache
	
	if (changeset_reset && ([changeset_dirtyPages count] == 0))
	{
		[pageCache removeAllObjects];
	}
	else if ([changeset_dirtyPages count])
	{
		NSUInteger removeCapacity = [pageCache count];
		NSUInteger updateCapacity = MIN([pageCache count], [changeset_dirtyPages count]);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[pageCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_dirtyPages objectForKey:key])
				[keysToUpdate addObject:key];
			else if (changeset_reset)
				[keysToRemove addObject:key];
		}];
		
		[pageCache removeObjectsForKeys:keysToRemove];
		
		NSNull *nsnull = [NSNull null];
		
		for (NSString *pageKey in keysToUpdate)
		{
			id page = [changeset_dirtyPages objectForKey:pageKey];
			
			// Each viewConnection needs its own independent mutable copy of the page.
			// Mutable pages cannot be shared between multiple view connections.
			
			if (page == nsnull)
				[pageCache removeObjectForKey:pageKey];
			else
				[pageCache setObject:[page mutableCopy] forKey:pageKey];
		}
	}
}

/**
 * Gets an exact list of changes that happend to the view, translating groups to sections as requested.
 * See the header file for more information.
**/
- (void)getSectionChanges:(NSArray **)sectionChangesPtr
               rowChanges:(NSArray **)rowChangesPtr
         forNotifications:(NSArray *)notifications
             withMappings:(YapDatabaseViewMappings *)mappings
{
	if (mappings == nil)
	{
		YDBLogWarn(@"%@ - mappings parameter is nil", THIS_METHOD);
		
		if (sectionChangesPtr) *sectionChangesPtr = nil;
		if (rowChangesPtr) *rowChangesPtr = nil;
		
		return;
	}
	if (mappings.snapshotOfLastUpdate == UINT64_MAX)
	{
		NSString *reason = [NSString stringWithFormat:
		    @"ViewConnection[%p, RegisteredName=%@] was asked for changes, but given bad mappings.",
			self, view.registeredName];
		
		NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
		    @"The given mappings have not been properly initialized."
			@" You need to invoke [mappings updateWithTransaction:transaction] once in order to initialize"
			@" the mappings object. It is recommended you do this after invoking"
			@" [databaseConnection beginLongLivedReadTransaction]. For example code, please see"
			@" YapDatabaseViewMappings.h, or see the wiki: https://github.com/yaptv/YapDatabase/wiki/Views"};
	
		@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	}
	
	NSString *registeredName = self.view.registeredName;
	NSMutableArray *all_changes = [NSMutableArray array];
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:@"changes"];
		
		[all_changes addObjectsFromArray:changeset_changes];
	}
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	__block BOOL isLongLivedReadTransaction = NO;
	
	[databaseConnection readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction) {
		
		isLongLivedReadTransaction = transaction.connection.isInLongLivedReadTransaction;
		[mappings updateWithTransaction:transaction];
	}];
	
	if ([notifications count] > 0)
	{
		NSDictionary *firstChangeset = [notifications objectAtIndex:0];
		NSDictionary *lastChangeset = [notifications lastObject];
		
		uint64_t firstSnapshot = [[firstChangeset objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
		uint64_t lastSnapshot  = [[lastChangeset  objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
		
		if ((originalMappings.snapshotOfLastUpdate != (firstSnapshot - 1)) ||
		    (mappings.snapshotOfLastUpdate != lastSnapshot))
		{
			NSString *reason = [NSString stringWithFormat:
			    @"ViewConnection[%p, RegisteredName=%@] was asked for changes,"
				@" but given mismatched mappings & notifications.", self, view.registeredName];
			
			NSString *failureReason = [NSString stringWithFormat:
			    @"preMappings.snapshotOfLastUpdate: expected(%llu) != found(%llu), "
				@"postMappings.snapshotOfLastUpdate: expected(%llu) != found(%llu), "
				@"isLongLivedReadTransaction = %@",
				originalMappings.snapshotOfLastUpdate, (firstSnapshot - 1),
				mappings.snapshotOfLastUpdate, lastSnapshot,
				(isLongLivedReadTransaction ? @"YES" : @"NO")];
			
			NSString *suggestion = [NSString stringWithFormat:
			    @"When you initialize the database, the snapshot (uint64) is set to zero."
				@" Every read-write transaction (that makes modifications) increments the snapshot."
				@" Now, when you ask the viewConnection for a changeset, "
				@" you need to pass matching mappings & notifications. That is, the mappings need to represent the"
				@" database at snapshot X, and the notifications need to represent the database at snapshots"
				@" @[ X+1, X+2, ...]. This does not appear to be the case. This most often happens when the"
				@" databaseConnection isn't using a longLivedReadTransaction. And this happens by accident"
				@" most often when you use a databaseConnection, which is in a longLivedReadTransaction, to perform"
				@" a read-write transaction. Doing so implicitly forces the connection out of the"
				@" longLivedReadTransaction, and moves it to the most recent snapshot. If this is the case,"
				@" be sure to use a separate connection for your read-write transaction."];
			
			NSDictionary *userInfo = @{
				NSLocalizedFailureReasonErrorKey: failureReason,
				NSLocalizedRecoverySuggestionErrorKey: suggestion };
		
			// If we don't throw the exception here,
			// then you'll just get an exception later from the tableView or collectionView.
			// It will look something like this:
			//
			// > Invalid update: invalid number of rows in section X. The number of rows contained in an
			// > existing section after the update (Y) must be equal to the number of rows contained in that section
			// > before the update (Z), plus or minus the number of rows inserted or deleted from that
			// > section (# inserted, # deleted).
			//
			// In order to guarantee you DON'T get an exception (either from YapDatabase or from Apple),
			// then you need to follow the instructions for setting up your connection, mappings, & notifications.
			//
			// For complete code samples, check out the wiki:
			// https://github.com/yaptv/YapDatabase/wiki/Views
			//
			// You may be tempted to simply comment out the exception below.
			// If you do, you're not fixing the root cause of your problem.
			// Furthermore, you're simply trading this exception, which comes with documented steps on how
			// to fix the problem, for an exception from Apple which will be even harder to diagnose.
			
			@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
		}
		
		if (!isLongLivedReadTransaction)
		{
			YDBLogWarn(@"%@ - The databaseConnection is NOT in a longLivedReadTransaction."
			           @" It needs to be in order to guarantee"
					   @" (A) you can provide a stable data-source for your UI thread and"
					   @" (B) you can get changesets which match the movement from one"
					   @" stable data-source state to another. If you think your databaseConnection IS"
					   @" in a longLivedReadTransaction, then perhaps you aborted it by accident."
					   @" This generally happens when you use a databaseConnection,"
					   @" which is in a longLivedReadTransaction, to perform a read-write transaction."
					   @" Doing so implicitly forces the connection out of the longLivedReadTransaction,"
					   @" and moves it to the most recent snapshot. If this is the case,"
					   @" be sure to use a separate connection for your read-write transaction.", THIS_METHOD);
		}
	}
	
	[YapDatabaseViewChange getSectionChanges:sectionChangesPtr
	                              rowChanges:rowChangesPtr
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:all_changes];
}

/**
 * A simple YES/NO query to see if the view changed at all, inclusive of all groups.
**/
- (BOOL)hasChangesForNotifications:(NSArray *)notifications
{
	NSString *registeredName = self.view.registeredName;
	
	for (NSNotification *notification in notifications)
	{
		NSDictionary *changeset =
		    [[notification.userInfo objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
		
		NSArray *changeset_changes = [changeset objectForKey:@"changes"];
		
		if ([changeset_changes count] > 0)
		{
			return YES;
		}
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - KeyTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)keyTable_getPageKeyForCollectionKeyStatement
{
	if (keyTable_getPageKeyForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ? ;", [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_getPageKeyForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_getPageKeyForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_setPageKeyForCollectionKeyStatement
{
	if (keyTable_setPageKeyForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"collection\", \"key\", \"pageKey\") VALUES (?, ?, ?);", 
		    [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_setPageKeyForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_setPageKeyForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_enumerateForCollectionStatement
{
	if (keyTable_enumerateForCollectionStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"key\", \"pageKey\" FROM \"%@\" WHERE \"collection\" = ?;", [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_enumerateForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_enumerateForCollectionStatement;
}

- (sqlite3_stmt *)keyTable_removeForCollectionKeyStatement
{
	if (keyTable_removeForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ?;", [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeForCollectionStatement
{
	if (keyTable_removeForCollectionStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ?;", [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForCollectionStatement;
}

- (sqlite3_stmt *)keyTable_removeAllStatement
{
	if (keyTable_removeAllStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [view keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeAllStatement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - PageTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement
{
	if (pageTable_getDataForPageKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"data\" FROM \"%@\" WHERE \"pageKey\" = ? ;", [view pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_getDataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setAllForPageKeyStatement
{
	if (pageTable_setAllForPageKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"pageKey\", \"data\", \"metadata\") VALUES (?, ?, ?);",
		    [view pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_setAllForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setAllForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setMetadataForPageKeyStatement
{
	if (pageTable_setMetadataForPageKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"UPDATE \"%@\" SET \"metadata\" = ? WHERE \"pageKey\" = ?;", [view pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_setMetadataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setMetadataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeForPageKeyStatement
{
	if (pageTable_removeForPageKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"pageKey\" = ?;", [view pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}

	}
	
	return pageTable_removeForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeAllStatement
{
	if (pageTable_removeAllStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [view pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_removeAllStatement;
}

@end
