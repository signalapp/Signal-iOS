//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AppDelegate.h"
#import "ChatListViewController.h"
#import "MainAppContext.h"
#import "OWSDeviceProvisioningURLParser.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import <Intents/Intents.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSOrphanDataCleaner.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/CallKitIdStore.h>
#import <SignalServiceKit/DarwinNotificationCenter.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StickerInfo.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalUI/ViewControllerUtils.h>
#import <UserNotifications/UserNotifications.h>
#import <WebRTC/WebRTC.h>

NSString *const AppDelegateStoryboardMain = @"Main";
NSString *const kAppLaunchesAttemptedKey = @"AppLaunchesAttempted";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
NSString *const kURLSchemeSGNLKey = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";
static NSString *const kURLHostAddStickersPrefix = @"addstickers";
NSString *const kURLHostTransferPrefix = @"transfer";
NSString *const kURLHostLinkDevicePrefix = @"linkdevice";

static void uncaughtExceptionHandler(NSException *exception)
{
    if (SSKDebugFlags.internalLogging) {
        OWSLogError(@"exception: %@", exception);
        OWSLogError(@"name: %@", exception.name);
        OWSLogError(@"reason: %@", exception.reason);
        OWSLogError(@"userInfo: %@", exception.userInfo);
    } else {
        NSString *reason = exception.reason;
        NSString *reasonHash =
            [[Cryptography computeSHA256Digest:[reason dataUsingEncoding:NSUTF8StringEncoding]] base64EncodedString];

        // Truncate the error message to minimize potential leakage of user data.
        // Attempt to truncate at word boundaries so that we don't, say, print *most* of a phone number
        // and have it evade the log filter...but fall back to printing the whole first N characters if there's
        // not a word boundary.
        static const NSUInteger TRUNCATED_REASON_LENGTH = 20;
        NSString *maybeEllipsis = @"";
        if ([reason length] > TRUNCATED_REASON_LENGTH) {
            NSRange lastSpaceRange = [reason rangeOfString:@" "
                                                   options:NSBackwardsSearch
                                                     range:NSMakeRange(0, TRUNCATED_REASON_LENGTH)];
            NSUInteger endIndex
                = (lastSpaceRange.location != NSNotFound) ? lastSpaceRange.location : TRUNCATED_REASON_LENGTH;
            reason = [reason substringToIndex:endIndex];
            maybeEllipsis = @"...";
        }
        OWSLogError(@"%@: %@%@ (hash: %@)", exception.name, reason, maybeEllipsis, reasonHash);
    }
    OWSLogError(@"callStackSymbols: %@", exception.callStackSymbols);
    OWSLogFlush();
}

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@property (nonatomic, readwrite) NSTimeInterval launchStartedAt;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

- (BOOL)shouldKillAppWhenBackgrounded
{
    if (_shouldKillAppWhenBackgrounded) {
        // Should only be killing app in the background if app launch failed
        OWSAssertDebug(self.didAppLaunchFail);
    }

    return _shouldKillAppWhenBackgrounded;
}

- (void)setDidAppLaunchFail:(BOOL)didAppLaunchFail
{
    if (!didAppLaunchFail) {
        self.shouldKillAppWhenBackgrounded = NO;
    }

    _didAppLaunchFail = didAppLaunchFail;
}

#pragma mark -

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidEnterBackground.");

    OWSLogFlush();

    if (self.shouldKillAppWhenBackgrounded) {
        exit(0);
    }
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

    [SignalApp.shared applicationWillTerminate];

    OWSLogFlush();
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);

    // This should be the first thing we do.
    SetCurrentAppContext([MainAppContext new], NO);

    self.launchStartedAt = CACurrentMediaTime();
    [BenchManager startEventWithTitle:@"Presenting HomeView" eventId:@"AppStart" logInProduction:TRUE];

    BOOL isLoggingEnabled;
    [InstrumentsMonitor enable];
    unsigned long long monitorId = [InstrumentsMonitor startSpanWithCategory:@"appstart"
                                                                      parent:@"application"
                                                                        name:@"didFinishLaunchingWithOptions"];

