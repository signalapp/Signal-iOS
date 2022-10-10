//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "MainAppContext.h"
#import "Session-Swift.h"
#import <SignalCoreKit/Threading.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const ReportedApplicationStateDidChangeNotification = @"ReportedApplicationStateDidChangeNotification";

@interface MainAppContext ()

@property (atomic) UIApplicationState reportedApplicationState;

@property (nonatomic, nullable) NSMutableArray<AppActiveBlock> *appActiveBlocks;

@end

#pragma mark -

@implementation MainAppContext

@synthesize mainWindow = _mainWindow;
@synthesize appLaunchTime = _appLaunchTime;
@synthesize wasWokenUpByPushNotification = _wasWokenUpByPushNotification;

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.reportedApplicationState = UIApplicationStateInactive;

    _appLaunchTime = [NSDate new];
    _wasWokenUpByPushNotification = false;

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

    // We can't use OWSSingletonAssert() since it uses the app context.

    self.appActiveBlocks = [NSMutableArray new];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)setReportedApplicationState:(UIApplicationState)reportedApplicationState
{
    OWSAssertIsOnMainThread();

    if (_reportedApplicationState == reportedApplicationState) {
        return;
    }
    _reportedApplicationState = reportedApplicationState;

    [[NSNotificationCenter defaultCenter] postNotificationName:ReportedApplicationStateDidChangeNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;

    OWSLogInfo(@"");

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillEnterForegroundNotification object:nil];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateBackground;

    OWSLogInfo(@"");
    [DDLog flushLog];

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidEnterBackgroundNotification object:nil];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;

    OWSLogInfo(@"");
    [DDLog flushLog];

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationWillResignActiveNotification object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateActive;

    OWSLogInfo(@"");

    [NSNotificationCenter.defaultCenter postNotificationName:OWSApplicationDidBecomeActiveNotification object:nil];

    [self runAppActiveBlocks];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");
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

- (BOOL)isShareExtension {
    return NO;
}

- (BOOL)isRTL
{
    // FIXME: We should try to remove this as we've had to add a hack to ensure the first call to this runs on the main thread
    static BOOL isRTL = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isRTL = [[UIApplication sharedApplication] userInterfaceLayoutDirection]
            == UIUserInterfaceLayoutDirectionRightToLeft;
    });
    return isRTL;
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

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjects:(NSArray<id> *)blockingObjects
{
    if (UIApplication.sharedApplication.isIdleTimerDisabled != shouldBeBlocking) {
        if (shouldBeBlocking) {
            NSMutableString *logString =
                [NSMutableString stringWithFormat:@"Blocking sleep because of: %@", blockingObjects.firstObject];
            if (blockingObjects.count > 1) {
                [logString appendString:[NSString stringWithFormat:@"(and %lu others)", blockingObjects.count - 1]];
            }
            OWSLogInfo(@"%@", logString);
        } else {
            OWSLogInfo(@"Unblocking Sleep.");
        }
    }
    UIApplication.sharedApplication.idleTimerDisabled = shouldBeBlocking;
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:value];
    [[NSUserDefaults sharedLokiProject] setInteger:value forKey:@"currentBadgeNumber"];
    [[NSUserDefaults sharedLokiProject] synchronize];
}

- (nullable UIViewController *)frontmostViewController
{
    return UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
}

- (nullable UIAlertAction *)openSystemSettingsAction
{
    return [UIAlertAction actionWithTitle:CommonStrings.openSettingsButton
                  accessibilityIdentifier:[NSString stringWithFormat:@"%@.%@", self.class, @"system_settings"]
                                    style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction *_Nonnull action) {
                                      [UIApplication.sharedApplication openSystemSettings];
                                  }];
}

- (BOOL)isRunningTests
{
    return (NSProcessInfo.processInfo.environment[@"XCTestConfigurationFilePath"] != nil);
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
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SignalApplicationGroup];
    return [groupContainerDirectoryURL path];
}

- (NSUserDefaults *)appUserDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:SignalApplicationGroup];
}

@end

NS_ASSUME_NONNULL_END
