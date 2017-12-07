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

- (void)setStatusBarStyle:(UIStatusBarStyle)statusBarStyle
{
    [[UIApplication sharedApplication] setStatusBarStyle:statusBarStyle];
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

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects;
{
    if (UIApplication.sharedApplication.isIdleTimerDisabled != shouldBeBlocking) {
        if (shouldBeBlocking) {
            NSMutableString *logString = [NSMutableString
                stringWithFormat:@"%@ Blocking sleep because of: %@", self.logTag, blockingObjects.firstObject];
            if (blockingObjects.count > 1) {
                [logString appendString:[NSString stringWithFormat:@"(and %lu others)", blockingObjects.count - 1]];
            }
            DDLogInfo(@"%@", logString);
        } else {
            DDLogInfo(@"%@ Unblocking Sleep.", self.logTag);
        }
    }
    UIApplication.sharedApplication.idleTimerDisabled = shouldBeBlocking;
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:value];
}

- (nullable UIViewController *)frontmostViewController
{
    return UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
}

- (nullable UIView *)rootReferenceView
{
    return UIApplication.sharedApplication.keyWindow;
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

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:value];
}

@end

NS_ASSUME_NONNULL_END
