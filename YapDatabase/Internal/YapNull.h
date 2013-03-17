#import <Foundation/Foundation.h>

/**
 * There are various situations in which we need to add a placeholder to signify a nil value.
 * For example, we need to cache the fact that the metadata for a given key is nil.
 *
 * However, we cannot add a nil object to a dictionary.
 * And we cannot use NSNull, or we prevent the user from using NSNull for their own purposes.
 * 
 * And thus, we replicate NSNull, and use it instead.
 * And now the user is free to use NSNull if needed.
**/
@interface YapNull : NSObject

+ (id)null;

@end
