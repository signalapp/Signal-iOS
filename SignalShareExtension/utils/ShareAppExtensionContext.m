//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "ShareAppExtensionContext.h"
#import <SignalMessaging/DebugLogger.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalUI/UIViewController+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShareAppExtensionContext ()

@property (nonatomic) UIViewController *rootViewController;

@property (atomic) UIApplicationState reportedApplicationState;

@end

#pragma mark -

@implementation ShareAppExtensionContext

@synthesize mainWindow = _mainWindow;
@synthesize appLaunchTime = _appLaunchTime;
@synthesize appForegroundTime = _appForegroundTime;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(rootViewController);

    _rootViewController = rootViewController;

    self.reportedApplicationState = UIApplicationStateActive;

    NSDate *launchDate = [NSDate new];
    _appLaunchTime = launchDate;
    _appForegroundTime = launchDate;

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

#pragma mark - Notifications

- (void)extensionHostDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.reportedApplicationState = UIApplicationStateActive;

    [BenchManager benchWithTitle:@"Slow post DidBecomeActive"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidBecomeActiveNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;

    OWSLogInfo(@"");
    OWSLogFlush();

    [BenchManager benchWithTitle:@"Slow post WillResignActive"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationWillResignActiveNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");
    OWSLogFlush();

    self.reportedApplicationState = UIApplicationStateBackground;

    [BenchManager benchWithTitle:@"Slow post DidEnterBackground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidEnterBackgroundNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.reportedApplicationState = UIApplicationStateInactive;

    [BenchManager benchWithTitle:@"Slow post WillEnterForeground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationWillEnterForegroundNotification
                                                 object:nil];
                           }];
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

- (BOOL)isNSE
{
    return NO;
}

- (UIApplicationState)mainApplicationStateOnLaunch
{
    OWSFailDebug(@"Not main app.");

    return UIApplicationStateInactive;
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

- (CGFloat)statusBarHeight
{
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
    OWSAssertDebug(backgroundTaskIdentifier == UIBackgroundTaskInvalid);
}

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjectsDescription:(NSString *)blockingObjectsDescription
{
    OWSLogDebug(@"Ignoring request to block sleep.");
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    OWSFailDebug(@"");
}

- (nullable UIViewController *)frontmostViewController
{
    OWSAssertDebug(self.rootViewController);

    return [self.rootViewController findFrontmostViewController:YES];
}

- (void)openSystemSettings
{
    return;
}

- (void)openURL:(NSURL *)url completion:(void (^__nullable)(BOOL))completion
{
}

- (BOOL)isRunningTests
{
    // We don't need to distinguish this in the SAE.
    return NO;
}

- (CGRect)frame
{
    return self.rootViewController.view.frame;
}

- (UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationPortrait;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    OWSFailDebug(@"");
}

- (void)runNowOrWhenMainAppIsActive:(AppActiveBlock)block
{
    OWSFailDebug(@"cannot run main app active blocks in share extension.");
}

- (id<SSKKeychainStorage>)keychainStorage
{
    return [SSKDefaultKeychainStorage shared];
}

- (NSString *)appDocumentDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

- (NSString *)appSharedDataDirectoryPath
{
    NSURL *groupContainerDirectoryURL =
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:TSConstants.applicationGroup];
    return [groupContainerDirectoryURL path];
}

- (NSString *)appDatabaseBaseDirectoryPath
{
    return self.appSharedDataDirectoryPath;
}

- (NSUserDefaults *)appUserDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:TSConstants.applicationGroup];
}

- (BOOL)canPresentNotifications
{
    return NO;
}

- (BOOL)shouldProcessIncomingMessages
{
    return NO;
}

- (BOOL)hasUI
{
    return YES;
}

- (BOOL)hasActiveCall
{
    return NO;
}

- (NSString *)debugLogsDirPath
{
    return DebugLogger.shareExtensionDebugLogsDirPath;
}

@end

NS_ASSUME_NONNULL_END
