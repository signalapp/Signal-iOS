//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIUtil.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const ThemeDidChangeNotification = @"ThemeDidChangeNotification";

NSString *const ThemeKeyLegacyThemeEnabled = @"ThemeKeyThemeEnabled";
NSString *const ThemeKeyCurrentMode = @"ThemeKeyCurrentMode";

@interface Theme ()

@property (nonatomic) NSNumber *isDarkThemeEnabledNumber;
@property (nonatomic) NSNumber *cachedCurrentThemeNumber;

#if TESTABLE_BUILD
@property (nonatomic, nullable) NSNumber *isDarkThemeEnabledForTests;
#endif

@end

@implementation Theme

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"ThemeCollection"];
}

#pragma mark -

+ (Theme *)shared
{
    static dispatch_once_t onceToken;
    static Theme *instance;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] initDefault]; });

    return instance;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        // IOS-782: +[Theme shared] re-enterant initialization
        // AppReadiness will invoke the block synchronously if the app is already ready.
        // This doesn't work here, because we'll end up reenterantly calling +shared
        // if the app is in dark mode and the first call to +[Theme shared] happens
        // after the app is ready.
        //
        // It looks like that pattern is only hit in the share extension, but we're better off
        // asyncing always to ensure the dependency chain is broken. We're okay waiting, since
        // there's no guarantee that this block in synchronously executed anyway.
        dispatch_async(dispatch_get_main_queue(), ^{ [self notifyIfThemeModeIsNotDefault]; });
    });

    return self;
}

- (void)notifyIfThemeModeIsNotDefault
{
    if (self.isDarkThemeEnabled || self.defaultTheme != self.getOrFetchCurrentTheme) {
        [self themeDidChange];
    }
}

#pragma mark -

+ (BOOL)isDarkThemeEnabled
{
    return [self.shared isDarkThemeEnabled];
}

- (BOOL)isDarkThemeEnabled
{
    //    OWSAssertIsOnMainThread();

#if TESTABLE_BUILD
    if (self.isDarkThemeEnabledForTests != nil) {
        return self.isDarkThemeEnabledForTests.boolValue;
    }
#endif

    if (!AppReadiness.isAppReady) {
        // Don't cache this value until it reflects the data store.
        return self.isSystemDarkThemeEnabled;
    }

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

#if TESTABLE_BUILD
+ (void)setIsDarkThemeEnabledForTests:(BOOL)value
{
    self.shared.isDarkThemeEnabledForTests = @(value);
}
#endif

+ (ThemeMode)getOrFetchCurrentTheme
{
    return [self.shared getOrFetchCurrentTheme];
}

- (ThemeMode)getOrFetchCurrentTheme
{
    if (self.cachedCurrentThemeNumber) {
        return self.cachedCurrentThemeNumber.unsignedIntegerValue;
    }

    if (!AppReadiness.isAppReady) {
        return self.defaultTheme;
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
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];

    self.cachedCurrentThemeNumber = @(currentMode);
    return currentMode;
}

+ (void)setCurrentTheme:(ThemeMode)mode
{
    [self.shared setCurrentTheme:mode];
}

- (void)setCurrentTheme:(ThemeMode)mode
{
    OWSAssertIsOnMainThread();

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
    // It's safe to do an async write because all accesses check self.cachedCurrentThemeNumber first.
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [Theme.keyValueStore setUInt:mode key:ThemeKeyCurrentMode transaction:transaction];
    });

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

- (ThemeMode)defaultTheme
{
    if (@available(iOS 13, *)) {
        return ThemeMode_System;
    }

    return ThemeMode_Light;
}

#pragma mark -

+ (void)systemThemeChanged
{
    [self.shared systemThemeChanged];
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

    // We may get multiple updates for the same change.
    BOOL isSystemDarkThemeEnabled = self.isSystemDarkThemeEnabled;
    if (self.isDarkThemeEnabledNumber.boolValue == isSystemDarkThemeEnabled) {
        return;
    }

    // The system theme has changed since the user was last in the app.
    self.isDarkThemeEnabledNumber = @(isSystemDarkThemeEnabled);
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

+ (UIColor *)secondaryBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray80Color : UIColor.ows_gray02Color);
}

+ (UIColor *)washColor
{
    return (Theme.isDarkThemeEnabled ? self.darkThemeWashColor : UIColor.ows_gray05Color);
}

+ (UIColor *)darkThemeWashColor
{
    return UIColor.ows_gray75Color;
}

+ (UIColor *)primaryTextColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemePrimaryColor : Theme.lightThemePrimaryColor);
}

+ (UIColor *)primaryIconColor
{
    return (Theme.isDarkThemeEnabled ? self.darkThemeNavbarIconColor : UIColor.ows_gray75Color);
}

+ (UIColor *)secondaryTextAndIconColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeSecondaryTextAndIconColor : UIColor.ows_gray60Color);
}

