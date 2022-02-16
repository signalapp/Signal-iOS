//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "MainAppContext.h"
#import "OWSBackup.h"
#import "OWSOrphanDataCleaner.h"
#import "OWSScreenLockUI.h"
#import "Session-Swift.h"
#import "SignalApp.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalUtilitiesKit/AppSetup.h>
#import <SessionMessagingKit/Environment.h>
#import <SignalUtilitiesKit/OWSNavigationController.h>
#import <SessionMessagingKit/OWSPreferences.h>
#import <SignalUtilitiesKit/OWSProfileManager.h>
#import <SignalUtilitiesKit/VersionMigrations.h>
#import <SessionMessagingKit/AppReadiness.h>
#import <SessionUtilitiesKit/NSUserDefaults+OWS.h>
#import <SessionMessagingKit/OWSDisappearingMessagesJob.h>
#import <SignalUtilitiesKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalUtilitiesKit/OWSFailedMessagesJob.h>
#import <SessionUtilitiesKit/OWSMath.h>
#import <SessionMessagingKit/OWSReadReceiptManager.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionMessagingKit/TSDatabaseView.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <sys/utsname.h>

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

    // OWSLinkPreview is now in SessionMessagingKit, so to still be able to deserialize them we
    // need to tell NSKeyedUnarchiver about the changes.
    [NSKeyedUnarchiver setClass:OWSLinkPreview.class forClassName:@"SessionServiceKit.OWSLinkPreview"];

    [Cryptography seedRandom];

    // XXX - careful when moving this. It must happen before we initialize OWSPrimaryStorage.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    [AppVersion sharedInstance];

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

    [SNAppearance switchToSessionAppearance];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    UIWindow *mainWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    LKAppMode appMode = [LKAppModeManager getAppModeOrSystemDefault];
    [self adaptAppMode:appMode];

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

    // Loki - Observe data nuke request notifications
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleDataNukeRequested:) name:NSNotification.dataNukeRequested object:nil];
    
    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

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

    LKAppMode appMode = [LKAppModeManager getAppModeOrSystemDefault];
    [self adaptAppMode:appMode];

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

- (void)enableBackgroundRefreshIfNecessary
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [UIApplication.sharedApplication setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    }];
}

- (void)handleActivation
{
    OWSAssertIsOnMainThread();

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
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
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([self.tsAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *userPublicKey = self.tsAccountManager.localNumber;

            // Update profile picture if needed
            NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
            NSDate *now = [NSDate new];
            NSDate *lastProfilePictureUpload = (NSDate *)[userDefaults objectForKey:@"lastProfilePictureUpload"];
            if (lastProfilePictureUpload != nil && [now timeIntervalSinceDate:lastProfilePictureUpload] > 14 * 24 * 60 * 60) {
                OWSProfileManager *profileManager = OWSProfileManager.sharedManager;
                NSString *name = [[LKStorage.shared getUser] name];
                UIImage *profilePicture = [profileManager profileAvatarForRecipientId:userPublicKey];
                [profileManager updateLocalProfileName:name avatarImage:profilePicture success:^{
                    // Do nothing; the user defaults flag is updated in LokiFileServerAPI
                } failure:^(NSError *error) {
                    // Do nothing
                } requiresSync:YES];
            }
            
            if (CurrentAppContext().isMainApp) {
                [SNOpenGroupAPIV2 getDefaultRoomsIfNeeded];
            }
            
            [[SNSnodeAPI getSnodePool] retainUntilComplete];
            
            [self startPollerIfNeeded];
            [self startClosedGroupPoller];
            [self startOpenGroupPollersIfNeeded];

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
            
            if (CurrentAppContext().isMainApp) {
                [SNJobQueue.shared resumePendingJobs];
                [self syncConfigurationIfNeeded];
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
    
    [SNConfiguration performMainSetup];

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
    
    [self.readReceiptManager prepareCachedValues];

    // Disable the SAE until the main app has successfully completed launch process
    // at least once in the post-SAE world.
    [OWSPreferences setIsReadyForAppExtensions];

    [self ensureRootViewController];

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

        [self startPollerIfNeeded];
        [self startClosedGroupPoller];
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
        __unused AnyPromise *promise = [LKPushNotificationAPI registerWithToken:deviceToken hexEncodedPublicKey:self.tsAccountManager.localNumber isForcedUpdate:NO];
    } else {
        __unused AnyPromise *promise = [LKPushNotificationAPI unregisterToken:deviceToken];
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
    [self.pushRegistrationManager didFailToReceiveVanillaPushTokenWithError:error];
#endif
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
        [SignalApp.sharedApp.homeViewController createNewDM];
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
        NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
        if (userPublicKey != nil) {
            self.poller = [[LKPoller alloc] init];
        }
    }
    [self.poller startIfNeeded];
}

- (void)stopPoller { [self.poller stop]; }

- (void)startOpenGroupPollersIfNeeded
{
    [SNOpenGroupManagerV2.shared startPolling];
}

- (void)stopOpenGroupPollers {
    [SNOpenGroupManagerV2.shared stopPolling];
}

# pragma mark - App Mode

- (void)adaptAppMode:(LKAppMode)appMode
{
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window == nil) { return; }
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
    if (LKAppModeUtilities.isSystemDefault) {
        if (@available(iOS 13.0, *)) {
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        }
    }
    [NSNotificationCenter.defaultCenter postNotificationName:NSNotification.appModeChanged object:nil];
}

- (void)setCurrentAppMode:(LKAppMode)appMode
{
    [NSUserDefaults.standardUserDefaults setInteger:appMode forKey:@"appMode"];
    [self adaptAppMode:appMode];
}

- (void)setAppModeToSystemDefault
{
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"appMode"];
    LKAppMode appMode = [LKAppModeManager getAppModeOrSystemDefault];
    [self adaptAppMode:appMode];
}

