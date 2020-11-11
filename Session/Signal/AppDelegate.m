//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "DebugLogger.h"
#import "MainAppContext.h"
#import "OWSBackup.h"
#import "OWSOrphanDataCleaner.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "Session-Swift.h"
#import "SignalApp.h"
#import "SignalsNavigationController.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalUtilitiesKit/AppSetup.h>
#import <SignalUtilitiesKit/Environment.h>
#import <SignalUtilitiesKit/OWSContactsManager.h>
#import <SignalUtilitiesKit/OWSNavigationController.h>
#import <SignalUtilitiesKit/OWSPreferences.h>
#import <SignalUtilitiesKit/OWSProfileManager.h>
#import <SignalUtilitiesKit/VersionMigrations.h>
#import <SignalUtilitiesKit/AppReadiness.h>
#import <SignalUtilitiesKit/NSUserDefaults+OWS.h>
#import <SignalUtilitiesKit/OWS2FAManager.h>
#import <SignalUtilitiesKit/OWSBatchMessageProcessor.h>
#import <SignalUtilitiesKit/OWSDisappearingMessagesJob.h>
#import <SignalUtilitiesKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalUtilitiesKit/OWSFailedMessagesJob.h>
#import <SignalUtilitiesKit/OWSIncompleteCallsJob.h>
#import <SignalUtilitiesKit/OWSMath.h>
#import <SignalUtilitiesKit/OWSMessageManager.h>
#import <SignalUtilitiesKit/OWSMessageSender.h>
#import <SignalUtilitiesKit/OWSPrimaryStorage+Calling.h>
#import <SignalUtilitiesKit/OWSReadReceiptManager.h>
#import <SignalUtilitiesKit/SSKEnvironment.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SignalUtilitiesKit/TSAccountManager.h>
#import <SignalUtilitiesKit/TSDatabaseView.h>
#import <SignalUtilitiesKit/TSPreKeyManager.h>
#import <SignalUtilitiesKit/TSSocketManager.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <sys/utsname.h>

@import WebRTC;
@import Intents;

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey = @"sgnl";
static NSString *const kURLHostVerifyPrefix = @"verify";

static NSTimeInterval launchStartedAt;

@interface AppDelegate () <UNUserNotificationCenterDelegate, LKAppModeManagerDelegate>

@property (nonatomic) BOOL hasInitialRootViewController;
@property (nonatomic) BOOL areVersionMigrationsComplete;
@property (nonatomic) BOOL didAppLaunchFail;
@property (nonatomic) LKPoller *poller;
@property (nonatomic) LKClosedGroupPoller *closedGroupPoller;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

