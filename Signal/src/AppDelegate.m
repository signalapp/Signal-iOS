//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "AppStoreRating.h"
#import "AppUpdateNag.h"
#import "CodeVerificationViewController.h"
#import "DebugLogger.h"
#import "HomeViewController.h"
#import "MainAppContext.h"
#import "NotificationsManager.h"
#import "OWS2FASettingsViewController.h"
#import "OWSBackup.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "PushManager.h"
#import "RegistrationViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "SignalsNavigationController.h"
#import "ViewControllerUtils.h"
#import <AxolotlKit/SessionCipher.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSContactsSyncing.h>
#import <SignalMessaging/OWSMath.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/Release.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSOrphanedDataCleaner.h>
#import <SignalServiceKit/OWSPrimaryStorage+Calling.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <sys/sysctl.h>

@import WebRTC;
@import Intents;

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

static NSTimeInterval launchStartedAt;

@interface AppDelegate ()

@property (nonatomic) BOOL hasInitialRootViewController;
@property (nonatomic) BOOL areVersionMigrationsComplete;
@property (nonatomic) BOOL didAppLaunchFail;
@property (nonatomic) BOOL hasReceivedLocalNotification;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

- (void)applicationDidEnterBackground:(UIApplication *)application {
    DDLogWarn(@"%@ applicationDidEnterBackground.", self.logTag);

    [DDLog flushLog];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    DDLogWarn(@"%@ applicationWillEnterForeground.", self.logTag);
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    DDLogWarn(@"%@ applicationDidReceiveMemoryWarning.", self.logTag);
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    DDLogWarn(@"%@ applicationWillTerminate.", self.logTag);

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

    DDLogWarn(@"%@ application: didFinishLaunchingWithOptions.", self.logTag);

    SetRandFunctionSeed();

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
        DDLogInfo(@"%@ application: didFinishLaunchingWithOptions failed.", self.logTag);

        return YES;
    }

    [AppVersion instance];

    [self startupLogging];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in storageIsReady.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    [AppSetup setupEnvironmentWithCallMessageHandlerBlock:^{
        return SignalApp.sharedApp.callMessageHandler;
    }
        notificationsProtocolBlock:^{
            return SignalApp.sharedApp.notificationsManager;
        }
        migrationCompletion:^{
            OWSAssertIsOnMainThread();

            [self versionMigrationsDidComplete];
        }];

    [UIUtil applySignalAppearence];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    UIWindow *mainWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    // Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }

    [OWSScreenLockUI.sharedManager setupWithRootWindow:self.window];
    [[OWSWindowManager sharedManager] setupWithRootWindow:self.window
                                     screenBlockingWindow:OWSScreenLockUI.sharedManager.screenBlockingWindow];
    [OWSScreenLockUI.sharedManager startObserving];

    // Ensure OWSContactsSyncing is instantiated.
    [OWSContactsSyncing sharedManager];

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

    DDLogInfo(@"%@ application: didFinishLaunchingWithOptions completed.", self.logTag);

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
        DDLogInfo(
            @"%@ exiting because we are in the background and the database password is not accessible.", self.logTag);
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
            DDLogInfo(@"%@ storage file: %@, %@", self.logTag, path, [OWSFileSystem fileSizeOfPath:path]);
        }
    }

    if ([OWSPreferences isReadyForAppExtensions]) {
        return YES;
    }

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    if ([NSFileManager.defaultManager fileExistsAtPath:OWSPrimaryStorage.legacyDatabaseFilePath]) {
        DDLogInfo(@"%@ Legacy Database file size: %@",
            self.logTag,
            [OWSFileSystem fileSizeOfPath:OWSPrimaryStorage.legacyDatabaseFilePath]);
        DDLogInfo(@"%@ \t Legacy SHM file size: %@",
            self.logTag,
            [OWSFileSystem fileSizeOfPath:OWSPrimaryStorage.legacyDatabaseFilePath_SHM]);
        DDLogInfo(@"%@ \t Legacy WAL file size: %@",
            self.logTag,
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
        error = [OWSProfileManager migrateToSharedData];
    }
    if (!error) {
        error = [TSAttachmentStream migrateToSharedData];
    }

    if (error) {
        OWSFail(@"%@ database conversion failed: %@", self.logTag, error);
        [self showLaunchFailureUI:error];
        return NO;
    }

    backgroundTask = nil;

    return YES;
}

