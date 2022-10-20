//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MainAppContext.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSIdentityManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface MainAppContext ()

@property (nonatomic, nullable) NSMutableArray<AppActiveBlock> *appActiveBlocks;

@property (nonatomic, readonly) UIApplicationState mainApplicationStateOnLaunch;

@end

#pragma mark -

@implementation MainAppContext

@synthesize mainWindow = _mainWindow;
@synthesize appLaunchTime = _appLaunchTime;
@synthesize appForegroundTime = _appForegroundTime;
@synthesize buildTime = _buildTime;
@synthesize reportedApplicationState = _reportedApplicationState;

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.reportedApplicationState = UIApplicationStateInactive;

    NSDate *launchDate = [NSDate new];
    _appLaunchTime = launchDate;
    _appForegroundTime = launchDate;
    _mainApplicationStateOnLaunch = [UIApplication sharedApplication].applicationState;

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

    // We can't use OWSSingletonAssert() since it uses the app context.

    self.appActiveBlocks = [NSMutableArray new];

    return self;
}

#pragma mark - Notifications

- (UIApplicationState)reportedApplicationState
{
    @synchronized(self) {
        return _reportedApplicationState;
    }
}

- (void)setReportedApplicationState:(UIApplicationState)reportedApplicationState
{
    OWSAssertIsOnMainThread();

    @synchronized(self) {
        if (_reportedApplicationState == reportedApplicationState) {
            return;
        }
        _reportedApplicationState = reportedApplicationState;
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;
    _appForegroundTime = [NSDate new];

    OWSLogInfo(@"");

    [BenchManager benchWithTitle:@"Slow post WillEnterForeground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationWillEnterForegroundNotification
                                                 object:nil];
                           }];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateBackground;

    OWSLogInfo(@"");
    OWSLogFlush();

    [BenchManager benchWithTitle:@"Slow post DidEnterBackground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidEnterBackgroundNotification
                                                 object:nil];
                           }];
}

- (void)applicationWillResignActive:(NSNotification *)notification
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

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateActive;

    OWSLogInfo(@"");

    [BenchManager benchWithTitle:@"Slow post DidBecomeActive"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidBecomeActiveNotification
                                                 object:nil];
                           }];

    [self runAppActiveBlocks];
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

- (BOOL)isNSE
{
    return NO;
}

- (BOOL)isRTL
{
    static BOOL isRTL = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isRTL = [[UIApplication sharedApplication] userInterfaceLayoutDirection]
            == UIUserInterfaceLayoutDirectionRightToLeft;
    });
    return isRTL;
}

- (CGFloat)statusBarHeight
{
    return [UIApplication sharedApplication].statusBarFrame.size.height;
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
    return [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:expirationHandler];
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    [UIApplication.sharedApplication endBackgroundTask:backgroundTaskIdentifier];
}

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjectsDescription:(NSString *)blockingObjectsDescription
{
    if (UIApplication.sharedApplication.isIdleTimerDisabled != shouldBeBlocking) {
        if (shouldBeBlocking) {
            OWSLogInfo(@"Blocking sleep because of: %@", blockingObjectsDescription);
        } else {
            OWSLogInfo(@"Unblocking Sleep.");
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

- (void)openSystemSettings
{
    [UIApplication.sharedApplication openSystemSettings];
}

- (void)openURL:(NSURL *)url completion:(void (^__nullable)(BOOL success))completion
{
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:completion];
}

- (BOOL)isRunningTests
{
    return getenv("runningTests_dontStartApp");
}

- (NSDate *)buildTime
{
    if (!_buildTime) {
        NSInteger buildTimestamp =
        [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildDetails"][@"Timestamp"] integerValue];

        if (buildTimestamp == 0) {
            // Production builds should _always_ expire, ensure that here.
            OWSAssert(OWSIsTestableBuild());

            OWSLogDebug(@"No build timestamp, assuming app never expires.");
            _buildTime = [NSDate distantFuture];
        } else {
            _buildTime = [NSDate dateWithTimeIntervalSince1970:buildTimestamp];
        }
    }

    return _buildTime;
}

- (CGRect)frame
{
    return self.mainWindow.frame;
}

- (UIInterfaceOrientation)interfaceOrientation
{
    OWSAssertIsOnMainThread();
    return [UIApplication sharedApplication].statusBarOrientation;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:value];
}

#pragma mark -

- (void)runNowOrWhenMainAppIsActive:(AppActiveBlock)block
{
    OWSAssertDebug(block);

    DispatchMainThreadSafe(^{
        if (self.isMainAppAndActive) {
            // App active blocks typically will be used to safely access the
            // shared data container, so use a background task to protect this
            // work.
            OWSBackgroundTask *_Nullable backgroundTask =
                [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
            block();
            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
            return;
        }

        [self.appActiveBlocks addObject:block];
    });
}

- (void)runAppActiveBlocks
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.isMainAppAndActive);

    // App active blocks typically will be used to safely access the
    // shared data container, so use a background task to protect this
    // work.
    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    NSArray<AppActiveBlock> *appActiveBlocks = [self.appActiveBlocks copy];
    [self.appActiveBlocks removeAllObjects];
    for (AppActiveBlock block in appActiveBlocks) {
        block();
    }

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;
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
    return YES;
}

- (BOOL)shouldProcessIncomingMessages
{
    return YES;
}

- (BOOL)hasUI
{
    return YES;
}

- (BOOL)didLastLaunchNotTerminate
{
    return SignalApp.shared.didLastLaunchNotTerminate;
}

- (BOOL)hasActiveCall
{
    if (AppReadiness.isAppReady) {
        return AppEnvironment.shared.callService.hasCallInProgress;
    } else {
        return NO;
    }
}

- (NSString *)debugLogsDirPath
{
    return DebugLogger.mainAppDebugLogsDirPath;
}

@end

NS_ASSUME_NONNULL_END
