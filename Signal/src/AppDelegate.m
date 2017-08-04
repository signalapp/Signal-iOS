//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "AppStoreRating.h"
#import "AppUpdateNag.h"
#import "CodeVerificationViewController.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "NotificationsManager.h"
#import "OWSContactsManager.h"
#import "OWSContactsSyncing.h"
#import "OWSProfileManager.h"
#import "OWSStaleNotificationObserver.h"
#import "Pastelog.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "RegistrationViewController.h"
#import "Release.h"
#import "SendExternalFileViewController.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import "VersionMigrations.h"
#import "ViewControllerUtils.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalServiceKit/OWSFailedMessagesJob.h>
#import <SignalServiceKit/OWSIncomingMessageReadObserver.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <SignalServiceKit/TSStorageManager+Calling.h>
#import <SignalServiceKit/TextSecureKitEnv.h>

@import WebRTC;
@import Intents;

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";

@interface AppDelegate ()

@property (nonatomic) UIWindow *screenProtectionWindow;
@property (nonatomic) OWSIncomingMessageReadObserver *incomingMessageReadObserver;
@property (nonatomic) OWSStaleNotificationObserver *staleNotificationObserver;
@property (nonatomic) OWSContactsSyncing *contactsSyncing;
@property (nonatomic) BOOL hasInitialRootViewController;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

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
    loggingIsEnabled = PropertyListPreferences.loggingIsEnabled;
#endif
    if (loggingIsEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }

    DDLogWarn(@"%@ application: didFinishLaunchingWithOptions.", self.tag);

    [AppVersion instance];

    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.
    srand((unsigned int)time(NULL));

    // XXX - careful when moving this. It must happen before we initialize TSStorageManager.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in databaseViewRegistrationComplete.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    [self setupEnvironment];

    [UIUtil applySignalAppearence];
    [[PushManager sharedManager] registerPushKitNotificationFuture];

    if (getenv("runningTests_dontStartApp")) {
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

    self.contactsSyncing = [[OWSContactsSyncing alloc] initWithContactsManager:[Environment getCurrent].contactsManager
                                                               identityManager:[OWSIdentityManager sharedManager]
                                                                 messageSender:[Environment getCurrent].messageSender];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(databaseViewRegistrationComplete)
                                                 name:kNSNotificationName_DatabaseViewRegistrationComplete
                                               object:nil];

    DDLogInfo(@"%@ application: didFinishLaunchingWithOptions completed.", self.tag);

    [OWSAnalytics appLaunchDidBegin];

    return YES;
}