- (void)showLaunchFailureUI:(NSError *)error
{
    // Disable normal functioning of app.
    self.didAppLaunchFail = YES;

    // We perform a subset of the [application:didFinishLaunchingWithOptions:].
    [AppVersion instance];
    [self startupLogging];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Show the launch screen
    self.window.rootViewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    [self.window makeKeyAndVisible];

    UIAlertController *controller =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_TITLE",
                                                        @"Title for the 'app launch failed' alert.")
                                            message:NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_MESSAGE",
                                                        @"Message for the 'app launch failed' alert.")
                                     preferredStyle:UIAlertControllerStyleAlert];

    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [Pastelog submitLogsWithCompletion:^{
                                                         DDLogInfo(
                                                             @"%@ exiting after sharing debug logs.", self.logTag);
                                                         [DDLog flushLog];
                                                         exit(0);
                                                     }];
                                                 }]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:controller animated:YES completion:nil];
}

- (nullable NSError *)convertDatabaseIfNecessary
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSString *databaseFilePath = [OWSPrimaryStorage legacyDatabaseFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]) {
        DDLogVerbose(@"%@ no legacy database file found", self.logTag);
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
        DDLogVerbose(@"%@ saltData: %@", self.logTag, saltData.hexadecimalString);

        // Derive and store the raw cipher key spec, to avoid the ongoing tax of future KDF
        NSData *_Nullable keySpecData =
            [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];

        if (!keySpecData) {
            DDLogError(@"%@ Failed to derive key spec.", self.logTag);
            return NO;
        }

        [OWSStorage storeDatabaseCipherKeySpec:keySpecData];

        return YES;
    };

    error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                              databasePassword:databasePassword
                                               recordSaltBlock:recordSaltBlock];
    if (!error) {
        [OWSStorage removeLegacyPassphrase];
    }

    return error;
}

- (void)startupLogging
{
    DDLogInfo(@"iOS Version: %@", [UIDevice currentDevice].systemVersion);

    NSString *localeIdentifier = [NSLocale.currentLocale objectForKey:NSLocaleIdentifier];
    if (localeIdentifier.length > 0) {
        DDLogInfo(@"Locale Identifier: %@", localeIdentifier);
    }
    NSString *countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
    if (countryCode.length > 0) {
        DDLogInfo(@"Country Code: %@", countryCode);
    }
    NSString *languageCode = [NSLocale.currentLocale objectForKey:NSLocaleLanguageCode];
    if (languageCode.length > 0) {
        DDLogInfo(@"Language Code: %@", languageCode);
    }

    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);

    DDLogInfo(@"iPhone Version: %@", platform);
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    DDLogInfo(@"%@ registered vanilla push token: %@", self.logTag, deviceToken);
    [PushRegistrationManager.sharedManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    DDLogError(@"%@ failed to register vanilla push token with error: %@", self.logTag, error);
#ifdef DEBUG
    DDLogWarn(
        @"%@ We're in debug mode. Faking success for remote registration with a fake push identifier", self.logTag);
    [PushRegistrationManager.sharedManager didReceiveVanillaPushToken:[[NSMutableData dataWithLength:32] copy]];
#else
    OWSProdError([OWSAnalyticsEvents appDelegateErrorFailedToRegisterForRemoteNotifications]);
    [PushRegistrationManager.sharedManager didFailToReceiveVanillaPushTokenWithError:error];
#endif
}

- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    DDLogInfo(@"%@ registered user notification settings", self.logTag);
    [PushRegistrationManager.sharedManager didRegisterUserNotificationSettings];
}

- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)url
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return NO;
    }

    if (!AppReadiness.isAppReady) {
        DDLogWarn(@"%@ Ignoring openURL: app not ready.", self.logTag);
        // We don't need to use [AppReadiness runNowOrWhenAppIsReady:];
        // the only URLs we handle in Signal iOS at the moment are used
        // for resuming the verification step of the registration flow.
        return NO;
    }

    if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![TSAccountManager isRegistered]) {
            id signupController = SignalApp.sharedApp.signUpFlowNavigationController;
            if ([signupController isKindOfClass:[OWSNavigationController class]]) {
                OWSNavigationController *navController = (OWSNavigationController *)signupController;
                UIViewController *controller = [navController.childViewControllers lastObject];
                if ([controller isKindOfClass:[CodeVerificationViewController class]]) {
                    CodeVerificationViewController *cvvc = (CodeVerificationViewController *)controller;
                    NSString *verificationCode           = [url.path substringFromIndex:1];
                    [cvvc setVerificationCodeAndTryToVerify:verificationCode];
                    return YES;
                } else {
                    DDLogWarn(@"Not the verification view controller we expected. Got %@ instead",
                              NSStringFromClass(controller.class));
                }
            }
        } else {
            OWSFail(@"Application opened with an unknown URL action: %@", url.host);
        }
    } else {
        OWSFail(@"Application opened with an unknown URL scheme: %@", url.scheme);
    }
    return NO;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    DDLogWarn(@"%@ applicationDidBecomeActive.", self.logTag);
    if (CurrentAppContext().isRunningTests) {
        return;
    }

    [self ensureRootViewController];

    [AppReadiness runNowOrWhenAppIsReady:^{
        [self handleActivation];
    }];

    // We want to process up to one local notification per activation, so clear the flag.
    self.hasReceivedLocalNotification = NO;

    // Clear all notifications whenever we become active.
    // When opening the app from a notification,
    // AppDelegate.didReceiveLocalNotification will always
    // be called _before_ we become active.
    [self clearAllNotificationsAndRestoreBadgeCount];

    DDLogInfo(@"%@ applicationDidBecomeActive completed.", self.logTag);
}

