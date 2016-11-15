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

+ (void)applyDefaultSystemAppearence
{
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
    [[UINavigationBar appearance] setBarStyle:UIBarStyleDefault];
    [[UIBarButtonItem appearance] setTintColor:[UIColor blackColor]];
    NSDictionary *navbarTitleTextAttributes = @{ NSForegroundColorAttributeName : [UIColor blackColor] };
    [[UINavigationBar appearance] setTitleTextAttributes:navbarTitleTextAttributes];
}

+ (void)applySignalAppearence
{
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    [[UINavigationBar appearance] setBarTintColor:[UIColor ows_materialBlueColor]];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];

    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTintColor:[UIColor ows_materialBlueColor]];


    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    [[UIBarButtonItem appearance] setTintColor:[UIColor whiteColor]];

    NSShadow *shadow = [NSShadow new];
    [shadow setShadowColor:[UIColor clearColor]];

    NSDictionary *navbarTitleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor whiteColor],
        NSShadowAttributeName : shadow,
    };

    [[UISwitch appearance] setOnTintColor:[UIColor ows_materialBlueColor]];

    [[UINavigationBar appearance] setTitleTextAttributes:navbarTitleTextAttributes];
}

@end
