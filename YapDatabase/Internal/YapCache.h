#import <Foundation/Foundation.h>

#define YAP_CACHE_STATISTICS 0

/**
 * YapCache implements a simple strict cache.
 *
 * It is very similar to NSCache and shares a similar API.
 * However, YapCache implements a strict countLimit and monitors usage so eviction is properly ordered.
 *
 * For example:
 * If you set a countLimit of 4, then when you add the 5th item to the cache, another item is automatically evicted.
 * It doesn't happen at a later time as with NSCache. It happens atomically during the addition of the 5th item.
 
 * Which item gets evicted? That depends entirely on usage.
 * YapCache maintains a doubly linked-list of keys ordered by access.
 * The most recently accessed key is at the front of the linked-list,
 * and the least recently accessed key is at the back.
 * So it's very quick and efficient to evict items based on recent usage.
 *
 * YapCache is NOT thread-safe.
 * It is designed to be used by the various YapDatabase classes, which inherently serialize access to the cache.
**/

@interface YapCache : NSObject

/**
 * Initializes a cache.
 *
 * Since the countLimit is a common configuration, it may optionally be passed during initialization.
 * This is also used as a hint internally when initializing components (i.e. [NSMutableDictionary initWithCapacity:]).
**/
- (id)initWithKeyClass:(Class)keyClass;
- (id)initWithKeyClass:(Class)keyClass countLimit:(NSUInteger)countLimit;

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

//
// The normal cache stuff...
//

- (void)setObject:(id)object forKey:(id)key;

- (id)objectForKey:(id)key;
- (BOOL)containsKey:(id)key;

- (NSUInteger)count;

- (void)removeAllObjects;
- (void)removeObjectForKey:(id)key;
- (void)removeObjectsForKeys:(NSArray *)keys;

- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))block;
- (void)enumerateKeysAndObjectsWithBlock:(void (^)(id key, id obj, BOOL *stop))block;

//
// Some debugging stuff that gets compiled out
//

#if YAP_CACHE_STATISTICS

/**
 * When querying the cache for an object via objectForKey,
 * the hitCount is incremented if the object is in the cache,
 * and the missCount is incremented if the object is not in the cache.
**/
@property (nonatomic, readonly) NSUInteger hitCount;
@property (nonatomic, readonly) NSUInteger missCount;

/**
 * When adding objects to the cache via setObject:forKey:,
 * the evictionCount is incremented if the cache is full,
 * and the added object causes another object (the least recently used object) to be evicted.
**/
@property (nonatomic, readonly) NSUInteger evictionCount;

#endif

@end
