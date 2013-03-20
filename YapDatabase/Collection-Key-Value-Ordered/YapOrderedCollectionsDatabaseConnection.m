#import "YapOrderedCollectionsDatabaseConnection.h"
#import "YapOrderedCollectionsDatabasePrivate.h"

#import "YapCollectionsDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

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

@implementation YapOrderedCollectionsDatabaseConnection

- (id)initWithDatabase:(YapOrderedCollectionsDatabase *)inDatabase
{
	if ((self = [super initWithDatabase:inDatabase]))
	{
		orderDict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	sqlite_finalize_null(&getOrderDataForKeyStatement);
	sqlite_finalize_null(&setOrderDataForKeyStatement);
	sqlite_finalize_null(&removeOrderDataForKeyStatement);
	sqlite_finalize_null(&removeOrderDataForCollectionStatement);
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
		sqlite_finalize_null(&removeOrderDataForCollectionStatement);
		sqlite_finalize_null(&removeAllOrderDataStatement);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapCollectionsDatabaseConnection superclass contains the following property:
 *
 * @property (nonatomic, strong, readonly) YapCollectionsDatabase *database;
 *
 * In our case, the database is actually an instance of YapOrderedCollectionsDatabase.
 * But if we attempt to redeclare the property with this type then we get a compiler error.
 *
 * So users can use the original property and cast the result if needed,
 * or use this new property declaration for convenience.
**/
- (YapOrderedCollectionsDatabase *)orderedDatabase
{
	return (YapOrderedCollectionsDatabase *)database;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)getOrderDataForKeyStatement
{
	if (getOrderDataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\" FROM \"order\" WHERE \"collection\" = ? AND \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &getOrderDataForKeyStatement, NULL);
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
		char *stmt = "INSERT OR REPLACE INTO \"order\" (\"collection\", \"key\", \"data\") VALUES (?, ?, ?);";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &setOrderDataForKeyStatement, NULL);
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
		char *stmt = "DELETE FROM \"order\" WHERE \"collection\" = ? AND \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &removeOrderDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeOrderDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeOrderDataForKeyStatement;
}

- (sqlite3_stmt *)removeOrderDataForCollectionStatement
{
	if (removeOrderDataForCollectionStatement == NULL)
	{
		char *stmt = "DELETE FROM \"order\" WHERE \"collection\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &removeOrderDataForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeOrderDataForCollectionStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return removeOrderDataForCollectionStatement;
}

- (sqlite3_stmt *)removeAllOrderDataStatement
{
	if (removeAllOrderDataStatement == NULL)
	{
		char *stmt = "DELETE FROM \"order\";";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &removeAllOrderDataStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'removeAllOrderDataStatement'! %d %s", status, sqlite3_errmsg(db));
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
- (void)readWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadTransaction *transaction))block
{
	[super _readWithBlock:block];
}

/**
 * Read-write access to the database.
 *
 * Only a single readwrite block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a readwrite block.
**/
- (void)readWriteWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadTransaction *transaction))block
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
 * 
 * An optional completion block may be used.
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncReadWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadTransaction *transaction))block
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
 * 
 * An optional completion block may be used.
 * Additionally the dispatch_queue to invoke the completion block may also be specified.
 * If NULL, dispatch_get_main_queue() is automatically used.
**/
- (void)asyncReadWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction))block
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
	// From YapOrderedCollectionsDatabaseConnection.h :
	//
	// #define YapOrderedCollectionsDatabaseReadTransaction \
	//         YapCollectionsDatabaseReadTransaction <YapOrderedCollectionsReadTransaction>
	//
	// But why the oddness?
	// Essentially, YapOrderedCollectionsDatabaseReadWriteTransaction requires multiple inheritance:
	// - YapOrderedCollectionsDatabaseReadTransaction
	// - YapCollectionsDatabaseReadWriteTransaction
	//
	// So to accomplish this, we use a "proxy" object which
	// forwards non-overrident methods to the primary transaction instance.
	
	YapCollectionsDatabaseReadTransaction *transaction =
	    [[YapCollectionsDatabaseReadTransaction alloc] initWithConnection:self];
	YapOrderedCollectionsDatabaseReadTransactionProxy *orderedTransaction =
	    [[YapOrderedCollectionsDatabaseReadTransactionProxy alloc] initWithConnection:self transaction:transaction];
	
	return (YapAbstractDatabaseTransaction *)orderedTransaction;
}

/**
 * Required method.
 * Returns the proper type of transaction for this connection class.
**/
- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	// From YapOrderedCollectionsDatabaseConnection.h :
	//
	// #define YapOrderedCollectionsDatabaseReadWriteTransaction \
	//         YapCollectionsDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction>
	//
	// But why the oddness?
	// Essentially, YapOrderedCollectionsDatabaseReadWriteTransaction requires multiple inheritance:
	// - YapOrderedDatabaseReadTransaction
	// - YapCollectionsDatabaseReadWriteTransaction
	//
	// So to accomplish this, we use a "proxy" object which
	// forwards non-overrident methods to the primary transaction instance.
	
	YapCollectionsDatabaseReadWriteTransaction *transaction =
	    [[YapCollectionsDatabaseReadWriteTransaction alloc] initWithConnection:self];
	YapOrderedCollectionsDatabaseReadWriteTransactionProxy *orderedTransaction =
	    [[YapOrderedCollectionsDatabaseReadWriteTransactionProxy alloc] initWithConnection:self
	                                                                           transaction:transaction];
	
	return (YapAbstractDatabaseTransaction *)orderedTransaction;
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
	
	__block NSMutableDictionary *orderChangesets = nil;
	
	[orderDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		YapDatabaseOrder *order = (YapDatabaseOrder *)obj;
		if ([order isModified])
		{
			NSString *collection = (NSString *)key;
			NSDictionary *orderChangeset = [order changeset];
			
			if (orderChangesets == nil)
				orderChangesets = [NSMutableDictionary dictionaryWithCapacity:2];
			
			[orderChangesets setObject:orderChangeset forKey:collection];
		}
	}];
	
	if (orderChangesets)
	{
		if (changeset == nil)
			changeset = [NSMutableDictionary dictionaryWithCapacity:2];
		
		[changeset setObject:orderChangesets forKey:@"order"];
	}
	
	return changeset;
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
	
	NSDictionary *orderChangesets = [changeset objectForKey:@"order"];
	[orderChangesets enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		NSString *collection = (NSString *)key;
		NSDictionary *orderChangeset = (NSDictionary *)obj;
		
		YapDatabaseOrder *order = [orderDict objectForKey:collection];
		if (order == nil)
		{
			order = [[YapDatabaseOrder alloc] initWithUserInfo:collection];
			[orderDict setObject:order forKey:collection];
		}
		
		[order mergeChangeset:orderChangeset];
	}];
}

@end
