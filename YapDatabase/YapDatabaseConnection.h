#import <Foundation/Foundation.h>

@class YapDatabase;
@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * From a single YapDatabase instance you can create multiple connections.
 * Each connection is thread-safe and may be used concurrently with other connections.
 * 
 * Multiple connections can simultaneously read from the database.
 * Multiple connections can simultaneously read from the database while another connection is modifying the database.
 * For example, the main thread could be reading from the database via connection A,
 * while a background thread is writing to the database via connection B.
 *
 * However, only a single connection may be writing to the database at any one time.
 * This is an inherent limitation of the underlying sqlite database.
 *
 * A connection instance is thread-safe, and operates by serializing access to itself.
 * Thus you can share a single connection between multiple threads.
 * But for conncurrent access between multiple threads you must use multiple connections.
**/

enum  {
	YapDatabaseConnectionFlushMemoryFlags_None       = 0,
	YapDatabaseConnectionFlushMemoryFlags_Caches     = 1 << 0,
	YapDatabaseConnectionFlushMemoryFlags_Statements = 1 << 1,
	YapDatabaseConnectionFlushMemoryFlags_All        = (YapDatabaseConnectionFlushMemoryFlags_Caches |
	                                                    YapDatabaseConnectionFlushMemoryFlags_Statements),
};
typedef int YapDatabaseConnectionFlushMemoryFlags;

typedef enum {
	YapDatabasePolicyContainment = 0,
	YapDatabasePolicyShare       = 1,
	YapDatabasePolicyCopy        = 2,
} YapDatabasePolicy;


@interface YapDatabaseConnection : NSObject

/**
 * A database connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * A database instance cannot be deallocated if a corresponding connection is stil alive.
**/
@property (nonatomic, strong, readonly) YapDatabase *database;

/**
 * The optional name property assists in debugging.
 * It is only used internally for log statements.
**/
@property (atomic, copy, readwrite) NSString *name;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cache
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Each database connection maintains an independent cache of deserialized objects.
 * This reduces disk IO and the overhead of the deserialization process.
 * You can optionally configure the cache size, or disable it completely.
 *
 * The cache is properly kept in sync with the atomic snapshot architecture of the database system.
 *
 * You can configure the objectCache at any time, including within readBlocks or readWriteBlocks.
 * To disable the object cache entirely, set objectCacheEnabled to NO.
 * To use an inifinite cache size, set the objectCacheLimit to zero.
 * 
 * By default the objectCache is enabled and has a limit of 250.
 *
 * New connections will inherit the default values set by the parent database object.
 * Thus the default values for new connection instances are configurable.
 * 
 * @see YapDatabase defaultObjectCacheEnabled
 * @see YapDatabase defaultObjectCacheLimit
 * 
 * Also see the wiki for a bit more info:
 * https://github.com/yaptv/YapDatabase/wiki/Cache
**/
@property (atomic, assign, readwrite) BOOL objectCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger objectCacheLimit;

/**
 * Each database connection maintains an independent cache of deserialized metadata.
 * This reduces disk IO and the overhead of the deserialization process.
 * You can optionally configure the cache size, or disable it completely.
 *
 * The cache is properly kept in sync with the atomic snapshot architecture of the database system.
 *
 * You can configure the metadataCache at any time, including within readBlocks or readWriteBlocks.
 * To disable the metadata cache entirely, set metadataCacheEnabled to NO.
 * To use an inifinite cache size, set the metadataCacheLimit to zero.
 * 
 * By default the metadataCache is enabled and has a limit of 500.
 * 
 * New connections will inherit the default values set by the parent database object.
 * Thus the default values for new connection instances are configurable.
 *
 * @see YapDatabase defaultMetadataCacheEnabled
 * @see YapDatabase defaultMetadataCacheLimit
 *
 * Also see the wiki for a bit more info:
 * https://github.com/yaptv/YapDatabase/wiki/Cache
**/
@property (atomic, assign, readwrite) BOOL metadataCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger metadataCacheLimit;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Policy
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase can use various optimizations to reduce overhead and memory footprint.
 * The policy properties allow you to opt in to these optimizations when ready.
 *
 * The default value is YapDatabasePolicyContainment.
 *
 * It is the slowest, but also the safest policy.
 * The other policies require a little more work, and little deeper understanding.
 *
 * These optimizations are discussed extensively in the wiki article "Performance Pro":
 * https://github.com/yaptv/YapDatabase/wiki/Performance-Pro
