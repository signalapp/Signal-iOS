//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MainAppContext.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSIdentityManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation MainAppContext

@synthesize mainWindow = _mainWindow;

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillEnterForegroundNotification object:nil];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidEnterBackgroundNotification object:nil];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillResignActiveNotification object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidBecomeActiveNotification object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];
}

#pragma mark -

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

- (void)setStatusBarHidden:(BOOL)isHidden animated:(BOOL)isAnimated
{
    [[UIApplication sharedApplication] setStatusBarHidden:isHidden animated:isAnimated];
}

- (CGFloat)statusBarHeight
{
    return [UIApplication sharedApplication].statusBarFrame.size.height;
}

- (BOOL)isInBackground
{
    return [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
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

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects
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

- (nullable UIAlertAction *)openSystemSettingsAction
{
    return [UIAlertAction actionWithTitle:CommonStrings.openSettingsButton
                                    style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction *_Nonnull action) {
                                      [UIApplication.sharedApplication openSystemSettings];
                                  }];
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
