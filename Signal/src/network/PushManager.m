//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "PushManager.h"
#import "AppDelegate.h"
#import "NotificationsManager.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "ThreadUtil.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSString+SSK.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSMessageReceiver.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSSocketManager.h>

NSString *const Signal_Thread_UserInfo_Key = @"Signal_Thread_Id";
NSString *const Signal_Message_UserInfo_Key = @"Signal_Message_Id";

NSString *const Signal_Full_New_Message_Category = @"Signal_Full_New_Message";
NSString *const Signal_Full_New_Message_Category_No_Longer_Verified =
    @"Signal_Full_New_Message_Category_No_Longer_Verified";

NSString *const Signal_Message_Reply_Identifier = @"Signal_New_Message_Reply";
NSString *const Signal_Message_MarkAsRead_Identifier = @"Signal_Message_MarkAsRead";

@interface PushManager ()

@property (nonatomic) NSMutableArray *currentNotifications;
@property (nonatomic) UIBackgroundTaskIdentifier callBackgroundTask;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSMessageFetcherJob *messageFetcherJob;
@property (nonatomic, readonly) NotificationsManager *notificationsManager;

@end

@implementation PushManager

+ (instancetype)sharedManager {
    static PushManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initDefault];
    });
    return sharedManager;
}

- (instancetype)initDefault
{
    return [self initWithMessageFetcherJob:SignalApp.sharedApp.messageFetcherJob
                            primaryStorage:[OWSPrimaryStorage sharedManager]
                             messageSender:[Environment current].messageSender
                      notificationsManager:SignalApp.sharedApp.notificationsManager];
}

- (instancetype)initWithMessageFetcherJob:(OWSMessageFetcherJob *)messageFetcherJob
                           primaryStorage:(OWSPrimaryStorage *)primaryStorage
                            messageSender:(OWSMessageSender *)messageSender
                     notificationsManager:(NotificationsManager *)notificationsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _messageSender = messageSender;
    _messageFetcherJob = messageFetcherJob;
    _callBackgroundTask = UIBackgroundTaskInvalid;
    // TODO: consolidate notification tracking with NotificationsManager, which also maintains a list of notifications.
    _currentNotifications = [NSMutableArray array];
    _notificationsManager = notificationsManager;

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMessageRead:)
                                                 name:kIncomingMessageMarkedAsReadNotification
                                               object:nil];

    return self;
}

- (CallUIAdapter *)callUIAdapter
{
    return SignalApp.sharedApp.callService.callUIAdapter;
}

- (void)handleMessageRead:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if ([notification.object isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *message = (TSIncomingMessage *)notification.object;

        DDLogDebug(@"%@ canceled notification for message:%@", self.logTag, message);
        [self cancelNotificationsWithThreadId:message.uniqueThreadId];
    }
}

#pragma mark Manage Incoming Push

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    DDLogInfo(@"%@ received remote notification", self.logTag);

    [AppReadiness runNowOrWhenAppIsReady:^{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-result"
        [self.messageFetcherJob run];
#pragma GCC diagnostic pop
    }];
}

- (void)applicationDidBecomeActive {
    [AppReadiness runNowOrWhenAppIsReady:^{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-result"
        [self.messageFetcherJob run];
#pragma GCC diagnostic pop
    }];
}

