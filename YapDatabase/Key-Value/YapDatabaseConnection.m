#import "YapDatabaseConnection.h"
#import "YapDatabasePrivate.h"

#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"
#import "YapNull.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif

/**
 * A connection provides a point of access to the database.
 *
 * You first create and configure a YapDatabase instance.
 * Then you can spawn one or more connections to the database file.
 *
 * Multiple connections can simultaneously read from the database.
 * Multiple connections can simultaneously read from the database while another connection is modifying the database.
 * For example, the main thread could be reading from the database via connection A,
 * while a background thread is writing to the database via connection B.
 *
 * However, only a single connection may be writing to the database at any one time.
 *
 * A connection instance is thread-safe, and operates by serializing access to itself.
 * Thus you can share a single connection between multiple threads.
 * But for conncurrent access between multiple threads you must use multiple connections.
**/
@implementation YapDatabaseConnection {

/* Defined in YapDatabasePrivate.h:

@private
	sqlite3_stmt *getCountStatement;
	sqlite3_stmt *getCountForKeyStatement;
	sqlite3_stmt *getDataForKeyStatement;
	sqlite3_stmt *getMetadataForKeyStatement;
	sqlite3_stmt *getAllForKeyStatement;
	sqlite3_stmt *setMetadataForKeyStatement;
	sqlite3_stmt *setAllForKeyStatement;
	sqlite3_stmt *removeForKeyStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *enumerateKeysStatement;
	sqlite3_stmt *enumerateMetadataStatement;
	sqlite3_stmt *enumerateAllStatement;

@public

	NSMutableDictionary *objectChanges;
	NSMutableDictionary *metadataChanges;
	NSMutableSet *removeKeys;
	BOOL allKeysRemoved;

*/
/* Defined in YapAbstractDatabasePrivate.h:

@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
	uint64_t cacheSnapshot;
	
@public
	sqlite3 *db;
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL hasMarkedSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.
 
*/
}

- (void)dealloc
{
	sqlite_finalize_null(&getCountStatement);
	sqlite_finalize_null(&getCountForKeyStatement);
	sqlite_finalize_null(&getDataForKeyStatement);
	sqlite_finalize_null(&getMetadataForKeyStatement);
	sqlite_finalize_null(&getAllForKeyStatement);
	sqlite_finalize_null(&setMetadataForKeyStatement);
	sqlite_finalize_null(&setAllForKeyStatement);
	sqlite_finalize_null(&removeForKeyStatement);
	sqlite_finalize_null(&removeAllStatement);
	sqlite_finalize_null(&enumerateKeysStatement);
	sqlite_finalize_null(&enumerateMetadataStatement);
	sqlite_finalize_null(&enumerateAllStatement);
}

/**
 * Optional override hook from YapAbstractDatabaseConnection.
**/
- (void)_flushMemoryWithLevel:(int)level
{
	[super _flushMemoryWithLevel:level];
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&getCountStatement);
		sqlite_finalize_null(&getCountForKeyStatement);
		sqlite_finalize_null(&getMetadataForKeyStatement);
		sqlite_finalize_null(&getAllForKeyStatement);
		sqlite_finalize_null(&setMetadataForKeyStatement);
		sqlite_finalize_null(&removeForKeyStatement);
		sqlite_finalize_null(&removeAllStatement);
		sqlite_finalize_null(&enumerateKeysStatement);
		sqlite_finalize_null(&enumerateMetadataStatement);
		sqlite_finalize_null(&enumerateAllStatement);
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

