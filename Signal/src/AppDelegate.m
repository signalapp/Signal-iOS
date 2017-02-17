//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "AppStoreRating.h"
#import "CategorizingLogger.h"
#import "CodeVerificationViewController.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import "OWSStaleNotificationObserver.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "RPAccountManager.h"
#import "Release.h"
#import "Signal-Swift.h"
#import "TSMessagesManager.h"
#import "TSSocketManager.h"
#import "TextSecureKitEnv.h"
#import "VersionMigrations.h"
#import <AxolotlKit/SessionCipher.h>
#import <PastelogKit/Pastelog.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/OWSIncomingMessageReadObserver.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>

@import WebRTC;
@import Intents;

NSString *const AppDelegateStoryboardMain = @"Main";
NSString *const AppDelegateStoryboardRegistration = @"Registration";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

@interface AppDelegate ()

@property (nonatomic, retain) UIWindow *screenProtectionWindow;
@property (nonatomic) OWSIncomingMessageReadObserver *incomingMessageReadObserver;
@property (nonatomic) OWSStaleNotificationObserver *staleNotificationObserver;

@end

@implementation AppDelegate

- (void)applicationDidEnterBackground:(UIApplication *)application {
    DDLogWarn(@"%@ applicationDidEnterBackground.", self.tag);
    
    [DDLog flushLog];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    DDLogWarn(@"%@ applicationWillEnterForeground.", self.tag);
    
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    DDLogWarn(@"%@ applicationDidReceiveMemoryWarning.", self.tag);
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    DDLogWarn(@"%@ applicationWillTerminate.", self.tag);
    
    [DDLog flushLog];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL loggingIsEnabled;
#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    loggingIsEnabled = TRUE;
    [DebugLogger.sharedLogger enableTTYLogging];
#elif RELEASE
    loggingIsEnabled = Environment.preferences.loggingIsEnabled;
#endif
    if (loggingIsEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }

    DDLogWarn(@"%@ application: didFinishLaunchingWithOptions.", self.tag);

    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.
    srand((unsigned int)time(NULL));

    // XXX - careful when moving this. It must happen before we initialize TSStorageManager.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    // Initializing env logger
    CategorizingLogger *logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index){
    }];

    // Setting up environment
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];

    [UIUtil applySignalAppearence];
    [[PushManager sharedManager] registerPushKitNotificationFuture];

    if (getenv("runningTests_dontStartApp")) {
        return YES;
    }

    if ([TSAccountManager isRegistered]) {
        [Environment.getCurrent.contactsManager doAfterEnvironmentInitSetup];
    }
    [Environment.getCurrent initCallListener];

    [self setupTSKitEnv];

    UIStoryboard *storyboard;
    if ([TSAccountManager isRegistered]) {
        storyboard = [UIStoryboard storyboardWithName:AppDelegateStoryboardMain bundle:[NSBundle mainBundle]];
    } else {
        storyboard = [UIStoryboard storyboardWithName:AppDelegateStoryboardRegistration bundle:[NSBundle mainBundle]];
    }
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    self.window.rootViewController = [storyboard instantiateInitialViewController];
    [self.window makeKeyAndVisible];

    [VersionMigrations performUpdateCheck]; // this call must be made after environment has been initialized because in
                                            // general upgrade may depend on environment

    // Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }

    [self prepareScreenProtection];

    // At this point, potentially lengthy DB locking migrations could be running.
    // Avoid blocking app launch by putting all further possible DB access in async thread.
    UIApplicationState launchState = application.applicationState;
    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{
        if (launchState == UIApplicationStateInactive) {
            DDLogWarn(@"The app was launched from inactive");
            [TSSocketManager becomeActiveFromForeground];
        } else if (launchState == UIApplicationStateBackground) {
            DDLogWarn(@"The app was launched from being backgrounded");
            [TSSocketManager becomeActiveFromBackgroundExpectMessage:NO];
        } else {
            DDLogWarn(@"The app was launched in an unknown way");
        }

        RTCInitializeSSL();

        [OWSSyncPushTokensJob runWithPushManager:[PushManager sharedManager]
                                  accountManager:[Environment getCurrent].accountManager
                                     preferences:[Environment preferences]].then(^{
            DDLogDebug(@"%@ Successfully ran syncPushTokensJob.", self.tag);
        }).catch(^(NSError *_Nonnull error) {
            DDLogDebug(@"%@ Failed to run syncPushTokensJob with error: %@", self.tag, error);
        });

        // Clean up any messages that expired since last launch.
        [[[OWSDisappearingMessagesJob alloc] initWithStorageManager:[TSStorageManager sharedManager]] run];

        // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
        // sent before the app exited should be marked as failures.
        [[[OWSFailedMessagesJob alloc] initWithStorageManager:[TSStorageManager sharedManager]] run];

        [AppStoreRating setupRatingLibrary];
    }];

    [[TSAccountManager sharedInstance] ifRegistered:NO runAsync:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:[Pastelog class]
                                                                                      action:@selector(submitLogs)];
            gesture.numberOfTapsRequired = 8;
            [self.window addGestureRecognizer:gesture];
        });
        RTCInitializeSSL();
    }];

    return YES;
}

