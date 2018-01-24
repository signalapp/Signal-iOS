//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "AppStoreRating.h"
#import "AppUpdateNag.h"
#import "CodeVerificationViewController.h"
#import "DebugLogger.h"
#import "MainAppContext.h"
#import "NotificationsManager.h"
#import "OWSBackup.h"
#import "OWSNavigationController.h"
#import "Pastelog.h"
#import "PushManager.h"
#import "RegistrationViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "SignalsNavigationController.h"
#import "ViewControllerUtils.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSContactsSyncing.h>
#import <SignalMessaging/OWSMath.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/Release.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSOrphanedDataCleaner.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <SignalServiceKit/TSStorageManager+Calling.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>

@import WebRTC;
@import Intents;

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

@interface AppDelegate ()

@property (nonatomic) UIWindow *screenProtectionWindow;
@property (nonatomic) BOOL hasInitialRootViewController;

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

    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
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

    // XXX - careful when moving this. It must happen before we initialize TSStorageManager.
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
    [self ensureIsReadyForAppExtensions];

    [AppVersion instance];

    [self startupLogging];


    // If a backup restore is in progress, try to complete it.
    // Otherwise, cleanup backup state.
    [OWSBackup applicationDidFinishLaunching];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in storageIsReady.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    [AppSetup setupEnvironment:^{
        return SignalApp.sharedApp.callMessageHandler;
    }
        notificationsProtocolBlock:^{
            return SignalApp.sharedApp.notificationsManager;
        }];

    [UIUtil applySignalAppearence];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Show the launch screen until the async database view registrations are complete.
    self.window.rootViewController = [self loadingRootViewController];

    [self.window makeKeyAndVisible];

    // performUpdateCheck must be invoked after Environment has been initialized because
    // upgrade process may depend on Environment.
    [VersionMigrations performUpdateCheck];

    // Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }

    [self prepareScreenProtection];

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

    if (![TSStorageManager isDatabasePasswordAccessible]) {
        DDLogInfo(
            @"%@ exiting because we are in the background and the database password is not accessible.", self.logTag);
        [DDLog flushLog];
        exit(0);
    }
}

- (void)ensureIsReadyForAppExtensions
{
    if ([OWSPreferences isReadyForAppExtensions]) {
        return;
    }

    NSError *_Nullable error = [self convertDatabaseIfNecessary];
    // TODO: Handle this error.
    OWSAssert(!error);

    [NSUserDefaults migrateToSharedUserDefaults];

    [TSStorageManager migrateToSharedData];
    [OWSProfileManager migrateToSharedData];
    [TSAttachmentStream migrateToSharedData];
}

- (nullable NSError *)convertDatabaseIfNecessary
{
    NSString *databaseFilePath = [TSStorageManager legacyDatabaseFilePath];

    NSError *error;
    NSData *_Nullable databasePassword = [OWSStorage tryToLoadDatabasePassword:&error];
    if (!databasePassword || error) {
        return (error
                ?: OWSErrorWithCodeDescription(
                       OWSErrorCodeDatabaseConversionFatalError, @"Failed to load database password"));
    }

    YapDatabaseSaltBlock saltBlock = ^(NSData *saltData) {
        DDLogVerbose(@"%@ saltData: %@", self.logTag, saltData.hexadecimalString);
        [OWSStorage storeDatabaseSalt:saltData];
    };
    YapDatabaseKeySpecBlock keySpecBlock = ^(NSData *keySpecData) {
        DDLogVerbose(@"%@ keySpecData: %@", self.logTag, keySpecData.hexadecimalString);
        [OWSStorage storeDatabaseKeySpec:keySpecData];
    };

    return [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                             databasePassword:databasePassword
                                                    saltBlock:saltBlock
                                                 keySpecBlock:keySpecBlock];
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
}

