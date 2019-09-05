//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const ThemeDidChangeNotification = @"ThemeDidChangeNotification";

NSString *const ThemeKeyLegacyThemeEnabled = @"ThemeKeyThemeEnabled";
NSString *const ThemeKeyCurrentMode = @"ThemeKeyCurrentMode";

@interface Theme ()

@property (nonatomic) NSNumber *isDarkThemeEnabledNumber;
@property (nonatomic) NSNumber *cachedCurrentThemeNumber;

@end

@implementation Theme

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"ThemeCollection"];
}

#pragma mark -

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static Theme *instance;
    dispatch_once(&onceToken, ^{
        instance = [Theme new];
    });

    return instance;
}

#pragma mark -

+ (BOOL)isDarkThemeEnabled
{
    return [self.sharedInstance isDarkThemeEnabled];
}

- (BOOL)isDarkThemeEnabled
{
    OWSAssertIsOnMainThread();

    if (self.isDarkThemeEnabledNumber == nil) {
        BOOL isDarkThemeEnabled;

        if (!CurrentAppContext().isMainApp) {
            // Always respect the system theme in extensions
            isDarkThemeEnabled = self.isSystemDarkThemeEnabled;
        } else {
            switch ([self getOrFetchCurrentTheme]) {
                case ThemeMode_System:
                    isDarkThemeEnabled = self.isSystemDarkThemeEnabled;
                    break;
                case ThemeMode_Dark:
                    isDarkThemeEnabled = YES;
                    break;
                case ThemeMode_Light:
                    isDarkThemeEnabled = NO;
                    break;
            }
        }

        self.isDarkThemeEnabledNumber = @(isDarkThemeEnabled);
    }

    return self.isDarkThemeEnabledNumber.boolValue;
}

+ (ThemeMode)getOrFetchCurrentTheme
{
    return [self.sharedInstance getOrFetchCurrentTheme];
}

- (ThemeMode)getOrFetchCurrentTheme
{
    if (self.cachedCurrentThemeNumber) {
        return self.cachedCurrentThemeNumber.unsignedIntegerValue;
    }

    __block ThemeMode currentMode;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        BOOL hasDefinedMode = [Theme.keyValueStore hasValueForKey:ThemeKeyCurrentMode transaction:transaction];
        if (!hasDefinedMode) {
            // If the theme has not yet been defined, check if the user ever manually changed
            // themes in a legacy app version. If so, preserve their selection. Otherwise,
            // default to matching the system theme.
            if (![Theme.keyValueStore hasValueForKey:ThemeKeyLegacyThemeEnabled transaction:transaction]) {
                currentMode = ThemeMode_System;
            } else {
                BOOL isLegacyModeDark = [Theme.keyValueStore getBool:ThemeKeyLegacyThemeEnabled
                                                        defaultValue:NO
                                                         transaction:transaction];
                currentMode = isLegacyModeDark ? ThemeMode_Dark : ThemeMode_Light;
            }
        } else {
            currentMode = [Theme.keyValueStore getUInt:ThemeKeyCurrentMode
                                          defaultValue:ThemeMode_System
                                           transaction:transaction];
        }
    }];

    self.cachedCurrentThemeNumber = @(currentMode);
    return currentMode;
}

+ (void)setCurrentTheme:(ThemeMode)mode
{
    [self.sharedInstance setCurrentTheme:mode];
}

- (void)setCurrentTheme:(ThemeMode)mode
{
    OWSAssertIsOnMainThread();

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [Theme.keyValueStore setUInt:mode key:ThemeKeyCurrentMode transaction:transaction];
    }];

    NSNumber *previousMode = self.isDarkThemeEnabledNumber;

    switch (mode) {
        case ThemeMode_Light:
            self.isDarkThemeEnabledNumber = @(NO);
            break;
        case ThemeMode_Dark:
            self.isDarkThemeEnabledNumber = @(YES);
            break;
        case ThemeMode_System:
            self.isDarkThemeEnabledNumber = @(self.isSystemDarkThemeEnabled);
            break;
    }

    self.cachedCurrentThemeNumber = @(mode);

    if (![previousMode isEqual:self.isDarkThemeEnabledNumber]) {
        [self themeDidChange];
    }
}

