//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShareAppExtensionContext.h"
#import "SignalShareExtension-Swift.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/Release.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/TextSecureKitEnv.h>

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

- (nullable UIView *)rootReferenceView
{
    return self.rootViewController.view;
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

- (void)setupEnvironment
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [Environment setCurrent:[Release releaseEnvironment]];

        // Encryption/Decryption mutates session state and must be synchronized on a serial queue.
        [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];

        TextSecureKitEnv *sharedEnv =
            [[TextSecureKitEnv alloc] initWithCallMessageHandler:[SAECallMessageHandler new]
                                                 contactsManager:[Environment current].contactsManager
                                                   messageSender:[Environment current].messageSender
                                            notificationsManager:[SAENotificationsManager new]
                                                  profileManager:OWSProfileManager.sharedManager];
        [TextSecureKitEnv setSharedEnv:sharedEnv];

        [[TSStorageManager sharedManager] setupDatabaseWithSafeBlockingMigrations:^{
            [VersionMigrations runSafeBlockingMigrations];
        }];
        [[Environment current].contactsManager startObserving];
    });
}

@end

NS_ASSUME_NONNULL_END
