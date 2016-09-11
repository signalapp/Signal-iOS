#import "AppDelegate.h"
#import "AppStoreRating.h"
#import "CategorizingLogger.h"
#import "CodeVerificationViewController.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import "PreferencesUtil.h"
#import "PushManager.h"
#import "Release.h"
#import "TSAccountManager.h"
#import "TSMessagesManager.h"
#import "TSPreKeyManager.h"
#import "TSSocketManager.h"
#import "TextSecureKitEnv.h"
#import "VersionMigrations.h"
#import "OWSStaleNotificationObserver.h"
#import <SignalServiceKit/OWSReadReceiptObserver.h>

static NSString *const kStoryboardName                  = @"Storyboard";
static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

@interface AppDelegate ()

@property (nonatomic, retain) UIWindow *screenProtectionWindow;
@property (nonatomic) OWSReadReceiptObserver *readReceiptObserver;
@property (nonatomic) OWSStaleNotificationObserver *staleNotificationObserver;

@end

@implementation AppDelegate

#pragma mark Detect updates - perform migrations

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Initializing logger
    CategorizingLogger *logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index){
    }];

    // Setting up environment
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];

    [self setupAppearance];
    [[PushManager sharedManager] registerPushKitNotificationFuture];

    if (getenv("runningTests_dontStartApp")) {
        return YES;
    }

    if ([TSAccountManager isRegistered]) {
        [Environment.getCurrent.contactsManager doAfterEnvironmentInitSetup];
    }
    [Environment.getCurrent initCallListener];

    [self setupTSKitEnv];

    BOOL loggingIsEnabled;

#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    loggingIsEnabled = TRUE;
    [DebugLogger.sharedLogger enableTTYLogging];
#elif RELEASE
    loggingIsEnabled = Environment.preferences.loggingIsEnabled;
#endif
    [self verifyBackgroundBeforeKeysAvailableLaunch];

    if (loggingIsEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }

    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:kStoryboardName bundle:[NSBundle mainBundle]];
    UIViewController *viewController =
        [storyboard instantiateViewControllerWithIdentifier:kInitialViewControllerIdentifier];

    self.window                    = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = viewController;

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

    if ([TSAccountManager isRegistered]) {
        if (application.applicationState == UIApplicationStateInactive) {
            [TSSocketManager becomeActiveFromForeground];
        } else if (application.applicationState == UIApplicationStateBackground) {
            [TSSocketManager becomeActiveFromBackgroundExpectMessage:NO];
        } else {
            DDLogWarn(@"The app was launched in an unknown way");
        }

        [[PushManager sharedManager] validateUserNotificationSettings];
        [TSPreKeyManager refreshPreKeys];
    }

    [AppStoreRating setupRatingLibrary];

    return YES;
}

- (void)setupTSKitEnv {
    [TextSecureKitEnv sharedEnv].contactsManager = [Environment getCurrent].contactsManager;
    [[TSStorageManager sharedManager] setupDatabase];
    [TextSecureKitEnv sharedEnv].notificationsManager = [[NotificationsManager alloc] init];
    self.readReceiptObserver = [OWSReadReceiptObserver new];
    [self.readReceiptObserver startObserving];

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

                    cvvc.challengeTextField.text = verificationCode;
                    [cvvc verifyChallengeAction:nil];
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
    if (getenv("runningTests_dontStartApp")) {
        return;
    }

    if ([TSAccountManager isRegistered]) {
        // We're double checking that the app is active, to be sure since we can't verify in production env due to code
        // signing.
        [TSSocketManager becomeActiveFromForeground];
        [[Environment getCurrent].contactsManager verifyABPermission];
    }

    [self removeScreenProtection];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    UIBackgroundTaskIdentifier __block bgTask = UIBackgroundTaskInvalid;
    bgTask                                    = [application beginBackgroundTaskWithExpirationHandler:^{

    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      if ([TSAccountManager isRegistered]) {
          dispatch_sync(dispatch_get_main_queue(), ^{
            [self protectScreen];
            [[[Environment getCurrent] signalsViewController] updateInboxCountLabel];
          });
          [TSSocketManager resignActivity];
      }

      [application endBackgroundTask:bgTask];
      bgTask = UIBackgroundTaskInvalid;
    });
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

- (void)setupAppearance {
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    [[UINavigationBar appearance] setBarTintColor:[UIColor ows_materialBlueColor]];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];

    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTintColor:[UIColor ows_materialBlueColor]];


    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    [[UIBarButtonItem appearance] setTintColor:[UIColor whiteColor]];

    NSShadow *shadow = [NSShadow new];
    [shadow setShadowColor:[UIColor clearColor]];

    NSDictionary *navbarTitleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor whiteColor],
        NSShadowAttributeName : shadow,
    };

    [[UISwitch appearance] setOnTintColor:[UIColor ows_materialBlueColor]];

    [[UINavigationBar appearance] setTitleTextAttributes:navbarTitleTextAttributes];
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
 *  Signal requires an iPhone to be unlocked after reboot to be able to access keying material.
 */
- (void)verifyBackgroundBeforeKeysAvailableLaunch {
    if ([self applicationIsActive]) {
        return;
    }

    if (![[TSStorageManager sharedManager] databasePasswordAccessible]) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.alertBody            = NSLocalizedString(@"PHONE_NEEDS_UNLOCK", nil);
        [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
        exit(0);
    }
}

- (BOOL)applicationIsActive {
    UIApplication *app = [UIApplication sharedApplication];

    if (app.applicationState == UIApplicationStateActive) {
        return YES;
    }

    return NO;
}

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