#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    isLoggingEnabled = TRUE;
    [DebugLogger.shared enableTTYLogging];
#else
    isLoggingEnabled = OWSPreferences.isLoggingEnabled;
#endif
    if (isLoggingEnabled) {
        [DebugLogger.shared enableFileLogging];
    }
    if (SSKDebugFlags.audibleErrorLogging) {
        [DebugLogger.shared enableErrorReporting];
    }
    [DebugLogger configureSwiftLogging];

#ifdef DEBUG
    [SSKFeatureFlags logFlags];
    [SSKDebugFlags logFlags];
#endif

    OWSLogWarn(@"application: didFinishLaunchingWithOptions.");
    [Cryptography seedRandom];

    // This *must* happen before we try and access or verify the database, since we
    // may be in a state where the database has been partially restored from transfer
    // (e.g. the key was replaced, but the database files haven't been moved into place)
    __block BOOL didDeviceTransferRestoreSucceed = YES;
    [BenchManager benchWithTitle:@"Slow device transfer service launch"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{ didDeviceTransferRestoreSucceed = [DeviceTransferService.shared launchCleanup]; }];

    // XXX - careful when moving this. It must happen before we load GRDB.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    [InstrumentsMonitor trackEventWithName:@"AppStart"];

    [AppVersion shared];

    // We need to do this _after_ we set up logging, when the keychain is unlocked,
    // but before we access the database, files on disk, or NSUserDefaults.
    LaunchFailure launchFailure =
        [self launchFailureWithDidDeviceTransferRestoreSucceed:didDeviceTransferRestoreSucceed];

    if (launchFailure != LaunchFailureNone) {
        [InstrumentsMonitor stopSpanWithCategory:@"appstart" hash:monitorId];
        OWSLogInfo(@"application: didFinishLaunchingWithOptions failed.");
        [self showUIForLaunchFailure:launchFailure];

        return YES;
    }

    [self launchToHomeScreenWithLaunchOptions:launchOptions
                         instrumentsMonitorId:monitorId
                    isEnvironmentAlreadySetUp:NO];
    return YES;
}

- (BOOL)launchToHomeScreenWithLaunchOptions:(NSDictionary *_Nullable)launchOptions
                       instrumentsMonitorId:(unsigned long long)monitorId
                  isEnvironmentAlreadySetUp:(BOOL)isEnvironmentAlreadySetUp
{
    [self setupNSEInteroperation];

    if (CurrentAppContext().isRunningTests) {
        [InstrumentsMonitor stopSpanWithCategory:@"appstart" hash:monitorId];
        return YES;
    }

    NSInteger appLaunchesAttempted = [[CurrentAppContext() appUserDefaults] integerForKey:kAppLaunchesAttemptedKey];
    [[CurrentAppContext() appUserDefaults] setInteger:appLaunchesAttempted + 1 forKey:kAppLaunchesAttemptedKey];
    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(
        ^{ [[CurrentAppContext() appUserDefaults] removeObjectForKey:kAppLaunchesAttemptedKey]; });

    if (!isEnvironmentAlreadySetUp) {
        [AppDelegate setUpMainAppEnvironmentWithCompletion:^(NSError *_Nullable error) {
            OWSAssertIsOnMainThread();

            if (error != nil) {
                OWSFailDebug(@"Error: %@", error);
                [self showUIForLaunchFailure:LaunchFailureCouldNotLoadDatabase];
            } else {
                [self versionMigrationsDidComplete];
            }
        }];
    }

    [UIUtil setupSignalAppearence];

    UIWindow *mainWindow = self.window;
    if (mainWindow == nil) {
        mainWindow = [OWSWindow new];
        self.window = mainWindow;
        CurrentAppContext().mainWindow = mainWindow;
    }
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    // This must happen in appDidFinishLaunching or earlier to ensure we don't
    // miss notifications.
    // Setting the delegate also seems to prevent us from getting the legacy notification
    // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;

    // Accept push notification when app is not open
    NSDictionary *remoteNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotification) {
        OWSLogInfo(@"Application was launched by tapping a push notification.");
        [self processRemoteNotification:remoteNotification];
    }

    [OWSScreenLockUI.shared setupWithRootWindow:self.window];
    [[OWSWindowManager shared] setupWithRootWindow:self.window
                              screenBlockingWindow:OWSScreenLockUI.shared.screenBlockingWindow];
    [OWSScreenLockUI.shared startObserving];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storageIsReady)
                                                 name:StorageIsReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationLockDidChange:)
                                                 name:NSNotificationName_2FAStateDidChange
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(spamChallenge:)
                                                 name:SpamChallengeResolver.NeedsCaptchaNotification
                                               object:nil];

    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

    OWSLogInfo(@"launchOptions: %@.", launchOptions);

    [OWSAnalytics appLaunchDidBegin];

    [InstrumentsMonitor stopSpanWithCategory:@"appstart" hash:monitorId];

    return YES;
}

