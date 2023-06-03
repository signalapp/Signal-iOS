//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AppDelegate.h"
#import "ChatListViewController.h"
#import "Signal-Swift.h"
#import <Intents/Intents.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/CallKitIdStore.h>
#import <SignalServiceKit/DarwinNotificationCenter.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StickerInfo.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalUI/ViewControllerUtils.h>
#import <UserNotifications/UserNotifications.h>
#import <WebRTC/WebRTC.h>

NSString *const AppDelegateStoryboardMain = @"Main";
NSString *const kAppLaunchesAttemptedKey = @"AppLaunchesAttempted";

NSString *const kURLSchemeSGNLKey = @"sgnl";
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

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [self applicationWillEnterForegroundSwift:application];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [self applicationDidBecomeActiveSwift:application];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [self applicationWillResignActiveSwift:application];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self applicationDidEnterBackgroundSwift:application];
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    return [self applicationSwift:application supportedInterfaceOrientationsFor:window];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidReceiveMemoryWarning.");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillTerminate.");
    OWSLogFlush();
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    [self handleDidFinishLaunchingWithLaunchOptions:launchOptions];
    return YES;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSLogError(@"App launch failed");
        return;
    }

    OWSLogInfo(@"registered vanilla push token");
    [self.pushRegistrationManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSLogError(@"App launch failed");
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

    return [self handleOpenUrl:url];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSLogError(@"App launch failed");
        completionHandler(NO);
        return;
    }

    AppReadinessRunNowOrWhenUIDidBecomeReadySync(^{
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
        OWSLogError(@"App launch failed");
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
        return [self handleOpenUrl:userActivity.webpageURL];
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

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (SSKDebugFlags.verboseNotificationLogging) {
        OWSLogInfo(@"didReceiveRemoteNotification w. completion.");
    }

    // Mark down that the APNS token is working because we got a push.
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [APNSRotationStore didReceiveAPNSPushWithTransaction:transaction];
        });
    });

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

@end
