#import <Foundation/Foundation.h>

#ifndef YapBidirectionalCache_Enable_Statistics
  #define YapBidirectionalCache_Enable_Statistics 0
#endif

NS_ASSUME_NONNULL_BEGIN

struct YapBidirectionalCacheCallBacks {
	int32_t version;
 	BOOL shouldCopy;
	CFDictionaryEqualCallBack equal;
	CFDictionaryHashCallBack hash;
};
typedef struct YapBidirectionalCacheCallBacks YapBidirectionalCacheCallBacks;

extern const YapBidirectionalCacheCallBacks kYapBidirectionalCacheDefaultCallBacks;

/**
 * A bidirectional cache has the following features:
 *
 * - stores <key, value> pairs
 * - supports a single value per key
 * - supports a single key per value
 * - efficient mapping from key to value
 * - efficient mapping from value to key
 * - optional strict cache size
 * - eviction based on least-recently-used
 *
 * The cache maintains two dictionaries internally.
 * One mapping from key to value.
 * And the other mapping from value to key.
 * So a lookup based on the either the key or value can be performed in O(1).
 *
 * Caching:
 *
 * When the countLimit is non-zero,
 *   this class operates as a cache, enforcing the designed limit, and using eviction when the limit is exceeded.
 * When the countLimit is zero,
 *   this class operates as a generic container (with no limit, and no automatic eviction).
 *
 * Eviction depends entirely on usage.
 * The cache maintains a doubly linked-list of tuples ordered by access.
 * The most recently accessed item is at the front of the linked-list,
 * and the least recently accessed item is at the back.
 * So it's very quick and efficient to evict items based on recent usage.
**/
@interface YapBidirectionalCache<KeyType, ObjectType> : NSObject

/**
 * Initializes a cache.
 * If you don't define a countLimit, then the default countLimit of 40 is used.
**/
- (instancetype)init;
- (instancetype)initWithCountLimit:(NSUInteger)countLimit;

/**
 * Advanced init method allows you to define the CallBacks for the keys & objects
 * to be used by the internal CFDictionaries.
 * 
 * The default value for callbacks is : {
 *   version = 0,
 *   shouldCopy = NO,
 *   equal = CFEqual,
 *   hash = CFHash
 * }
**/
- (instancetype)initWithCountLimit:(NSUInteger)countLimit
                      keyCallbacks:(const YapBidirectionalCacheCallBacks * _Nullable)keyCallbacks
                   objectCallbacks:(const YapBidirectionalCacheCallBacks * _Nullable)objectCallbacks;

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
 * These methods are for "debugging".
 *
 * They allows you to specify a set of classes that you intend to use for the keys and/or values.
 * If set, the class will check to ensure you're always using the proper class type when you set or query the cache.
 *
 * You can think of this feature as something similar to templates / generic types in C++.
 * Except that it's run-time enforcement, and not compile-time.
 *
 * Since this is for debugging, the checks are ONLY run when assertions are enabled.
 * In general, assertions are disabled when you compile for release.
 * But to be precise, the checks are only run if NS_BLOCK_ASSERTIONS is not defined.
**/
@property (nonatomic, copy, readwrite, nullable) NSSet<Class> *allowedKeyClasses;
@property (nonatomic, copy, readwrite, nullable) NSSet<Class> *allowedObjectClasses;

#if YapBidirectionalCache_Enable_Statistics

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

- (nullable ObjectType)objectForKey:(KeyType)key;
- (BOOL)containsKey:(KeyType)key;

- (nullable KeyType)keyForObject:(ObjectType)object;
- (BOOL)containsObject:(ObjectType)object;

- (NSUInteger)count;

- (void)setObject:(ObjectType)object forKey:(KeyType)key;

- (void)removeAllObjects;

- (void)removeObjectForKey:(KeyType)key;
- (void)removeObjectsForKeys:(id <NSFastEnumeration>)keys;

- (void)removeKeyForObject:(ObjectType)object;
- (void)removeKeysForObjects:(id <NSFastEnumeration>)objects;

- (void)enumerateKeysWithBlock:(void (^)(KeyType key, BOOL *stop))block;
- (void)enumerateObjectsWithBlock:(void (^)(ObjectType object, BOOL *stop))block;
- (void)enumerateKeysAndObjectsWithBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