#pragma mark - Dependencies

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (OWSReadReceiptManager *)readReceiptManager
{
    return [OWSReadReceiptManager sharedManager];
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

- (PushRegistrationManager *)pushRegistrationManager
{
    OWSAssertDebug(AppEnvironment.shared.pushRegistrationManager);

    return AppEnvironment.shared.pushRegistrationManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSDisappearingMessagesJob *)disappearingMessagesJob
{
    OWSAssertDebug(SSKEnvironment.shared.disappearingMessagesJob);

    return SSKEnvironment.shared.disappearingMessagesJob;
}

- (TSSocketManager *)socketManager
{
    OWSAssertDebug(SSKEnvironment.shared.socketManager);

    return SSKEnvironment.shared.socketManager;
}

- (OWSMessageManager *)messageManager
{
    OWSAssertDebug(SSKEnvironment.shared.messageManager);

    return SSKEnvironment.shared.messageManager;
}

- (OWSWindowManager *)windowManager
{
    return Environment.shared.windowManager;
}

- (OWSBackup *)backup
{
    return AppEnvironment.shared.backup;
}

- (OWSNotificationPresenter *)notificationPresenter
{
    return AppEnvironment.shared.notificationPresenter;
}

- (OWSUserNotificationActionHandler *)userNotificationActionHandler
{
    return AppEnvironment.shared.userNotificationActionHandler;
}

- (OWSLegacyNotificationActionHandler *)legacyNotificationActionHandler
{
    return AppEnvironment.shared.legacyNotificationActionHandler;
}

#pragma mark - Lifecycle

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [DDLog flushLog];

    [self stopPoller];
    [self stopClosedGroupPoller];
    [self stopOpenGroupPollers];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidReceiveMemoryWarning");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [DDLog flushLog];

    [self stopPoller];
    [self stopClosedGroupPoller];
    [self stopOpenGroupPollers];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // This should be the first thing we do
    SetCurrentAppContext([MainAppContext new]);

    launchStartedAt = CACurrentMediaTime();

    [LKAppModeManager configureWithDelegate:self];

    BOOL isLoggingEnabled;
#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    isLoggingEnabled = TRUE;
    [DebugLogger.sharedLogger enableTTYLogging];
#elif RELEASE
    isLoggingEnabled = OWSPreferences.isLoggingEnabled;
#endif
    if (isLoggingEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }

    [Cryptography seedRandom];

    // XXX - careful when moving this. It must happen before we initialize OWSPrimaryStorage.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

#if RELEASE
    // ensureIsReadyForAppExtensions may have changed the state of the logging
    // preference (due to [NSUserDefaults migrateToSharedUserDefaults]), so honor
    // that change if necessary.
    if (isLoggingEnabled && !OWSPreferences.isLoggingEnabled) {
        [DebugLogger.sharedLogger disableFileLogging];
    }
#endif

    [AppVersion sharedInstance];

    [self startupLogging];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in storageIsReady.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    [AppSetup
        setupEnvironmentWithAppSpecificSingletonBlock:^{
            // Create AppEnvironment
            [AppEnvironment.shared setup];
            [SignalApp.sharedApp setup];
        }
        migrationCompletion:^{
            OWSAssertIsOnMainThread();

            [self versionMigrationsDidComplete];
        }];

    [SNConfiguration performMainSetup];

    [LKAppearanceUtilities switchToSessionAppearance];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    UIWindow *mainWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    LKAppMode appMode = [NSUserDefaults.standardUserDefaults integerForKey:@"appMode"];
    [self setCurrentAppMode:appMode];

    if (@available(iOS 11, *)) {
        // This must happen in appDidFinishLaunching or earlier to ensure we don't
        // miss notifications.
        // Setting the delegate also seems to prevent us from getting the legacy notification
        // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    }

    [OWSScreenLockUI.sharedManager setupWithRootWindow:self.window];
    [[OWSWindowManager sharedManager] setupWithRootWindow:self.window
                                     screenBlockingWindow:OWSScreenLockUI.sharedManager.screenBlockingWindow];
    [OWSScreenLockUI.sharedManager startObserving];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storageIsReady)
                                                 name:StorageIsReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationLockDidChange:)
                                                 name:NSNotificationName_2FAStateDidChange
                                               object:nil];

    // Loki - Observe data nuke request notifications
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleDataNukeRequested:) name:NSNotification.dataNukeRequested object:nil];
    
    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

    [OWSAnalytics appLaunchDidBegin];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        return;
    }

    if (CurrentAppContext().isRunningTests) {
        return;
    }
    
    NSUserDefaults *sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.loki-project.loki-messenger"];
    [sharedUserDefaults setBool:YES forKey:@"isMainAppActive"];
    [sharedUserDefaults synchronize];

    [self ensureRootViewController];

    LKAppMode appMode = [NSUserDefaults.standardUserDefaults integerForKey:@"appMode"];
    [self setCurrentAppMode:appMode];

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self handleActivation];
    }];

    // Clear all notifications whenever we become active.
    // When opening the app from a notification,
    // AppDelegate.didReceiveLocalNotification will always
    // be called _before_ we become active.
    [self clearAllNotificationsAndRestoreBadgeCount];

    // On every activation, clear old temp directories.
    ClearOldTemporaryDirectories();
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        return;
    }

    [self clearAllNotificationsAndRestoreBadgeCount];
    
    NSUserDefaults *sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.loki-project.loki-messenger"];
    [sharedUserDefaults setBool:NO forKey:@"isMainAppActive"];
    [sharedUserDefaults synchronize];

    [DDLog flushLog];
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window
{
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - Background Fetching

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [LKBackgroundPoller pollWithCompletionHandler:completionHandler];
    }];
}

#pragma mark - App Readiness

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) { return; }

    if (!OWSPrimaryStorage.isDatabasePasswordAccessible) {
        OWSLogInfo(@"Exiting because we are in the background and the database password is not accessible.");

        UILocalNotification *notification = [UILocalNotification new];
        NSString *messageFormat = NSLocalizedString(@"NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
            @"Lock screen notification text presented after user powers on their device without unlocking. Embeds "
            @"{{device model}} (either 'iPad' or 'iPhone')");
        notification.alertBody = [NSString stringWithFormat:messageFormat, UIDevice.currentDevice.localizedModel];

        // Make sure we clear any existing notifications so that they don't start stacking up
        // if the user receives multiple pushes.
        [UIApplication.sharedApplication cancelAllLocalNotifications];
        [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];

        [UIApplication.sharedApplication scheduleLocalNotification:notification];
        [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];

        [DDLog flushLog];
        exit(0);
    }
}

