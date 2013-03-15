#import <Foundation/Foundation.h>


/**
 * Classes like NSDictionary, YapCache, and YapSharedCache use key/value pairs.
 * But the collection databases use collection/key/value pairs.
 * 
 * This class allows you to combine the collection & key into a single unit,
 * and provides the proper methods to use the object as a key in dictionary-like classes.
**/
@interface YapCacheCollectionKey : NSObject <NSCopying>

- (id)initWithCollection:(NSString *)collection key:(NSString *)key;

@property (nonatomic, strong, retain) NSString *collection;
@property (nonatomic, strong, retain) NSString *key;

- (BOOL)isEqual:(id)anObject;
- (NSUInteger)hash;

@end