**/
@property (atomic, assign, readwrite) YapDatabasePolicy objectPolicy;
@property (atomic, assign, readwrite) YapDatabasePolicy metadataPolicy;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark State
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The snapshot number is the internal synchronization state primitive for the connection.
 * It's generally only useful for database internals,
 * but it can sometimes come in handy for general debugging of your app.
 *
 * The snapshot is a simple 64-bit number that gets incremented upon every readwrite transaction
 * that makes modifications to the database. Due to the concurrent architecture of YapDatabase,
 * there may be multiple concurrent connections that are inspecting the database at similar times,
 * yet they are looking at slightly different "snapshots" of the database.
 * 
 * The snapshot number may thus be inspected to determine (in a general fashion) what state the connection
 * is in compared with other connections.
 * 
 * You may also query YapDatabase.snapshot to determine the most up-to-date snapshot among all connections.
 *
 * Example:
 * 
 * YapDatabase *database = [[YapDatabase alloc] init...];
 * database.snapshot; // returns zero
 *
 * YapDatabaseConnection *connection1 = [database newConnection];
 * YapDatabaseConnection *connection2 = [database newConnection];
 * 
 * connection1.snapshot; // returns zero
 * connection2.snapshot; // returns zero
 * 
 * [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *     [transaction setObject:objectA forKey:keyA];
 * }];
 * 
 * database.snapshot;    // returns 1
 * connection1.snapshot; // returns 1
 * connection2.snapshot; // returns 1
 * 
 * [connection1 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *     [transaction setObject:objectB forKey:keyB];
 *     [NSThread sleepForTimeInterval:1.0]; // sleep for 1 second
 *     
 *     connection1.snapshot; // returns 1 (we know it will turn into 2 once the transaction completes)
 * } completion:^{
 *     
 *     connection1.snapshot; // returns 2
 * }];
 * 
 * [connection2 asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){
 *     [NSThread sleepForTimeInterval:5.0]; // sleep for 5 seconds
 * 
 *     connection2.snapshot; // returns 1. See why?
 * }];
 *
 * It's because connection2 started its transaction when the database was in snapshot 1.
 * Thus, for the duration of its transaction, the database remains in that state.
 * 
 * However, once connection2 completes its transaction, it will automatically update itself to snapshot 2.
 *
 * In general, the snapshot is primarily for internal use.
 * However, it may come in handy for some tricky edge-case bugs (why doesn't my connection see that other commit?)
**/
@property (atomic, assign, readonly) uint64_t snapshot;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
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
- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block;

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
**/
- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block;

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block;

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
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock;

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
- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(dispatch_block_t)completionBlock
           completionQueue:(dispatch_queue_t)completionQueue;

/**
 * Read-write access to the database.
 * 
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
 * 
 * This method is asynchronous.
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block;

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayed if another sibling connection
 * is currently executing a read-write block.
 *
 * This method is asynchronous.
 * 
 * An optional completion block may be used.
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionBlock:(dispatch_block_t)completionBlock;

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayed if another sibling connection
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
                completionQueue:(dispatch_queue_t)completionQueue;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Long-Lived Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoke this method to start a long-lived read-only transaction.
 * This allows you to effectively create a stable state for the connection.
 * This is most often used for connections that service the main thread for UI data.
 * 
 * For a complete discussion, please see the wiki page:
 * https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
**/
- (NSArray *)beginLongLivedReadTransaction;
- (NSArray *)endLongLivedReadTransaction;

- (BOOL)isInLongLivedReadTransaction;

/**
 * A long-lived read-only transaction is most often setup on a connection that is designed to be read-only.
 * But sometimes we forget, and a read-write transaction gets added that uses the read-only connection.
 * This will implicitly end the long-lived read-only transaction. Oops.
 *
 * This is a bug waiting to happen.
 * And when it does happen, it will be one of those bugs that's nearly impossible to reproduce.
 * So its better to have an early warning system to help you fix the bug before it occurs.
 *
 * For a complete discussion, please see the wiki page:
 * https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
 *
 * In debug mode (#if DEBUG), these exceptions are turned ON by default.
 * In non-debug mode (#if !DEBUG), these exceptions are turned OFF by default.
**/
- (void)enableExceptionsForImplicitlyEndingLongLivedReadTransaction;
- (void)disableExceptionsForImplicitlyEndingLongLivedReadTransaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changesets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A YapDatabaseModifiedNotification is posted for every readwrite transaction that makes changes to the database.
 *
 * Given one or more notifications, these methods allow you to easily
 * query to see if a change affects a given collection, key, or combinary.
 *
 * This is most often used in conjunction with longLivedReadTransactions.
 *
 * For more information on longLivedReadTransaction, see the following wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
**/

// Query for any change to a collection

- (BOOL)hasChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications;
- (BOOL)hasObjectChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications;
- (BOOL)hasMetadataChangeForCollection:(NSString *)collection inNotifications:(NSArray *)notifications;

// Query for a change to a particular key/collection tuple

- (BOOL)hasChangeForKey:(NSString *)key
           inCollection:(NSString *)collection
        inNotifications:(NSArray *)notifications;

- (BOOL)hasObjectChangeForKey:(NSString *)key
                 inCollection:(NSString *)collection
              inNotifications:(NSArray *)notifications;

- (BOOL)hasMetadataChangeForKey:(NSString *)key
                   inCollection:(NSString *)collection
                inNotifications:(NSArray *)notifications;

// Query for a change to a particular set of keys in a collection

- (BOOL)hasChangeForAnyKeys:(NSSet *)keys
               inCollection:(NSString *)collection
            inNotifications:(NSArray *)notifications;

- (BOOL)hasObjectChangeForAnyKeys:(NSSet *)keys
                     inCollection:(NSString *)collection
                  inNotifications:(NSArray *)notifications;

- (BOOL)hasMetadataChangeForAnyKeys:(NSSet *)keys
                       inCollection:(NSString *)collection
                    inNotifications:(NSArray *)notifications;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates or fetches the extension with the given name.
 * If this connection has not yet initialized the proper extension connection, it is done automatically.
 * 
 * @return
 *     A subclass of YapDatabaseExtensionConnection,
 *     according to the type of extension registered under the given name.
 *
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 * 
 * @see YapDatabase registerExtension:withName:
**/
- (id)extension:(NSString *)extensionName;
- (id)ext:(NSString *)extensionName; // <-- Shorthand (same as extension: method)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Memory
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method may be used to flush the internal caches used by the connection,
 * as well as flushing pre-compiled sqlite statements.
 * Depending upon how often you use the database connection,
 * you may want to be more or less aggressive on how much stuff you flush.
 *
 * YapDatabaseConnectionFlushMemoryFlags_None:
 *     No-op. Doesn't flush anything.
 * 
 * YapDatabaseConnectionFlushMemoryFlags_Caches:
 *     Flushes all caches, including the object cache and metadata cache.
 * 
 * YapDatabaseConnectionFlushMemoryFlags_Statements:
 *     Flushes all pre-compiled sqlite statements.
 * 
 * YapDatabaseConnectionFlushMemoryFlags_All:
 *     Full flush of all caches and  pre-compiled sqlite statements.
**/
- (void)flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags;

#if TARGET_OS_IPHONE
/**
 * When a UIApplicationDidReceiveMemoryWarningNotification is received,
 * the code automatically invokes flushMemoryWithFlags and passes the set flags.
 * 
 * The default value is YapDatabaseConnectionFlushMemoryFlags_All.
 * 
 * @see flushMemoryWithFlags:
**/
@property (atomic, assign, readwrite) YapDatabaseConnectionFlushMemoryFlags autoFlushMemoryFlags;
#endif

@end
