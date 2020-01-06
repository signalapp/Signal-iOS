//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "Theme.h"
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
    UINavigationBar.appearance.barTintColor = [UIColor colorWithRGBHex:0x161616]; // Colors.navigationBarBackground
    UINavigationBar.appearance.tintColor = [UIColor colorWithRGBHex:0xFFFFFF]; // Colors.text
    UIToolbar.appearance.barTintColor = Theme.navbarBackgroundColor;
    UIToolbar.appearance.tintColor = Theme.navbarIconColor;

    UIBarButtonItem.appearance.tintColor = [UIColor colorWithRGBHex:0xFFFFFF]; // Colors.text

    // Using the keyboardAppearance causes crashes due to a bug in UIKit.
    //    UITextField.appearance.keyboardAppearance = (Theme.isDarkThemeEnabled
    //                                                 ? UIKeyboardAppearanceDark
    //                                                 : UIKeyboardAppearanceDefault);
    //    UITextView.appearance.keyboardAppearance = (Theme.isDarkThemeEnabled
    //                                                 ? UIKeyboardAppearanceDark
    //                                                 : UIKeyboardAppearanceDefault);

    [[UISwitch appearance] setOnTintColor:[UIColor colorWithRGBHex:0x00F782]]; // Colors.accent
    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    
    // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
    UINavigationBar.appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : [UIColor colorWithRGBHex:0xFFFFFF] }; // Colors.text
}

@end
