#import <Foundation/Foundation.h>

/**
 * This class acts as a substitute for NSMutableDictionary.
 *
 * This is a rather simple class that allows read-only transactions to reference a mutable dictionary,
 * and removes any possibility of mutating it on accident.
 *
 * This class is not thread-safe. It is expected to be used within a serial queue.
**/
@interface YapReadOnlyMutableDictionary : NSObject

/**
 * Initializes a new instance with the given dictionary.
**/
- (id)initWithOriginalDictionary:(NSDictionary *)originalDictionary;

/**
 * The normal NSDictionary methods that are supported.
**/

- (NSUInteger)count;
- (NSArray *)allKeys;

- (id)objectForKey:(id)key;

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;

@end
