#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * YapDirtyDictionary is a simple wrapper around NSMutableDictionary that
 * tracks both the current value & the original value.
 * This makes it easy to see what values have truely changed.
 *
 * It's helpful in situations where a particular value may change multiple times,
 * but the final value ultimately remains the same as the original value.
 * This information allows us to skip disk IO which isn't needed.
**/
@interface YapDirtyDictionary<KeyType, ObjectType> : NSObject

- (instancetype)init;
- (instancetype)initWithCapacity:(NSUInteger)capacity;

- (NSUInteger)count;

/**
 * Returns the current value, regardless of whether it's "dirty" or "clean".
**/
- (nullable id)objectForKey:(KeyType)key;

/**
 * Returns the current value, but only if it's "dirty" (doesn't match the original value).
**/
- (nullable id)dirtyValueForKey:(KeyType)key;

/**
 * Returns the original value (the oldest previousValue for the key).
**/
- (nullable id)originalValueForKey:(KeyType)key;

/**
 * Sets the current value for the key.
 *
 * When making the change, you should attempt to set the previous value.
 * The first time a value is set for a particular key, the previous value will be stored alongside it.
 * Subsequent changes to a value won't modify the original 'previous value'.
**/
- (void)setObject:(ObjectType)object forKey:(KeyType)key withPreviousValue:(nullable ObjectType)prevObj;

/**
 * Removes all objects from the dictionary, and all stored original values too.
 *
 * Use this method when you no longer need to track anything using the dictionary,
 * and you simply want a clean slate.
**/
- (void)removeAllObjects;

/**
 * Removes only those objects from the dictionary for which the current value matches the original value.
 * 
 * Use this method when you're done tracking changes,
 * and you want to pass the dictionary to other connections (e.g. in a changeset).
**/
- (void)removeCleanObjects;

/**
 * Enumerates all key/value pairs, including both "dirty" & "clean" values.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;

/**
 * Enumerates only the key/value pairs that are dirty (current value differs from original value).
**/
- (void)enumerateDirtyKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
