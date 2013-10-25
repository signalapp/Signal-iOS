#import <Foundation/Foundation.h>

/**
 * Singleton class to represent the "value" for a key that was touched. (i.e. value didn't change)
 *
 * YapDatabase stores changesets in dictionaries, where the object represents the updated value for a key.
 * When an item is touched, we use this singleton as the value to signify internally that the item didn't change.
 * This allows us to act as if the item did change in most all respects,
 * but internally won't cause us to flush the item from the caches.
**/
@interface YapTouch : NSObject

+ (id)touch;

@end