/**
 *  This code should in principle never be called. The only cases where it would be called are with the old-style
 * "content-available:1" pushes if there is no "voip" token registered
 *
 */
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    DDLogInfo(@"%@ received content-available push", self.logTag);

    // If we want to re-introduce silent pushes we can remove this assert.
    OWSFail(@"Unexpected content-available push.");

    [AppReadiness runNowOrWhenAppIsReady:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            completionHandler(UIBackgroundFetchResultNewData);
        });
    }];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    OWSAssertIsOnMainThread();
    DDLogInfo(@"%@ launched from local notification", self.logTag);

    NSString *_Nullable threadId = notification.userInfo[Signal_Thread_UserInfo_Key];

    if (threadId) {
        [SignalApp.sharedApp presentConversationForThreadId:threadId];
    } else {
        OWSFail(@"%@ threadId was unexpectedly nil in %s", self.logTag, __PRETTY_FUNCTION__);
    }

    // We only want to receive a single local notification per launch.
    [application cancelAllLocalNotifications];
    [self.currentNotifications removeAllObjects];
    [self.notificationsManager clearAllNotifications];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)(void))completionHandler
{
    DDLogInfo(@"%@ in %s", self.logTag, __FUNCTION__);

    [self application:application
        handleActionWithIdentifier:identifier
              forLocalNotification:notification
                  withResponseInfo:@{}
                 completionHandler:completionHandler];
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)(void))completionHandler
{
    DDLogInfo(@"%@ handling action with identifier: %@", self.logTag, identifier);

    if ([identifier isEqualToString:Signal_Message_Reply_Identifier]) {
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];

        if (threadId) {
            TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
            NSString *replyText = responseInfo[UIUserNotificationActionResponseTypedTextKey];

            // In line with most apps, we send a normal outgoing messgae here - not a "quoted reply".
            [ThreadUtil sendMessageWithText:replyText
                inThread:thread
                quotedReplyModel:nil
                messageSender:self.messageSender
                success:^{
                    // TODO do we really want to mark them all as read?
                    [self markAllInThreadAsRead:notification.userInfo completionHandler:completionHandler];
                }
                failure:^(NSError *_Nonnull error) {
                    // TODO Surface the specific error in the notification?
                    DDLogError(@"Message send failed with error: %@", error);

                    UILocalNotification *failedSendNotif = [[UILocalNotification alloc] init];
                    failedSendNotif.alertBody =
                        [NSString stringWithFormat:NSLocalizedString(@"NOTIFICATION_SEND_FAILED", nil), [thread name]]
                            .filterStringForDisplay;
                    failedSendNotif.userInfo = @{ Signal_Thread_UserInfo_Key : thread.uniqueId };
                    [self presentNotification:failedSendNotif checkForCancel:NO];
                    completionHandler();
                }];
        }
    } else if ([identifier isEqualToString:Signal_Message_MarkAsRead_Identifier]) {
        // TODO mark all as read? Or just this one?
        [self markAllInThreadAsRead:notification.userInfo completionHandler:completionHandler];
    } else if ([identifier isEqualToString:PushManagerActionsAcceptCall]) {
        NSString *localIdString = notification.userInfo[PushManagerUserInfoKeysLocalCallId];
        if (!localIdString) {
            DDLogError(@"%@ missing localIdString.", self.logTag);
            return;
        }

        NSUUID *localId = [[NSUUID alloc] initWithUUIDString:localIdString];
        if (!localId) {
            DDLogError(@"%@ localIdString failed to parse as UUID.", self.logTag);
            return;
        }

        [self.callUIAdapter answerCallWithLocalId:localId];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsDeclineCall]) {
        NSString *localIdString = notification.userInfo[PushManagerUserInfoKeysLocalCallId];
        if (!localIdString) {
            DDLogError(@"%@ missing localIdString.", self.logTag);
            return;
        }

        NSUUID *localId = [[NSUUID alloc] initWithUUIDString:localIdString];
        if (!localId) {
            DDLogError(@"%@ localIdString failed to parse as UUID.", self.logTag);
            return;
        }

        [self.callUIAdapter declineCallWithLocalId:localId];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsCallBack]) {
        NSString *recipientId = notification.userInfo[PushManagerUserInfoKeysCallBackSignalRecipientId];
        if (!recipientId) {
            DDLogError(@"%@ missing call back id", self.logTag);
            return;
        }

        [self.callUIAdapter startAndShowOutgoingCallWithRecipientId:recipientId hasLocalVideo:NO];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsShowThread]) {
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];

        if (threadId) {
            [SignalApp.sharedApp presentConversationForThreadId:threadId];
        } else {
            OWSFail(@"%@ threadId was unexpectedly nil in action with identifier: %@", self.logTag, identifier);
        }
        completionHandler();
    } else {
        OWSFail(@"%@ Unhandled action with identifier: %@", self.logTag, identifier);
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        if (threadId) {
            [SignalApp.sharedApp presentConversationForThreadId:threadId];
        } else {
            OWSFail(@"%@ threadId was unexpectedly nil in action with identifier: %@", self.logTag, identifier);
        }
        completionHandler();
    }
}

- (void)markAllInThreadAsRead:(NSDictionary *)userInfo completionHandler:(void (^)(void))completionHandler
{
    NSString *threadId = userInfo[Signal_Thread_UserInfo_Key];
    if (!threadId) {
        OWSProdLogAndFail(@"%@ missing thread id for notification.", self.logTag);
        return;
    }

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    [OWSPrimaryStorage.dbReadWriteConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            // TODO: I suspect we only want to mark the message in
            // question as read.
            [thread markAllAsReadWithTransaction:transaction];
        }
        completionBlock:^{
            [self cancelNotificationsWithThreadId:threadId];

            completionHandler();
        }];
}

