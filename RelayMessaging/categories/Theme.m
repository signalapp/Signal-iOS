//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import "UIUtil.h"
#import <RelayMessaging/RelayMessaging-Swift.h>

@import RelayServiceKit;

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
    return (Theme.isDarkThemeEnabled ? UIColor.blackColor : UIColor.whiteColor);
}

+ (UIColor *)primaryColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.whiteColor : [UIColor colorWithWhite:0.10f alpha:1.0f]);
}

+ (UIColor *)secondaryColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.48f alpha:1.0f] : [UIColor colorWithWhite:0.40f alpha:1.0f]);
}

+ (UIColor *)boldColor
{
    // TODO: Review with design.
    return (Theme.isDarkThemeEnabled ? UIColor.whiteColor : UIColor.blackColor);
}

#pragma mark - Global App Colors

+ (UIColor *)navbarBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.blackColor : UIColor.whiteColor);
}

+ (UIColor *)navbarIconColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.48f alpha:1.0f] : [UIColor colorWithWhite:0.40f alpha:1.0f]);
}

+ (UIColor *)navbarTitleColor
{
    // TODO: Theme, Review with design.
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.48f alpha:1.0f] : [UIColor colorWithWhite:0.40f alpha:1.0f]);
}

+ (UIColor *)toolbarBackgroundColor
{
    return self.navbarBackgroundColor;
}

+ (UIColor *)cellSelectedColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.whiteColor : UIColor.blackColor);
}

+ (UIColor *)conversationButtonBackgroundColor
{
    return (Theme.isDarkThemeEnabled ? [UIColor colorWithWhite:0.95f alpha:1.0f] : [UIColor colorWithWhite:0.98f alpha:1.0f]);
}

#pragma mark - Conversations
+ (UIColor *)conversationColorForString:(NSString *)colorSeed;
{
    NSData *contactData = [colorSeed dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned long long hash = 0;
    NSUInteger hashingLength = sizeof(hash);
    NSData *_Nullable hashData = [Cryptography computeSHA256Digest:contactData truncatedToBytes:hashingLength];
    if (hashData) {
        [hashData getBytes:&hash length:hashingLength];
    } else {
        OWSProdLogAndFail(@"%@ could not compute hash for color seed.", self.logTag);
    }

    
    NSUInteger index = (hash % [UIColor.FL_popColors count]);

    return UIColor.FL_popColors[index];
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