- (BOOL)isSystemDarkThemeEnabled
{
    if (@available(iOS 13, *)) {
        return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    } else {
        return NO;
    }
}

#pragma mark -

+ (void)systemThemeChanged
{
    [self.sharedInstance systemThemeChanged];
}

- (void)systemThemeChanged
{
    // Do nothing, since we haven't setup the theme yet.
    if (self.isDarkThemeEnabledNumber == nil) {
        return;
    }

    // Theme can only be changed externally when in system mode.
    if ([self getOrFetchCurrentTheme] != ThemeMode_System) {
        return;
    }

    // The system them has changed since the user was last in the app.
    self.isDarkThemeEnabledNumber = @(self.isSystemDarkThemeEnabled);
    [self themeDidChange];
}

- (void)themeDidChange
{
    [UIUtil setupSignalAppearence];

    [UIView performWithoutAnimation:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ThemeDidChangeNotification object:nil userInfo:nil];
    }];
}

#pragma mark -

+ (UIColor *)backgroundColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeBackgroundColor : UIColor.ows_whiteColor);
}

+ (UIColor *)darkThemeOffBackgroundColor
{
    return [UIColor colorWithWhite:0.2f alpha:1.f];
}

+ (UIColor *)offBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? self.darkThemeOffBackgroundColor : UIColor.ows_gray05Color);
}

+ (UIColor *)primaryColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemePrimaryColor : UIColor.ows_gray90Color);
}

+ (UIColor *)secondaryColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeSecondaryColor : UIColor.ows_gray60Color);
}

+ (UIColor *)darkThemeSecondaryColor
{
    return UIColor.ows_gray25Color;
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
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray45Color : UIColor.ows_gray45Color);
}

+ (UIColor *)hairlineColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray25Color);
}

+ (UIColor *)outlineColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray15Color;
}

#pragma mark - Global App Colors

+ (UIColor *)navbarBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? self.darkThemeNavbarBackgroundColor : UIColor.ows_whiteColor);
}

+ (UIColor *)darkThemeNavbarBackgroundColor
{
    return UIColor.ows_blackColor;
}

+ (UIColor *)navbarIconColor
{
    return (Theme.isDarkThemeEnabled ? self.darkThemeNavbarIconColor : UIColor.ows_gray60Color);
}

+ (UIColor *)darkThemeNavbarIconColor
{
    return UIColor.ows_gray25Color;
}

+ (UIColor *)navbarTitleColor
{
    return Theme.primaryColor;
}

+ (UIColor *)toolbarBackgroundColor
{
    return self.navbarBackgroundColor;
}

+ (UIColor *)conversationInputBackgroundColor
{
    return (Theme.isDarkThemeEnabled ?  UIColor.ows_gray75Color : [UIColor colorWithRGBHex:0xefefef]);
}

+ (UIColor *)attachmentKeyboardItemBackgroundColor
{
    return self.conversationInputBackgroundColor;
}

+ (UIColor *)attachmentKeyboardItemImageColor
{
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithRGBHex:0xd8d8d9] : [UIColor colorWithRGBHex:0x636467]);
}

+ (UIColor *)cellSelectedColor
{
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.2 alpha:1] : [UIColor colorWithWhite:0.92 alpha:1]);
}

+ (UIColor *)cellSeparatorColor
{
    return Theme.hairlineColor;
}

+ (UIColor *)cursorColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_materialBlueColor;
}

+ (UIColor *)darkThemeBackgroundColor
{
    return UIColor.ows_gray95Color;
}

+ (UIColor *)darkThemePrimaryColor
{
    return UIColor.ows_gray05Color;
}

+ (UIColor *)galleryHighlightColor
{
    return [UIColor colorWithRGBHex:0x1f8fe8];
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
    return Theme.isDarkThemeEnabled ? self.darkThemeKeyboardAppearance : UIKeyboardAppearanceDefault;
}

+ (UIColor *)keyboardBackgroundColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray90Color : UIColor.ows_gray02Color;
}

+ (UIKeyboardAppearance)darkThemeKeyboardAppearance
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
    return Theme.offBackgroundColor;
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
    return Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.25f alpha:1.f]
                                    : [UIColor colorWithWhite:0.95f alpha:1.f];
}

@end

NS_ASSUME_NONNULL_END