# pragma mark - Other

- (void)handleDataNukeRequested:(NSNotification *)notification
{
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    BOOL isUsingFullAPNs = [userDefaults boolForKey:@"isUsingFullAPNs"];
    NSString *hexEncodedDeviceToken = [userDefaults stringForKey:@"deviceToken"];
    if (isUsingFullAPNs && hexEncodedDeviceToken != nil) {
        NSData *deviceToken = [NSData dataFromHexString:hexEncodedDeviceToken];
        [[LKPushNotificationAPI unregisterToken:deviceToken] retainUntilComplete];
    }
    [ThreadUtil deleteAllContent];
    [SSKEnvironment.shared.identityManager clearIdentityKey];
    [SNSnodeAPI clearSnodePool];
    [self stopPoller];
    [self stopClosedGroupPoller];
    [self stopOpenGroupPollers];
    BOOL wasUnlinked = [NSUserDefaults.standardUserDefaults boolForKey:@"wasUnlinked"];
    [SignalApp resetAppData:^{
        // Resetting the data clears the old user defaults. We need to restore the unlink default.
        [NSUserDefaults.standardUserDefaults setBool:wasUnlinked forKey:@"wasUnlinked"];
    }];
}

# pragma mark - App Link

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:true];
    
    // URL Scheme is sessionmessenger://DM?sessionID=1234
    // We can later add more parameters like message etc.
    NSString *intent = components.host;
    if (intent != nil && [intent isEqualToString:@"DM"]) {
        NSArray<NSURLQueryItem*> *params = [components queryItems];
        NSPredicate *sessionIDPredicate = [NSPredicate predicateWithFormat:@"name == %@", @"sessionID"];
        NSArray<NSURLQueryItem*> *matches = [params filteredArrayUsingPredicate:sessionIDPredicate];
        if (matches.count > 0) {
            NSString *sessionID = matches.firstObject.value;
            [self createNewDMFromDeepLink:sessionID];
            return YES;
        }
    }
    return NO;
}

- (void)createNewDMFromDeepLink:(NSString *)sessionID
{
    UIViewController *viewController = self.window.rootViewController;
    if ([viewController class] == [OWSNavigationController class]) {
        UIViewController *visibleVC = ((OWSNavigationController *)viewController).visibleViewController;
        if ([visibleVC isKindOfClass:HomeVC.class]) {
            HomeVC *homeVC = (HomeVC *)visibleVC;
            [homeVC createNewDMFromDeepLink:sessionID];
        }
    }
}

@end
