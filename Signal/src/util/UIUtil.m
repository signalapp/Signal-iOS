#import "UIUtil.h"

#define CONTACT_PICTURE_VIEW_BORDER_WIDTH 0.5f

@implementation UIUtil

+ (void)applyRoundedBorderToImageView:(UIImageView *__strong *)imageView {
    [[*imageView layer] setBorderWidth:CONTACT_PICTURE_VIEW_BORDER_WIDTH];
    [[*imageView layer] setBorderColor:[[UIColor clearColor] CGColor]];
    [[*imageView layer] setCornerRadius:CGRectGetWidth([*imageView frame]) / 2];
    [[*imageView layer] setMasksToBounds:YES];
}


+ (void)removeRoundedBorderToImageView:(UIImageView *__strong *)imageView {
    [[*imageView layer] setBorderWidth:0];
    [[*imageView layer] setCornerRadius:0];
}

+ (completionBlock)modalCompletionBlock {
    completionBlock block = ^void() {
      [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    };

    return block;
}

@end
