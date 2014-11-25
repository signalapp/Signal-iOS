#import "UIUtil.h"

static NSString *const HELVETICA_NEUE_LTSTD_LIGHT_NAME = @"HelveticaNeueLTStd-Lt";
static NSString *const HELVETICA_NEUE_LTSTD_BOLD_NAME = @"HelveticaNeueLTStd-Bold";
static NSString *const HELVETICA_NEUE_LTSTD_MEDIUM_NAME = @"HelveticaNeueLTStd-Md";
static NSString *const HELVETICA_REGULAR_NAME = @"Helvetica";
static NSString *const HELVETICA_LIGHT_NAME = @"Helvetica-Light";

#define CONTACT_PICTURE_VIEW_BORDER_WIDTH 0.5f

@implementation UIUtil

+ (UIFont *)helveticaNeueLTStdLightFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_LIGHT_NAME size:size];
}

+ (UIFont *)helveticaNeueLTStdBoldFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_BOLD_NAME size:size];
}

+ (UIFont *)helveticaNeueLTStdMediumFontWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_NEUE_LTSTD_MEDIUM_NAME size:size];
}

+ (UIFont *)helveticaRegularWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_REGULAR_NAME size:size];
}

+ (UIFont *)helveticaLightWithSize:(CGFloat)size {
    return [UIFont fontWithName:HELVETICA_LIGHT_NAME size:size];
}

+ (void)applyRoundedBorderToImageView:(UIImageView *__strong*)imageView {
    [[*imageView layer] setBorderWidth:CONTACT_PICTURE_VIEW_BORDER_WIDTH];
    [[*imageView layer] setBorderColor:[[UIColor lightGrayColor] CGColor]];
    [[*imageView layer] setCornerRadius:CGRectGetWidth([*imageView frame])/2];
    [[*imageView layer] setMasksToBounds:YES];
}

+ (void)removeRoundedBorderToImageView:(UIImageView *__strong*)imageView {
    [[*imageView layer] setBorderWidth:0];
    [[*imageView layer] setCornerRadius:0];
}

@end
