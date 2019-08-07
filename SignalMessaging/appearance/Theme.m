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

NSString *const ThemeKeyThemeEnabled = @"ThemeKeyThemeEnabled";


@interface Theme ()

@property (nonatomic) NSNumber *isDarkThemeEnabledNumber;

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

+ (BOOL)isDarkThemeEnabled
{
    return [self.sharedInstance isDarkThemeEnabled];
}

- (BOOL)isDarkThemeEnabled
{
    OWSAssertIsOnMainThread();

    if (!CurrentAppContext().isMainApp) {
        // Ignore theme in app extensions.
        return NO;
    }

    if (self.isDarkThemeEnabledNumber == nil) {
        __block BOOL isDarkThemeEnabled;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            isDarkThemeEnabled =
                [Theme.keyValueStore getBool:ThemeKeyThemeEnabled defaultValue:NO transaction:transaction];
        }];
        self.isDarkThemeEnabledNumber = @(isDarkThemeEnabled);
    }

    return self.isDarkThemeEnabledNumber.boolValue;
}

+ (void)setIsDarkThemeEnabled:(BOOL)value
{
    return [self.sharedInstance setIsDarkThemeEnabled:value];
}

- (void)setIsDarkThemeEnabled:(BOOL)value
{
    OWSAssertIsOnMainThread();

    self.isDarkThemeEnabledNumber = @(value);
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [Theme.keyValueStore setBool:value key:ThemeKeyThemeEnabled transaction:transaction];
    }];

    [UIUtil setupSignalAppearence];

    [UIView performWithoutAnimation:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ThemeDidChangeNotification object:nil userInfo:nil];
    }];
}

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
