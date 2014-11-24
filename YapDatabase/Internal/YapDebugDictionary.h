#import <Foundation/Foundation.h>


/**
 * This is a simple class to ensure that keys & objects we're putting into a dictionary are all of the desired class.
 * It's intended only for debugging purposes, especially in refactoring cases.
**/
@interface YapDebugDictionary : NSObject <NSCopying>

- (instancetype)initWithKeyClass:(Class)keyClass objectClass:(Class)objectClass;
- (instancetype)initWithKeyClass:(Class)keyClass objectClass:(Class)objectClass capacity:(NSUInteger)capacity;

- (instancetype)initWithDictionary:(YapDebugDictionary *)dictionary copyItems:(BOOL)copyItems;

// Inspection

- (id)objectForKey:(id)aKey;

- (void)setObject:(id)anObject forKey:(id)aKey;

- (void)removeObjectForKey:(id)aKey;

// Pass through

@property (nonatomic, readonly) NSUInteger count;

@property (nonatomic, readonly, copy) NSArray *allKeys;
@property (nonatomic, readonly, copy) NSArray *allValues;

- (NSEnumerator *)objectEnumerator;

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block;

@end