- (void)enableBackgroundRefreshIfNecessary
{
    [AppReadiness runNowOrWhenAppIsReady:^{
        if (OWS2FAManager.sharedManager.is2FAEnabled && [TSAccountManager isRegistered]) {
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

    DDLogWarn(@"%@ handleActivation.", self.logTag);

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RTCInitializeSSL();

        if ([TSAccountManager isRegistered]) {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDLogInfo(@"%@ running post launch block for registered user: %@",
                    self.logTag,
                    [TSAccountManager localNumber]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [[OWSDisappearingMessagesJob sharedJob] startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

                // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
                // sent before the app exited should be marked as failures.
                [[[OWSFailedMessagesJob alloc] initWithPrimaryStorage:[OWSPrimaryStorage sharedManager]] run];
                [[[OWSFailedAttachmentDownloadsJob alloc] initWithPrimaryStorage:[OWSPrimaryStorage sharedManager]]
                    run];

                [AppStoreRating setupRatingLibrary];
            });
        } else {
            DDLogInfo(@"%@ running post launch block for unregistered user.", self.logTag);

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [SignalApp clearAllNotifications];

            [TSSocketManager requestSocketOpen];

            UITapGestureRecognizer *gesture =
                [[UITapGestureRecognizer alloc] initWithTarget:[Pastelog class] action:@selector(submitLogs)];
            gesture.numberOfTapsRequired = 8;
            [self.window addGestureRecognizer:gesture];
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([TSAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            [TSSocketManager requestSocketOpen];
            [[Environment current].contactsManager fetchSystemContactsOnceIfAlreadyAuthorized];
            // This will fetch new messages, if we're using domain fronting.
            [[PushManager sharedManager] applicationDidBecomeActive];

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                DDLogInfo(
                    @"%@ Retrying to register for remote notifications since user hasn't registered yet.", self.logTag);
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                __unused AnyPromise *promise =
                    [OWSSyncPushTokensJob runWithAccountManager:SignalApp.sharedApp.accountManager
                                                    preferences:[Environment preferences]];
            }

            if ([OWS2FAManager sharedManager].isDueForReminder) {
                if (!self.hasInitialRootViewController || self.window.rootViewController == nil) {
                    DDLogDebug(
                        @"%@ Skipping 2FA reminder since there isn't yet an initial view controller", self.logTag);
                } else {
                    UIViewController *rootViewController = self.window.rootViewController;
                    OWSNavigationController *reminderNavController =
                        [OWS2FAReminderViewController wrappedInNavController];

                    [rootViewController presentViewController:reminderNavController animated:YES completion:nil];
                }
            }
        });
    }

    DDLogInfo(@"%@ handleActivation completed.", self.logTag);
}

- (void)applicationWillResignActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    DDLogWarn(@"%@ applicationWillResignActive.", self.logTag);

    [DDLog flushLog];
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    [SignalApp clearAllNotifications];
    [AppReadiness runNowOrWhenAppIsReady:^{
        [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
    }];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    [AppReadiness runNowOrWhenAppIsReady:^{
        if (![TSAccountManager isRegistered]) {
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
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return NO;
    }

    if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"]) {
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            DDLogError(@"%@ unexpectedly received INStartVideoCallIntent pre iOS10", self.logTag);
            return NO;
        }

        DDLogInfo(@"%@ got start video call intent", self.logTag);

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartVideoCallIntent class]]) {
            DDLogError(@"%@ unexpected class for start call video: %@", self.logTag, intent);
            return NO;
        }
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            DDLogWarn(@"%@ unable to find handle in startCallIntent: %@", self.logTag, startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppIsReady:^{
            NSString *_Nullable phoneNumber = handle;
            if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
                phoneNumber = [[OWSPrimaryStorage sharedManager] phoneNumberForCallKitId:handle];
                if (phoneNumber.length < 1) {
                    DDLogWarn(
                        @"%@ ignoring attempt to initiate video call to unknown anonymous signal user.", self.logTag);
                    return;
                }
            }

            // This intent can be received from more than one user interaction.
            //
            // * It can be received if the user taps the "video" button in the CallKit UI for an
            //   an ongoing call.  If so, the correct response is to try to activate the local
            //   video for that call.
            // * It can be received if the user taps the "video" button for a contact in the
            //   contacts app.  If so, the correct response is to try to initiate a new call
            //   to that user - unless there already is another call in progress.
            if (SignalApp.sharedApp.callService.call != nil) {
                if ([phoneNumber isEqualToString:SignalApp.sharedApp.callService.call.remotePhoneNumber]) {
                    DDLogWarn(@"%@ trying to upgrade ongoing call to video.", self.logTag);
                    [SignalApp.sharedApp.callService handleCallKitStartVideo];
                    return;
                } else {
                    DDLogWarn(@"%@ ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.",
                        self.logTag);
                    return;
                }
            }

            OutboundCallInitiator *outboundCallInitiator = SignalApp.sharedApp.outboundCallInitiator;
            OWSAssert(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithHandle:phoneNumber];
        }];
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {

        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            DDLogError(@"%@ unexpectedly received INStartAudioCallIntent pre iOS10", self.logTag);
            return NO;
        }

        DDLogInfo(@"%@ got start audio call intent", self.logTag);

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartAudioCallIntent class]]) {
            DDLogError(@"%@ unexpected class for start call audio: %@", self.logTag, intent);
            return NO;
        }
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            DDLogWarn(@"%@ unable to find handle in startCallIntent: %@", self.logTag, startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppIsReady:^{
            NSString *_Nullable phoneNumber = handle;
            if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
                phoneNumber = [[OWSPrimaryStorage sharedManager] phoneNumberForCallKitId:handle];
                if (phoneNumber.length < 1) {
                    DDLogWarn(
                        @"%@ ignoring attempt to initiate audio call to unknown anonymous signal user.", self.logTag);
                    return;
                }
            }

            if (SignalApp.sharedApp.callService.call != nil) {
                DDLogWarn(@"%@ ignoring INStartAudioCallIntent due to ongoing WebRTC call.", self.logTag);
                return;
            }

            OutboundCallInitiator *outboundCallInitiator = SignalApp.sharedApp.outboundCallInitiator;
            OWSAssert(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithHandle:phoneNumber];
        }];
        return YES;
    } else {
        DDLogWarn(@"%@ called %s with userActivity: %@, but not yet supported.",
            self.logTag,
            __PRETTY_FUNCTION__,
            userActivity.activityType);
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

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    // It is safe to continue even if the app isn't ready.
    [[PushManager sharedManager] application:application didReceiveRemoteNotification:userInfo];
}

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    // It is safe to continue even if the app isn't ready.
    [[PushManager sharedManager] application:application
                didReceiveRemoteNotification:userInfo
                      fetchCompletionHandler:completionHandler];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    // Don't process more than one local notification per activation.
    if (self.hasReceivedLocalNotification) {
        OWSFail(@"%@ %s ignoring redundant local notification.", self.logTag, __PRETTY_FUNCTION__);
        return;
    }
    self.hasReceivedLocalNotification = YES;

    DDLogInfo(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, notification);

    [AppStoreRating preventPromptAtNextTest];
    [AppReadiness runNowOrWhenAppIsReady:^{
        [[PushManager sharedManager] application:application didReceiveLocalNotification:notification];
    }];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)(void))completionHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    // The docs for handleActionWithIdentifier:... state:
    // "You must call [completionHandler] at the end of your method.".
    // Nonetheless, it is presumably safe to call the completion handler
    // later, after this method returns.
    //
    // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623068-application?language=objc
    [AppReadiness runNowOrWhenAppIsReady:^{
        [[PushManager sharedManager] application:application
                      handleActionWithIdentifier:identifier
                            forLocalNotification:notification
                               completionHandler:completionHandler];
    }];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)(void))completionHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFail(@"%@ %s app launch failed", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    // Don't process more than one local notification per activation.
    if (self.hasReceivedLocalNotification) {
        OWSFail(@"%@ %s ignoring redundant local notification.", self.logTag, __PRETTY_FUNCTION__);
        return;
    }
    self.hasReceivedLocalNotification = YES;

    // The docs for handleActionWithIdentifier:... state:
    // "You must call [completionHandler] at the end of your method.".
    // Nonetheless, it is presumably safe to call the completion handler
    // later, after this method returns.
    //
    // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623068-application?language=objc
    [AppReadiness runNowOrWhenAppIsReady:^{
        [[PushManager sharedManager] application:application
                      handleActionWithIdentifier:identifier
                            forLocalNotification:notification
                                withResponseInfo:responseInfo
                               completionHandler:completionHandler];
    }];
}

- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    DDLogInfo(@"%@ performing background fetch", self.logTag);
    [AppReadiness runNowOrWhenAppIsReady:^{
        __block AnyPromise *job = [[SignalApp sharedApp].messageFetcherJob run].then(^{
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
    }];
}

- (void)versionMigrationsDidComplete
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ versionMigrationsDidComplete", self.logTag);

    self.areVersionMigrationsComplete = YES;

    [self checkIfAppIsReady];
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();
    DDLogInfo(@"%@ storageIsReady", self.logTag);

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

    DDLogInfo(@"%@ checkIfAppIsReady", self.logTag);

    // TODO: Once "app ready" logic is moved into AppSetup, move this line there.
    [[OWSProfileManager sharedManager] ensureLocalProfileCached];
    
    // Note that this does much more than set a flag;
    // it will also run all deferred blocks.
    [AppReadiness setAppIsReady];

    if ([TSAccountManager isRegistered]) {
        DDLogInfo(@"localNumber: %@", [TSAccountManager localNumber]);

        // Fetch messages as soon as possible after launching. In particular, when
        // launching from the background, without this, we end up waiting some extra
        // seconds before receiving an actionable push notification.
        __unused AnyPromise *messagePromise = [SignalApp.sharedApp.messageFetcherJob run];

        // This should happen at any launch, background or foreground.
        __unused AnyPromise *pushTokenpromise =
            [OWSSyncPushTokensJob runWithAccountManager:SignalApp.sharedApp.accountManager
                                            preferences:[Environment preferences]];
    }

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];

    [AppVersion.instance mainAppLaunchDidComplete];

    [Environment.current.contactsManager loadSignalAccountsFromCache];
    [Environment.current.contactsManager startObserving];

    // If there were any messages in our local queue which we hadn't yet processed.
    [[OWSMessageReceiver sharedInstance] handleAnyUnprocessedEnvelopesAsync];
    [[OWSBatchMessageProcessor sharedInstance] handleAnyUnprocessedEnvelopesAsync];

    if (!Environment.preferences.hasGeneratedThumbnails) {
        [OWSPrimaryStorage.sharedManager.newDatabaseConnection
            asyncReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
                [TSAttachmentStream enumerateCollectionObjectsUsingBlock:^(id _Nonnull obj, BOOL *_Nonnull stop){
                    // no-op. It's sufficient to initWithCoder: each object.
                }];
            }
            completionBlock:^{
                [Environment.preferences setHasGeneratedThumbnails:YES];
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
    [OWSOrphanedDataCleaner auditAndCleanupAsync:nil];
#endif

    [OWSProfileManager.sharedManager fetchLocalUsersProfile];
    [[OWSReadReceiptManager sharedManager] prepareCachedValues];

    // Disable the SAE until the main app has successfully completed launch process
    // at least once in the post-SAE world.
    [OWSPreferences setIsReadyForAppExtensions];

    [self ensureRootViewController];

    [OWSBackup.sharedManager setup];

#ifdef DEBUG
    // Resume lazy restore.
    [OWSBackupLazyRestoreJob runAsync];
#endif

}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"registrationStateDidChange");

    [self enableBackgroundRefreshIfNecessary];

    if ([TSAccountManager isRegistered]) {
        DDLogInfo(@"%@ localNumber: %@", [TSAccountManager localNumber], self.logTag);

        [[OWSPrimaryStorage sharedManager].newDatabaseConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [ExperienceUpgradeFinder.sharedManager markAllAsSeenWithTransaction:transaction];
            }];
        // Start running the disappearing messages job in case the newly registered user
        // enables this feature
        [[OWSDisappearingMessagesJob sharedJob] startIfNecessary];
        [[OWSProfileManager sharedManager] ensureLocalProfileCached];

        // For non-legacy users, read receipts are on by default.
        [OWSReadReceiptManager.sharedManager setAreReadReceiptsEnabled:YES];
    }
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
}

- (void)ensureRootViewController
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ ensureRootViewController", self.logTag);

    if (!AppReadiness.isAppReady || self.hasInitialRootViewController) {
        return;
    }
    self.hasInitialRootViewController = YES;

    NSTimeInterval startupDuration = CACurrentMediaTime() - launchStartedAt;
    DDLogInfo(@"%@ Presenting app %.2f seconds after launch started.", self.logTag, startupDuration);

    if ([TSAccountManager isRegistered]) {
        HomeViewController *homeView = [HomeViewController new];
        SignalsNavigationController *navigationController =
            [[SignalsNavigationController alloc] initWithRootViewController:homeView];
        self.window.rootViewController = navigationController;
    } else {
        RegistrationViewController *viewController = [RegistrationViewController new];
        OWSNavigationController *navigationController =
            [[OWSNavigationController alloc] initWithRootViewController:viewController];
        navigationController.navigationBarHidden = YES;
        self.window.rootViewController = navigationController;
    }

    [AppUpdateNag.sharedInstance showAppUpgradeNagIfNecessary];
}

@end
