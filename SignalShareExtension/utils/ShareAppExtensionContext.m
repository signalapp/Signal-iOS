//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ShareAppExtensionContext.h"
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWSStorage.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShareAppExtensionContext ()

@property (nonatomic) UIViewController *rootViewController;

@property (atomic) UIApplicationState reportedApplicationState;

@end

#pragma mark -

@implementation ShareAppExtensionContext

@synthesize mainWindow = _mainWindow;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(rootViewController);

    _rootViewController = rootViewController;

    self.reportedApplicationState = UIApplicationStateActive;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostDidBecomeActive:)
                                                 name:NSExtensionHostDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostWillResignActive:)
                                                 name:NSExtensionHostWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostDidEnterBackground:)
                                                 name:NSExtensionHostDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostWillEnterForeground:)
                                                 name:NSExtensionHostWillEnterForegroundNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)extensionHostDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.reportedApplicationState = UIApplicationStateActive;

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidBecomeActiveNotification object:nil];
}

- (void)extensionHostWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillResignActiveNotification object:nil];
}

- (void)extensionHostDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    self.reportedApplicationState = UIApplicationStateBackground;

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidEnterBackgroundNotification object:nil];
}

- (void)extensionHostWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.reportedApplicationState = UIApplicationStateInactive;

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillEnterForegroundNotification object:nil];
}

#pragma mark -

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
    static BOOL isRTL = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Borrowed from PureLayout's AppExtension compatible RTL support.
        // App Extensions may not access -[UIApplication sharedApplication]; fall back to checking the bundle's
        // preferred localization character direction
        isRTL = [NSLocale characterDirectionForLanguage:[[NSBundle mainBundle] preferredLocalizations][0]]
            == NSLocaleLanguageDirectionRightToLeft;
    });
    return isRTL;
}

- (void)setStatusBarHidden:(BOOL)isHidden animated:(BOOL)isAnimated
{
    DDLogInfo(@"Ignoring request to show/hide status bar since we're in an app extension");
}

- (CGFloat)statusBarHeight
{
    OWSFail(@"%@ in %s unexpected for share extension", self.logTag, __PRETTY_FUNCTION__);
    return 20;
}

- (BOOL)isInBackground
{
    return self.reportedApplicationState == UIApplicationStateBackground;
}

- (BOOL)isAppForegroundAndActive
{
    return self.reportedApplicationState == UIApplicationStateActive;
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

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects
{
    DDLogDebug(@"%@ Ignoring request to block sleep.", self.logTag);
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

- (nullable UIViewController *)frontmostViewController
{
    OWSAssert(self.rootViewController);

    return [self.rootViewController findFrontmostViewController:YES];
}

- (nullable UIAlertAction *)openSystemSettingsAction
{
    return nil;
}

- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

- (BOOL)isRunningTests
{
    // We don't need to distinguish this in the SAE.
    return NO;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

@end

NS_ASSUME_NONNULL_END
