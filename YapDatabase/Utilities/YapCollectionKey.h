#import <Foundation/Foundation.h>


/**
 * An efficient collection/key tuple class.
 *
 * Combines collection & key into a single object,
 * and provides the proper methods to use the object in various classes (such as NSDictionary, NSSet, etc).
**/
@interface YapCollectionKey : NSObject <NSCopying, NSCoding>

YapCollectionKey* YapCollectionKeyCreate(NSString *collection, NSString *key);

- (id)initWithCollection:(NSString *)collection key:(NSString *)key;

@property (nonatomic, strong, readonly) NSString *collection;
@property (nonatomic, strong, readonly) NSString *key;

- (BOOL)isEqualToCollectionKey:(YapCollectionKey *)collectionKey;

// These methods are overriden and optimized:
- (BOOL)isEqual:(id)anObject;
- (NSUInteger)hash;

// Super optimized:
BOOL YapCollectionKeyEqual(__unsafe_unretained YapCollectionKey *ck1, __unsafe_unretained YapCollectionKey *ck2);

@end
