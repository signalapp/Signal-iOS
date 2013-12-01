#import <Foundation/Foundation.h>

@class YapMemoryTableTransaction;


/**
 * A "memory table" is a dictionary that supports versioning.
 * There may be multiple values for a single key, with each value associated with a different snapshot.
 * 
 * The memory table is accessed via a YapMemoryTableTransaction instance,
 * which is itself associated with a particular timestamp. Thus the transaction is able to properly identify
 * which version is appropriate for itself.
**/
@interface YapMemoryTable : NSObject

/**
 * Initializes a memory table.
 *
 * The keyClass is used for debugging, to ensure the proper key type is always used when accessing the table.
 * The keyClass is used within NSAssert statements that typically get compiled out for release builds.
**/
- (id)initWithKeyClass:(Class)keyClass;

/**
 * Creates and returns a new connection associated with the shared cache.
**/
- (YapMemoryTableTransaction *)newReadTransactionWithSnapshot:(uint64_t)snapshot;
- (YapMemoryTableTransaction *)newReadWriteTransactionWithSnapshot:(uint64_t)snapshot;

/**
 * Invoked automatically by YapDatabase architecture.
**/
- (void)asyncCheckpoint:(int64_t)minSnapshot;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapMemoryTableTransaction : NSObject

@property (nonatomic, readonly) uint64_t snapshot;
@property (nonatomic, readonly) BOOL isReadWriteTransaction;

- (id)objectForKey:(id)key;

- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))block;

- (void)enumerateKeysAndObjectsWithBlock:(void (^)(id key, id obj, BOOL *stop))block;

//
// For ReadWrite transactions:

- (void)setObject:(id)object forKey:(id)key;

- (void)removeObjectForKey:(id)key;
- (void)removeObjectsForKeys:(NSArray *)keys;

- (void)removeAllObjects;

//
// Batch access / modifications

- (void)accessWithBlock:(dispatch_block_t)block;
- (void)modifyWithBlock:(dispatch_block_t)block;

//
// Transaction state

- (void)commit;
- (void)rollback;

@end
