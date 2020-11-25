//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import <SessionUtilitiesKit/NSNotificationCenter+OWS.h>
#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SessionMessagingKit/YapDatabaseConnection+OWS.h>

#import <SessionUIKit/SessionUIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const ThemeDidChangeNotification = @"ThemeDidChangeNotification";

NSString *const ThemeCollection = @"ThemeCollection";
NSString *const ThemeKeyThemeEnabled = @"ThemeKeyThemeEnabled";


@interface Theme ()

@property (nonatomic) NSNumber *isDarkThemeEnabledNumber;

@end

@implementation Theme

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static Theme *instance;
    dispatch_once(&onceToken, ^{
        instance = [Theme new];
    });

    return instance;
}

+ (BOOL)isDarkThemeEnabled
{
    return LKAppModeUtilities.isDarkMode;
}

- (BOOL)isDarkThemeEnabled
{
    OWSAssertIsOnMainThread();

    return LKAppModeUtilities.isDarkMode;
}

+ (void)setIsDarkThemeEnabled:(BOOL)value
{
    return [self.sharedInstance setIsDarkThemeEnabled:value];
}

- (void)setIsDarkThemeEnabled:(BOOL)value
{
    return;
}

+ (UIColor *)backgroundColor
{
    return LKColors.navigationBarBackground;
}

+ (UIColor *)offBackgroundColor
{
    return LKColors.unimportant;
}

+ (UIColor *)primaryColor
{
    return LKColors.text;
}

+ (UIColor *)secondaryColor
{
    return LKColors.separator;
}

+ (UIColor *)boldColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.blackColor);
}

+ (UIColor *)middleGrayColor
{
    return [UIColor colorWithWhite:0.5f alpha:1.f];
}

+ (UIColor *)placeholderColor
{
    return LKColors.navigationBarBackground;
}

+ (UIColor *)hairlineColor
{
    return LKColors.separator;
}

#pragma mark - Global App Colors

+ (UIColor *)navbarBackgroundColor
{
    return UIColor.lokiDarkestGray;
}

+ (UIColor *)darkThemeNavbarBackgroundColor
{
    return UIColor.ows_blackColor;
}

+ (UIColor *)navbarIconColor
{
    return UIColor.lokiGreen;
}

+ (UIColor *)darkThemeNavbarIconColor;
{
    return LKColors.text;
}

+ (UIColor *)navbarTitleColor
{
    return Theme.primaryColor;
}

+ (UIColor *)toolbarBackgroundColor
{
    return self.navbarBackgroundColor;
}

+ (UIColor *)cellSelectedColor
{
    return UIColor.lokiDarkGray;
}

+ (UIColor *)cellSeparatorColor
{
    return Theme.hairlineColor;
}

+ (UIColor *)darkThemeBackgroundColor
{
    return LKColors.navigationBarBackground;
}

+ (UIColor *)darkThemePrimaryColor
{
    return LKColors.text;
}

+ (UIColor *)galleryHighlightColor
{
    return UIColor.lokiGreen;
}

+ (UIColor *)conversationButtonBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.35f alpha:1.f] : UIColor.ows_gray02Color);
}

+ (UIBlurEffect *)barBlurEffect
{
    return Theme.isDarkThemeEnabled ? self.darkThemeBarBlurEffect
                                    : [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

+ (UIBlurEffect *)darkThemeBarBlurEffect
{
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
}

+ (UIKeyboardAppearance)keyboardAppearance
{
    return LKAppModeUtilities.isLightMode ? UIKeyboardAppearanceDefault : UIKeyboardAppearanceDark;
}

+ (UIKeyboardAppearance)darkThemeKeyboardAppearance;
{
    return UIKeyboardAppearanceDark;
}

#pragma mark - Search Bar

+ (UIBarStyle)barStyle
{
    return Theme.isDarkThemeEnabled ? UIBarStyleBlack : UIBarStyleDefault;
}

+ (UIColor *)searchFieldBackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.offBackgroundColor : UIColor.ows_gray05Color;
}

#pragma mark -

+ (UIColor *)toastForegroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_whiteColor);
}

+ (UIColor *)toastBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray60Color);
}

+ (UIColor *)scrollButtonBackgroundColor
{
    return UIColor.lokiDarkerGray;
}

@end

NS_ASSUME_NONNULL_END
