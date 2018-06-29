//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "UIColor+OWS.h"
#import <SignalServiceKit/AppContext.h>

#define CONTACT_PICTURE_VIEW_BORDER_WIDTH 0.5f

@implementation UIUtil

+ (void)applyRoundedBorderToImageView:(UIImageView *)imageView
{
    imageView.layer.borderWidth = CONTACT_PICTURE_VIEW_BORDER_WIDTH;
    imageView.layer.borderColor = [UIColor clearColor].CGColor;
    imageView.layer.cornerRadius = CGRectGetWidth(imageView.frame) / 2;
    imageView.layer.masksToBounds = YES;
}

+ (void)removeRoundedBorderToImageView:(UIImageView *__strong *)imageView
{
    [[*imageView layer] setBorderWidth:0];
    [[*imageView layer] setCornerRadius:0];
}

+ (completionBlock)modalCompletionBlock
{
    completionBlock block = ^void() {
        [CurrentAppContext() setStatusBarStyle:UIStatusBarStyleLightContent];
    };

    return block;
}

+ (void)applyDefaultSystemAppearence
{
//    [CurrentAppContext() setStatusBarStyle:UIStatusBarStyleDefault];
//    [[UINavigationBar appearance] setBarStyle:UIBarStyleDefault];
//    [[UINavigationBar appearance] setTintColor:[UIColor blackColor]];
//    [[UIBarButtonItem appearance] setTintColor:[UIColor blackColor]];
//    [[UINavigationBar appearance] setTitleTextAttributes:@{
//        NSForegroundColorAttributeName : [UIColor blackColor],
//    }];
}

+ (void)applySignalAppearence
{
    //    [CurrentAppContext() setStatusBarStyle:UIStatusBarStyleLightContent];
    UINavigationBar.appearance.barTintColor = UIColor.ows_navbarBackgroundColor;
    //    [[UINavigationBar appearance] setBarTintColor:[UIColor ows_materialBlueColor]];
    UINavigationBar.appearance.tintColor = UIColor.ows_navbarForegroundColor;
    UIToolbar.appearance.barTintColor = UIColor.ows_navbarBackgroundColor;
    UIToolbar.appearance.tintColor = UIColor.ows_navbarForegroundColor;

    UIBarButtonItem.appearance.tintColor = UIColor.ows_navbarForegroundColor;

    //    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTintColor:[UIColor
    //    ows_materialBlueColor]];

    [[UISwitch appearance] setOnTintColor:[UIColor ows_materialBlueColor]];
    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    
    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{
        NSForegroundColorAttributeName : UIColor.ows_navbarForegroundColor
    };
}

@end