- (UIViewController *)loadingRootViewController
{
    UIViewController *viewController =
        [[UIStoryboard storyboardWithName:@"Launch Screen" bundle:nil] instantiateInitialViewController];

    NSString *lastLaunchedAppVersion = AppVersion.instance.lastAppVersion;
    NSString *lastCompletedLaunchAppVersion = AppVersion.instance.lastCompletedLaunchAppVersion;
    // Every time we change a database view in such a way that might cause a delay on launch,
    // we need to bump this constant.
    //
    // We added a number of database views in v2.13.0.
    NSString *kLastVersionWithDatabaseViewChange = @"2.13.0";
    BOOL mayNeedUpgrade = ([TSAccountManager isRegistered] && lastLaunchedAppVersion
        && (!lastCompletedLaunchAppVersion ||
               [VersionMigrations isVersion:lastCompletedLaunchAppVersion
                                   lessThan:kLastVersionWithDatabaseViewChange]));
    DDLogInfo(@"%@ mayNeedUpgrade: %d", self.tag, mayNeedUpgrade);
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

- (void)setupEnvironment
{
    [Environment setCurrent:[Release releaseEnvironment]];

    // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
    [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];

    TextSecureKitEnv *sharedEnv =
        [[TextSecureKitEnv alloc] initWithCallMessageHandler:[Environment getCurrent].callMessageHandler
                                             contactsManager:[Environment getCurrent].contactsManager
                                               messageSender:[Environment getCurrent].messageSender
                                        notificationsManager:[Environment getCurrent].notificationsManager
                                              profileManager:OWSProfileManager.sharedManager];
    [TextSecureKitEnv setSharedEnv:sharedEnv];

    [[TSStorageManager sharedManager] setupDatabaseWithSafeBlockingMigrations:^{
        [VersionMigrations runSafeBlockingMigrations];
    }];

    self.incomingMessageReadObserver =
        [[OWSIncomingMessageReadObserver alloc] initWithMessageSender:[Environment getCurrent].messageSender];
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
    OWSProdError([OWSAnalyticsEvents appDelegateErrorFailedToRegisterForRemoteNotifications]);
#ifdef DEBUG
    DDLogWarn(@"%@ We're in debug mode. Faking success for remote registration with a fake push identifier", self.tag);
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:[[NSMutableData dataWithLength:32] copy]];
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
    } else if ([url.scheme.lowercaseString isEqualToString:@"file"]) {

        if ([Environment getCurrent].callService.call != nil) {
            DDLogWarn(@"%@ ignoring 'open with Signal' due to ongoing WebRTC call.", self.tag);
            return NO;
        }

        NSString *filename = url.lastPathComponent;
        if ([filename stringByDeletingPathExtension].length < 1) {
            DDLogError(@"Application opened with URL invalid filename: %@", url);
            [OWSAlerts showAlertWithTitle:
                           NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_TITLE",
                               @"Title for the alert indicating the 'export with signal' attachment had an error.")
                                  message:NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_MESSAGE_INVALID_FILENAME",
                                              @"Message for the alert indicating the 'export with signal' file had an "
                                              @"invalid filename.")];
            return NO;
        }
        NSString *fileExtension = [filename pathExtension];
        if (fileExtension.length < 1) {
            DDLogError(@"Application opened with URL missing file extension: %@", url);
            [OWSAlerts showAlertWithTitle:
                           NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_TITLE",
                               @"Title for the alert indicating the 'export with signal' attachment had an error.")
                                  message:NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_MESSAGE_UNKNOWN_TYPE",
                                              @"Message for the alert indicating the 'export with signal' file had "
                                              @"unknown type.")];
            return NO;
        }
        
        
        NSString *utiType;
        NSError *typeError;
        [url getResourceValue:&utiType forKey:NSURLTypeIdentifierKey error:&typeError];
        if (typeError) {
            OWSFail(
                @"%@ Determining type of picked document at url: %@ failed with error: %@", self.tag, url, typeError);
            return NO;
        }
        if (!utiType) {
            OWSFail(@"%@ falling back to default filetype for picked document at url: %@", self.tag, url);
            utiType = (__bridge NSString *)kUTTypeData;
            return NO;
        }
        
        NSNumber *isDirectory;
        NSError *isDirectoryError;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
        if (isDirectoryError) {
            OWSFail(@"%@ Determining if picked document at url: %@ was a directory failed with error: %@",
                self.tag,
                url,
                isDirectoryError);
            return NO;
        } else if ([isDirectory boolValue]) {
            DDLogInfo(@"%@ User picked directory at url: %@", self.tag, url);
            DDLogError(@"Application opened with URL of unknown UTI type: %@", url);
            [OWSAlerts
                showAlertWithTitle:
                    NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                        @"Alert title when picking a document fails because user picked a directory/bundle")
                           message:
                               NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                   @"Alert body when picking a document fails because user picked a directory/bundle")];
            return NO;
        }
        
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data) {
            DDLogError(@"Application opened with URL with unloadable content: %@", url);
            [OWSAlerts showAlertWithTitle:
                           NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_TITLE",
                               @"Title for the alert indicating the 'export with signal' attachment had an error.")
                                  message:NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_MESSAGE_MISSING_DATA",
                                              @"Message for the alert indicating the 'export with signal' data "
                                              @"couldn't be loaded.")];
            return NO;
        }
        SignalAttachment *attachment = [SignalAttachment attachmentWithData:data dataUTI:utiType filename:filename];
        if (!attachment) {
            DDLogError(@"Application opened with URL with invalid content: %@", url);
            [OWSAlerts showAlertWithTitle:
                           NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_TITLE",
                               @"Title for the alert indicating the 'export with signal' attachment had an error.")
                                  message:NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_MESSAGE_MISSING_ATTACHMENT",
                                              @"Message for the alert indicating the 'export with signal' attachment "
                                              @"couldn't be loaded.")];
            return NO;
        }
        if ([attachment hasError]) {
            DDLogError(@"Application opened with URL with content error: %@ %@", url, [attachment errorName]);
            [OWSAlerts showAlertWithTitle:
                           NSLocalizedString(@"EXPORT_WITH_SIGNAL_ERROR_TITLE",
                               @"Title for the alert indicating the 'export with signal' attachment had an error.")
                                  message:[attachment errorName]];
            return NO;
        }
        DDLogInfo(@"Application opened with URL: %@", url);

        [[TSAccountManager sharedInstance] ifRegistered:YES
                                               runAsync:^{
                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                       // Wait up to N seconds for database view registrations to
                                                       // complete.
                                                       [self showImportUIForAttachment:attachment remainingRetries:5];
                                                   });
                                               }];

        return YES;
    } else {
        DDLogWarn(@"Application opened with an unknown URL scheme: %@", url.scheme);
    }
    return NO;
}

