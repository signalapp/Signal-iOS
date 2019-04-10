//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "DebugLogger.h"
#import "HomeViewController.h"
#import "MainAppContext.h"
#import "OWS2FASettingsViewController.h"
#import "OWSBackup.h"
#import "OWSOrphanDataCleaner.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "SignalsNavigationController.h"
#import "ViewControllerUtils.h"
#import <Intents/Intents.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/OWSIncompleteCallsJob.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSPrimaryStorage+Calling.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <WebRTC/WebRTC.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <sys/utsname.h>

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

static NSTimeInterval launchStartedAt;

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@property (nonatomic) BOOL hasInitialRootViewController;
@property (nonatomic) BOOL areVersionMigrationsComplete;
@property (nonatomic) BOOL didAppLaunchFail;

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

#pragma mark -

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidEnterBackground.");

    [DDLog flushLog];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillEnterForeground.");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidReceiveMemoryWarning.");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillTerminate.");

    [DDLog flushLog];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // This should be the first thing we do.
    SetCurrentAppContext([MainAppContext new]);

    launchStartedAt = CACurrentMediaTime();

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

    OWSLogWarn(@"application: didFinishLaunchingWithOptions.");
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

    // We need to do this _after_ we set up logging, when the keychain is unlocked,
    // but before we access YapDatabase, files on disk, or NSUserDefaults
    if (![self ensureIsReadyForAppExtensions]) {
        // If this method has failed; do nothing.
        //
        // ensureIsReadyForAppExtensions will show a failure mode UI that
        // lets users report this error.
        OWSLogInfo(@"application: didFinishLaunchingWithOptions failed.");

        return YES;
    }

    [AppVersion sharedInstance];

    [self startupLogging];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in storageIsReady.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    [AppSetup
        setupEnvironmentWithAppSpecificSingletonBlock:^{
            // Create AppEnvironment.
            [AppEnvironment.shared setup];
            [SignalApp.sharedApp setup];
        }
        migrationCompletion:^{
            OWSAssertIsOnMainThread();

            [self versionMigrationsDidComplete];
        }];

    [UIUtil setupSignalAppearence];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    UIWindow *mainWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    if (@available(iOS 11, *)) {
        // This must happen in appDidFinishLaunching or earlier to ensure we don't
        // miss notifications.
        // Setting the delegate also seems to prevent us from getting the legacy notification
        // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    }

    // Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        OWSLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
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

    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

    [OWSAnalytics appLaunchDidBegin];

    return YES;
}

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        return;
    }

    if (![OWSPrimaryStorage isDatabasePasswordAccessible]) {
        OWSLogInfo(@"exiting because we are in the background and the database password is not accessible.");

        UILocalNotification *notification = [UILocalNotification new];
        NSString *messageFormat = NSLocalizedString(@"NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
            @"Lock screen notification text presented after user powers on their device without unlocking. Embeds "
            @"{{device model}} (either 'iPad' or 'iPhone')");
        notification.alertBody = [NSString stringWithFormat:messageFormat, UIDevice.currentDevice.localizedModel];

        // Make sure we clear any existing notifications so that they don't start stacking up
        // if the user receives multiple pushes.
        [UIApplication.sharedApplication cancelAllLocalNotifications];
        [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];

        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];

        [DDLog flushLog];
        exit(0);
    }
}