- (void)showLaunchFailureUI:(NSError *)error
{
    // Disable normal functioning of app.
    self.didAppLaunchFail = YES;

    // We perform a subset of the [application:didFinishLaunchingWithOptions:].
    [AppVersion sharedInstance];
    [self startupLogging];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Show the launch screen
    self.window.rootViewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    [self.window makeKeyAndVisible];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_TITLE",
                                                        @"Title for the 'app launch failed' alert.")
                                            message:NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_MESSAGE",
                                                        @"Message for the 'app launch failed' alert.")
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_Nonnull action) {
                                                [Pastelog submitLogsWithCompletion:^{
                                                    OWSFail(@"Exiting after sharing debug logs.");
                                                }];
                                            }]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentAlert:alert];
}

- (void)startupLogging
{
    OWSLogInfo(@"iOS Version: %@", [UIDevice currentDevice].systemVersion);

    NSString *localeIdentifier = [NSLocale.currentLocale objectForKey:NSLocaleIdentifier];
    if (localeIdentifier.length > 0) {
        OWSLogInfo(@"Locale Identifier: %@", localeIdentifier);
    }
    NSString *countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
    if (countryCode.length > 0) {
        OWSLogInfo(@"Country Code: %@", countryCode);
    }
    NSString *languageCode = [NSLocale.currentLocale objectForKey:NSLocaleLanguageCode];
    if (languageCode.length > 0) {
        OWSLogInfo(@"Language Code: %@", languageCode);
    }

    struct utsname systemInfo;
    uname(&systemInfo);

    OWSLogInfo(@"Device Model: %@ (%@)",
        UIDevice.currentDevice.model,
        [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding]);

    NSDictionary<NSString *, NSString *> *buildDetails =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildDetails"];
    OWSLogInfo(@"WebRTC Commit: %@", buildDetails[@"WebRTCCommit"]);
    OWSLogInfo(@"Build XCode Version: %@", buildDetails[@"XCodeVersion"]);
    OWSLogInfo(@"Build OS X Version: %@", buildDetails[@"OSXVersion"]);
    OWSLogInfo(@"Build Cocoapods Version: %@", buildDetails[@"CocoapodsVersion"]);
    OWSLogInfo(@"Build Carthage Version: %@", buildDetails[@"CarthageVersion"]);
    OWSLogInfo(@"Build Date/Time: %@", buildDetails[@"DateTime"]);
}

- (void)enableBackgroundRefreshIfNecessary
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [UIApplication.sharedApplication setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    }];
}

- (void)handleActivation
{
    OWSAssertIsOnMainThread();

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RTCInitializeSSL();

        if ([self.tsAccountManager isRegistered]) {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSLogInfo(@"Running post launch block for registered user: %@.", [self.tsAccountManager localNumber]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [self.disappearingMessagesJob startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

                // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
                // sent before the app exited should be marked as failures.
                [[[OWSFailedMessagesJob alloc] initWithPrimaryStorage:self.primaryStorage] run];
                [[[OWSFailedAttachmentDownloadsJob alloc] initWithPrimaryStorage:self.primaryStorage] run];
            });
        } else {
            OWSLogInfo(@"Running post launch block for unregistered user.");

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [AppEnvironment.shared.notificationPresenter clearAllNotifications];

            UITapGestureRecognizer *gesture =
                [[UITapGestureRecognizer alloc] initWithTarget:[Pastelog class] action:@selector(submitLogs)];
            gesture.numberOfTapsRequired = 8;
            [self.window addGestureRecognizer:gesture];
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([self.tsAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *userPublicKey = self.tsAccountManager.localNumber;

            [self startPollerIfNeeded];
            [self startClosedGroupPollerIfNeeded];
            [self startOpenGroupPollersIfNeeded];

            // Loki: Update profile picture if needed
            NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
            NSDate *now = [NSDate new];
            NSDate *lastProfilePictureUpload = (NSDate *)[userDefaults objectForKey:@"lastProfilePictureUpload"];
            if (lastProfilePictureUpload != nil && [now timeIntervalSinceDate:lastProfilePictureUpload] > 4 * 24 * 60 * 60) {
                OWSProfileManager *profileManager = OWSProfileManager.sharedManager;
                NSString *displayName = [profileManager profileNameForRecipientWithID:userPublicKey];
                UIImage *profilePicture = [profileManager profileAvatarForRecipientId:userPublicKey];
                [profileManager updateLocalProfileName:displayName avatarImage:profilePicture success:^{
                    // Do nothing; the user defaults flag is updated in LokiFileServerAPI
                } failure:^(NSError *error) {
                    // Do nothing
                } requiresSync:YES];
            }

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                OWSLogInfo(@"Retrying remote notification registration since user hasn't registered yet.");
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                __unused AnyPromise *promise =
                    [OWSSyncPushTokensJob runWithAccountManager:AppEnvironment.shared.accountManager
                                                    preferences:Environment.shared.preferences];
            }
        });
    }
}

