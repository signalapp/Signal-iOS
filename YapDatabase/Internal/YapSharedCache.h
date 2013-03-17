#import <Foundation/Foundation.h>

@class YapSharedCacheConnection;

#define YAP_CACHE_DEBUG 0


@interface YapSharedCache : NSObject

/**
 * Initializes a cache.
 *
 * The keyClass is used for debugging, to ensure the proper key type is always used when accessing the cache.
 * This is used primarily for collection databases which use a special keyClass that combines the collection and key.
 * The keyClass is used within NSAssert statements that typically get compiled out for release builds.
**/
- (id)initWithKeyClass:(Class)keyClass;

/**
 * Returns the total number of items in the shared cache.
 * 
 * The value will be dependent upon how man connections there are, and what the limit is on each connection.
 * The theoretical max count is the sum of the limits of each connection.
 * However, in practice multiple connections will share objects, and total count will be much lower.
**/
@property (atomic, readonly) NSUInteger count;

/**
 * Creates and returns a new connection associated with the shared cache.
**/
- (YapSharedCacheConnection *)newConnection;

/**
 * This method works in conjuction with [YapAbstractDatabase notePendingChanges:fromConnection:].
 * It allows the shared cache to update the shared data.
 * 
 * The changeset block is retained until noteCommittedChangesetBlock:: is invoked.
**/
- (void)notePendingChangesetBlock:(int (^)(id key))changesetBlock
                         snapshot:(uint64_t)snapshot;

/**
 * This method works in conjuction with [YapAbstractDatabase noteCommittedChanges:fromConnection:].
 * It MUST only be called after all YapAbstractDatabaseConnections have processed the changeset.
 * It allows the shared cache to delete stale data.
**/
- (void)noteCommittedChangesetBlock:(int (^)(id key))changesetBlock
                           snapshot:(uint64_t)snapshot;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapSharedCacheConnection : NSObject

/**
 * Returns a reference to the 'parent' of the connection.
 *
 * A connection maintains a strong reference to the parent to ensure the parent cannot
 * be released while a connection is still alive. To ensure there are no retain cycles,
 * the parent does not maintain a strong reference to its children.
**/
@property (nonatomic, strong, readonly) YapSharedCache *sharedCache;

/**
 * The countLimit specifies the maximum number of items to keep in the cache.
 * This limit is strictly enforced.
 *
 * The default countLimit is 40.
 *
 * You may optionally disable the countLimit by setting it to zero.
 *
 * You may change the countLimit at any time.
 * Changes to the countLimit take immediate effect on the cache (before the set method returns).
 * Thus, if needed, you can temporarily increase the cache size for certain operations.
**/
@property (nonatomic, assign, readwrite) NSUInteger countLimit;

/**
 * Returns the total number of objects in this connection's local cache.
 * 
 * If you want to know the total number of objects in the shared cache (between all connections),
 * use sharedCacheConnection.sharedCache.count;
**/
@property (nonatomic, readonly) NSUInteger count;

/**
 * Begins a read only transaction.
 * 
 * The snapshot comes from the database layer, and represents the snapshot number (modification count).
 * The snapshot is used when reading objects from the shared cache,
 * to ensure we don't read stale data or future data (in relation to the given snapshot).
**/
- (void)startReadTransaction:(uint64_t)snapshot;

/**
 * The newSnapshot represents the snapshot of objects that get changed during this transaction.
 * It ensures that other connections don't read future data accidentally.
 * 
 * The changesetBlock is retained, and used throughout the transaction.
**/
- (void)startReadWriteTransaction:(uint64_t)newSnapshot
               withChangesetBlock:(int (^)(id key))changesetBlock;

/**
 * Ends the current transaction.
 * 
 * You must end your transaction before starting another.
 * You cannot nest transactions.
**/
- (void)endTransaction;

/**
 * Returns the cached object for the given key.
 * The local cache is inspected first, and then the shared cache (if needed).
 * 
 * For readWrite transactions, the changesetBlock is consulted before checking the shared cache.
 * That is, for readWrite transactions, before checking the shared cache the changesetBlock is used to
 * determine if the value has been deleted or modified during this transaction.
 * If so, then the shared cache is not consulted.
**/
- (id)objectForKey:(id)key;

/**
 * Adds the object to the local and shared cache.
 * 
 * The object will be associated with the current snapshot,
 * and so will only be readable by other connections on a snapshot greather-than or equal-to our snapshot.
**/
- (void)setObject:(id)object forKey:(id)key;

/**
 * Removes all cached objects from the local cache.
 * Items may also be removed from the shared cache if this connection was the only one using them.
**/
- (void)removeAllObjects;

/**
 * Removes the cached object for the given key from the local cache.
 * The item may also be removed from the shared cache if this connection was the only one using it.
**/
- (void)removeObjectForKey:(id)key;

/**
 * Removes the cached objects from the local cache.
 * Items may also be removed from the shared cache if this connection was the only one using them.
**/
- (void)removeObjectsForKeys:(NSArray *)keys;

/**
 * Enumerates over all keys in the local cache.
**/
- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))block;

/**
 * This method should be invoked after a sibling YapSharedCacheConnection has made changes.
 * This method must be invoked outside of a transaction.
 * 
 * @param changesetBlock
 *     The block take a key and returns one of the following values based on changes to that key:
 *     -1 : The key/value pair was deleted from the database. The connection will remove the cached value.
 *      0 : No changes made to key/value pair. The connection will leave the value untouched.
 *      1 : The value for the key was changed. The connection will refresh the value from the shared cache.
 * 
 * @param snapshot
 *      The snapshot number of the modification.
**/
- (void)noteCommittedChangesetBlock:(int (^)(id key))changesetBlock
                           snapshot:(uint64_t)snapshot;

//
// Some debugging stuff that gets compiled out
//

#if YAP_CACHE_DEBUG

/**
 * When querying the cache for an object via objectForKey:
 * 
 * - the localHitCount is incremented if the object is in the local cache
 * - the sharedHitCount is incremented if the object isn't in the local cache, but is found in the shared cache
 * - and the missCount is incremented if the object is not in either cache
**/
@property (nonatomic, readonly) NSUInteger localHitCount;
@property (nonatomic, readonly) NSUInteger sharedHitCount;
@property (nonatomic, readonly) NSUInteger missCount;

/**
 * When adding objects to the cache via setObject:forKey:
 * 
 * - the evictionCount is incremented if the cache is full,
 *   and the added object causes another object (the least recently used object) to be evicted.
**/
@property (nonatomic, readonly) NSUInteger evictionCount;

#endif

@end
