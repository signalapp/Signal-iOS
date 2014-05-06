#import <Foundation/Foundation.h>

/**
 *
 * UTUtil contains various class methods that centralize common app UI functionality that would otherwise be hardcoded.
 *
 */

@interface UIUtil : NSObject

+ (UIFont *)helveticaNeueLTStdLightFontWithSize:(CGFloat)size;
+ (UIFont *)helveticaNeueLTStdBoldFontWithSize:(CGFloat)size;
+ (UIFont *)helveticaNeueLTStdMediumFontWithSize:(CGFloat)size;
+ (UIFont *)helveticaRegularWithSize:(CGFloat)size;
+ (UIFont *)helveticaLightWithSize:(CGFloat)size;
+ (UIColor*)darkBackgroundColor;
+ (UIColor*)blueColor;
+ (UIColor*)yellowColor;
+ (UIColor*)redColor;
+ (UIColor*)greenColor;
+ (UIColor*)whiteColor;
+ (UIColor*)transparentLightGrayColor;
+ (void)applyRoundedBorderToImageView:(UIImageView *__strong*)imageView;
+ (void)removeRoundedBorderToImageView:(UIImageView *__strong*)imageView;

@end
