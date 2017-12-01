//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShareAppExtensionContext.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ShareAppExtensionContext

- (BOOL)isMainApp
{
    return NO;
}

- (BOOL)isMainAppAndActive
{
    return NO;
}

- (BOOL)isRTL
{
    // Borrowed from PureLayout's AppExtension compatible RTL support.
    // App Extensions may not access -[UIApplication sharedApplication]; fall back to checking the bundle's preferred
    // localization character direction
    return [NSLocale characterDirectionForLanguage:[[NSBundle mainBundle] preferredLocalizations][0]]
        == NSLocaleLanguageDirectionRightToLeft;
}

- (UIApplicationState)mainApplicationState
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
    return UIApplicationStateBackground;
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler
{
    return UIBackgroundTaskInvalid;
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    OWSAssert(backgroundTaskIdentifier == UIBackgroundTaskInvalid);
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

@end

NS_ASSUME_NONNULL_END