- (void)setupTSKitEnv {
    // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
    [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionCipher]];

    TextSecureKitEnv *sharedEnv =
        [[TextSecureKitEnv alloc] initWithCallMessageHandler:[Environment getCurrent].callMessageHandler
                                             contactsManager:[Environment getCurrent].contactsManager
                                        notificationsManager:[Environment getCurrent].notificationsManager];
    [TextSecureKitEnv setSharedEnv:sharedEnv];

    [[TSStorageManager sharedManager] setupDatabase];

    OWSMessageSender *messageSender =
        [[OWSMessageSender alloc] initWithNetworkManager:[Environment getCurrent].networkManager
                                          storageManager:[TSStorageManager sharedManager]
                                         contactsManager:[Environment getCurrent].contactsManager
                                         contactsUpdater:[Environment getCurrent].contactsUpdater];

    self.incomingMessageReadObserver =
        [[OWSIncomingMessageReadObserver alloc] initWithStorageManager:[TSStorageManager sharedManager]
                                                         messageSender:messageSender];
    [self.incomingMessageReadObserver startObserving];

    self.staleNotificationObserver = [OWSStaleNotificationObserver new];
    [self.staleNotificationObserver startObserving];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    DDLogDebug(@"%@ Successfully registered for remote notifications with token: %@", self.tag, deviceToken);
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    DDLogError(@"%@ Failed to register for remote notifications with error %@", self.tag, error);
#ifdef DEBUG
    DDLogWarn(@"%@ We're in debug mode. Faking success for remote registration with a fake push identifier", self.tag);
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:[NSData dataWithLength:32]];
#else
    [PushManager.sharedManager.pushNotificationFutureSource trySetFailure:error];
#endif
}

- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
    [PushManager.sharedManager.userNotificationFutureSource trySetResult:notificationSettings];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![TSAccountManager isRegistered]) {
            id signupController = [Environment getCurrent].signUpFlowNavigationController;
            if ([signupController isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navController = (UINavigationController *)signupController;
                UIViewController *controller          = [navController.childViewControllers lastObject];
                if ([controller isKindOfClass:[CodeVerificationViewController class]]) {
                    CodeVerificationViewController *cvvc = (CodeVerificationViewController *)controller;
                    NSString *verificationCode           = [url.path substringFromIndex:1];
                    [cvvc setVerificationCodeAndTryToVerify:verificationCode];
                } else {
                    DDLogWarn(@"Not the verification view controller we expected. Got %@ instead",
                              NSStringFromClass(controller.class));
                }
            }
        } else {
            DDLogWarn(@"Application opened with an unknown URL action: %@", url.host);
        }
    } else {
        DDLogWarn(@"Application opened with an unknown URL scheme: %@", url.scheme);
    }
    return NO;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    DDLogWarn(@"%@ applicationDidBecomeActive.", self.tag);

    if (getenv("runningTests_dontStartApp")) {
        return;
    }

    [[TSAccountManager sharedInstance] ifRegistered:YES
                                           runAsync:^{
                                               // We're double checking that the app is active, to be sure since we
                                               // can't verify in production env due to code
                                               // signing.
                                               [TSSocketManager becomeActiveFromForeground];
                                               [[Environment getCurrent].contactsManager verifyABPermission];
                                               
                                               // This will fetch new messages, if we're using domain
                                               // fronting.
                                               [[PushManager sharedManager] applicationDidBecomeActive];
                                           }];
    
    [self removeScreenProtection];

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    DDLogWarn(@"%@ applicationWillResignActive.", self.tag);
    
    UIBackgroundTaskIdentifier __block bgTask = UIBackgroundTaskInvalid;
    bgTask                                    = [application beginBackgroundTaskWithExpirationHandler:^{

    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      if ([TSAccountManager isRegistered]) {
          dispatch_sync(dispatch_get_main_queue(), ^{
              [self protectScreen];
              [[[Environment getCurrent] signalsViewController] updateInboxCountLabel];
              [TSSocketManager resignActivity];
          });
      }

      [application endBackgroundTask:bgTask];
      bgTask = UIBackgroundTaskInvalid;
    });
    
    [DDLog flushLog];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    if ([TSAccountManager isRegistered]) {
        [[Environment getCurrent].signalsViewController composeNew];
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
        [[Environment getCurrent]
                .signalsViewController.presentedViewController presentViewController:controller
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
            DDLogError(@"%@ unexpectedly received INStartVideoCallIntent pre iOS10", self.tag);
            return NO;
        }

        DDLogInfo(@"%@ got start video call intent", self.tag);

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartVideoCallIntent class]]) {
            DDLogError(@"%@ unexpected class for start call video: %@", self.tag, intent);
            return NO;
        }
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            DDLogWarn(@"%@ unable to find handle in startCallIntent: %@", self.tag, startCallIntent);
            return NO;
        }

        if ([Environment getCurrent].phoneManager.hasOngoingRedphoneCall) {
            DDLogWarn(@"%@ ignoring INStartVideoCallIntent due to ongoing RedPhone call.", self.tag);
            return NO;
        }

        // This intent can be received from more than one user interaction.
        //
        // * It can be received if the user taps the "video" button in the CallKit UI for an
        //   an ongoing call.  If so, the correct response is to try to activate the local
        //   video for that call.
        // * It can be received if the user taps the "video" button for a contact in the
        //   contacts app.  If so, the correct response is to try to initiate a new call
        //   to that user - unless there already is another call in progress.
        if ([Environment getCurrent].callService.call != nil) {
            if ([handle isEqualToString:[Environment getCurrent].callService.call.remotePhoneNumber]) {
                DDLogWarn(@"%@ trying to upgrade ongoing call to video.", self.tag);
                [[Environment getCurrent].callService handleCallKitStartVideo];
                return YES;
            } else {
                DDLogWarn(
                    @"%@ ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.", self.tag);
                return NO;
            }
        }

        OutboundCallInitiator *outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
        OWSAssert(outboundCallInitiator);
        return [outboundCallInitiator initiateCallWithHandle:handle];
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {

        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            DDLogError(@"%@ unexpectedly received INStartAudioCallIntent pre iOS10", self.tag);
            return NO;
        }

        DDLogInfo(@"%@ got start audio call intent", self.tag);

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartAudioCallIntent class]]) {
            DDLogError(@"%@ unexpected class for start call audio: %@", self.tag, intent);
            return NO;
        }
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            DDLogWarn(@"%@ unable to find handle in startCallIntent: %@", self.tag, startCallIntent);
            return NO;
        }

        if ([Environment getCurrent].phoneManager.hasOngoingRedphoneCall) {
            DDLogWarn(@"%@ ignoring INStartAudioCallIntent due to ongoing RedPhone call.", self.tag);
            return NO;
        }
        if ([Environment getCurrent].callService.call != nil) {
            DDLogWarn(@"%@ ignoring INStartAudioCallIntent due to ongoing WebRTC call.", self.tag);
            return NO;
        }

        OutboundCallInitiator *outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
        OWSAssert(outboundCallInitiator);
        return [outboundCallInitiator initiateCallWithHandle:handle];
    } else {
        DDLogWarn(@"%@ called %s with userActivity: %@, but not yet supported.",
            self.tag,
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

- (void)protectScreen {
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.screenProtectionWindow.hidden = NO;
    }
}

- (void)removeScreenProtection {
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.screenProtectionWindow.hidden = YES;
    }
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
    [AppStoreRating preventPromptAtNextTest];
    [[PushManager sharedManager] application:application didReceiveLocalNotification:notification];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)())completionHandler {
    [[PushManager sharedManager] application:application
                  handleActionWithIdentifier:identifier
                        forLocalNotification:notification
                           completionHandler:completionHandler];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)())completionHandler {
    [[PushManager sharedManager] application:application
                  handleActionWithIdentifier:identifier
                        forLocalNotification:notification
                            withResponseInfo:responseInfo
                           completionHandler:completionHandler];
}

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        return;
    }

    if (![TSStorageManager isDatabasePasswordAccessible]) {
        DDLogInfo(@"%@ exiting because we are in the background and the database password is not accessible.", self.tag);
        [DDLog flushLog];
        exit(0);
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
