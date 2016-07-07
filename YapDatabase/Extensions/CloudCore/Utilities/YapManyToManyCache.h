/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

/**
 * A many-to-many cache has the following features:
 * 
 * - store multiple values for the same key
 * - efficient map from key to value(s)
 * - efficient map from value to key(s)
 * - store arbitrary metadata along with key/value tuple
 * - strict cache size
 * - eviction based on least-recently-used
 * 
 * The cache maintains a sorted array based on the keys.
 * So a lookup based on the key can be performed in O(log n) using a binary search algoritm.
 * 
 * Similarly, the cache also maintains a sorted array based on the values.
 * So a lookup based on the value can be performed in O(log n) using a binary search algorithm.
 * 
 * Thus, as opposed to a traditional dictionary/hashmap,
 * it is efficient to perform lookups on either the key or value.
 * Perhaps a better name for {key,value} would have been {keyA,keyB},
 * however the key/value nomenclature is more accessible (and arguably much less confusing than keyA/keyB).
 *
 * Keep in mind that, although there can be multiple values for a given key,
 * the same key/value tuple can only be inserted once.
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
@interface YapManyToManyCache : NSObject

/**
 * Initializes a cache.
 * If you don't define a countLimit, then the default countLimit of 40 is used.
 * 
 * @see countLimit
**/
- (instancetype)init;
- (instancetype)initWithCountLimit:(NSUInteger)countLimit;

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
 * Returns the number of items in the cache.
**/
@property (nonatomic, readonly) NSUInteger count;

/**
 * Inserts the given key/value tuple.
 * 
 * Keep in mind that although multiple values for the same key are allowed,
 * a specific key/value tuple is only allowed to exist once in the structure.
 *
 * So if the key/value tuple already exists in the cache, then it it not inserted again.
 * However, this method will always replace the metadata for the tuple with the given value.
 * 
 * The key & value must be non-nil.
 * The key & value must implement the following methods:
 * - (BOOL)isEqual:(id)another
 * - (NSComparisonResult)compare:(id)another
 * 
 * If the key/value tuple already exists, it's metadata value is used using the given metadata.
 * And then the key/value tuple is moved to the beginning of the most-recently-used linked-list.
**/
- (void)insertKey:(id)key value:(id)value;
- (void)insertKey:(id)key value:(id)value metadata:(id)metadata;

/**
 * Returns whether or not the cache contains the key/value tuple.
 * 
 * The key & value must be non-nil.
 * If you're only interested in matches for a key or value (but not together) use a different method.
**/
- (BOOL)containsKey:(id)key value:(id)value;

/**
 * Returns the metadata for the given key/value tuple.
 * 
 * Returns nil if the given key/value tuple doesn't exist in the cache,
 * or if the key/value tuple doesn't have any associated metadata.
 * 
 * If the key/value tuple exists, it's moved to the beginning of the most-recently-used linked-list.
**/
- (id)metadataForKey:(id)key value:(id)value;

/**
 * Returns YES if the given key or value has 1 or more entries in the cache.
**/
- (BOOL)containsKey:(id)key;
- (BOOL)containsValue:(id)value;

/**
 * Returns the number of entries for the given key or value.
**/
- (NSUInteger)countForKey:(id)key;
- (NSUInteger)countForValue:(id)value;

/**
 * Allows you to enumerate:
 * - all values based on a given key
 * - all keys based on a given value
 * 
 * All key/value tuples accessed during enumeration are moved to the beginning of the most-recently-used linked-list.
**/
- (void)enumerateValuesForKey:(id)key withBlock:(void (^)(id value, id metadata, BOOL *stop))block;
- (void)enumerateKeysForValue:(id)value withBlock:(void (^)(id value, id metadata, BOOL *stop))block;

/**
 * Enumerates all key/value pairs in the cache.
 * 
 * As this method is designed to enumerate all values, it ddes not affect the most-recently-used linked-list.
**/
- (void)enumerateWithBlock:(void (^)(id key, id value, id metadata, BOOL *stop))block;

/**
 * Removes the tuple that matches the given key/value pair.
 *
 * The key & value must be non-nil.
 * If you're only interested in matches for a key or value (but not together) use a different method.
**/
- (void)removeItemWithKey:(id)key value:(id)value;

/**
 * Removes all tuples that match the given key or value.
**/
- (void)removeAllItemsWithKey:(id)key;
- (void)removeAllItemsWithValue:(id)value;

/**
 * Removes all items in the cache.
 * Upon return the count will be zero.
**/
- (void)removeAllItems;

- (void)debug;

@end
