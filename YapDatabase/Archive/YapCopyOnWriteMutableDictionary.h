#import <Foundation/Foundation.h>

/**
 * This class acts as a substitute for NSMutableDictionary.
 * It starts with an original version, and proceeds to use it for read requests.
 * But if a request is made to modify the dictionary, the original dictionary is first copied,
 * and then the new "modified dictionary" is used going forward.
 * 
 * This is a rather simple class that allows write transactions to avoid the overhead of
 * copying the metadata dictionary if they don't make any changes to the database.
 * 
 * This class is not thread-safe. It is expected to be used within a serial queue.
**/
@interface YapCopyOnWriteMutableDictionary : NSObject

/**
 * Initializes a new instance with the given dictionary.
 * 
 * If the original dictionary is actually a mutable dictionary,
 * it should not be modified while this class is using it.
**/
- (id)initWithOriginalDictionary:(NSDictionary *)originalDictionary;

/**
 * The normal NSMutableDictionary methods that are supported.
**/

- (NSUInteger)count;
- (NSArray *)allKeys;

- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;

- (void)removeAllObjects;
- (void)removeObjectForKey:(id)key;
- (void)removeObjectsForKeys:(NSArray *)keys;

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;

/**
 * Returns whether or not the dictionary was modified.
**/
- (BOOL)isModified;

/**
 * If the dictionary was modified, returns the newly created and modified dictionary.
 * Otherwise returns nil.
**/
- (NSMutableDictionary *)modifiedDictionary;

@end
