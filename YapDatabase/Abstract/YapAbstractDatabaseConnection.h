#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"

@class YapAbstractDatabase;

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 * 
 * This is the base class which is shared by YapDatabaseConnection and YapCollectionsDatabaseConnection.
 *
 * - YapDatabase = Key/Value
 * - YapCollectionsDatabase = Collection/Key/Value
 * 
 * From a single YapDatabase (or YapCollectionsDatabase) instance you can create multiple connections.
 * Each connection is thread-safe and may be used concurrently.
 *
 * YapAbstractDatabaseConnection provides the generic implementation of a database connection such as:
 * - common properties
 * - common initializers
 * - common setup code
 * - stub methods which are overriden by subclasses
 * 
 * @see YapDatabaseConnection.h
 * @see YapCollectionsDatabaseConnection.h
**/

typedef enum  {
	YapDatabaseConnectionFlushMemoryLevelNone     = 0,
	YapDatabaseConnectionFlushMemoryLevelMild     = 1,
	YapDatabaseConnectionFlushMemoryLevelModerate = 2,
	YapDatabaseConnectionFlushMemoryLevelFull     = 3,
} YapDatabaseConnectionFlushMemoryLevel;

typedef enum {
	YapDatabasePolicyShare       = 0,
	YapDatabasePolicyContainment = 1,
} YapDatabasePolicy;


@interface YapAbstractDatabaseConnection : NSObject

/**
 * A database connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * A database instance cannot be deallocated if a corresponding connection is stil alive.
 *
 * If you use only a single connection,
 * it is sometimes convenient to retain an ivar only for the connection, and not the database itself.
**/
@property (nonatomic, strong, readonly) YapAbstractDatabase *abstractDatabase;

/**
 * The optional name property assists in debugging.
 * It is only used internally for log statements.
**/
@property (atomic, copy, readwrite) NSString *name;

#pragma mark Cache

/**
 * Each database connection maintains an independent cache of deserialized objects.
 * This reduces the overhead of the deserialization process.
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
 * @see YapAbstractDatabase defaultObjectCacheEnabled
 * @see YapAbstractDatabase defaultObjectCacheLimit
 * 
 * Also see the wiki for a bit more info:
 * https://github.com/yaptv/YapDatabase/wiki/Cache
**/
@property (atomic, assign, readwrite) BOOL objectCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger objectCacheLimit;

/**
 * Each database connection maintains an independent cache of deserialized metadata.
 * This reduces the overhead of the deserialization process.
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
 * @see YapAbstractDatabase defaultMetadataCacheEnabled
 * @see YapAbstractDatabase defaultMetadataCacheLimit
 *
 * Also see the wiki for a bit more info:
 * https://github.com/yaptv/YapDatabase/wiki/Cache
**/
@property (atomic, assign, readwrite) BOOL metadataCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger metadataCacheLimit;

#pragma mark Policy

/**
 * YapDatabase uses various optimizations to reduce overhead and memory footprint.
 * 
 * These optimizations are discussed extensively in the wiki article "Thread Safety":
 * https://github.com/yaptv/YapDatabase/wiki/Thread-Safety
 * 
 * The policy properties allow you to opt out of these optimizations if needed.
 * 
 * The default value is YapDatabasePolicyShare.
**/
@property (atomic, assign, readwrite) YapDatabasePolicy objectPolicy;
@property (atomic, assign, readwrite) YapDatabasePolicy metadataPolicy;

#pragma mark State

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
 * You may also query YapAbstractDatabase.snapshot to determine the most up-to-date snapshot among all connections.
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

#pragma mark Long-Lived Transactions

/**
 * Invoke this method to start a long-lived read-only transaction.
 * This allows you to effectively create a stable state for the connection.
 * This is most often used for connections that service the main thread for UI data.
 * 
 * For a complete discussion, please see the wiki page:
 * https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
 * 
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

#pragma mark Extensions

/**
 * Creates or fetches the extension with the given name.
 * If this connection has not yet initialized the proper extension connection, it is done automatically.
 * 
 * @return
 *     A subclass of YapAbstractDatabaseExtensionConnection,
 *     according to the type of extension registered under the given name.
 *
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 * 
 * @see [YapAbstractDatabase registerExtension:withName:]
**/
- (id)extension:(NSString *)extensionName;
- (id)ext:(NSString *)extensionName; // <-- Shorthand (same as extension: method)

#pragma mark Memory

/**
 * This method may be used to flush the internal caches used by the connection,
 * as well as flushing pre-compiled sqlite statements.
 * Depending upon how often you use the database connection,
 * you may want to be more or less aggressive on how much stuff you flush.
 *
 * YapDatabaseConnectionFlushMemoryLevelNone (0):
 *     No-op. Doesn't flush any caches or anything from internal memory.
 * 
 * YapDatabaseConnectionFlushMemoryLevelMild (1):
 *     Flushes the object cache and metadata cache.
 * 
 * YapDatabaseConnectionFlushMemoryLevelModerate (2):
 *     Mild plus drops less common pre-compiled sqlite statements.
 * 
 * YapDatabaseConnectionFlushMemoryLevelFull (3):
 *     Full flush of all caches and removes all pre-compiled sqlite statements.
**/
- (void)flushMemoryWithLevel:(int)level;

#if TARGET_OS_IPHONE
/**
 * When a UIApplicationDidReceiveMemoryWarningNotification is received,
 * the code automatically invokes flushMemoryWithLevel and passes this set level.
 * 
 * The default value is YapDatabaseConnectionFlushMemoryLevelMild.
 * 
 * @see flushMemoryWithLevel:
**/
@property (atomic, assign, readwrite) int autoFlushMemoryLevel;
#endif

@end
