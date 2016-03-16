#import <Foundation/Foundation.h>

#ifndef YapCache_Enable_Statistics
  #define YapCache_Enable_Statistics 0
#endif

NS_ASSUME_NONNULL_BEGIN

/**
 * YapCache implements a simple strict cache.
 *
 * It is very similar to NSCache and shares a similar API.
 * However, YapCache implements a strict countLimit and monitors usage so eviction is properly ordered.
 *
 * For example:
 * If you set a countLimit of 4, then when you add the 5th item to the cache, another item is automatically evicted.
 * It doesn't happen at a later time as with NSCache. It happens atomically during the addition of the 5th item.
 *
 * Which item gets evicted depends entirely on usage.
 * YapCache maintains a doubly linked-list of keys ordered by access.
 * The most recently accessed key is at the front of the linked-list,
 * and the least recently accessed key is at the back.
 * So it's very quick and efficient to evict items based on recent usage.
 *
 * YapCache is considerably faster than NSCache.
 * The project even comes with a benchmarking tool for comparing the speed of YapCache vs NSCache.
 * 
 * However, YapCache is NOT thread-safe. (Whereas NSCache is.)
 * This is because YapCache was designed specifically for performance.
 * Thus it's NOT recommended you use YapCache unless you're always going to be using it from the same thread,
 * or from within the same serial dispatch queue. The various YapDatabase classes which use it inherently
 * serialize access to the cache via their own internal serial queue.
 * 
 * Also, YapCache does NOT automatically purge itself in the even of a low memory condition. (Whereas NSCache does.)
 * This also has to do with YapCache not being thread-safe.
 * And thus performing this action (if desired) is up to you.
 * The various YapDatabase classes which use it do this themselves.
**/
@interface YapCache<KeyType, ObjectType> : NSObject

/**
 * Initializes a cache.
 * If you don't define a countLimit, then the default countLimit of 40 is used.
**/
- (instancetype)init;
- (instancetype)initWithCountLimit:(NSUInteger)countLimit;

/**
 * This init method allows you to define the keyCallbacks to be used by the internal CFDictionary.
 * This is useful for a number of reasons.
 * 
 * By default (if you use the other init methods), YapCache will use kCFTypeDictionaryKeyCallBacks.
 * This means that the keys you use with the cache will be retained, and not copied.
 * This is also how NSCache works. But is not how NSMutableDictionary works.
 * In contrast NSMutableDictionary will copy (not retain) the keys you give it.
 * In general:
 * - retaining the keys is faster
 * - copying the keys is safer
 *
 * But, in truth, it all depends on what you're using for keys. If you're using something like NSNumber,
 * or some other immutable class, then there's no point in worrying about copying. But if you're using strings,
 * and there's a possibility you might be using mutable strings, then copying is much safer.
 * 
 * So basically, if you want a cache-style dictionary (limit enforcing), but you need the key-copy safety similar to
 * NSMutableDictionary, then you can pass kCFCopyStringDictionaryKeyCallBacks to get it.
 * 
 * Additionally, you can sometimes customize the keyCallbacks to get a performance boost.
 * Various classes within YapDatabase, which use YapCache, use a YapCollectionKey object as the key.
 * And the YapCollectionKey class actually provides its own CFDictionaryKeyCallBacks struct that provides
 * a nice little performance boost.
**/
- (instancetype)initWithCountLimit:(NSUInteger)countLimit keyCallbacks:(CFDictionaryKeyCallBacks)keyCallbacks;

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

//
// The normal cache stuff...
//

- (void)setObject:(ObjectType)object forKey:(KeyType)key;

- (nullable ObjectType)objectForKey:(KeyType)key;
- (BOOL)containsKey:(KeyType)key;

- (NSUInteger)count;

- (void)removeAllObjects;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeObjectsForKeys:(id <NSFastEnumeration>)keys;

- (void)enumerateKeysWithBlock:(void (^)(KeyType key, BOOL *stop))block;
- (void)enumerateKeysAndObjectsWithBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;

//
// Some debugging stuff that gets compiled out
//

#if YapCache_Enable_Statistics

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

NS_ASSUME_NONNULL_END