- (UIUserNotificationCategory *)fullNewMessageNotificationCategory {
    UIMutableUserNotificationAction *action_markRead = [self markAsReadAction];

    UIMutableUserNotificationAction *action_reply = [UIMutableUserNotificationAction new];
    action_reply.identifier                       = Signal_Message_Reply_Identifier;
    action_reply.title                            = NSLocalizedString(@"PUSH_MANAGER_REPLY", @"");
    action_reply.destructive                      = NO;
    action_reply.authenticationRequired           = NO;
    action_reply.behavior = UIUserNotificationActionBehaviorTextInput;
    action_reply.activationMode = UIUserNotificationActivationModeBackground;

    UIMutableUserNotificationCategory *messageCategory = [UIMutableUserNotificationCategory new];
    messageCategory.identifier                         = Signal_Full_New_Message_Category;
    [messageCategory setActions:@[ action_markRead, action_reply ] forContext:UIUserNotificationActionContextMinimal];
    [messageCategory setActions:@[ action_markRead, action_reply ] forContext:UIUserNotificationActionContextDefault];

    return messageCategory;
}

- (UIUserNotificationCategory *)fullNewMessageNoLongerVerifiedNotificationCategory
{
    UIMutableUserNotificationAction *action_markRead = [self markAsReadAction];

    UIMutableUserNotificationCategory *messageCategory = [UIMutableUserNotificationCategory new];
    messageCategory.identifier = Signal_Full_New_Message_Category_No_Longer_Verified;
    [messageCategory setActions:@[ action_markRead ] forContext:UIUserNotificationActionContextMinimal];
    [messageCategory setActions:@[ action_markRead ] forContext:UIUserNotificationActionContextDefault];

    return messageCategory;
}

- (UIMutableUserNotificationAction *)markAsReadAction
{
    UIMutableUserNotificationAction *action = [UIMutableUserNotificationAction new];
    action.identifier = Signal_Message_MarkAsRead_Identifier;
    action.title = NSLocalizedString(@"PUSH_MANAGER_MARKREAD", nil);
    action.destructive = NO;
    action.authenticationRequired = NO;
    action.activationMode = UIUserNotificationActivationModeBackground;
    return action;
}

#pragma mark - Signal Calls

NSString *const PushManagerCategoriesIncomingCall = @"PushManagerCategoriesIncomingCall";
NSString *const PushManagerCategoriesMissedCall = @"PushManagerCategoriesMissedCall";
NSString *const PushManagerCategoriesMissedCallFromNoLongerVerifiedIdentity =
    @"PushManagerCategoriesMissedCallFromNoLongerVerifiedIdentity";

NSString *const PushManagerActionsAcceptCall = @"PushManagerActionsAcceptCall";
NSString *const PushManagerActionsDeclineCall = @"PushManagerActionsDeclineCall";
NSString *const PushManagerActionsCallBack = @"PushManagerActionsCallBack";
NSString *const PushManagerActionsIgnoreIdentityChangeAndCallBack =
    @"PushManagerActionsIgnoreIdentityChangeAndCallBack";
NSString *const PushManagerActionsShowThread = @"PushManagerActionsShowThread";

NSString *const PushManagerUserInfoKeysLocalCallId = @"PushManagerUserInfoKeysLocalCallId";
NSString *const PushManagerUserInfoKeysCallBackSignalRecipientId = @"PushManagerUserInfoKeysCallBackSignalRecipientId";

- (UIUserNotificationCategory *)signalIncomingCallCategory
{
    UIMutableUserNotificationAction *acceptAction = [UIMutableUserNotificationAction new];
    acceptAction.identifier = PushManagerActionsAcceptCall;
    acceptAction.title = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    acceptAction.activationMode = UIUserNotificationActivationModeForeground;
    acceptAction.destructive = NO;
    acceptAction.authenticationRequired = NO;

    UIMutableUserNotificationAction *declineAction = [UIMutableUserNotificationAction new];
    declineAction.identifier = PushManagerActionsDeclineCall;
    declineAction.title = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
    declineAction.activationMode = UIUserNotificationActivationModeBackground;
    declineAction.destructive = NO;
    declineAction.authenticationRequired = NO;

    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier = PushManagerCategoriesIncomingCall;
    [callCategory setActions:@[ acceptAction, declineAction ] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[ acceptAction, declineAction ] forContext:UIUserNotificationActionContextDefault];

    return callCategory;
}