+ (UIColor *)darkThemeSecondaryTextAndIconColor
{
    return UIColor.ows_gray25Color;
}

+ (UIColor *)ternaryTextColor
{
    return UIColor.ows_gray45Color;
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
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray15Color);
}

+ (UIColor *)outlineColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray15Color;
}

+ (UIColor *)backdropColor
{
    return UIColor.ows_blackAlpha40Color;
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

+ (UIColor *)darkThemeNavbarIconColor
{
    return UIColor.ows_gray15Color;
}

+ (UIColor *)navbarTitleColor
{
    return Theme.primaryTextColor;
}

+ (UIColor *)toolbarBackgroundColor
{
    return self.navbarBackgroundColor;
}

+ (UIColor *)conversationInputBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : UIColor.ows_gray05Color);
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
    return Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_accentBlueColor;
}

+ (UIColor *)accentBlueColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_accentBlueDarkColor : UIColor.ows_accentBlueColor;
}

+ (UIColor *)tableCellBackgroundColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray95Color : Theme.backgroundColor;
}

+ (UIColor *)tableViewBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_blackColor : UIColor.ows_gray02Color);
}

+ (UIColor *)tableCell2BackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2BackgroundColor : UIColor.ows_whiteColor;
}

+ (UIColor *)tableCell2PresentedBackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2PresentedBackgroundColor : UIColor.ows_whiteColor;
}

+ (UIColor *)tableCell2SelectedBackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2SelectedBackgroundColor : UIColor.ows_gray15Color;
}

+ (UIColor *)tableCell2SelectedBackgroundColor2
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2SelectedBackgroundColor2 : UIColor.ows_gray15Color;
}

+ (UIColor *)tableCell2MultiSelectedBackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2MultiSelectedBackgroundColor : UIColor.ows_gray05Color;
}

+ (UIColor *)tableCell2PresentedSelectedBackgroundColor
{
    return Theme.isDarkThemeEnabled ? Theme.darkThemeTableCell2PresentedSelectedBackgroundColor
                                    : UIColor.ows_gray15Color;
}

+ (UIColor *)tableView2BackgroundColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeTableView2BackgroundColor : UIColor.ows_gray10Color);
}

+ (UIColor *)tableView2PresentedBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeTableView2PresentedBackgroundColor : UIColor.ows_gray10Color);
}

+ (UIColor *)tableView2SeparatorColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeTableView2SeparatorColor : UIColor.ows_gray20Color);
}

+ (UIColor *)tableView2PresentedSeparatorColor
{
    return (Theme.isDarkThemeEnabled ? Theme.darkThemeTableView2PresentedSeparatorColor : UIColor.ows_gray20Color);
}

+ (UIColor *)darkThemeTableCell2BackgroundColor
{
    return UIColor.ows_gray90Color;
}

+ (UIColor *)darkThemeTableCell2PresentedBackgroundColor
{
    return UIColor.ows_gray80Color;
}

+ (UIColor *)darkThemeTableCell2SelectedBackgroundColor
{
    return UIColor.ows_gray80Color;
}

+ (UIColor *)darkThemeTableCell2SelectedBackgroundColor2
{
    return UIColor.ows_gray65Color;
}

+ (UIColor *)darkThemeTableCell2MultiSelectedBackgroundColor
{
    return UIColor.ows_gray75Color;
}

+ (UIColor *)darkThemeTableCell2PresentedSelectedBackgroundColor
{
    return UIColor.ows_gray75Color;
}

+ (UIColor *)darkThemeTableView2BackgroundColor
{
    return UIColor.ows_blackColor;
}

+ (UIColor *)darkThemeTableView2PresentedBackgroundColor
{
    return UIColor.ows_gray90Color;
}

+ (UIColor *)darkThemeTableView2SeparatorColor
{
    return UIColor.ows_gray75Color;
}

+ (UIColor *)darkThemeTableView2PresentedSeparatorColor
{
    return UIColor.ows_gray65Color;
}

+ (UIColor *)darkThemeBackgroundColor
{
    return UIColor.ows_blackColor;
}

+ (UIColor *)darkThemePrimaryColor
{
    return UIColor.ows_gray02Color;
}

+ (UIColor *)lightThemePrimaryColor
{
    return UIColor.ows_gray90Color;
}

+ (UIColor *)galleryHighlightColor
{
    return [UIColor colorWithRGBHex:0x1f8fe8];
}

+ (UIColor *)conversationButtonBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray80Color : UIColor.ows_gray02Color);
}

+ (UIColor *)conversationButtonTextColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray05Color : UIColor.ows_accentBlueColor);
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
    return Theme.washColor;
}

+ (UIColor *)searchFieldElevatedBackgroundColor
{
    return Theme.isDarkThemeEnabled ? UIColor.ows_gray75Color : [[UIColor alloc] initWithRgbHex:0xe0e0e0];
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
