//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import <RelayMessaging/RelayMessaging-Swift.h>
#import <RelayServiceKit/AppContext.h>

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
    UINavigationBar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UINavigationBar.appearance.tintColor = Theme.navbarIconColor;
    UIToolbar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UIToolbar.appearance.tintColor = Theme.navbarIconColor;

    UIBarButtonItem.appearance.tintColor = Theme.navbarIconColor;

    //    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTintColor:[UIColor
    //    FL_mediumBlue2]];

    [[UISwitch appearance] setOnTintColor:[UIColor FL_mediumBlue2]];
    [[UIToolbar appearance] setTintColor:[UIColor FL_mediumBlue2]];
    
    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : Theme.navbarTitleColor };
}

@end
