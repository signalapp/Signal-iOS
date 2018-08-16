//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const ThemeDidChangeNotification = @"ThemeDidChangeNotification";

NSString *const ThemeCollection = @"ThemeCollection";
NSString *const ThemeKeyThemeEnabled = @"ThemeKeyThemeEnabled";

@implementation Theme

+ (BOOL)isDarkThemeEnabled
{
    OWSAssertIsOnMainThread();

#ifndef THEME_ENABLED
    return NO;
#else
    if (!CurrentAppContext().isMainApp) {
        // Ignore theme in app extensions.
        return NO;
    }

    return [OWSPrimaryStorage.sharedManager.dbReadConnection boolForKey:ThemeKeyThemeEnabled
                                                           inCollection:ThemeCollection
                                                           defaultValue:NO];
#endif
}

+ (void)setIsDarkThemeEnabled:(BOOL)value
{
    OWSAssertIsOnMainThread();

    [OWSPrimaryStorage.sharedManager.dbReadWriteConnection setBool:value
                                                            forKey:ThemeKeyThemeEnabled
                                                      inCollection:ThemeCollection];

    [UIUtil setupSignalAppearence];

    [UIView performWithoutAnimation:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ThemeDidChangeNotification object:nil userInfo:nil];
    }];
}

+ (UIColor *)backgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_blackColor : UIColor.ows_whiteColor);
}

+ (UIColor *)offBackgroundColor
{
    return (
        Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor colorWithWhite:0.94f alpha:1.f]);
}

+ (UIColor *)primaryColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark05Color : UIColor.ows_light90Color);
}

+ (UIColor *)secondaryColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark30Color : UIColor.ows_light60Color);
}

+ (UIColor *)boldColor
{
    // TODO: Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.blackColor);
}

+ (UIColor *)middleGrayColor
{
    // TODO: Review with design.
    return [UIColor colorWithWhite:0.5f alpha:1.f];
}

+ (UIColor *)placeholderColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_light35Color : UIColor.ows_dark55Color);
}

+ (UIColor *)hairlineColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_light45Color : UIColor.ows_dark60Color);
}

#pragma mark - Global App Colors

+ (UIColor *)navbarBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_blackColor : UIColor.ows_whiteColor);
}

+ (UIColor *)navbarIconColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark60Color : UIColor.ows_light60Color);
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
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.2 alpha:1] : [UIColor colorWithWhite:0.92 alpha:1]);
}

+ (UIColor *)cellSeparatorColor
{
    return [UIColor colorWithWhite:0.78f alpha:1];
}

+ (UIColor *)conversationButtonBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.35f alpha:1.f] : UIColor.ows_light02Color);
}

+ (UIBlurEffect *)barBlurEffect
{
    return Theme.isDarkThemeEnabled ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]
                                    : [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

#pragma mark -

+ (UIBarStyle)barStyle
{
    if (Theme.isDarkThemeEnabled) {
        return UIBarStyleDefault;
    } else {
        return UIBarStyleDefault;
    }
}

+ (UISearchBarStyle)searchBarStyle
{
    if (Theme.isDarkThemeEnabled) {
        return UISearchBarStyleProminent;
    } else {
        return UISearchBarStyleMinimal;
    }
}

+ (UIColor *)searchBarBackgroundColor
{
    return Theme.backgroundColor;
}

#pragma mark -

+ (UIColor *)toastForegroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_whiteColor);
}

+ (UIColor *)toastBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark60Color : UIColor.ows_light60Color);
}

@end

NS_ASSUME_NONNULL_END