- (BOOL)ensureIsReadyForAppExtensions
{
    // Given how sensitive this migration is, we verbosely
    // log the contents of all involved paths before and after.
    //
    // TODO: Remove this logging once we have high confidence
    // in our migration logic.
    NSArray<NSString *> *paths = @[
        OWSPrimaryStorage.legacyDatabaseFilePath,
        OWSPrimaryStorage.legacyDatabaseFilePath_SHM,
        OWSPrimaryStorage.legacyDatabaseFilePath_WAL,
        OWSPrimaryStorage.sharedDataDatabaseFilePath,
        OWSPrimaryStorage.sharedDataDatabaseFilePath_SHM,
        OWSPrimaryStorage.sharedDataDatabaseFilePath_WAL,
    ];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            OWSLogInfo(@"storage file: %@, %@", path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }

    if ([OWSPreferences isReadyForAppExtensions]) {
        return YES;
    }

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    SUPPRESS_DEADSTORE_WARNING(backgroundTask);

    if ([NSFileManager.defaultManager fileExistsAtPath:OWSPrimaryStorage.legacyDatabaseFilePath]) {
        OWSLogInfo(
            @"Legacy Database file size: %@", [OWSFileSystem fileSizeOfPath:OWSPrimaryStorage.legacyDatabaseFilePath]);
        OWSLogInfo(@"\t Legacy SHM file size: %@",
            [OWSFileSystem fileSizeOfPath:OWSPrimaryStorage.legacyDatabaseFilePath_SHM]);
        OWSLogInfo(@"\t Legacy WAL file size: %@",
            [OWSFileSystem fileSizeOfPath:OWSPrimaryStorage.legacyDatabaseFilePath_WAL]);
    }

    NSError *_Nullable error = [self convertDatabaseIfNecessary];

    if (!error) {
        [NSUserDefaults migrateToSharedUserDefaults];
    }

    if (!error) {
        error = [OWSPrimaryStorage migrateToSharedData];
    }
    if (!error) {
        error = [OWSUserProfile migrateToSharedData];
    }
    if (!error) {
        error = [TSAttachmentStream migrateToSharedData];
    }

    if (error) {
        OWSFailDebug(@"database conversion failed: %@", error);
        [self showLaunchFailureUI:error];
        return NO;
    }

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;

    return YES;
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
                                                    OWSFail(@"exiting after sharing debug logs.");
                                                }];
                                            }]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentAlert:alert];
}

- (nullable NSError *)convertDatabaseIfNecessary
{
    OWSLogInfo(@"");

    NSString *databaseFilePath = [OWSPrimaryStorage legacyDatabaseFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]) {
        OWSLogVerbose(@"no legacy database file found");
        return nil;
    }

    NSError *_Nullable error;
    NSData *_Nullable databasePassword = [OWSStorage tryToLoadDatabaseLegacyPassphrase:&error];
    if (!databasePassword || error) {
        return (error
                ?: OWSErrorWithCodeDescription(
                       OWSErrorCodeDatabaseConversionFatalError, @"Failed to load database password"));
    }

    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSLogVerbose(@"saltData: %@", saltData.hexadecimalString);

        // Derive and store the raw cipher key spec, to avoid the ongoing tax of future KDF
        NSData *_Nullable keySpecData =
            [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];

        if (!keySpecData) {
            OWSLogError(@"Failed to derive key spec.");
            return NO;
        }

        [OWSStorage storeDatabaseCipherKeySpec:keySpecData];

        return YES;
    };

    YapDatabaseOptions *dbOptions = [OWSStorage defaultDatabaseOptions];
    error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                              databasePassword:databasePassword
                                                       options:dbOptions
                                               recordSaltBlock:recordSaltBlock];
    if (!error) {
        [OWSStorage removeLegacyPassphrase];
    }

    return error;
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

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogInfo(@"registered vanilla push token");
    [self.pushRegistrationManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogError(@"failed to register vanilla push token with error: %@", error);
#ifdef DEBUG
    OWSLogWarn(@"We're in debug mode. Faking success for remote registration with a fake push identifier");
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
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogInfo(@"registered legacy notification settings");
    [self.notificationPresenter didRegisterLegacyNotificationSettings];
}

- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)url
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if (!AppReadiness.isAppReady) {
        OWSLogWarn(@"Ignoring openURL: app not ready.");
        // We don't need to use [AppReadiness runNowOrWhenAppDidBecomeReady:];
        // the only URLs we handle in Signal iOS at the moment are used
        // for resuming the verification step of the registration flow.
        return NO;
    }

    if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![self.tsAccountManager isRegistered]) {
            id signupController = SignalApp.sharedApp.signUpFlowNavigationController;
            if ([signupController isKindOfClass:[OWSNavigationController class]]) {
                OWSNavigationController *navController = (OWSNavigationController *)signupController;
                UIViewController *controller = [navController.childViewControllers lastObject];
                if ([controller isKindOfClass:[OnboardingVerificationViewController class]]) {
                    OnboardingVerificationViewController *verificationView
                        = (OnboardingVerificationViewController *)controller;
                    NSString *verificationCode           = [url.path substringFromIndex:1];
                    [verificationView setVerificationCodeAndTryToVerify:verificationCode];
                    return YES;
                } else {
                    OWSLogWarn(@"Not the verification view controller we expected. Got %@ instead",
                        NSStringFromClass(controller.class));
                }
            }
        } else {
            OWSFailDebug(@"Application opened with an unknown URL action: %@", url.host);
        }
    } else {
        OWSFailDebug(@"Application opened with an unknown URL scheme: %@", url.scheme);
    }
    return NO;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationDidBecomeActive.");
    if (CurrentAppContext().isRunningTests) {
        return;
    }

    [self ensureRootViewController];

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

    OWSLogInfo(@"applicationDidBecomeActive completed.");
}

