#import "UIUtil.h"

static NSString *const HELVETICA_NEUE_LTSTD_LIGHT_NAME = @"HelveticaNeueLTStd-Lt";
static NSString *const HELVETICA_NEUE_LTSTD_BOLD_NAME = @"HelveticaNeueLTStd-Bold";
static NSString *const HELVETICA_NEUE_LTSTD_MEDIUM_NAME = @"HelveticaNeueLTStd-Md";
static NSString *const HELVETICA_REGULAR_NAME = @"Helvetica";
static NSString *const HELVETICA_LIGHT_NAME = @"Helvetica-Light";

#define CONTACT_PICTURE_VIEW_BORDER_WIDTH 2.0f

@implementation UIUtil

+ (UIFont*)helveticaNeueLTStdLightFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_LIGHT_NAME size:size];
}

+ (UIFont*)helveticaNeueLTStdBoldFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_BOLD_NAME size:size];
}

+ (UIFont*)helveticaNeueLTStdMediumFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_MEDIUM_NAME size:size];
}

+ (UIFont*)helveticaRegularWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_REGULAR_NAME size:size];
}

+ (UIFont*)helveticaLightWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_LIGHT_NAME size:size];
}

+ (UIColor*)darkBackgroundColor {
    return [UIColor colorWithRed:35.0f/255.0f green:31.0f/255.0f blue:32.0f/255.0f alpha:1.0f];
}

+ (UIColor*)blueColor {
    return [UIColor colorWithRed:0.0f green:174.0f/255.0f blue:239.0f/255.0f alpha:1.0f];
}

+ (UIColor*)yellowColor {
    return [UIColor colorWithRed:1.0f green:221.0f/255.0f blue:170.0f/255.0f alpha:1.0f];
}

+ (UIColor*)redColor {
    return [UIColor colorWithRed:237.0f/255.0f green:96.0f/255.0f blue:98.0f/255.0f alpha:1.0f];
}

+ (UIColor *)greenColor {
    return [UIColor colorWithRed:0.0f green:199.0f/255.0f blue:149.0f/255.0f alpha:1.0f];
}

+ (UIColor*)whiteColor {
    return [UIColor colorWithRed:0.8f green:0.8f blue:0.8f alpha:1.0f];
}

+ (UIColor*)transparentLightGrayColor {
    return [UIColor colorWithRed:0.5f green:0.5f blue:0.5f alpha:0.7f];
}

+ (void)applyRoundedBorderToImageView:(UIImageView* __strong*)imageView {
    [[*imageView layer] setBorderWidth:CONTACT_PICTURE_VIEW_BORDER_WIDTH];
    [[*imageView layer] setBorderColor:[[UIColor lightGrayColor] CGColor]];
    [[*imageView layer] setCornerRadius:CGRectGetWidth([*imageView frame])/2];
    [[*imageView layer] setMasksToBounds:YES];
}

+ (void)removeRoundedBorderToImageView:(UIImageView* __strong*)imageView {
    [[*imageView layer] setBorderWidth:0];
    [[*imageView layer] setCornerRadius:0];
}

@end
