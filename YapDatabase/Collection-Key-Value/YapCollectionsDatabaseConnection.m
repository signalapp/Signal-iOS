#import "YapCollectionsDatabaseConnection.h"
#import "YapCollectionsDatabasePrivate.h"

#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"

#import "YapCollectionKey.h"
#import "YapCache.h"
#import "YapNull.h"
#import "YapSet.h"

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
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapCollectionsDatabaseConnection {

/* As defined in YapCollectionsDatabasePrivate.h :

@private
	sqlite3_stmt *getCollectionCountStatement;
	sqlite3_stmt *getKeyCountForCollectionStatement;
	sqlite3_stmt *getKeyCountForAllStatement;
	sqlite3_stmt *getCountForKeyStatement;
	sqlite3_stmt *getDataForKeyStatement;
	sqlite3_stmt *getMetadataForKeyStatement;
	sqlite3_stmt *getAllForKeyStatement;
	sqlite3_stmt *setAllForKeyStatement;
	sqlite3_stmt *setMetaForKeyStatement;
	sqlite3_stmt *removeForKeyStatement;
	sqlite3_stmt *removeCollectionStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *enumerateCollectionsStatement;
	sqlite3_stmt *enumerateKeysInCollectionStatement;
    sqlite3_stmt *enumerateKeysInAllCollectionsStatement;
	sqlite3_stmt *enumerateMetadataInCollectionStatement;
	sqlite3_stmt *enumerateMetadataInAllCollectionsStatement;
	sqlite3_stmt *enumerateAllInCollectionStatement;
	sqlite3_stmt *enumerateAllInAllCollectionsStatement;

*/
/* Defined in YapAbstractDatabasePrivate.h:

@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
@public
	sqlite3 *db;
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL needsMarkSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.
*/
}

- (void)dealloc
{
	sqlite_finalize_null(&getCollectionCountStatement);
	sqlite_finalize_null(&getKeyCountForCollectionStatement);
	sqlite_finalize_null(&getKeyCountForAllStatement);
	sqlite_finalize_null(&getCountForKeyStatement);
	sqlite_finalize_null(&getDataForKeyStatement);
	sqlite_finalize_null(&setMetaForKeyStatement);
	sqlite_finalize_null(&setAllForKeyStatement);
	sqlite_finalize_null(&removeForKeyStatement);
	sqlite_finalize_null(&removeCollectionStatement);
	sqlite_finalize_null(&removeAllStatement);
	sqlite_finalize_null(&enumerateCollectionsStatement);
	sqlite_finalize_null(&enumerateKeysInCollectionStatement);
	sqlite_finalize_null(&enumerateKeysInAllCollectionsStatement);
	sqlite_finalize_null(&enumerateKeysAndMetadataInCollectionStatement);
	sqlite_finalize_null(&enumerateKeysAndMetadataInAllCollectionsStatement);
	sqlite_finalize_null(&enumerateKeysAndObjectsInCollectionStatement);
	sqlite_finalize_null(&enumerateKeysAndObjectsInAllCollectionsStatement);
	sqlite_finalize_null(&enumerateRowsInCollectionStatement);
	sqlite_finalize_null(&enumerateRowsInAllCollectionsStatement);
}