- (void)showImportUIForAttachment:(SignalAttachment *)attachment remainingRetries:(int)remainingRetries
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(attachment);
    OWSAssert(remainingRetries > 0);

    if ([TSDatabaseView hasPendingViewRegistrations]) {
        if (remainingRetries < 1) {
            DDLogInfo(@"Ignoring 'Import with Signal...' due to pending view registrations.");
        } else {
            DDLogInfo(@"Delaying 'Import with Signal...' due to pending view registrations.");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (![TSDatabaseView hasPendingViewRegistrations]) {
                    [self showImportUIForAttachment:attachment remainingRetries:remainingRetries - 1];
                }
            });
        }
        return;
    }

    SendExternalFileViewController *viewController = [SendExternalFileViewController new];
    viewController.attachment = attachment;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:viewController];
    [[[Environment getCurrent] signalsViewController] presentTopLevelModalViewController:navigationController
                                                                        animateDismissal:NO
                                                                     animatePresentation:YES];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    DDLogWarn(@"%@ applicationDidBecomeActive.", self.tag);

    if (getenv("runningTests_dontStartApp")) {
        return;
    }
    
    [self removeScreenProtection];

    [self ensureRootViewController];

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async thread.
        [[TSAccountManager sharedInstance]
            ifRegistered:YES
                runAsync:^{
                    DDLogInfo(@"%@ running post launch block for registered user: %@",
                        self.tag,
                        [TSAccountManager localNumber]);

                    RTCInitializeSSL();

                    [OWSSyncPushTokensJob runWithPushManager:[PushManager sharedManager]
                                              accountManager:[Environment getCurrent].accountManager
                                                 preferences:[Environment preferences]
                                                  showAlerts:NO];

                    // Clean up any messages that expired since last launch immediately
                    // and continue cleaning in the background.
                    [[OWSDisappearingMessagesJob sharedJob] startIfNecessary];

                    // Mark all "attempting out" messages as "unsent", i.e. any messages that were not successfully
                    // sent before the app exited should be marked as failures.
                    [[[OWSFailedMessagesJob alloc] initWithStorageManager:[TSStorageManager sharedManager]] run];
                    [[[OWSFailedAttachmentDownloadsJob alloc] initWithStorageManager:[TSStorageManager sharedManager]]
                        run];

                    [AppStoreRating setupRatingLibrary];
                }];

        [[TSAccountManager sharedInstance]
            ifRegistered:NO
                runAsync:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        DDLogInfo(@"%@ running post launch block for unregistered user.", self.tag);

                        // Unregistered user should have no unread messages. e.g. if you delete your account.
                        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

                        [TSSocketManager requestSocketOpen];

                        UITapGestureRecognizer *gesture =
                            [[UITapGestureRecognizer alloc] initWithTarget:[Pastelog class]
                                                                    action:@selector(submitLogs)];
                        gesture.numberOfTapsRequired = 8;
                        [self.window addGestureRecognizer:gesture];
                    });
                    RTCInitializeSSL();
                }];
    });

    [[TSAccountManager sharedInstance]
        ifRegistered:YES
            runAsync:^{
                [TSSocketManager requestSocketOpen];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [[Environment getCurrent].contactsManager fetchSystemContactsIfAlreadyAuthorized];
                });

                // This will fetch new messages, if we're using domain
                // fronting.
                [[PushManager sharedManager] applicationDidBecomeActive];
            }];

    DDLogInfo(@"%@ applicationDidBecomeActive completed.", self.tag);
}

