#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Macro for lazy programmer (less typing than alloc/init)
#define YapCollectionKeyCreate(_collection, _key) [[YapCollectionKey alloc] initWithCollection:_collection key:_key]

/**
 * An efficient collection/key tuple class.
 *
 * Combines collection & key into a single object,
 * and provides the proper methods to use the object in various classes (such as NSDictionary, NSSet, etc).
**/
@interface YapCollectionKey : NSObject <NSCopying, NSCoding>

- (id)initWithCollection:(nullable NSString *)collection key:(NSString *)key;

@property (nonatomic, strong, readonly) NSString *collection;
@property (nonatomic, strong, readonly) NSString *key;

- (BOOL)isEqualToCollectionKey:(YapCollectionKey *)collectionKey;

// These methods are overriden and optimized:
- (BOOL)isEqual:(id)anObject;
- (NSUInteger)hash;

// C versions for low-level optimizations:

BOOL YapCollectionKeyEqual(const __unsafe_unretained YapCollectionKey *ck1,
                           const __unsafe_unretained YapCollectionKey *ck2);

CFHashCode YapCollectionKeyHash(const __unsafe_unretained YapCollectionKey *ck);

// For optimizing usage in YapCache
+ (CFDictionaryKeyCallBacks)keyCallbacks;

@end

NS_ASSUME_NONNULL_END
