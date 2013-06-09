#import <Foundation/Foundation.h>


@interface YapCollectionsDatabaseViewPage : NSObject <NSCopying, NSCoding>

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity;

- (NSUInteger)count;

- (NSString *)collectionAtIndex:(NSUInteger)index;
- (NSString *)keyAtIndex:(NSUInteger)index;

- (void)getCollection:(NSString **)collectionPtr key:(NSString **)keyPtr atIndex:(NSUInteger)index;

- (NSUInteger)indexOfCollection:(NSString *)collection key:(NSString *)key;

- (void)removeObjectsAtIndex:(NSUInteger)index;
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes;

- (void)addCollection:(NSString *)collection key:(NSString *)key;
- (void)insertCollection:(NSString *)collection key:(NSString *)key atIndex:(NSUInteger)index;

- (void)enumerateWithBlock:(void (^)(NSString *collection, NSString *key, NSUInteger idx, BOOL *stop))block;

- (void)enumerateWithOptions:(NSEnumerationOptions)options
                  usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger idx, BOOL *stop))block;

- (void)enumerateIndexes:(NSIndexSet *)indexSet
             withOptions:(NSEnumerationOptions)options
              usingBlock:(void (^)(NSString *collection, NSString *key, NSUInteger idx, BOOL *stop))block;

@end