/**
 * Override hook from YapAbstractDatabaseConnection.
**/
- (void)_flushMemoryWithLevel:(int)level
{
	[super _flushMemoryWithLevel:level];
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&getCollectionCountStatement);
		sqlite_finalize_null(&getKeyCountForAllStatement);
		sqlite_finalize_null(&getCountForKeyStatement);
		sqlite_finalize_null(&setMetaForKeyStatement);
		sqlite_finalize_null(&removeForKeyStatement);
		sqlite_finalize_null(&removeCollectionStatement);
		sqlite_finalize_null(&removeAllStatement);
		sqlite_finalize_null(&enumerateCollectionsStatement);
		sqlite_finalize_null(&enumerateKeysInCollectionStatement);
		sqlite_finalize_null(&enumerateKeysInAllCollectionsStatement);
		sqlite_finalize_null(&enumerateKeysAndMetadataInCollectionStatement);
		sqlite_finalize_null(&enumerateKeysAndMetadataInAllCollectionsStatement);
		sqlite_finalize_null(&enumerateKeysAndObjectsInCollectionStatement);
		sqlite_finalize_null(&enumerateKeysAndObjectsInAllCollectionsStatement);
		sqlite_finalize_null(&enumerateRowsInCollectionStatement);
		sqlite_finalize_null(&enumerateRowsInAllCollectionsStatement);
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
		sqlite_finalize_null(&getDataForKeyStatement);
		sqlite_finalize_null(&setAllForKeyStatement);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapCollectionsDatabase *)database
{
	return (YapCollectionsDatabase *)database;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)getCollectionCountStatement
{
	if (getCollectionCountStatement == NULL)
	{
		char *stmt = "SELECT COUNT(DISTINCT collection) AS NumberOfRows FROM \"database\";";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getCollectionCountStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getCollectionCountStatement;
}

- (sqlite3_stmt *)getKeyCountForCollectionStatement
{
	if (getKeyCountForCollectionStatement == NULL)
	{
		char *stmt = "SELECT COUNT(*) AS NumberOfRows FROM \"database\" WHERE \"collection\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getKeyCountForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getKeyCountForCollectionStatement;
}

- (sqlite3_stmt *)getKeyCountForAllStatement
{
	if (getKeyCountForAllStatement == NULL)
	{
		char *stmt = "SELECT COUNT(*) AS NumberOfRows FROM \"database\";";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getKeyCountForAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getKeyCountForAllStatement;
}

- (sqlite3_stmt *)getCountForKeyStatement
{
	if (getCountForKeyStatement == NULL)
	{
		char *stmt = "SELECT COUNT(*) AS NumberOfRows FROM \"database\" WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getCountForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getCountForKeyStatement;
}

- (sqlite3_stmt *)getDataForKeyStatement
{
	if (getDataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\" FROM \"database\" WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getDataForKeyStatement;
}

- (sqlite3_stmt *)getMetadataForKeyStatement
{
	if (getMetadataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"metadata\" FROM \"database\" WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getMetadataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getMetadataForKeyStatement;
}

- (sqlite3_stmt *)getAllForKeyStatement
{
	if (getAllForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\", \"metadata\" FROM \"database\" WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &getAllForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return getAllForKeyStatement;
}

- (sqlite3_stmt *)setMetaForKeyStatement
{
	if (setMetaForKeyStatement == NULL)
	{
		char *stmt = "UPDATE \"database\" SET \"metadata\" = ? WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &setMetaForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return setMetaForKeyStatement;
}

- (sqlite3_stmt *)setAllForKeyStatement
{
	if (setAllForKeyStatement == NULL)
	{
		char *stmt = "INSERT OR REPLACE INTO \"database\""
		              " (\"collection\", \"key\", \"data\", \"metadata\") VALUES (?, ?, ?, ?);";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &setAllForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return setAllForKeyStatement;
}

- (sqlite3_stmt *)removeForKeyStatement
{
	if (removeForKeyStatement == NULL)
	{
		char *stmt = "DELETE FROM \"database\" WHERE \"collection\" = ? AND \"key\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &removeForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return removeForKeyStatement;
}

- (sqlite3_stmt *)removeCollectionStatement
{
	if (removeCollectionStatement == NULL)
	{
		char *stmt = "DELETE FROM \"database\" WHERE \"collection\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &removeCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return removeCollectionStatement;
}

- (sqlite3_stmt *)removeAllStatement
{
	if (removeAllStatement == NULL)
	{
		char *stmt = "DELETE FROM \"database\";";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return removeAllStatement;
}

- (sqlite3_stmt *)enumerateCollectionsStatement
{
	if (enumerateCollectionsStatement == NULL)
	{
		char *stmt = "SELECT DISTINCT \"collection\" FROM \"database\";";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateCollectionsStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateCollectionsStatement;
}

- (sqlite3_stmt *)enumerateKeysInCollectionStatement
{
	if (enumerateKeysInCollectionStatement == NULL)
	{
		char *stmt = "SELECT \"key\" FROM \"database\" WHERE collection = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysInCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysInCollectionStatement;
}

- (sqlite3_stmt *)enumerateKeysInAllCollectionsStatement
{
	if (enumerateKeysInAllCollectionsStatement == NULL)
	{
		char *stmt = "SELECT \"collection\", \"key\" FROM \"database\";";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysInAllCollectionsStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysInAllCollectionsStatement;
}

- (sqlite3_stmt *)enumerateKeysAndMetadataInCollectionStatement
{
	if (enumerateKeysAndMetadataInCollectionStatement == NULL)
	{
		char *stmt = "SELECT \"key\", \"metadata\" FROM \"database\" WHERE collection = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysAndMetadataInCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysAndMetadataInCollectionStatement;
}

- (sqlite3_stmt *)enumerateKeysAndMetadataInAllCollectionsStatement
{
	if (enumerateKeysAndMetadataInAllCollectionsStatement == NULL)
	{
		char *stmt = "SELECT \"collection\", \"key\", \"metadata\" FROM \"database\" ORDER BY \"collection\" ASC;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysAndMetadataInAllCollectionsStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysAndMetadataInAllCollectionsStatement;
}

- (sqlite3_stmt *)enumerateKeysAndObjectsInCollectionStatement
{
	if (enumerateKeysAndObjectsInCollectionStatement == NULL)
	{
		char *stmt = "SELECT \"key\", \"data\" FROM \"database\" WHERE \"collection\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysAndObjectsInCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysAndObjectsInCollectionStatement;
}

- (sqlite3_stmt *)enumerateKeysAndObjectsInAllCollectionsStatement
{
	if (enumerateKeysAndObjectsInAllCollectionsStatement == NULL)
	{
		char *stmt = "SELECT \"collection\", \"key\", \"data\" FROM \"database\" ORDER BY \"collection\" ASC;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateKeysAndObjectsInAllCollectionsStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateKeysAndObjectsInAllCollectionsStatement;
}

- (sqlite3_stmt *)enumerateRowsInCollectionStatement
{
	if (enumerateRowsInCollectionStatement == NULL)
	{
		char *stmt = "SELECT \"key\", \"data\", \"metadata\" FROM \"database\" WHERE \"collection\" = ?;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateRowsInCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateRowsInCollectionStatement;
}

- (sqlite3_stmt *)enumerateRowsInAllCollectionsStatement
{
	if (enumerateRowsInAllCollectionsStatement == NULL)
	{
		char *stmt =
		    "SELECT \"collection\", \"key\", \"data\", \"metadata\""
		    " FROM \"database\""
		    " ORDER BY \"collection\" ASC;";
		int stmtLen = (int)strlen(stmt);
		
		int status = sqlite3_prepare_v2(db, stmt, stmtLen+1, &enumerateRowsInAllCollectionsStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateRowsInAllCollectionsStatement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Access
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
**/
- (void)readWithBlock:(void (^)(YapCollectionsDatabaseReadTransaction *))block
{
	[super _readWithBlock:block];
}

/**
 * Read-write access to the database.
 * 
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
**/
- (void)readWriteWithBlock:(void (^)(YapCollectionsDatabaseReadWriteTransaction *transaction))block
{
	[super _readWriteWithBlock:block];
}

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWithBlock:(void (^)(YapCollectionsDatabaseReadTransaction *transaction))block
{
	[super _asyncReadWithBlock:block completionBlock:NULL completionQueue:NULL];
}

/**
 * Read-write access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
 * 
 * An optional completion block may be used.
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncReadWithBlock:(void (^)(YapCollectionsDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock
{
	[super _asyncReadWithBlock:block completionBlock:completionBlock completionQueue:NULL];
}

/**
 * Read-write access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
 * 
 * An optional completion block may be used.
 * Additionally the dispatch_queue to invoke the completion block may also be specified.
 * If NULL, dispatch_get_main_queue() is automatically used.
**/
- (void)asyncReadWithBlock:(void (^)(YapCollectionsDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock
           completionQueue:(dispatch_queue_t)completionQueue
{
	[super _asyncReadWithBlock:block completionBlock:completionBlock completionQueue:completionQueue];
}

/**
 * Read-write access to the database.
 * 
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
 * 
 * This method is asynchronous.
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapCollectionsDatabaseReadWriteTransaction *transaction))block
{
	[super _asyncReadWriteWithBlock:block completionBlock:NULL completionQueue:NULL];
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayted if another sibling connection
 * is currently executing a read-write block.
 *
 * This method is asynchronous.
 * 
 * An optional completion block may be used.
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapCollectionsDatabaseReadWriteTransaction *transaction))block
                completionBlock:(dispatch_block_t)completionBlock
{
	[super _asyncReadWriteWithBlock:block completionBlock:completionBlock completionQueue:NULL];
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayted if another sibling connection
 * is currently executing a read-write block.
 *
 * This method is asynchronous.
 * 
 * An optional completion block may be used.
 * Additionally the dispatch_queue to invoke the completion block may also be specified.
 * If NULL, dispatch_get_main_queue() is automatically used.
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapCollectionsDatabaseReadWriteTransaction *transaction))block
                completionBlock:(dispatch_block_t)completionBlock
                completionQueue:(dispatch_queue_t)completionQueue
{
	[super _asyncReadWriteWithBlock:block completionBlock:completionBlock completionQueue:completionQueue];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark States
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required method.
 * Returns the proper type of transaction for this connection class.
**/
- (YapAbstractDatabaseTransaction *)newReadTransaction
{
	return [[YapCollectionsDatabaseReadTransaction alloc] initWithConnection:self isReadWriteTransaction:NO];
}

/**
 * Required method.
 * Returns the proper type of transaction for this connection class.
**/
- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	return [[YapCollectionsDatabaseReadWriteTransaction alloc] initWithConnection:self isReadWriteTransaction:YES];
}

/**
 * We override this method to setup our changeset variables.
**/
- (void)preReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	[super preReadWriteTransaction:transaction];
	
	if (objectChanges == nil)
		objectChanges = [[NSMutableDictionary alloc] init];
	if (metadataChanges == nil)
		metadataChanges = [[NSMutableDictionary alloc] init];
	if (removedKeys == nil)
		removedKeys = [[NSMutableSet alloc] init];
	if (removedCollections == nil)
		removedCollections = [[NSMutableSet alloc] init];
	
	allKeysRemoved = NO;
}

/**
 * We override this method to reset our changeset variables.
**/
- (void)postReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	[super postReadWriteTransaction:transaction];
	
	if ([objectChanges count] > 0)
		objectChanges = nil;
	if ([metadataChanges count] > 0)
		metadataChanges = nil;
	if ([removedKeys count] > 0)
		removedKeys = nil;
	if ([removedCollections count] > 0)
		removedCollections = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changesets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapAbstractDatabaseConnection.
 * 
 * This method is invoked from within the postReadWriteTransaction operations.
 * This method is invoked before anything has been committed.
 *
 * If changes have been made, it should return a changeset dictionary.
 * If no changes have been made, it should return nil.
 * 
 * @see processChangeset:
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
{
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	
	[super getInternalChangeset:&internalChangeset externalChangeset:&externalChangeset];
	
	// Reserved keys:
	//
	// - extensions
	// - extensionNames
	// - snapshot
	
	if ([objectChanges count]      > 0 ||
		[metadataChanges count]    > 0 ||
		[removedKeys count]        > 0 ||
		[removedCollections count] > 0 || allKeysRemoved)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithCapacity:6]; // +1 for snapshot
		
		if (externalChangeset == nil)
			externalChangeset = [NSMutableDictionary dictionaryWithCapacity:6]; // +1 for snapshot
		
		if ([objectChanges count] > 0)
		{
			[internalChangeset setObject:objectChanges forKey:YapCollectionsDatabaseObjectChangesKey];
			
			YapSet *immutableObjectChanges = [[YapSet alloc] initWithDictionary:objectChanges];
			[externalChangeset setObject:immutableObjectChanges forKey:YapCollectionsDatabaseObjectChangesKey];
		}
		
		if ([metadataChanges count] > 0)
		{
			[internalChangeset setObject:metadataChanges forKey:YapCollectionsDatabaseMetadataChangesKey];
			
			YapSet *immutableMetadataChanges = [[YapSet alloc] initWithDictionary:metadataChanges];
			[externalChangeset setObject:immutableMetadataChanges forKey:YapCollectionsDatabaseMetadataChangesKey];
		}
		
		if ([removedKeys count] > 0)
		{
			[internalChangeset setObject:removedKeys forKey:YapCollectionsDatabaseRemovedKeysKey];
			
			YapSet *immutableRemovedKeys = [[YapSet alloc] initWithSet:removedKeys];
			[externalChangeset setObject:immutableRemovedKeys forKey:YapCollectionsDatabaseRemovedKeysKey];
		}
		
		if ([removedCollections count] > 0)
		{
			[internalChangeset setObject:removedCollections forKey:YapCollectionsDatabaseRemovedCollectionsKey];
			
			YapSet *immutableRemovedCollections = [[YapSet alloc] initWithSet:removedCollections];
			[externalChangeset setObject:immutableRemovedCollections
			                      forKey:YapCollectionsDatabaseRemovedCollectionsKey];
		}
		
		if (allKeysRemoved)
		{
			[internalChangeset setObject:@(YES) forKey:YapCollectionsDatabaseAllKeysRemovedKey];
			[externalChangeset setObject:@(YES) forKey:YapCollectionsDatabaseAllKeysRemovedKey];
		}
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
}

/**
 * Required override method from YapAbstractDatabaseConnection.
 *
 * This method is invoked with the changeset from a sibling connection.
 * The connection should update any in-memory components (such as the cache) to properly reflect the changeset.
 * 
 * @see changeset
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	[super processChangeset:changeset];
	
	// Extract changset information
	
	NSDictionary *changeset_objectChanges   =  [changeset objectForKey:YapCollectionsDatabaseObjectChangesKey];
	NSDictionary *changeset_metadataChanges =  [changeset objectForKey:YapCollectionsDatabaseMetadataChangesKey];
	
	NSSet *changeset_removedKeys        =  [changeset objectForKey:YapCollectionsDatabaseRemovedKeysKey];
	NSSet *changeset_removedCollections =  [changeset objectForKey:YapCollectionsDatabaseRemovedCollectionsKey];
	
	BOOL changeset_allKeysRemoved = [[changeset objectForKey:YapCollectionsDatabaseAllKeysRemovedKey] boolValue];
	
	BOOL hasObjectChanges      = [changeset_objectChanges count] > 0;
	BOOL hasMetadataChanges    = [changeset_metadataChanges count] > 0;
	BOOL hasRemovedKeys        = [changeset_removedKeys count] > 0;
	BOOL hasRemovedCollections = [changeset_removedCollections count] > 0;
	
	// Update objectCache
	
	if (changeset_allKeysRemoved && !hasObjectChanges)
	{
		// Shortcut: Everything was removed from the database
		
		[objectCache removeAllObjects];
	}
	else if (hasObjectChanges && !hasRemovedKeys && !hasRemovedCollections && !changeset_allKeysRemoved)
	{
		// Shortcut: Nothing was removed from the database.
		// So we can simply enumerate over the changes and update the cache inline as needed.
		
		[changeset_objectChanges enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			
			if ([objectCache containsKey:cacheKey])
				[objectCache setObject:object forKey:cacheKey];
		}];
	}
	else if (hasObjectChanges || hasRemovedKeys || hasRemovedCollections)
	{
		NSUInteger updateCapacity = MIN([objectCache count], [changeset_objectChanges count]);
		NSUInteger removeCapacity = MIN([objectCache count], [changeset_removedKeys count]);
		
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		
		[objectCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjectsInAllCollections];
			// [transaction setObject:obj forKey:key inCollection:collection];
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			
			if ([changeset_objectChanges objectForKey:key])
			{
				[keysToUpdate addObject:key];
			}
			else if ([changeset_removedKeys containsObject:key] ||
					 [changeset_removedCollections containsObject:cacheKey.collection] || changeset_allKeysRemoved)
			{
				[keysToRemove addObject:key];
			}
		}];
		
		[objectCache removeObjectsForKeys:keysToRemove];
		
		id yapnull = [YapNull null];
		
		for (id key in keysToUpdate)
		{
			id newObject = [changeset_objectChanges objectForKey:key];
			
			if (newObject == yapnull) // setPrimitiveDataForKey was used on key
				[objectCache removeObjectForKey:key];
			else
				[objectCache setObject:newObject forKey:key];
		}
	}
	
	// Update metadataCache
	
	if (changeset_allKeysRemoved && !hasMetadataChanges)
	{
		// Shortcut: Everything was removed from the database
		
		[metadataCache removeAllObjects];
	}
	else if (hasMetadataChanges && !hasRemovedKeys && !hasRemovedCollections && !changeset_allKeysRemoved)
	{
		// Shortcut: Nothing was removed from the database.
		// So we can simply enumerate over the changes and update the cache inline as needed.
		
		[changeset_metadataChanges enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			
			if ([metadataCache containsKey:cacheKey])
				[metadataCache setObject:object forKey:cacheKey];
		}];
	}
	else if (hasMetadataChanges || hasRemovedKeys || hasRemovedCollections)
	{
		NSUInteger updateCapacity = MIN([metadataCache count], [changeset_metadataChanges count]);
		NSUInteger removeCapacity = MIN([metadataCache count], [changeset_removedKeys count]);
		
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		
		[metadataCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjectsInAllCollections];
			// [transaction setObject:obj forKey:key inCollection:collection];
			
			__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
			
			if ([changeset_metadataChanges objectForKey:key])
			{
				[keysToUpdate addObject:key];
			}
			else if ([changeset_removedKeys containsObject:key] ||
					 [changeset_removedCollections containsObject:cacheKey.collection] || changeset_allKeysRemoved)
			{
				[keysToRemove addObject:key];
			}
		}];
		
		[metadataCache removeObjectsForKeys:keysToRemove];
		
		for (id key in keysToUpdate)
		{
			id newObject = [changeset_metadataChanges objectForKey:key];
			
			[metadataCache setObject:newObject forKey:key];
		}
	}
}

- (BOOL)hasChangeForCollection:(NSString *)collection
               inNotifications:(NSArray *)notifications
        includingObjectChanges:(BOOL)includeObjectChanges
               metadataChanges:(BOOL)includeMetadataChanges
{
	if (collection == nil)
		collection = @"";
	
	for (NSNotification *notification in notifications)
	{
		if (![notification isKindOfClass:[NSNotification class]])
		{
			YDBLogWarn(@"%@ - notifications parameter contains non-NSNotification object", THIS_METHOD);
			continue;
		}
		
		NSDictionary *changeset = notification.userInfo;
		
		if (includeObjectChanges)
		{
			YapSet *changeset_objectChanges = [changeset objectForKey:YapCollectionsDatabaseObjectChangesKey];
			for (YapCollectionKey *collectionKey in changeset_objectChanges)
			{
				if ([collectionKey.collection isEqualToString:collection])
				{
					return YES;
				}
			}
		}
		
		if (includeMetadataChanges)
		{
			YapSet *changeset_metadataChanges = [changeset objectForKey:YapCollectionsDatabaseMetadataChangesKey];
			for (YapCollectionKey *collectionKey in changeset_metadataChanges)
			{
				if ([collectionKey.collection isEqualToString:collection])
				{
					return YES;
				}
			}
		}
		
		YapSet *changeset_removedKeys = [changeset objectForKey:YapCollectionsDatabaseRemovedKeysKey];
		for (YapCollectionKey *collectionKey in changeset_removedKeys)
		{
			if ([collectionKey.collection isEqualToString:collection])
			{
				return YES;
			}
		}
		
		YapSet *changeset_removedCollections = [changeset objectForKey:YapCollectionsDatabaseRemovedCollectionsKey];
		if ([changeset_removedCollections containsObject:collection])
			return YES;
		
		BOOL changeset_allKeysRemoved = [[changeset objectForKey:YapCollectionsDatabaseAllKeysRemovedKey] boolValue];
		if (changeset_allKeysRemoved)
			return YES;
	}
	
	return NO;
}

- (BOOL)hasChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications
{
	return [self hasChangeForCollection:collection
	                    inNotifications:notifications
	             includingObjectChanges:YES
	                    metadataChanges:YES];
}

- (BOOL)hasObjectChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications
{
	return [self hasChangeForCollection:collection
	                    inNotifications:notifications
	             includingObjectChanges:YES
	                    metadataChanges:NO];
}

- (BOOL)hasMetadataChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications
{
	return [self hasChangeForCollection:collection
	                    inNotifications:notifications
	             includingObjectChanges:NO
	                    metadataChanges:YES];
}

// Query for a change to a particular key/collection tuple

- (BOOL)hasChangeForKey:(NSString *)key
           inCollection:(NSString *)collection
        inNotifications:(NSArray *)notifications
 includingObjectChanges:(BOOL)includeObjectChanges
        metadataChanges:(BOOL)includeMetadataChanges
{
	if (collection == nil)
		collection = @"";
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	for (NSNotification *notification in notifications)
	{
		if (![notification isKindOfClass:[NSNotification class]])
		{
			YDBLogWarn(@"%@ - notifications parameter contains non-NSNotification object", THIS_METHOD);
			continue;
		}
		
		NSDictionary *changeset = notification.userInfo;
		
		if (includeObjectChanges)
		{
			YapSet *changeset_objectChanges = [changeset objectForKey:YapCollectionsDatabaseObjectChangesKey];
			if ([changeset_objectChanges containsObject:collectionKey])
				return YES;
		}
		
		if (includeMetadataChanges)
		{
			YapSet *changeset_metadataChanges = [changeset objectForKey:YapCollectionsDatabaseMetadataChangesKey];
			if ([changeset_metadataChanges containsObject:collectionKey])
				return YES;
		}
		
		YapSet *changeset_removedKeys = [changeset objectForKey:YapCollectionsDatabaseRemovedKeysKey];
		if ([changeset_removedKeys containsObject:collectionKey])
			return YES;
		
		YapSet *changeset_removedCollections = [changeset objectForKey:YapCollectionsDatabaseRemovedCollectionsKey];
		if ([changeset_removedCollections containsObject:collection])
			return YES;
		
		BOOL changeset_allKeysRemoved = [[changeset objectForKey:YapCollectionsDatabaseAllKeysRemovedKey] boolValue];
		if (changeset_allKeysRemoved)
			return YES;
	}
	
	return NO;
}

- (BOOL)hasChangeForKey:(NSString *)key
           inCollection:(NSString *)collection
        inNotifications:(NSArray *)notifications
{
	return [self hasChangeForKey:key
	                inCollection:collection
	             inNotifications:notifications
	      includingObjectChanges:YES
	             metadataChanges:YES];
}

- (BOOL)hasObjectChangeForKey:(NSString *)key
                 inCollection:(NSString *)collection
               inNotification:(NSArray *)notifications
{
	return [self hasChangeForKey:key
	                inCollection:collection
	             inNotifications:notifications
	      includingObjectChanges:YES
	             metadataChanges:NO];
}

- (BOOL)hasMetadataChangeForKey:(NSString *)key
                   inCollection:(NSString *)collection
                 inNotification:(NSArray *)notifications
{
	return [self hasChangeForKey:key
	                inCollection:collection
	             inNotifications:notifications
	      includingObjectChanges:NO
	             metadataChanges:YES];
}

// Query for a change to a particular set of keys in a collection

- (BOOL)hasChangeForAnyKeys:(NSSet *)keys
               inCollection:(NSString *)collection
            inNotifications:(NSArray *)notifications
     includingObjectChanges:(BOOL)includeObjectChanges
            metadataChanges:(BOOL)includeMetadataChanges
{
	if ([keys count] == 0) return NO;
	if (collection == nil)
		collection = @"";
	
	for (NSNotification *notification in notifications)
	{
		if (![notification isKindOfClass:[NSNotification class]])
		{
			YDBLogWarn(@"%@ - notifications parameter contains non-NSNotification object", THIS_METHOD);
			continue;
		}
		
		NSDictionary *changeset = notification.userInfo;
		
		if (includeObjectChanges)
		{
			YapSet *changeset_objectChanges = [changeset objectForKey:YapCollectionsDatabaseObjectChangesKey];
			for (YapCollectionKey *collectionKey in changeset_objectChanges)
			{
				if ([collectionKey.collection isEqualToString:collection])
				{
					if ([keys containsObject:collectionKey.key])
					{
						return YES;
					}
				}
			}
		}
		
		if (includeMetadataChanges)
		{
			YapSet *changeset_metadataChanges = [changeset objectForKey:YapCollectionsDatabaseMetadataChangesKey];
			for (YapCollectionKey *collectionKey in changeset_metadataChanges)
			{
				if ([collectionKey.collection isEqualToString:collection])
				{
					if ([keys containsObject:collectionKey.key])
					{
						return YES;
					}
				}
			}
		}
		
		YapSet *changeset_removedKeys = [changeset objectForKey:YapCollectionsDatabaseRemovedKeysKey];
		for (YapCollectionKey *collectionKey in changeset_removedKeys)
		{
			if ([collectionKey.collection isEqualToString:collection])
			{
				if ([keys containsObject:collectionKey.key])
				{
					return YES;
				}
			}
		}
		
		YapSet *changeset_removedCollections = [changeset objectForKey:YapCollectionsDatabaseRemovedCollectionsKey];
		if ([changeset_removedCollections containsObject:collection])
			return YES;
		
		BOOL changeset_allKeysRemoved = [[changeset objectForKey:YapCollectionsDatabaseAllKeysRemovedKey] boolValue];
		if (changeset_allKeysRemoved)
			return YES;
	}
	
	return NO;
}

- (BOOL)hasChangeForAnyKeys:(NSSet *)keys
               inCollection:(NSString *)collection
            inNotifications:(NSArray *)notifications
{
	return [self hasChangeForAnyKeys:keys
	                    inCollection:collection
	                 inNotifications:notifications
	          includingObjectChanges:YES
	                 metadataChanges:YES];
}

- (BOOL)hasObjectChangeForAnyKeys:(NSSet *)keys
                     inCollection:(NSString *)collection
                   inNotification:(NSArray *)notifications
{
	return [self hasChangeForAnyKeys:keys
	                    inCollection:collection
	                 inNotifications:notifications
	          includingObjectChanges:YES
	                 metadataChanges:NO];
}

- (BOOL)hasMetadataChangeForAnyKeys:(NSSet *)keys
                       inCollection:(NSString *)collection
                     inNotification:(NSArray *)notifications
{
	return [self hasChangeForAnyKeys:keys
	                    inCollection:collection
	                 inNotifications:notifications
	          includingObjectChanges:NO
	                 metadataChanges:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapAbstractDatabaseConnection.
**/
- (BOOL)registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName
{
	__block BOOL result = NO;
	
	[self readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction) {
		
		if ([self canRegisterExtension:extension withName:extensionName])
		{
			YapAbstractDatabaseExtensionConnection *extensionConnection;
			YapAbstractDatabaseExtensionTransaction *extensionTransaction;
			
			extensionConnection = [extension newConnection:self];
			extensionTransaction = [extensionConnection newReadWriteTransaction:transaction];
			
			BOOL isFirstTimeExtensionReigstration = NO;
			[extensionTransaction willRegister:&isFirstTimeExtensionReigstration];
			
			result = [extensionTransaction createFromScratch:isFirstTimeExtensionReigstration];
			
			if (result)
			{
				[extensionTransaction didRegister:isFirstTimeExtensionReigstration];
				[self didRegisterExtension:extension withName:extensionName];
				
				[self addRegisteredExtensionConnection:extensionConnection];
				[transaction addRegisteredExtensionTransaction:extensionTransaction];
			}
			else
			{
				[transaction rollback];
			}
		}
	}];
	
	return result;
}

/**
 * Required override method from YapAbstractDatabaseConnection.
**/
- (void)unregisterExtension:(NSString *)extensionName
{
	[self readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction) {
		
		NSString *className = [transaction stringValueForKey:@"class" extension:extensionName];
		
		Class class = NSClassFromString(className);
		if (class == NULL)
		{
			YDBLogError(@"Unable to unregister extension(%@) with unknown class(%@)", extensionName, className);
			return;
		}
		if (![class isSubclassOfClass:[YapAbstractDatabaseExtension class]])
		{
			YDBLogError(@"Unable to unregister extension(%@) with improper class(%@)", extensionName, className);
			return;
		}
		
		[class dropTablesForRegisteredName:extensionName withTransaction:transaction];
		
		[transaction removeAllValuesForExtension:extensionName];
		
		[self removeRegisteredExtensionConnection:extensionName];
		[transaction removeRegisteredExtensionTransaction:extensionName];
	}];
}

@end