- (void)versionMigrationsDidComplete
{
    OWSAssertIsOnMainThread();

    self.areVersionMigrationsComplete = YES;

    [self checkIfAppIsReady];
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();

    [self checkIfAppIsReady];
}

- (void)checkIfAppIsReady
{
    OWSAssertIsOnMainThread();

    // App isn't ready until storage is ready AND all version migrations are complete
    if (!self.areVersionMigrationsComplete) {
        return;
    }
    if (![OWSStorage isStorageReady]) {
        return;
    }
    if ([AppReadiness isAppReady]) {
        // Only mark the app as ready once
        return;
    }

    // TODO: Once "app ready" logic is moved into AppSetup, move this line there.
    [self.profileManager ensureLocalProfileCached];

    // Note that this does much more than set a flag;
    // it will also run all deferred blocks.
    [AppReadiness setAppIsReady];

    if (CurrentAppContext().isRunningTests) { return; }

    if ([self.tsAccountManager isRegistered]) {

        // This should happen at any launch, background or foreground
        __unused AnyPromise *pushTokenpromise =
            [OWSSyncPushTokensJob runWithAccountManager:AppEnvironment.shared.accountManager
                                            preferences:Environment.shared.preferences];
    }

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];

    [AppVersion.sharedInstance mainAppLaunchDidComplete];

    [Environment.shared.audioSession setup];

    [SSKEnvironment.shared.reachabilityManager setup];

    if (!Environment.shared.preferences.hasGeneratedThumbnails) {
        [self.primaryStorage.newDatabaseConnection
            asyncReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
                [TSAttachmentStream enumerateCollectionObjectsUsingBlock:^(id _Nonnull obj, BOOL *_Nonnull stop){
                    // no-op. It's sufficient to initWithCoder: each object.
                }];
            }
            completionBlock:^{
                [Environment.shared.preferences setHasGeneratedThumbnails:YES];
            }];
    }

#ifdef DEBUG
    // A bug in orphan cleanup could be disastrous so let's only
    // run it in DEBUG builds for a few releases.
    //
    // TODO: Release to production once we have analytics.
    // TODO: Orphan cleanup is somewhat expensive - not least in doing a bunch
    // TODO: of disk access.  We might want to only run it "once per version"
    // TODO: or something like that in production.
    [OWSOrphanDataCleaner auditOnLaunchIfNecessary];
#endif

    [self.profileManager fetchLocalUsersProfile];
    [self.readReceiptManager prepareCachedValues];

    // Disable the SAE until the main app has successfully completed launch process
    // at least once in the post-SAE world.
    [OWSPreferences setIsReadyForAppExtensions];

    [self ensureRootViewController];

    [self.messageManager startObserving];

    [self.udManager setup];

    [self preheatDatabaseViews];

    [self.primaryStorage touchDbAsync];

    // Every time the user upgrades to a new version:
    //
    // * Update account attributes.
    // * Sync configuration.
    if ([self.tsAccountManager isRegistered]) {
        AppVersion *appVersion = AppVersion.sharedInstance;
        if (appVersion.lastAppVersion.length > 0
            && ![appVersion.lastAppVersion isEqualToString:appVersion.currentAppVersion]) {
            [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];

            [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
        }
    }
}