- (void)spamChallenge:(NSNotification *)notification
{
    UIViewController *fromVC = UIApplication.sharedApplication.frontmostViewController;
    [SpamCaptchaViewController presentActionSheetFrom:fromVC];
}

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        return;
    }

    if (StorageCoordinator.hasGrdbFile && GRDBDatabaseStorageAdapter.isKeyAccessible) {
        return;
    }

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

    OWSLogFlush();
    exit(0);
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

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    OWSAssertIsOnMainThread();

    return [self tryToOpenUrl:url];
}

- (BOOL)tryToOpenUrl:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([SignalMe isPossibleUrl:url]) {
        return [self tryToShowSignalMeChatForUrl:url];
    } else if ([StickerPackInfo isStickerPackShareUrl:url]) {
        StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];
        if (stickerPackInfo == nil) {
            OWSFailDebug(@"Could not parse sticker pack share URL: %@", url);
            return NO;
        }
        return [self tryToShowStickerPackView:stickerPackInfo];
    } else if ([GroupManager isPossibleGroupInviteLink:url]) {
        return [self tryToShowGroupInviteLinkUI:url];
    } else if ([SignalProxy isValidProxyLink:url]) {
        return [self tryToShowProxyLinkUI:url];
    } else if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![self.tsAccountManager isRegistered]) {
            if (!AppReadiness.isAppReady) {
                OWSFailDebug(@"Ignoring URL; app is not ready.");
                return NO;
            }
            return [SignalApp.shared receivedVerificationCode:[url.path substringFromIndex:1]];
        } else if ([url.host hasPrefix:kURLHostAddStickersPrefix] && [self.tsAccountManager isRegistered]) {
            StickerPackInfo *_Nullable stickerPackInfo = [self parseAddStickersUrl:url];
            if (stickerPackInfo == nil) {
                OWSFailDebug(@"Invalid URL: %@", url);
                return NO;
            }
            return [self tryToShowStickerPackView:stickerPackInfo];
        } else if ([url.host hasPrefix:kURLHostLinkDevicePrefix] && [self.tsAccountManager isRegistered]
            && self.tsAccountManager.isPrimaryDevice) {
            OWSDeviceProvisioningURLParser *parser =
                [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:url.absoluteString];
            if (!parser.isValid) {
                OWSFailDebug(@"Invalid URL: %@", url);
                return NO;
            }
            return [self tryToShowLinkDeviceViewWithParser:parser];
        } else {
            OWSLogVerbose(@"Invalid URL: %@", url);
            OWSFailDebug(@"Unknown URL host: %@", url.host);
        }
    } else {
        OWSFailDebug(@"Unknown URL scheme: %@", url.scheme);
    }

    return NO;
}

