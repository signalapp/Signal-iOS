#import "YapOrderedDatabaseConnection.h"
#import "YapOrderedDatabasePrivate.h"

#import "YapDatabaseConnection.h"
#import "YapDatabasePrivate.h"

#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapDatabasePrivate.h"

#import "YapCache.h"

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


@implementation YapOrderedDatabaseConnection {

/* Defined in YapOrderedDatabasePrivate.h:

@private
	sqlite3_stmt *getOrderDataForKeyStatement;
	sqlite3_stmt *setOrderDataForKeyStatement;
	sqlite3_stmt *removeOrderDataForKeyStatement;
	sqlite3_stmt *removeAllOrderDataStatement;
	
@public
	YapDatabaseOrder *order;

*/
/* Defined in YapAbstractDatabasePrivate.h:

@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
	uint64_t snapshot;
	
@public
	sqlite3 *db;
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL hasMarkedSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.

*/
}

- (id)initWithDatabase:(YapOrderedDatabase *)inDatabase
{
	if ((self = [super initWithDatabase:inDatabase]))
	{
		order = [[YapDatabaseOrder alloc] init];
	}
	return self;
}

- (void)dealloc
{
	sqlite_finalize_null(&getOrderDataForKeyStatement);
	sqlite_finalize_null(&setOrderDataForKeyStatement);
	sqlite_finalize_null(&removeOrderDataForKeyStatement);
	sqlite_finalize_null(&removeAllOrderDataStatement);
}

