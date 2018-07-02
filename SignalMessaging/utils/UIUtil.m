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

+ (void)setupSignalAppearence
{
    UINavigationBar.appearance.barTintColor = UIColor.ows_navbarBackgroundColor;
    UINavigationBar.appearance.tintColor = UIColor.ows_navbarIconColor;
    UIToolbar.appearance.barTintColor = UIColor.ows_navbarBackgroundColor;
    UIToolbar.appearance.tintColor = UIColor.ows_navbarIconColor;

    UIBarButtonItem.appearance.tintColor = UIColor.ows_navbarIconColor;
    // Because our launch screen is blue, we specify the light content in our plist
    // but once the app has loaded we want to switch to dark.
    [CurrentAppContext() setStatusBarStyle:UIStatusBarStyleDefault];

    //    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTintColor:[UIColor
    //    ows_materialBlueColor]];

    [[UISwitch appearance] setOnTintColor:[UIColor ows_materialBlueColor]];
    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    
    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : UIColor.ows_navbarTitleColor };
}

@end