- (nullable StickerPackInfo *)parseAddStickersUrl:(NSURL *)url
{
    NSString *_Nullable packIdHex;
    NSString *_Nullable packKeyHex;
    NSURLComponents *components = [NSURLComponents componentsWithString:url.absoluteString];
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        if ([queryItem.name isEqualToString:@"pack_id"]) {
            OWSAssertDebug(packIdHex == nil);
            packIdHex = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"pack_key"]) {
            OWSAssertDebug(packKeyHex == nil);
            packKeyHex = queryItem.value;
        } else {
            OWSLogWarn(@"Unknown query item: %@", queryItem.name);
        }
    }

    return [StickerPackInfo parsePackIdHex:packIdHex packKeyHex:packKeyHex];
}

- (BOOL)tryToShowStickerPackView:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertDebug(!self.didAppLaunchFail);
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring sticker pack URL; not registered.");
            return;
        }

        StickerPackViewController *packView =
            [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];
        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController
                dismissViewControllerAnimated:NO
                                   completion:^{ [packView presentFrom:rootViewController animated:NO]; }];
        } else {
            [packView presentFrom:rootViewController animated:NO];
        }
    });
    return YES;
}

- (BOOL)tryToShowSignalMeChatForUrl:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring signal me URL; not registered.");
            return;
        }

        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [SignalMe openChatWithUrl:url
                                                              fromViewController:rootViewController];
                                                   }];
        } else {
            [SignalMe openChatWithUrl:url fromViewController:rootViewController];
        }
    });
    return YES;
}

- (BOOL)tryToShowLinkDeviceViewWithParser:(OWSDeviceProvisioningURLParser *)parser
{
    OWSAssertDebug(!self.didAppLaunchFail);
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring linked device URL; not registered.");
            return;
        }
        if (!self.tsAccountManager.isPrimaryDevice) {
            OWSFailDebug(@"Ignoring linked device URL; not primary.");
            return;
        }

        UINavigationController *navController = [AppSettingsViewController inModalNavigationController];
        NSMutableArray<UIViewController *> *viewControllers = [navController.viewControllers mutableCopy];

        LinkedDevicesTableViewController *linkedDevicesVC = [LinkedDevicesTableViewController new];
        [viewControllers addObject:linkedDevicesVC];

        OWSLinkDeviceViewController *linkDeviceVC = [OWSLinkDeviceViewController new];
        [viewControllers addObject:linkDeviceVC];

        linkDeviceVC.delegate = linkedDevicesVC;

        [navController setViewControllers:viewControllers animated:NO];

        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [rootViewController presentFormSheetViewController:navController
                                                                                                 animated:NO
                                                                                               completion:^ {}];
                                                   }];
        } else {
            [rootViewController presentFormSheetViewController:navController animated:NO completion:^ {}];
        }

        [linkDeviceVC provisionWithConfirmationWithParser:parser];
    });
    return YES;
}

- (BOOL)tryToShowGroupInviteLinkUI:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (AppReadiness.isAppReady && !self.tsAccountManager.isRegistered) {
        OWSFailDebug(@"Ignoring URL; not registered.");
        return NO;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring sticker pack URL; not registered.");
            return;
        }

        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [GroupInviteLinksUI openGroupInviteLink:url
                                                                            fromViewController:rootViewController];
                                                   }];
        } else {
            [GroupInviteLinksUI openGroupInviteLink:url fromViewController:rootViewController];
        }
    });
    return YES;
}