/**
 * Optional override hook from YapAbstractDatabaseConnection.
**/
- (void)_flushMemoryWithLevel:(int)level
{
	[super _flushMemoryWithLevel:level];
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&getOrderDataForKeyStatement);
		sqlite_finalize_null(&setOrderDataForKeyStatement);
		sqlite_finalize_null(&removeOrderDataForKeyStatement);
		sqlite_finalize_null(&removeAllOrderDataStatement);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapOrderedDatabase *)orderedDatabase
{
	return (YapOrderedDatabase *)database;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)getOrderDataForKeyStatement
{
	if (getOrderDataForKeyStatement == NULL)
	{
		char *query = "SELECT \"data\" FROM \"order\" WHERE \"key\" = ?;";
		size_t queryLength = strlen(query);
		
		int status = sqlite3_prepare_v2(db, query, queryLength+1, &getOrderDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'getOrderDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return getOrderDataForKeyStatement;
}

- (sqlite3_stmt *)setOrderDataForKeyStatement
{
	if (setOrderDataForKeyStatement == NULL)
	{
		char *query = "INSERT OR REPLACE INTO \"order\" (\"key\", \"data\") VALUES (?, ?);";
		size_t queryLength = strlen(query);
		
		int status = sqlite3_prepare_v2(db, query, queryLength+1, &setOrderDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'setOrderDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return setOrderDataForKeyStatement;
}

- (sqlite3_stmt *)removeOrderDataForKeyStatement
{
	if (removeOrderDataForKeyStatement == NULL)
	{
		char *query = "DELETE FROM \"order\" WHERE \"key\" = ?;";
		size_t queryLength = strlen(query);
		
		int status = sqlite3_prepare_v2(db, query, queryLength+1, &removeOrderDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeOrderDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeOrderDataForKeyStatement;
}

- (sqlite3_stmt *)removeAllOrderDataStatement
{
	if (removeAllOrderDataStatement == NULL)
	{
		char *query = "DELETE FROM \"order\";";
		size_t queryLength = strlen(query);
		
		int status = sqlite3_prepare_v2(db, query, queryLength+1, &removeAllOrderDataStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeAllOrderDataStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeAllOrderDataStatement;
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
- (void)readWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
{
	[super _readWithBlock:block];
}

/**
 * Read-write access to the database.
 *
 * Only a single readwrite block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a readwrite block.
**/
- (void)readWriteWithBlock:(void (^)(YapOrderedDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapOrderedDatabaseReadWriteTransaction *transaction))block
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
	// From YapOrderedDatabaseConnection.h :
	//
	// #define YapOrderedDatabaseReadTransaction \
	//         YapDatabaseReadTransaction <YapOrderedReadTransaction>
	//
	// But why the oddness?
	// Essentially, YapOrderedDatabaseReadWriteTransaction requires multiple inheritance:
	// - YapOrderedDatabaseReadTransaction
	// - YapDatabaseReadWriteTransaction
	//
	// So to accomplish this, we use a "proxy" object which
	// forwards non-overrident methods to the primary transaction instance.
	
	YapDatabaseReadTransaction *transaction =
	    [[YapDatabaseReadTransaction alloc] initWithConnection:self];
	YapOrderedDatabaseReadTransactionProxy *orderedTransaction =
	    [[YapOrderedDatabaseReadTransactionProxy alloc] initWithConnection:self transaction:transaction];
	
	return (YapAbstractDatabaseTransaction *)orderedTransaction;
}

/**
 * Required method.
 * Returns the proper type of transaction for this connection class.
**/
- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	// From YapOrderedDatabaseConnection.h :
	//
	// #define YapOrderedDatabaseReadTransaction \
	//         YapDatabaseReadTransaction <YapOrderedReadTransaction>
	//
	// But why the oddness?
	// Essentially, YapOrderedDatabaseReadWriteTransaction requires multiple inheritance:
	// - YapOrderedDatabaseReadTransaction
	// - YapDatabaseReadWriteTransaction
	//
	// So to accomplish this, we use a "proxy" object which
	// forwards non-overrident methods to the primary transaction instance.
	
	YapDatabaseReadWriteTransaction *transaction =
	    [[YapDatabaseReadWriteTransaction alloc] initWithConnection:self];
	YapOrderedDatabaseReadWriteTransactionProxy *orderedTransaction =
	    [[YapOrderedDatabaseReadWriteTransactionProxy alloc] initWithConnection:self transaction:transaction];
	
	return (YapAbstractDatabaseTransaction *)orderedTransaction;
}

/**
 * We override this method to ensure the order is prepared for use.
**/
- (void)preReadTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	[super preReadTransaction:transaction];
	
	if (![order isPrepared])
	{
		[order prepare:self];
	}
}

/**
 * We override this method to ensure the order is prepared for use.
**/
- (void)preReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	[super preReadWriteTransaction:transaction];
	
	if (![order isPrepared])
	{
		[order prepare:self];
	}
}

/**
 * This method is invoked from within the postReadWriteTransaction operations.
 * This method is invoked before anything has been committed.
 * 
 * If changes have been made, it should return a changeset dictionary.
 * If no changes have been made, it should return nil.
 * 
 * @see processChangeset:
**/
- (NSMutableDictionary *)changeset
{
	NSMutableDictionary *changeset = [super changeset];
	
	if ([order isModified])
	{
		NSDictionary *orderChangeset = [order changeset];
		
		if (changeset == nil)
			changeset = [NSMutableDictionary dictionaryWithCapacity:2]; // For "order" & "snapshot"
		
		[changeset setObject:orderChangeset forKey:@"order"];
	}
	
	return changeset;
}

/**
 * Required override method from YapAbstractDatabaseConnection.
 *
 * This method is invoked with the changeset from a sibling connection.
 * The connection should update any in-memory components (such as the cache) to properly reflect the changeset.
 * 
 * *see changeset
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	[super processChangeset:changeset];
	
	NSDictionary *orderChangeset = [changeset objectForKey:@"order"];
	if (orderChangeset)
	{
		[order mergeChangeset:changeset];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapOrderReadTransaction Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked from within our call to [order prepare:self].
 * It's invoked to read the "KEY_PAGE_INFOS" & "KEY_MAX_PAGE_SIZE" columns from the order database.
 * 
 * We call prepare to first setup the order.
 * We also call it if we encounter a race condition and need to reset the order object.
**/
- (NSData *)dataForKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	sqlite3_stmt *statement = [self getOrderDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSData *result = nil;
	int status;
	
	// SELECT "data" FROM "order" WHERE "key" = ?;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@: Error executing select statement: %d %s",
		              NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	return result;
}

@end