- (void)enableBackgroundRefreshIfNecessary
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (OWS2FAManager.sharedManager.is2FAEnabled && [self.tsAccountManager isRegisteredAndReady]) {
            // Ping server once a day to keep-alive 2FA clients.
            const NSTimeInterval kBackgroundRefreshInterval = 24 * 60 * 60;
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:kBackgroundRefreshInterval];
        } else {
            [[UIApplication sharedApplication]
                setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        }
    }];
}

- (void)handleActivation
{
    OWSAssertIsOnMainThread();

    OWSLogWarn(@"handleActivation.");

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RTCInitializeSSL();

        if ([self.tsAccountManager isRegistered]) {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSLogInfo(@"running post launch block for registered user: %@", [self.tsAccountManager localNumber]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [self.disappearingMessagesJob startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

                // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
                // sent before the app exited should be marked as failures.
                [[[OWSFailedMessagesJob alloc] initWithPrimaryStorage:self.primaryStorage] run];
                // Mark all "incomplete" calls as missed, e.g. any incoming or outgoing calls that were not
                // connected, failed or hung up before the app existed should be marked as missed.
                [[[OWSIncompleteCallsJob alloc] initWithPrimaryStorage:self.primaryStorage] run];
                [[[OWSFailedAttachmentDownloadsJob alloc] initWithPrimaryStorage:self.primaryStorage] run];
            });
        } else {
            OWSLogInfo(@"running post launch block for unregistered user.");

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [AppEnvironment.shared.notificationPresenter clearAllNotifications];

            [self.socketManager requestSocketOpen];

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
            [self.socketManager requestSocketOpen];
            [Environment.shared.contactsManager fetchSystemContactsOnceIfAlreadyAuthorized];
            [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                OWSLogInfo(@"Retrying to register for remote notifications since user hasn't registered yet.");
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                __unused AnyPromise *promise =
                    [OWSSyncPushTokensJob runWithAccountManager:AppEnvironment.shared.accountManager
                                                    preferences:Environment.shared.preferences];
            }

            if ([OWS2FAManager sharedManager].isDueForReminder) {
                if (!self.hasInitialRootViewController || self.window.rootViewController == nil) {
                    OWSLogDebug(@"Skipping 2FA reminder since there isn't yet an initial view controller");
                } else {
                    UIViewController *rootViewController = self.window.rootViewController;
                    OWSNavigationController *reminderNavController =
                        [OWS2FAReminderViewController wrappedInNavController];

                    [rootViewController presentViewController:reminderNavController animated:YES completion:nil];
                }
            }
        });
    }

    OWSLogInfo(@"handleActivation completed.");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationWillResignActive.");

    [self clearAllNotificationsAndRestoreBadgeCount];

    [DDLog flushLog];
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
    }];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        completionHandler(NO);
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            UIAlertController *controller =
                [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                                                    message:NSLocalizedString(@"REGISTRATION_RESTRICTED_MESSAGE", nil)
                                             preferredStyle:UIAlertControllerStyleAlert];

            [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *_Nonnull action){

                                                         }]];
            UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
            [fromViewController presentViewController:controller
                                             animated:YES
                                           completion:^{
                                               completionHandler(NO);
                                           }];
            return;
        }

        [SignalApp.sharedApp.homeViewController showNewConversationView];

        completionHandler(YES);
    }];
}

/**
 * Among other things, this is used by "call back" callkit dialog and calling from native contacts app.
 *
 * We always return YES if we are going to try to handle the user activity since
 * we never want iOS to contact us again using a URL.
 *
 * From https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application?language=objc:
 *
 * If you do not implement this method or if your implementation returns NO, iOS tries to
 * create a document for your app to open using a URL.
 */
