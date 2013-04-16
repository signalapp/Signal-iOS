#import <Foundation/Foundation.h>


/**
 * Classes like NSDictionary and YapCache use key/value pairs.
 * But the collection databases use collection/key/value pairs.
 * 
 * This class allows you to combine the collection & key into a single unit,
 * and provides the proper methods to use the object as a key in dictionary-like classes (e.g. YapCache).
**/
@interface YapCacheCollectionKey : NSObject <NSCopying>

- (id)initWithCollection:(NSString *)collection key:(NSString *)key;

@property (nonatomic, strong, readonly) NSString *collection;
@property (nonatomic, strong, readonly) NSString *key;

- (BOOL)isEqual:(id)anObject;
- (NSUInteger)hash;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Classes like NSDictionary and YapCache use key/value pairs.
 * But views may use section/key/value pairs.
 * 
 * This class allows you to combine the section & key into a single unit,
 * and provides the proper methods to use the object as a key in dictionary-like classes (e.g. YapCache).
**/
@interface YapCacheSectionKey : NSObject <NSCopying>

- (id)initWithSection:(NSUInteger)section key:(NSString *)key;

@property (nonatomic, assign, readonly) NSUInteger section;
@property (nonatomic, strong, readonly) NSString *key;

- (BOOL)isEqual:(id)anObject;
- (NSUInteger)hash;

@end
