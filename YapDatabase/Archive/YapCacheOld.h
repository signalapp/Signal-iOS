#import <Foundation/Foundation.h>

/**
 * YapCache implements a simple strict cache.
 * 
 * It is very similar to NSCache.
 * They both share a similar API, and they both automatically purge items during low-memory conditions (iOS).
 * However, YapCache implements a strict countLimit and monitors usage so eviction is properly ordered.
 * 
 * For example:
 * If you set a countLimit of 4, then when you add the 5th item to the cache, another item is automatically evicted.
 * It doesn't happen at a later time as with NSCache. It happens atomically during the addition of the 5th item.
 
 * Which item gets evicted? That depends entirely on usage.
 * YapCache maintains an ordered list based on which keys have been most recently accessed or added.
 * So when you fetch an item from the cache, that item goes to the end of the eviction list.
 * Thus, the item evicted is always the least recently used item.
 * 
 * YapCache defaults to using a thread-safe architecture, serializing access to itself using an internal serial queue.
 * If you already serialize access to the cache externall, you may optionally disable this feature.
**/
@interface YapCacheOld : NSObject

/**
 * Initializes a cache.
 * 
 * Since the countLimit is a common configuration, it may optionally be passed during initialization.
 * This is als used as hint internally when initializing components (i.e. [NSMutableDictionary initWithCapacity:]).
 * 
 * Unless configured otherwise, the cache will be thread-safe.
**/
- (id)init;
- (id)initWithCountLimit:(NSUInteger)countLimit;
- (id)initWithCountLimit:(NSUInteger)countLimit threadSafe:(BOOL)shouldUseInternalSerialQueue;

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
 * The normal cache stuff...
**/

- (void)setObject:(id)object forKey:(id)key;

- (id)objectForKey:(id)key;

- (NSUInteger)count;

- (void)removeAllObjects;
- (void)removeObjectForKey:(id)key;
- (void)removeObjectsForKeys:(NSArray *)keys;

/**
 * Atomic operation that performs the following:
 * 
 * if ([cache objectForKey:key] != nil)
 *     [cache setObject:object forKey:key];
 * 
 * This is useful when updating objects in the database. When doing so, you obviously need to update
 * the object in the cache. But if the object isn't already in the cache, it may not be optimal to
 * add it to the cache and thus risk evicting other objectst that are in use.
**/
- (void)replaceObjectIfExistsForKey:(id)key withObject:(id)object;

@end