- (BOOL)tryToShowProxyLinkUI:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        ProxyLinkSheetViewController *proxySheet = [[ProxyLinkSheetViewController alloc] initWithUrl:url];
        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [rootViewController presentViewController:proxySheet
                                                                                        animated:YES
                                                                                      completion:nil];
                                                   }];
        } else {
            [rootViewController presentViewController:proxySheet animated:YES completion:nil];
        }
    });
    return YES;
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

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{ [self handleActivation]; });

    // Clear all notifications whenever we become active.
    // When opening the app from a notification,
    // AppDelegate.didReceiveLocalNotification will always
    // be called _before_ we become active.
    [self clearAllNotificationsAndRestoreBadgeCount];

    // On every activation, clear old temp directories.
    ClearOldTemporaryDirectories();

    // Ensure that all windows have the correct frame.
    [self.windowManager updateWindowFrames];

    OWSLogInfo(@"applicationDidBecomeActive completed.");
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
                OWSLogInfo(@"running post launch block for registered user: %@", [self.tsAccountManager localAddress]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [self.disappearingMessagesJob startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

            });
        } else {
            OWSLogInfo(@"running post launch block for unregistered user.");

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([self.tsAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            [Environment.shared.contactsManagerImpl fetchSystemContactsOnceIfAlreadyAuthorized];

            // TODO: Should we run this immediately even if we would like to process
            // already decrypted envelopes handed to us by the NSE?
            [self.messageFetcherJob runObjc];

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                OWSLogInfo(@"Retrying to register for remote notifications since user hasn't registered yet.");
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                [OWSSyncPushTokensJob run];
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

    OWSLogFlush();
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [self.messageManager updateApplicationBadgeCount];
    });
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

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            ActionSheetController *controller = [[ActionSheetController alloc]
                initWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                      message:NSLocalizedString(@"REGISTRATION_RESTRICTED_MESSAGE", nil)];

            [controller addAction:[[ActionSheetAction alloc] initWithTitle:CommonStrings.okButton
                                                                     style:ActionSheetActionStyleDefault
                                                                   handler:^(ActionSheetAction *_Nonnull action) {

                                                                   }]];
            UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
            [fromViewController presentViewController:controller
                                             animated:YES
                                           completion:^{
                                               completionHandler(NO);
                                           }];
            return;
        }

        [SignalApp.shared showNewConversationView];

        completionHandler(YES);
    });
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
    continueUserActivity:(NSUserActivity *)userActivity
      restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable))restorationHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([userActivity.activityType isEqualToString:@"INSendMessageIntent"]) {
        OWSLogInfo(@"got send message intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INSendMessageIntent class]]) {
            OWSFailDebug(@"unexpected class for send message intent: %@", intent);
            return NO;
        }
        INSendMessageIntent *sendMessageIntent = (INSendMessageIntent *)intent;
        NSString *_Nullable threadUniqueId = sendMessageIntent.conversationIdentifier;
        if (!threadUniqueId) {
            OWSFailDebug(@"Missing thread id for INSendMessageIntent");
            return NO;
        }

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            [SignalApp.shared presentConversationAndScrollToFirstUnreadMessageForThreadId:threadUniqueId animated:NO];
        });
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"]) {
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

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            TSThread *_Nullable thread = [self threadForIntentHandle:handle];
            if (!thread) {
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
            SignalCall *_Nullable currentCall = AppEnvironment.shared.callService.currentCall;
            if (currentCall != nil) {
                if (currentCall.isIndividualCall && [thread.uniqueId isEqual:currentCall.thread.uniqueId]) {
                    OWSLogWarn(@"trying to upgrade ongoing call to video.");
                    [AppEnvironment.shared.callService.individualCallService handleCallKitStartVideo];
                    return;
                } else {
                    OWSLogWarn(@"ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.");
                    return;
                }
            }

            [AppEnvironment.shared.callService initiateCallWithThread:thread isVideo:YES];
        });
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {
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

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            TSThread *_Nullable thread = [self threadForIntentHandle:handle];
            if (!thread) {
                OWSLogWarn(@"ignoring attempt to initiate audio call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.currentCall != nil) {
                OWSLogWarn(@"ignoring INStartAudioCallIntent due to ongoing WebRTC call.");
                return;
            }

            [AppEnvironment.shared.callService initiateCallWithThread:thread isVideo:NO];
        });
        return YES;

    // On iOS 13, all calls triggered from contacts use this intent
    } else if ([userActivity.activityType isEqualToString:@"INStartCallIntent"]) {
        if (@available(iOS 13, *)) {
            OWSLogInfo(@"got start call intent");

            INInteraction *interaction = [userActivity interaction];
            INIntent *intent = interaction.intent;

            if (![intent isKindOfClass:[INStartCallIntent class]]) {
                OWSLogError(@"unexpected class for start call: %@", intent);
                return NO;
            }

            INStartCallIntent *startCallIntent = (INStartCallIntent *)intent;
            NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
            if (!handle) {
                OWSLogWarn(@"unable to find handle in startCallIntent: %@", intent);
                return NO;
            }

            BOOL isVideo = startCallIntent.callCapability == INCallCapabilityVideoCall;

            AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
                if (![self.tsAccountManager isRegisteredAndReady]) {
                    OWSLogInfo(@"Ignoring user activity; app not ready.");
                    return;
                }

                TSThread *_Nullable thread = [self threadForIntentHandle:handle];
                if (!thread) {
                    OWSLogWarn(@"ignoring attempt to initiate call to unknown user.");
                    return;
                }

                if (AppEnvironment.shared.callService.currentCall != nil) {
                    OWSLogWarn(@"ignoring INStartCallIntent due to ongoing WebRTC call.");
                    return;
                }

                [AppEnvironment.shared.callService initiateCallWithThread:thread isVideo:isVideo];
            });
            return YES;
        } else {
            OWSLogError(@"unexpectedly received INStartCallIntent pre iOS13");
            return NO;
        }
    } else if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        if (userActivity.webpageURL == nil) {
            OWSFailDebug(@"Missing webpageURL.");
            return NO;
        }
        return [self tryToOpenUrl:userActivity.webpageURL];
    } else {
        OWSLogWarn(@"userActivity: %@, but not yet supported.", userActivity.activityType);
    }

    return NO;
}