- (BOOL)application:(UIApplication *)application
    continueUserActivity:(nonnull NSUserActivity *)userActivity
      restorationHandler:(nonnull void (^)(NSArray *_Nullable))restorationHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"]) {
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            OWSLogError(@"unexpectedly received INStartVideoCallIntent pre iOS10");
            return NO;
        }

        OWSLogInfo(@"got start video call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartVideoCallIntent class]]) {
            OWSLogError(@"unexpected class for start call video: %@", intent);
            return NO;
        }
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppDidBecomeReady:^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            NSString *_Nullable phoneNumber = [self phoneNumberForIntentHandle:handle];
            if (phoneNumber.length < 1) {
                OWSLogWarn(@"ignoring attempt to initiate video call to unknown user.");
                return;
            }

            // This intent can be received from more than one user interaction.
            //
            // * It can be received if the user taps the "video" button in the CallKit UI for an
            //   an ongoing call.  If so, the correct response is to try to activate the local
            //   video for that call.
            // * It can be received if the user taps the "video" button for a contact in the
            //   contacts app.  If so, the correct response is to try to initiate a new call
            //   to that user - unless there already is another call in progress.
            if (AppEnvironment.shared.callService.call != nil) {
                if ([phoneNumber isEqualToString:AppEnvironment.shared.callService.call.remotePhoneNumber]) {
                    OWSLogWarn(@"trying to upgrade ongoing call to video.");
                    [AppEnvironment.shared.callService handleCallKitStartVideo];
                    return;
                } else {
                    OWSLogWarn(@"ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.");
                    return;
                }
            }

            OutboundCallInitiator *outboundCallInitiator = AppEnvironment.shared.outboundCallInitiator;
            OWSAssertDebug(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithHandle:phoneNumber];
        }];
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {

        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            OWSLogError(@"unexpectedly received INStartAudioCallIntent pre iOS10");
            return NO;
        }

        OWSLogInfo(@"got start audio call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartAudioCallIntent class]]) {
            OWSLogError(@"unexpected class for start call audio: %@", intent);
            return NO;
        }
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppDidBecomeReady:^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            NSString *_Nullable phoneNumber = [self phoneNumberForIntentHandle:handle];
            if (phoneNumber.length < 1) {
                OWSLogWarn(@"ignoring attempt to initiate audio call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.call != nil) {
                OWSLogWarn(@"ignoring INStartAudioCallIntent due to ongoing WebRTC call.");
                return;
            }

            OutboundCallInitiator *outboundCallInitiator = AppEnvironment.shared.outboundCallInitiator;
            OWSAssertDebug(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithHandle:phoneNumber];
        }];
        return YES;
    } else {
        OWSLogWarn(@"userActivity: %@, but not yet supported.", userActivity.activityType);
    }

    // TODO Something like...
    // *phoneNumber = [[[[[[userActivity interaction] intent] contacts] firstObject] personHandle] value]
    // thread = blah
    // [callUIAdapter startCall:thread]
    //
    // Here's the Speakerbox Example for intent / NSUserActivity handling:
    //
    //    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
    //        guard let handle = userActivity.startCallHandle else {
    //            print("Could not determine start call handle from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        guard let video = userActivity.video else {
    //            print("Could not determine video from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        callManager.startCall(handle: handle, video: video)
    //        return true
    //    }

    return NO;
}

- (nullable NSString *)phoneNumberForIntentHandle:(NSString *)handle
{
    OWSAssertDebug(handle.length > 0);

    if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
        NSString *_Nullable phoneNumber = [self.primaryStorage phoneNumberForCallKitId:handle];
        if (phoneNumber.length < 1) {
            OWSLogWarn(@"ignoring attempt to initiate audio call to unknown anonymous signal user.");
            return nil;
        }
        return phoneNumber;
    }

    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:handle
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {
        return phoneNumber.toE164;
    }
    return nil;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window
{
    if (self.hasCall) {
        OWSLogInfo(@"has call");
        // The call-banner window is only suitable for portrait display
        return UIInterfaceOrientationMaskPortrait;
    }

    UIViewController *_Nullable rootViewController = self.window.rootViewController;
    if (!rootViewController) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return rootViewController.supportedInterfaceOrientations;
}

