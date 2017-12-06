//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShareAppExtensionContext.h"
#import <SignalMessaging/UIViewController+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShareAppExtensionContext ()

@property (nonatomic) UIViewController *rootViewController;

@end

#pragma mark -

@implementation ShareAppExtensionContext

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(rootViewController);

    _rootViewController = rootViewController;

    OWSSingletonAssert();

    return self;
}

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

- (void)setStatusBarStyle:(UIStatusBarStyle)statusBarStyle
{
    DDLogInfo(@"Ignoring request to set status bar style since we're in an app extension");
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

- (void)openSystemSettings
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

- (void)doMultiDeviceUpdateWithProfileKey:(OWSAES256Key *)profileKey
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

- (BOOL)isRunningTests
{
    // TODO: I don't think we'll need to distinguish this in the SAE.
    return NO;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    OWSFail(@"%@ called %s.", self.logTag, __PRETTY_FUNCTION__);
}

@end

NS_ASSUME_NONNULL_END