- (void)preheatDatabaseViews
{
    [self.primaryStorage.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (NSString *viewName in @[
                 TSThreadDatabaseViewExtensionName,
                 TSMessageDatabaseViewExtensionName,
                 TSThreadOutgoingMessageDatabaseViewExtensionName,
                 TSUnreadDatabaseViewExtensionName,
                 TSUnseenDatabaseViewExtensionName,
                 TSThreadSpecialMessagesDatabaseViewExtensionName,
             ]) {
            YapDatabaseViewTransaction *databaseView = [transaction ext:viewName];
            OWSAssertDebug([databaseView isKindOfClass:[YapDatabaseViewTransaction class]]);
        }
    }];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    [self enableBackgroundRefreshIfNecessary];

    if ([self.tsAccountManager isRegistered]) {
        // Start running the disappearing messages job in case the newly registered user
        // enables this feature
        [self.disappearingMessagesJob startIfNecessary];
        [self.profileManager ensureLocalProfileCached];

        // For non-legacy users, read receipts are on by default.
        [self.readReceiptManager setAreReadReceiptsEnabled:YES];

        [self startPollerIfNeeded];
        [self startClosedGroupPollerIfNeeded];
        [self startOpenGroupPollersIfNeeded];
    }
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
}

- (void)ensureRootViewController
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady || self.hasInitialRootViewController) { return; }
    self.hasInitialRootViewController = YES;

    UIViewController *rootViewController;
    BOOL navigationBarHidden = NO;
    if ([self.tsAccountManager isRegistered]) {
        if (self.backup.hasPendingRestoreDecision) {
            rootViewController = [BackupRestoreViewController new];
        } else {
            rootViewController = [HomeVC new];
        }
    } else {
        rootViewController = [LandingVC new];
        navigationBarHidden = NO;
    }
    OWSAssertDebug(rootViewController);
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:rootViewController];
    navigationController.navigationBarHidden = navigationBarHidden;
    self.window.rootViewController = navigationController;

    [UIViewController attemptRotationToDeviceOrientation];
}

#pragma mark - Status Bar Interaction

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    CGPoint location = [[[event allTouches] anyObject] locationInView:[self window]];
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    if (CGRectContainsPoint(statusBarFrame, location)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TappedStatusBarNotification object:nil];
    }
}

#pragma mark - Notifications

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        return;
    }

    [self.pushRegistrationManager didReceiveVanillaPushToken:deviceToken];

    OWSLogInfo(@"Registering for push notifications with token: %@.", deviceToken);
    BOOL isUsingFullAPNs = [NSUserDefaults.standardUserDefaults boolForKey:@"isUsingFullAPNs"];
    if (isUsingFullAPNs) {
        __unused AnyPromise *promise = [LKPushNotificationManager registerWithToken:deviceToken hexEncodedPublicKey:self.tsAccountManager.localNumber isForcedUpdate:NO];
    } else {
        __unused AnyPromise *promise = [LKPushNotificationManager unregisterWithToken:deviceToken isForcedUpdate:NO];
    }
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        return;
    }

    OWSLogError(@"Failed to register push token with error: %@.", error);
#ifdef DEBUG
    OWSLogWarn(@"We're in debug mode. Faking success for remote registration with a fake push identifier.");
    [self.pushRegistrationManager didReceiveVanillaPushToken:[[NSMutableData dataWithLength:32] copy]];
#else
    OWSProdError([OWSAnalyticsEvents appDelegateErrorFailedToRegisterForRemoteNotifications]);
    [self.pushRegistrationManager didFailToReceiveVanillaPushTokenWithError:error];
#endif
}

- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        return;
    }

    [self.notificationPresenter didRegisterLegacyNotificationSettings];
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
    }];
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"App launch failed");
        completionHandler(NO);
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) { return; }
        [SignalApp.sharedApp.homeViewController createNewPrivateChat];
        completionHandler(YES);
    }];
}

// The method will be called on the delegate only if the application is in the foreground. If the method is not
// implemented or the handler is not called in a timely manner then the notification will not be presented. The
// application can choose to have the notification presented as a sound, badge, alert and/or in the notification list.
// This decision should be based on whether the information in the notification is otherwise visible to the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
        __IOS_AVAILABLE(10.0)__TVOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)__OSX_AVAILABLE(10.14)
{
    if (notification.request.content.userInfo[@"remote"]) {
        OWSLogInfo(@"[Loki] Ignoring remote notifications while the app is in the foreground.");
        return;
    }
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        // We need to respect the in-app notification sound preference. This method, which is called
        // for modern UNUserNotification users, could be a place to do that, but since we'd still
        // need to handle this behavior for legacy UINotification users anyway, we "allow" all
        // notification options here, and rely on the shared logic in NotificationPresenter to
        // honor notification sound preferences for both modern and legacy users.
        UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
        completionHandler(options);
    }];
}