- (BOOL)hasCall
{
    return self.windowManager.hasCall;
}

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }
    if (!(AppReadiness.isAppReady && [self.tsAccountManager isRegisteredAndReady])) {
        OWSLogInfo(@"Ignoring remote notification; app not ready.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];
    }];
}

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }
    if (!(AppReadiness.isAppReady && [self.tsAccountManager isRegisteredAndReady])) {
        OWSLogInfo(@"Ignoring remote notification; app not ready.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            completionHandler(UIBackgroundFetchResultNewData);
        });
    }];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogInfo(@"%@", notification);
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            OWSLogInfo(@"Ignoring action; app not ready.");
            return;
        }

        [self.legacyNotificationActionHandler
            handleNotificationResponseWithActionIdentifier:OWSLegacyNotificationActionHandler.kDefaultActionIdentifier
                                              notification:notification
                                              responseInfo:@{}
                                         completionHandler:^{
                                         }];
    }];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)())completionHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        completionHandler();
        return;
    }

    // The docs for handleActionWithIdentifier:... state:
    // "You must call [completionHandler] at the end of your method.".
    // Nonetheless, it is presumably safe to call the completion handler
    // later, after this method returns.
    //
    // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623068-application?language=objc
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            OWSLogInfo(@"Ignoring action; app not ready.");
            completionHandler();
            return;
        }

        [self.legacyNotificationActionHandler handleNotificationResponseWithActionIdentifier:identifier
                                                                                notification:notification
                                                                                responseInfo:@{}
                                                                           completionHandler:completionHandler];
    }];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)())completionHandler
{
    OWSLogInfo(@"handling action with identifier: %@", identifier);

    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        completionHandler();
        return;
    }

    // The docs for handleActionWithIdentifier:... state:
    // "You must call [completionHandler] at the end of your method.".
    // Nonetheless, it is presumably safe to call the completion handler
    // later, after this method returns.
    //
    // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623068-application?language=objc
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            OWSLogInfo(@"Ignoring action; app not ready.");
            completionHandler();
            return;
        }

        [self.legacyNotificationActionHandler handleNotificationResponseWithActionIdentifier:identifier
                                                                                notification:notification
                                                                                responseInfo:responseInfo
                                                                           completionHandler:completionHandler];
    }];
}

- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    OWSLogInfo(@"performing background fetch");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        __block AnyPromise *job = [AppEnvironment.shared.messageFetcherJob run].then(^{
            // HACK: Call completion handler after n seconds.
            //
            // We don't currently have a convenient API to know when message fetching is *done* when
            // working with the websocket.
            //
            // We *could* substantially rewrite the TSSocketManager to take advantage of the `empty` message
            // But once our REST endpoint is fixed to properly de-enqueue fallback notifications, we can easily
            // use the rest endpoint here rather than the websocket and circumvent making changes to critical code.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completionHandler(UIBackgroundFetchResultNewData);
                job = nil;
            });
        });
        [job retainUntilComplete];
    }];
}

- (void)versionMigrationsDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"versionMigrationsDidComplete");

    self.areVersionMigrationsComplete = YES;

    [self checkIfAppIsReady];
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"storageIsReady");

    [self checkIfAppIsReady];
}

- (void)checkIfAppIsReady
{
    OWSAssertIsOnMainThread();

    // App isn't ready until storage is ready AND all version migrations are complete.
    if (!self.areVersionMigrationsComplete) {
        return;
    }
    if (![OWSStorage isStorageReady]) {
        return;
    }
    if ([AppReadiness isAppReady]) {
        // Only mark the app as ready once.
        return;
    }

    OWSLogInfo(@"checkIfAppIsReady");

    // TODO: Once "app ready" logic is moved into AppSetup, move this line there.
    [self.profileManager ensureLocalProfileCached];

    // Note that this does much more than set a flag;
    // it will also run all deferred blocks.
    [AppReadiness setAppIsReady];

    if (CurrentAppContext().isRunningTests) {
        OWSLogVerbose(@"Skipping post-launch logic in tests.");
        return;
    }

    if ([self.tsAccountManager isRegistered]) {
        OWSLogInfo(@"localNumber: %@", [TSAccountManager localNumber]);

        // Fetch messages as soon as possible after launching. In particular, when
        // launching from the background, without this, we end up waiting some extra
        // seconds before receiving an actionable push notification.
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];

        // This should happen at any launch, background or foreground.
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
    //       of disk access.  We might want to only run it "once per version"
    //       or something like that in production.
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

    OWSLogInfo(@"registrationStateDidChange");

    [self enableBackgroundRefreshIfNecessary];

    if ([self.tsAccountManager isRegistered]) {
        OWSLogInfo(@"localNumber: %@", [self.tsAccountManager localNumber]);

        [self.primaryStorage.newDatabaseConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [ExperienceUpgradeFinder.sharedManager markAllAsSeenWithTransaction:transaction];
            }];
        // Start running the disappearing messages job in case the newly registered user
        // enables this feature
        [self.disappearingMessagesJob startIfNecessary];
        [self.profileManager ensureLocalProfileCached];

        // For non-legacy users, read receipts are on by default.
        [self.readReceiptManager setAreReadReceiptsEnabled:YES];
    }
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
}

