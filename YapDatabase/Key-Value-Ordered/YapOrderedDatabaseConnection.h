#import <Foundation/Foundation.h>

#import "YapDatabaseConnection.h"
#import "YapDatabaseOrder.h"

@class YapOrderedDatabase;
@protocol YapOrderedReadTransaction;
@protocol YapOrderedReadWriteTransaction;

#define YapOrderedDatabaseReadTransaction \
        YapDatabaseReadTransaction <YapOrderedReadTransaction>

#define YapOrderedDatabaseReadWriteTransaction \
		YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction>

/**
 * A connection provides a point of access to the database.
 *
 * You first create and configure a database instance.
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
@interface YapOrderedDatabaseConnection : YapDatabaseConnection <YapOrderReadTransaction>

/* Inherited from YapDatabaseConnection:

@property (nonatomic, assign, readwrite) BOOL objectCacheEnabled;
@property (nonatomic, assign, readwrite) NSUInteger objectCacheLimit;

@property (nonatomic, assign, readwrite) BOOL metadataCacheEnabled;
@property (nonatomic, assign, readwrite) NSUInteger metadataCacheLimit;

*/

/**
 * A database connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * A YapDatabase instance cannot be deallocated if a corresponding YapDatabaseConnection is still alive.
 *
 * It is sometimes convenient to retain an ivar only for the connection, and not the database itself.
**/
@property (nonatomic, strong, readonly) YapOrderedDatabase *orderedDatabase;

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
**/
- (void)readWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block;

/**
 * Read-write access to the database.
 *
 * Only a single readwrite block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a readwrite block.
**/
- (void)readWriteWithBlock:(void (^)(YapOrderedDatabaseReadWriteTransaction *transaction))block;

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block;

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
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWithBlock:(void (^)(YapOrderedDatabaseReadTransaction *transaction))block
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
- (void)asyncReadWriteWithBlock:(void (^)(YapOrderedDatabaseReadWriteTransaction *transaction))block;

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
                completionBlock:(dispatch_block_t)completionBlock;

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
                completionQueue:(dispatch_queue_t)completionQueue;

@end
