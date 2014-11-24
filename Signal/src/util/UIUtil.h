#import <Foundation/Foundation.h>

#import "UIColor+OWS.h"
#import "UIFont+OWS.h"

/**
 *
 * UIUtil contains various class methods that centralize common app UI functionality that would otherwise be hardcoded.
 *
 */

@interface UIUtil : NSObject

+ (void)applyRoundedBorderToImageView:(UIImageView *__strong*)imageView;
+ (void)removeRoundedBorderToImageView:(UIImageView *__strong*)imageView;

@end