// The method will be called on the delegate when the user responded to the notification by opening the application,
// dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
// returns from application:didFinishLaunchingWithOptions:.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler __IOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)
        __OSX_AVAILABLE(10.14)__TVOS_PROHIBITED
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        [self.userNotificationActionHandler handleNotificationResponse:response completionHandler:completionHandler];
    }];
}

// The method will be called on the delegate when the application is launched in response to the user's request to view
// in-app notification settings. Add UNAuthorizationOptionProvidesAppNotificationSettings as an option in
// requestAuthorizationWithOptions:completionHandler: to add a button to inline notification settings view and the
// notification settings view in Settings. The notification will be nil when opened from Settings.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center openSettingsForNotification:(nullable UNNotification *)notification __IOS_AVAILABLE(12.0)
        __OSX_AVAILABLE(10.14)__WATCHOS_PROHIBITED __TVOS_PROHIBITED
{

}

#pragma mark - Polling

- (void)startPollerIfNeeded
{
    if (self.poller == nil) {
        NSString *userPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
        if (userPublicKey != nil) {
            self.poller = [[LKPoller alloc] init];
        }
    }
    [self.poller startIfNeeded];
}

- (void)stopPoller { [self.poller stop]; }

- (void)startClosedGroupPollerIfNeeded
{
    if (self.closedGroupPoller == nil) {
        NSString *userPublicKey = OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
        if (userPublicKey != nil) {
            self.closedGroupPoller = [[LKClosedGroupPoller alloc] init];
        }
    }
    [self.closedGroupPoller startIfNeeded];
}

- (void)stopClosedGroupPoller { [self.closedGroupPoller stop]; }

- (void)startOpenGroupPollersIfNeeded
{
    [LKPublicChatManager.shared startPollersIfNeeded];
    [SSKEnvironment.shared.attachmentDownloads continueDownloadIfPossible];
}

- (void)stopOpenGroupPollers { [LKPublicChatManager.shared stopPollers]; }

# pragma mark - App Mode

- (LKAppMode)getCurrentAppMode
{
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window == nil) { return LKAppModeLight; }
    UIUserInterfaceStyle userInterfaceStyle = window.traitCollection.userInterfaceStyle;
    BOOL isLightMode = userInterfaceStyle == UIUserInterfaceStyleLight || userInterfaceStyle == UIUserInterfaceStyleUnspecified;
    return isLightMode ? LKAppModeLight : LKAppModeDark;
}

- (void)setCurrentAppMode:(LKAppMode)appMode
{
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window == nil) { return; }
    [NSUserDefaults.standardUserDefaults setInteger:appMode forKey:@"appMode"];
    switch (appMode) {
        case LKAppModeLight: {
            if (@available(iOS 13.0, *)) {
                window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            }
            window.backgroundColor = UIColor.whiteColor;
            break;
        }
        case LKAppModeDark: {
            if (@available(iOS 13.0, *)) {
                window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            }
            window.backgroundColor = UIColor.blackColor;
            break;
        }
    }
    [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.appModeChanged object:nil];
}

# pragma mark - Other

- (void)handleDataNukeRequested:(NSNotification *)notification
{
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    BOOL isUsingFullAPNs = [userDefaults boolForKey:@"isUsingFullAPNs"];
    NSString *hexEncodedDeviceToken = [userDefaults stringForKey:@"deviceToken"];
    if (isUsingFullAPNs && hexEncodedDeviceToken != nil) {
        NSData *deviceToken = [NSData dataFromHexString:hexEncodedDeviceToken];
        [[LKPushNotificationManager unregisterWithToken:deviceToken isForcedUpdate:YES] retainUntilComplete];
    }
    [ThreadUtil deleteAllContent];
    [SSKEnvironment.shared.messageSenderJobQueue clearAllJobs];
    [SSKEnvironment.shared.identityManager clearIdentityKey];
    [SNSnodeAPI clearSnodePool];
    [self stopPoller];
    [self stopClosedGroupPoller];
    [self stopOpenGroupPollers];
    [LKPublicChatManager.shared stopPollers];
    BOOL wasUnlinked = [NSUserDefaults.standardUserDefaults boolForKey:@"wasUnlinked"];
    [SignalApp resetAppData:^{
        // Resetting the data clears the old user defaults. We need to restore the unlink default.
        [NSUserDefaults.standardUserDefaults setBool:wasUnlinked forKey:@"wasUnlinked"];
    }];
}

@end