- (void)applicationWillResignActive:(UIApplication *)application {
    DDLogWarn(@"%@ applicationWillResignActive.", self.tag);

    UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if ([TSAccountManager isRegistered]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
                    // If app has not re-entered active, show screen protection if necessary.
                    [self showScreenProtection];
                }
                [[[Environment getCurrent] signalsViewController] updateInboxCountLabel];
                [application endBackgroundTask:bgTask];
            });
        }
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

        NSString *_Nullable phoneNumber = handle;
        if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
            phoneNumber = [[TSStorageManager sharedManager] phoneNumberForCallKitId:handle];
            if (phoneNumber.length < 1) {
                DDLogWarn(@"%@ ignoring attempt to initiate video call to unknown anonymous signal user.", self.tag);
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
        if ([Environment getCurrent].callService.call != nil) {
            if ([phoneNumber isEqualToString:[Environment getCurrent].callService.call.remotePhoneNumber]) {
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
        return [outboundCallInitiator initiateCallWithHandle:phoneNumber];
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

        NSString *_Nullable phoneNumber = handle;
        if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
            phoneNumber = [[TSStorageManager sharedManager] phoneNumberForCallKitId:handle];
            if (phoneNumber.length < 1) {
                DDLogWarn(@"%@ ignoring attempt to initiate audio call to unknown anonymous signal user.", self.tag);
                return NO;
            }
        }

        if ([Environment getCurrent].callService.call != nil) {
            DDLogWarn(@"%@ ignoring INStartAudioCallIntent due to ongoing WebRTC call.", self.tag);
            return NO;
        }

        OutboundCallInitiator *outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
        OWSAssert(outboundCallInitiator);
        return [outboundCallInitiator initiateCallWithHandle:phoneNumber];
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

- (void)databaseViewRegistrationComplete
{
    DDLogInfo(@"databaseViewRegistrationComplete");

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];

    [AppVersion.instance appLaunchDidComplete];

    [self ensureRootViewController];

    // If there were any messages in our local queue which we hadn't yet processed.
    [[OWSMessageReceiver sharedInstance] handleAnyUnprocessedEnvelopesAsync];
}

- (void)ensureRootViewController
{
    DDLogInfo(@"ensureRootViewController");

    if ([TSDatabaseView hasPendingViewRegistrations] || self.hasInitialRootViewController) {
        return;
    }
    self.hasInitialRootViewController = YES;

    DDLogInfo(@"Presenting initial root view controller");

    if ([TSAccountManager isRegistered]) {
        SignalsViewController *homeView = [SignalsViewController new];
        SignalsNavigationController *navigationController =
            [[SignalsNavigationController alloc] initWithRootViewController:homeView];
        self.window.rootViewController = navigationController;
    } else {
        RegistrationViewController *viewController = [RegistrationViewController new];
        UINavigationController *navigationController =
            [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.navigationBarHidden = YES;
        self.window.rootViewController = navigationController;
    }

    [AppUpdateNag.sharedInstance showAppUpgradeNagIfNecessary];
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
