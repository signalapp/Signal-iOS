//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MainAppContext.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalServiceKit/OWSIdentityManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation MainAppContext

- (BOOL)isMainApp
{
    return YES;
}

- (BOOL)isMainAppAndActive
{
    return [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
}

- (BOOL)isRTL
{
    return
        [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft;
}

- (UIApplicationState)mainApplicationState
{
    return [UIApplication sharedApplication].applicationState;
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler
{
    return [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:expirationHandler];
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    [UIApplication.sharedApplication endBackgroundTask:backgroundTaskIdentifier];
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:value];
}

- (nullable UIViewController *)frontmostViewController
{
    return UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
}

- (void)openSystemSettings
{
    [UIApplication.sharedApplication openSystemSettings];
}

- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey
{
    OWSAssert(profileKey);

    [MultiDeviceProfileKeyUpdateJob runWithProfileKey:profileKey
                                      identityManager:OWSIdentityManager.sharedManager
                                        messageSender:Environment.current.messageSender
                                       profileManager:OWSProfileManager.sharedManager];
}

- (BOOL)isRunningTests
{
    return getenv("runningTests_dontStartApp");
}

@end

NS_ASSUME_NONNULL_END