- (UIViewController *)loadingRootViewController
{
    UIViewController *viewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    NSString *lastLaunchedAppVersion = AppVersion.instance.lastAppVersion;
    NSString *lastCompletedLaunchAppVersion = AppVersion.instance.lastCompletedLaunchAppVersion;
    // Every time we change or add a database view in such a way that
    // might cause a delay on launch, we need to bump this constant.
    //
    // We upgraded YapDatabase in v2.20.0 and need to regenerate all database views.
    NSString *kLastVersionWithDatabaseViewChange = @"2.20.0";
    BOOL mayNeedUpgrade = ([TSAccountManager isRegistered] && lastLaunchedAppVersion
        && (!lastCompletedLaunchAppVersion ||
               [VersionMigrations isVersion:lastCompletedLaunchAppVersion
                                   lessThan:kLastVersionWithDatabaseViewChange]));
    DDLogInfo(@"%@ mayNeedUpgrade: %d", self.logTag, mayNeedUpgrade);
    if (mayNeedUpgrade) {
        UIView *rootView = viewController.view;
        UIImageView *iconView = nil;
        for (UIView *subview in viewController.view.subviews) {
            if ([subview isKindOfClass:[UIImageView class]]) {
                iconView = (UIImageView *)subview;
                break;
            }
        }
        if (!iconView) {
            OWSFail(@"Database view registration overlay has unexpected contents.");
        } else {
            UILabel *bottomLabel = [UILabel new];
            bottomLabel.text = NSLocalizedString(
                @"DATABASE_VIEW_OVERLAY_SUBTITLE", @"Subtitle shown while the app is updating its database.");
            bottomLabel.font = [UIFont ows_mediumFontWithSize:16.f];
            bottomLabel.textColor = [UIColor whiteColor];
            bottomLabel.numberOfLines = 0;
            bottomLabel.lineBreakMode = NSLineBreakByWordWrapping;
            bottomLabel.textAlignment = NSTextAlignmentCenter;
            [rootView addSubview:bottomLabel];

            UILabel *topLabel = [UILabel new];
            topLabel.text = NSLocalizedString(
                @"DATABASE_VIEW_OVERLAY_TITLE", @"Title shown while the app is updating its database.");
            topLabel.font = [UIFont ows_mediumFontWithSize:20.f];
            topLabel.textColor = [UIColor whiteColor];
            topLabel.numberOfLines = 0;
            topLabel.lineBreakMode = NSLineBreakByWordWrapping;
            topLabel.textAlignment = NSTextAlignmentCenter;
            [rootView addSubview:topLabel];

            [bottomLabel autoPinWidthToSuperviewWithMargin:20.f];
            [topLabel autoPinWidthToSuperviewWithMargin:20.f];
            [bottomLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topLabel withOffset:10.f];
            [iconView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:bottomLabel withOffset:40.f];
        }
    }

    return viewController;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    DDLogInfo(@"%@ registered vanilla push token: %@", self.logTag, deviceToken);
    [PushRegistrationManager.sharedManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
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
    DDLogInfo(@"%@ registered user notification settings", self.logTag);
    [PushRegistrationManager.sharedManager didRegisterUserNotificationSettings];
}

- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)url
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
    if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![TSAccountManager isRegistered]) {
            id signupController = SignalApp.sharedApp.signUpFlowNavigationController;
            if ([signupController isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navController = (UINavigationController *)signupController;
                UIViewController *controller          = [navController.childViewControllers lastObject];
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
    DDLogWarn(@"%@ applicationDidBecomeActive.", self.logTag);

    if (CurrentAppContext().isRunningTests) {
        return;
    }
    
    [self removeScreenProtection];

    [self ensureRootViewController];

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

                // TODO remove this once we're sure our app boot process is coherent.
                // Currently this happens *before* db registration is complete when
                // launching the app directly, but *after* db registration is complete when
                // the app is launched in the background, e.g. from a voip notification.
                [[OWSProfileManager sharedManager] ensureLocalProfileCached];

                // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
                // sent before the app exited should be marked as failures.
                [[[OWSFailedMessagesJob alloc] initWithStorageManager:[TSStorageManager sharedManager]] run];
                [[[OWSFailedAttachmentDownloadsJob alloc] initWithStorageManager:[TSStorageManager sharedManager]] run];

                [AppStoreRating setupRatingLibrary];
            });
        } else {
            DDLogInfo(@"%@ running post launch block for unregistered user.", self.logTag);

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

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
        });
        
    }

    DDLogInfo(@"%@ applicationDidBecomeActive completed.", self.logTag);
}

- (void)applicationWillResignActive:(UIApplication *)application {
    DDLogWarn(@"%@ applicationWillResignActive.", self.logTag);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if ([TSAccountManager isRegistered]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
                    // If app has not re-entered active, show screen protection if necessary.
                    [self showScreenProtection];
                }
                [SignalApp.sharedApp.homeViewController updateInboxCountLabel];

                backgroundTask = nil;
            });
        } else {
            backgroundTask = nil;
        }
    });

    [DDLog flushLog];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    if ([TSAccountManager isRegistered]) {
        [SignalApp.sharedApp.homeViewController showNewConversationView];
        completionHandler(YES);
    } else {
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
    }
}

/**
 * Among other things, this is used by "call back" callkit dialog and calling from native contacts app.
 */
- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray * _Nullable))restorationHandler
{
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

        NSString *_Nullable phoneNumber = handle;
        if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
            phoneNumber = [[TSStorageManager sharedManager] phoneNumberForCallKitId:handle];
            if (phoneNumber.length < 1) {
                DDLogWarn(@"%@ ignoring attempt to initiate video call to unknown anonymous signal user.", self.logTag);
                return NO;
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
                return YES;
            } else {
                DDLogWarn(
                    @"%@ ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.", self.logTag);
                return NO;
            }
        }

        OutboundCallInitiator *outboundCallInitiator = SignalApp.sharedApp.outboundCallInitiator;
        OWSAssert(outboundCallInitiator);
        return [outboundCallInitiator initiateCallWithHandle:phoneNumber];
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

        NSString *_Nullable phoneNumber = handle;
        if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
            phoneNumber = [[TSStorageManager sharedManager] phoneNumberForCallKitId:handle];
            if (phoneNumber.length < 1) {
                DDLogWarn(@"%@ ignoring attempt to initiate audio call to unknown anonymous signal user.", self.logTag);
                return NO;
            }
        }

        if (SignalApp.sharedApp.callService.call != nil) {
            DDLogWarn(@"%@ ignoring INStartAudioCallIntent due to ongoing WebRTC call.", self.logTag);
            return NO;
        }

        OutboundCallInitiator *outboundCallInitiator = SignalApp.sharedApp.outboundCallInitiator;
        OWSAssert(outboundCallInitiator);
        return [outboundCallInitiator initiateCallWithHandle:phoneNumber];
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


/**
 * Screen protection obscures the app screen shown in the app switcher.
 */
- (void)prepareScreenProtection
{
    UIWindow *window = [[UIWindow alloc] initWithFrame:self.window.bounds];
    window.hidden = YES;
    window.opaque = YES;
    window.userInteractionEnabled = NO;
    window.windowLevel = CGFLOAT_MAX;
    window.backgroundColor = UIColor.ows_materialBlueColor;
    window.rootViewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    self.screenProtectionWindow = window;
}

- (void)showScreenProtection
{
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.screenProtectionWindow.hidden = NO;
    }
}

- (void)removeScreenProtection {
    self.screenProtectionWindow.hidden = YES;
}

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    [[PushManager sharedManager] application:application didReceiveRemoteNotification:userInfo];
}

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [[PushManager sharedManager] application:application
                didReceiveRemoteNotification:userInfo
                      fetchCompletionHandler:completionHandler];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    OWSAssertIsOnMainThread();

    if (!self.isEnvironmentSetup) {
        OWSFail(@"%@ ignoring %s because environment is not yet set up: %@.",
            self.logTag,
            __PRETTY_FUNCTION__,
            notification);
        return;
    }
    DDLogInfo(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, notification);

    [AppStoreRating preventPromptAtNextTest];
    [[PushManager sharedManager] application:application didReceiveLocalNotification:notification];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)())completionHandler
{
    if (!self.isEnvironmentSetup) {
        OWSFail(@"%@ ignoring %s because environment is not yet set up.", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    [[PushManager sharedManager] application:application
                  handleActionWithIdentifier:identifier
                        forLocalNotification:notification
                           completionHandler:completionHandler];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)())completionHandler
{
    if (!self.isEnvironmentSetup) {
        OWSFail(@"%@ ignoring %s because environment is not yet set up.", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    [[PushManager sharedManager] application:application
                  handleActionWithIdentifier:identifier
                        forLocalNotification:notification
                            withResponseInfo:responseInfo
                           completionHandler:completionHandler];
}

- (void)storageIsReady
{
    DDLogInfo(@"%@ storageIsReady", self.logTag);

    [OWSPreferences setIsRegistered:[TSAccountManager isRegistered]];

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

    [AppVersion.instance appLaunchDidComplete];

    [Environment.current.contactsManager loadSignalAccountsFromCache];

    // If there were any messages in our local queue which we hadn't yet processed.
    [[OWSMessageReceiver sharedInstance] handleAnyUnprocessedEnvelopesAsync];
    [[OWSBatchMessageProcessor sharedInstance] handleAnyUnprocessedEnvelopesAsync];

    [[OWSProfileManager sharedManager] ensureLocalProfileCached];

    self.isEnvironmentSetup = YES;

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
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"registrationStateDidChange");

    [OWSPreferences setIsRegistered:[TSAccountManager isRegistered]];

    if ([TSAccountManager isRegistered]) {
        DDLogInfo(@"localNumber: %@", [TSAccountManager localNumber]);

        [[TSStorageManager sharedManager].newDatabaseConnection
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

- (void)ensureRootViewController
{
    DDLogInfo(@"%@ ensureRootViewController", self.logTag);

    if (![OWSStorage isStorageReady] || self.hasInitialRootViewController) {
        return;
    }
    self.hasInitialRootViewController = YES;

    DDLogInfo(@"Presenting initial root view controller");

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
