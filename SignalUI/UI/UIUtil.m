//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UIUtil.h"
#import "Theme.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalUI/SignalUI-Swift.h>

@implementation UIUtil

+ (void)setupSignalAppearence
{
    UINavigationBar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UINavigationBar.appearance.tintColor = Theme.primaryIconColor;
    UIToolbar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UIToolbar.appearance.tintColor = Theme.primaryIconColor;

    // We do _not_ specify BarButton.appearance.tintColor because it is sufficient to specify
    // UINavigationBar.appearance.tintColor. Furthermore, specifying the BarButtonItem's
    // apearence makes it more difficult to override the navbar theme, e.g. how we _always_
    // use dark theme in the media send flow and gallery views. If we were specifying
    // barButton.appearance.tintColor we would then have to manually override each BarButtonItem's
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

    [[UITableViewCell appearance] setTintColor:Theme.primaryIconColor];
    [[UIToolbar appearance] setTintColor:UIColor.ows_accentBlueColor];

    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : Theme.navbarTitleColor };

    [UITextView appearanceWhenContainedInInstancesOfClasses:@[ [OWSNavigationController class] ]].tintColor
        = Theme.cursorColor;
    [UITextField appearanceWhenContainedInInstancesOfClasses:@[ [OWSNavigationController class] ]].tintColor
        = Theme.cursorColor;
}

@end
