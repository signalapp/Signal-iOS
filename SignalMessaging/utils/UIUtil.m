//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "Theme.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
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
    UINavigationBar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UINavigationBar.appearance.tintColor = Theme.primaryIconColor;
    UIToolbar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UIToolbar.appearance.tintColor = Theme.primaryIconColor;

    // We do _not_ specifiy BarButton.appearance.tintColor because it is sufficient to specify
    // UINavigationBar.appearance.tintColor. Furthermore, specifying the BarButtonItem's
    // apearence makes it more difficult to override the navbar theme, e.g. how we _always_
    // use dark theme in the media send flow and gallery views. If we were specifying
    // barButton.appearence.tintColor we would then have to manually override each BarButtonItem's
    // tint, rather than just the navbars.
    //
    // UIBarButtonItem.appearance.tintColor = Theme.primaryIconColor;

    // Using the keyboardAppearance causes crashes due to a bug in UIKit.
    //    UITextField.appearance.keyboardAppearance = (Theme.isDarkThemeEnabled
    //                                                 ? UIKeyboardAppearanceDark
    //                                                 : UIKeyboardAppearanceDefault);
    //    UITextView.appearance.keyboardAppearance = (Theme.isDarkThemeEnabled
    //                                                 ? UIKeyboardAppearanceDark
    //                                                 : UIKeyboardAppearanceDefault);

    [[UISwitch appearance] setOnTintColor:UIColor.ows_accentBlueColor];
    [[UIToolbar appearance] setTintColor:UIColor.ows_accentBlueColor];

    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : Theme.navbarTitleColor };

    [UITextView appearanceWhenContainedInInstancesOfClasses:@[[OWSNavigationController class]]].tintColor = Theme.cursorColor;
    [UITextField appearanceWhenContainedInInstancesOfClasses:@[[OWSNavigationController class]]].tintColor = Theme.cursorColor;
}

@end