- (UIUserNotificationCategory *)signalMissedCallCategory
{
    UIMutableUserNotificationAction *callBackAction = [UIMutableUserNotificationAction new];
    callBackAction.identifier = PushManagerActionsCallBack;
    callBackAction.title = [CallStrings callBackButtonTitle];
    callBackAction.activationMode = UIUserNotificationActivationModeForeground;
    callBackAction.destructive = NO;
    callBackAction.authenticationRequired = YES;

    UIMutableUserNotificationCategory *missedCallCategory = [UIMutableUserNotificationCategory new];
    missedCallCategory.identifier = PushManagerCategoriesMissedCall;
    [missedCallCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextMinimal];
    [missedCallCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextDefault];

    return missedCallCategory;
}

- (UIUserNotificationCategory *)signalMissedCallWithNoLongerVerifiedIdentityChangeCategory
{

    UIMutableUserNotificationAction *showThreadAction = [UIMutableUserNotificationAction new];
    showThreadAction.identifier = PushManagerActionsShowThread;
    showThreadAction.title = [CallStrings showThreadButtonTitle];
    showThreadAction.activationMode = UIUserNotificationActivationModeForeground;
    showThreadAction.destructive = NO;
    showThreadAction.authenticationRequired = YES;

    UIMutableUserNotificationCategory *rejectedCallCategory = [UIMutableUserNotificationCategory new];
    rejectedCallCategory.identifier = PushManagerCategoriesMissedCallFromNoLongerVerifiedIdentity;
    [rejectedCallCategory setActions:@[ showThreadAction ] forContext:UIUserNotificationActionContextMinimal];
    [rejectedCallCategory setActions:@[ showThreadAction ] forContext:UIUserNotificationActionContextDefault];

    return rejectedCallCategory;
}

#pragma mark Util

- (int)allNotificationTypes {
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
}

- (UIUserNotificationSettings *)userNotificationSettings
{
    DDLogDebug(@"%@ registering user notification settings", self.logTag);
    UIUserNotificationSettings *settings = [UIUserNotificationSettings
        settingsForTypes:(UIUserNotificationType)[self allNotificationTypes]
              categories:[NSSet setWithObjects:[self fullNewMessageNotificationCategory],
                                [self fullNewMessageNoLongerVerifiedNotificationCategory],
                                [self signalIncomingCallCategory],
                                [self signalMissedCallCategory],
                                [self signalMissedCallWithNoLongerVerifiedIdentityChangeCategory],
                                nil]];

    return settings;
}

- (BOOL)applicationIsActive {
    UIApplication *app = [UIApplication sharedApplication];

    if (app.applicationState == UIApplicationStateActive) {
        return YES;
    }

    return NO;
}

// TODO: consolidate notification tracking with NotificationsManager, which also maintains a list of notifications.
- (void)presentNotification:(UILocalNotification *)notification checkForCancel:(BOOL)checkForCancel
{
    notification.alertBody = notification.alertBody.filterStringForDisplay;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        if (checkForCancel && threadId != nil) {
            if ([[OWSDeviceManager sharedManager] hasReceivedSyncMessageInLastSeconds:60.f]) {
                // "If you’ve heard from desktop in last minute, wait 5 seconds."
                //
                // This provides a window in which we can cancel notifications
                // already viewed on desktop before they are presented here.
                const CGFloat kDelaySeconds = 5.f;
                notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:kDelaySeconds];
            } else {
                notification.fireDate = [NSDate new];
            }

            notification.timeZone = [NSTimeZone localTimeZone];
        }

        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        [self.currentNotifications addObject:notification];
    });
}

// TODO: consolidate notification tracking with NotificationsManager, which also maintains a list of notifications.
- (void)cancelNotificationsWithThreadId:(NSString *)threadId
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *toDelete = [NSMutableArray array];
        [self.currentNotifications
            enumerateObjectsUsingBlock:^(UILocalNotification *notif, NSUInteger idx, BOOL *stop) {
                if ([notif.userInfo[Signal_Thread_UserInfo_Key] isEqualToString:threadId]) {
                    [[UIApplication sharedApplication] cancelLocalNotification:notif];
                    [toDelete addObject:notif];
                }
            }];
        [self.currentNotifications removeObjectsInArray:toDelete];
    });
}

@end