- (YapDatabase *)database
{
	return (YapDatabase *)database;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)getCountStatement
{
	if (getCountStatement == NULL)
	{
		char *stmt = "SELECT COUNT(*) AS NumberOfRows FROM \"database\";";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &getCountStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getCountStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getCountStatement;
}

- (sqlite3_stmt *)getCountForKeyStatement
{
	if (getCountForKeyStatement == NULL)
	{
		char *stmt = "SELECT COUNT(*) AS NumberOfRows FROM \"database\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &getCountForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getCountForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getCountForKeyStatement;
}

- (sqlite3_stmt *)getDataForKeyStatement
{
	if (getDataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\" FROM \"database\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &getDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getDataForKeyStatement;
}

- (sqlite3_stmt *)getMetadataForKeyStatement
{
	if (getMetadataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"metadata\" FROM \"database\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &getMetadataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getMetadataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getMetadataForKeyStatement;
}

- (sqlite3_stmt *)getAllForKeyStatement
{
	if (getAllForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\", \"metadata\" FROM \"database\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &getAllForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getAllForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getAllForKeyStatement;
}

- (sqlite3_stmt *)setMetadataForKeyStatement
{
	if (setMetadataForKeyStatement == NULL)
	{
		char *stmt = "UPDATE \"database\" SET \"metadata\" = ? WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &setMetadataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'setMetadataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return setMetadataForKeyStatement;
}

- (sqlite3_stmt *)setAllForKeyStatement
{
	if (setAllForKeyStatement == NULL)
	{
		char *stmt = "INSERT OR REPLACE INTO \"database\" (\"key\", \"data\", \"metadata\") VALUES (?, ?, ?);";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &setAllForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'setAllForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return setAllForKeyStatement;
}

- (sqlite3_stmt *)removeForKeyStatement
{
	if (removeForKeyStatement == NULL)
	{
		char *stmt = "DELETE FROM \"database\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &removeForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeForKeyStatement;
}

- (sqlite3_stmt *)removeAllStatement
{
	if (removeAllStatement == NULL)
	{
		char *stmt = "DELETE FROM \"database\"";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeAllStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeAllStatement;
}

- (sqlite3_stmt *)enumerateKeysStatement
{
	if (enumerateKeysStatement == NULL)
	{
		char *stmt = "SELECT \"key\" FROM \"database\";";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &enumerateKeysStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'enumerateKeysStatement': %d %s", status, sqlite3_errmsg(db));
		}

	}
	
	return enumerateKeysStatement;
}

- (sqlite3_stmt *)enumerateMetadataStatement
{
	if (enumerateMetadataStatement == NULL)
	{
		char *stmt = "SELECT \"key\", \"metadata\" FROM \"database\";";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &enumerateMetadataStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'enumerateMetadataStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateMetadataStatement;
}

- (sqlite3_stmt *)enumerateAllStatement
{
	if (enumerateAllStatement == NULL)
	{
		char *stmt = "SELECT \"key\", \"data\", \"metadata\" FROM \"database\";";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &enumerateAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'enumerateAllStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return enumerateAllStatement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Access
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Read-only access to the database.
 * 
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * The only time this method ever blocks is if another thread is currently using this connection instance
 * to execute a readBlock or readWriteBlock. Recall that you may create multiple connections for concurrent access.
 *
 * This method is synchronous.
**/
- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *))block
{
	[super _readWithBlock:block];
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
 *
 * This method is synchronous.
**/
- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
	[super _asyncReadWithBlock:block completionBlock:NULL completionQueue:NULL];
}

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock
{
	[super _asyncReadWithBlock:block completionBlock:completionBlock completionQueue:NULL];
}

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock
           completionQueue:(dispatch_queue_t)completionQueue
{
	[super _asyncReadWithBlock:block completionBlock:completionBlock completionQueue:completionQueue];
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayted if another sibling connection
 * is currently executing a read-write block.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
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
 **/
- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
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
	return [[YapDatabaseReadTransaction alloc] initWithConnection:self];
}

/**
 * Required method.
 * Returns the proper type of transaction for this connection class.
**/
- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	return [[YapDatabaseReadWriteTransaction alloc] initWithConnection:self];
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
}

/**
 * Required override method from YapAbstractDatabaseConnection.
 *
 * This method is invoked from within the postReadWriteTransaction operation.
 * This method is invoked before anything has been committed.
 *
 * If changes have been made, it should return a changeset dictionary.
 * If no changes have been made, it should return nil.
 * 
 * @see processChangeset
**/
- (NSMutableDictionary *)changeset
{
	if ([objectChanges count] > 0 || [metadataChanges count] > 0 || allKeysRemoved)
	{
		NSMutableDictionary *changeset = [NSMutableDictionary dictionaryWithCapacity:5];
		
		if ([objectChanges count] > 0)
			[changeset setObject:objectChanges forKey:@"objectChanges"];
		
		if ([metadataChanges count] > 0)
			[changeset setObject:metadataChanges forKey:@"metadataChanges"];
		
		if ([removedKeys count] > 0)
			[changeset setObject:removedKeys forKey:@"removedKeys"];
		
		if (allKeysRemoved)
			[changeset setObject:@(YES) forKey:@"allKeysRemoved"];
		
		return changeset;
	}
	else
	{
		return nil;
	}
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
	NSDictionary *c_objectChanges = [changeset objectForKey:@"objectChanges"];
	NSDictionary *c_metadataChanges = [changeset objectForKey:@"metadataChanges"];
	NSSet *c_removedKeys = [changeset objectForKey:@"removedKeys"];
	BOOL c_allKeysRemoved = [[changeset objectForKey:@"allKeysRemoved"] boolValue];
	
	if ([c_objectChanges count] || [c_removedKeys count] || c_allKeysRemoved)
	{
		NSUInteger updateCapacity = MIN([objectCache count], [c_objectChanges count]);
		NSUInteger removeCapacity = MIN([objectCache count], [c_removedKeys count]);
		
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		
		[objectCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([c_objectChanges objectForKey:key]) {
				[keysToUpdate addObject:key];
			}
			else if ([c_removedKeys containsObject:key] || c_allKeysRemoved) {
				[keysToRemove addObject:key];
			}
		}];
	
		id yapnull = [YapNull null];
		
		for (id key in keysToUpdate)
		{
			id newObject = [c_objectChanges objectForKey:key];
			
			if (newObject == yapnull) // setPrimitiveDataForKey was used on key
				[objectCache removeObjectForKey:key];
			else
				[objectCache setObject:newObject forKey:key];
		}
		
		[objectCache removeObjectsForKeys:keysToRemove];
	}
	
	if ([c_metadataChanges count] || [c_removedKeys count] || c_allKeysRemoved)
	{
		NSUInteger updateCapacity = MIN([metadataCache count], [c_metadataChanges count]);
		NSUInteger removeCapacity = MIN([metadataCache count], [c_removedKeys count]);
		
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		
		[metadataCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([c_metadataChanges objectForKey:key]) {
				[keysToUpdate addObject:key];
			}
			else if ([c_removedKeys containsObject:key] || c_allKeysRemoved) {
				[keysToRemove addObject:key];
			}
		}];
		
		for (id key in keysToUpdate)
		{
			id newObject = [c_metadataChanges objectForKey:key];
			[metadataCache setObject:newObject forKey:key];
		}
		
		[metadataCache removeObjectsForKeys:keysToRemove];
	}
}

@end