- (nullable TSThread *)threadForIntentHandle:(NSString *)handle
{
    OWSAssertDebug(handle.length > 0);

    if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
        return [CallKitIdStore threadForCallKitId:handle];
    }

    NSData *_Nullable groupId = [CallKitCallManager decodeGroupIdFromIntentHandle:handle];
    if (groupId) {
        __block TSGroupThread *thread = nil;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            thread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
        }];
        return thread;
    }

    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromUserSpecifiedText:handle
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {
        SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber.toE164];
        return [TSContactThread getOrCreateThreadWithContactAddress:address];
    }

    return nil;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window
{
    if (CurrentAppContext().isRunningTests) {
        return UIInterfaceOrientationMaskPortrait;
    }

    if (self.didAppLaunchFail) {
        return UIInterfaceOrientationMaskPortrait;
    }

    if (self.hasCall) {
        OWSLogInfo(@"has call");
        // The call-banner window is only suitable for portrait display on iPhone
        if (!UIDevice.currentDevice.isIPad) {
            return UIInterfaceOrientationMaskPortrait;
        }
    }

    UIViewController *_Nullable rootViewController = self.window.rootViewController;
    if (!rootViewController) {
        return UIDevice.currentDevice.defaultSupportedOrientations;
    }
    return rootViewController.supportedInterfaceOrientations;
}

- (BOOL)hasCall
{
    return CurrentAppContext().hasActiveCall;
}

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (SSKDebugFlags.verboseNotificationLogging) {
        OWSLogInfo(@"didReceiveRemoteNotification w. completion.");
    }

    [self processRemoteNotification:userInfo
                         completion:^{
                             dispatch_after(
                                 dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                     completionHandler(UIBackgroundFetchResultNewData);
                                 });
                         }];
}

- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    OWSLogInfo(@"performing background fetch");
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        [self.messageFetcherJob runObjc].done(^(id value) {
            // HACK: Call completion handler after n seconds.
            //
            // We don't currently have a convenient API to know when message fetching is *done* when
            // working with the websocket.
            //
            // We *could* substantially rewrite the SocketManager to take advantage of the `empty` message
            // But once our REST endpoint is fixed to properly de-enqueue fallback notifications, we can easily
            // use the rest endpoint here rather than the websocket and circumvent making changes to critical code.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completionHandler(UIBackgroundFetchResultNewData);
            });
        });
    });
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"storageIsReady");

    [self checkIfAppIsReady];
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
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

@end
