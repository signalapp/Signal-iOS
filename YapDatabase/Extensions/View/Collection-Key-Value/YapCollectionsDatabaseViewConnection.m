#import "YapCollectionsDatabaseViewConnection.h"
#import "YapCollectionsDatabaseViewPrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
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

- (id)initWithExtension:(YapAbstractDatabaseExtension *)inExtension
     databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super initWithExtension:inExtension databaseConnection:inDatabaseConnection]))
	{
		keyCache = [[YapCache alloc] initWithKeyClass:[YapCollectionKey class]];
		pageCache = [[YapCache alloc] initWithKeyClass:[NSString class]];
	}
	return self;
}

- (YapCollectionsDatabaseView *)view
{
	return (YapCollectionsDatabaseView *)extension;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapCollectionsDatabaseViewTransaction alloc] initWithExtensionConnection:self
	                                                              databaseTransaction:databaseTransaction];
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	YapCollectionsDatabaseViewTransaction *transaction =
	    [[YapCollectionsDatabaseViewTransaction alloc] initWithExtensionConnection:self
	                                                           databaseTransaction:databaseTransaction];
	
	if (dirtyKeys == nil)
		dirtyKeys = [[NSMutableDictionary alloc] init];
	if (dirtyPages == nil)
		dirtyPages = [[NSMutableDictionary alloc] init];
	if (dirtyMetadata == nil)
		dirtyMetadata = [[NSMutableDictionary alloc] init];
	if (operations == nil)
		operations = [[NSMutableArray alloc] init];
	
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)keyTableName
{
	return [(YapCollectionsDatabaseView *)extension keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapCollectionsDatabaseView *)extension pageTableName];
}

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
	
	[operations removeAllObjects];
}

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
	
	// The operations log is copied into the external changeset.
	// So it's safe to simply reset.
	
	[operations removeAllObjects];
	
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
	
	if ([operations count])
	{
		externalChangeset = [NSMutableDictionary dictionaryWithCapacity:1];
		
  		[externalChangeset setObject:[operations copy] forKey:@"operations"];
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
			else
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
			else
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - KeyTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)keyTable_getPageKeyForCollectionKeyStatement
{
	if (keyTable_getPageKeyForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ? ;", [self keyTableName]];
		
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
		    [self keyTableName]];
		
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
		    @"SELECT \"key\", \"pageKey\" FROM \"%@\" WHERE \"collection\" = ?;", [self keyTableName]];
		
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
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ?;", [self keyTableName]];
		
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
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ?;", [self keyTableName]];
		
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
		    @"DELETE FROM \"%@\";", [self keyTableName]];
		
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
		    @"SELECT \"data\" FROM \"%@\" WHERE \"pageKey\" = ? ;", [self pageTableName]];
		
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
		    [self pageTableName]];
		
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
		    @"UPDATE \"%@\" SET \"metadata\" = ? WHERE \"pageKey\" = ?;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
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
		    @"DELETE FROM \"%@\" WHERE \"pageKey\" = ?;", [self pageTableName]];
		
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
		    @"DELETE FROM \"%@\";", [self pageTableName]];
		
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