- (void)ensureRootViewController
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"ensureRootViewController");

    if (!AppReadiness.isAppReady || self.hasInitialRootViewController) {
        return;
    }
    self.hasInitialRootViewController = YES;

    NSTimeInterval startupDuration = CACurrentMediaTime() - launchStartedAt;
    OWSLogInfo(@"Presenting app %.2f seconds after launch started.", startupDuration);

    UIViewController *rootViewController;
    BOOL navigationBarHidden = NO;
    if ([self.tsAccountManager isRegistered]) {
        if (self.backup.hasPendingRestoreDecision) {
            rootViewController = [BackupRestoreViewController new];
        } else {
            rootViewController = [HomeViewController new];
        }
    } else {
        rootViewController = [[OnboardingController new] initialViewController];
        navigationBarHidden = YES;
    }
    OWSAssertDebug(rootViewController);
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:rootViewController];
    navigationController.navigationBarHidden = navigationBarHidden;
    self.window.rootViewController = navigationController;

    [AppUpdateNag.sharedInstance showAppUpgradeNagIfNecessary];

    [UIViewController attemptRotationToDeviceOrientation];
}

#pragma mark - status bar touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    CGPoint location = [[[event allTouches] anyObject] locationInView:[self window]];
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    if (CGRectContainsPoint(statusBarFrame, location)) {
        OWSLogDebug(@"touched status bar");
        [[NSNotificationCenter defaultCenter] postNotificationName:TappedStatusBarNotification object:nil];
    }
}

#pragma mark - UNUserNotificationsDelegate

// The method will be called on the delegate only if the application is in the foreground. If the method is not
// implemented or the handler is not called in a timely manner then the notification will not be presented. The
// application can choose to have the notification presented as a sound, badge, alert and/or in the notification list.
// This decision should be based on whether the information in the notification is otherwise visible to the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
    __IOS_AVAILABLE(10.0)__TVOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)__OSX_AVAILABLE(10.14)
{
    OWSLogInfo(@"");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        // We need to respect the in-app notification sound preference. This method, which is called
        // for modern UNUserNotification users, could be a place to do that, but since we'd still
        // need to handle this behavior for legacy UINotification users anyway, we "allow" all
        // notification options here, and rely on the shared logic in NotificationPresenter to
        // honor notification sound preferences for both modern and legacy users.
        UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert
            | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
        completionHandler(options);
    }];
}

// The method will be called on the delegate when the user responded to the notification by opening the application,
// dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
// returns from application:didFinishLaunchingWithOptions:.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler __IOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)
                                       __OSX_AVAILABLE(10.14)__TVOS_PROHIBITED
{
    OWSLogInfo(@"");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        [self.userNotificationActionHandler handleNotificationResponse:response completionHandler:completionHandler];
    }];
}

// The method will be called on the delegate when the application is launched in response to the user's request to view
// in-app notification settings. Add UNAuthorizationOptionProvidesAppNotificationSettings as an option in
// requestAuthorizationWithOptions:completionHandler: to add a button to inline notification settings view and the
// notification settings view in Settings. The notification will be nil when opened from Settings.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(nullable UNNotification *)notification __IOS_AVAILABLE(12.0)
                                    __OSX_AVAILABLE(10.14)__WATCHOS_PROHIBITED __TVOS_PROHIBITED
{
    OWSLogInfo(@"");
}

@end
