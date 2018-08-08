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

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:ThemeDidChangeNotification object:nil userInfo:nil];
}

+ (UIColor *)backgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_blackColor : UIColor.ows_whiteColor);
}

+ (UIColor *)offBackgroundColor
{
    return (
        Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.2f alpha:1.f] : [UIColor colorWithWhite:0.9f alpha:1.f]);
}

+ (UIColor *)primaryColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_light90Color);
}

+ (UIColor *)secondaryColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark60Color : UIColor.ows_light60Color);
}

+ (UIColor *)boldColor
{
    // TODO: Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.blackColor);
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
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark60Color : UIColor.ows_light60Color);
}

+ (UIColor *)toolbarBackgroundColor
{
    return self.navbarBackgroundColor;
}

+ (UIColor *)cellSelectedColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_blackColor);
}

+ (UIColor *)conversationButtonBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_dark05Color : UIColor.ows_light02Color);
}

#pragma mark -

+ (UIBarStyle)barStyle
{
    if (Theme.isDarkThemeEnabled) {
        return UIBarStyleBlack;
    } else {
        return UIBarStyleDefault;
    }
}

@end

NS_ASSUME_NONNULL_END
