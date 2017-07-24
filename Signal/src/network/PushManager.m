//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PushManager.h"
#import "AppDelegate.h"
#import "NSData+ows_StripToken.h"
#import "OWSContactsManager.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSMessageReceiver.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSAccountManager.h>
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

@property (nonatomic) TOCFutureSource *registerWithServerFutureSource;
@property (nonatomic) NSMutableArray *currentNotifications;
@property (nonatomic) UIBackgroundTaskIdentifier callBackgroundTask;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSMessageFetcherJob *messageFetcherJob;
@property (nonatomic, readonly) CallUIAdapter *callUIAdapter;

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
    return [self initWithNetworkManager:[Environment getCurrent].networkManager
                         storageManager:[TSStorageManager sharedManager]
                          callUIAdapter:[Environment getCurrent].callService.callUIAdapter
                        messageReceiver:[OWSMessageReceiver sharedInstance]
                          messageSender:[Environment getCurrent].messageSender];
}

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                         callUIAdapter:(CallUIAdapter *)callUIAdapter
                       messageReceiver:(OWSMessageReceiver *)messageReceiver
                         messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callUIAdapter = callUIAdapter;
    _messageSender = messageSender;

    OWSSignalService *signalService = [OWSSignalService sharedInstance];
    _messageFetcherJob = [[OWSMessageFetcherJob alloc] initWithMessageReceiver:messageReceiver
                                                                networkManager:networkManager
                                                                 signalService:signalService];

    _callBackgroundTask = UIBackgroundTaskInvalid;
    _currentNotifications = [NSMutableArray array];

    OWSSingletonAssert();

    return self;
}

#pragma mark Manage Incoming Push

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    [self.messageFetcherJob runAsync];
}

- (void)applicationDidBecomeActive {
    [self.messageFetcherJob runAsync];
}

/**
 *  This code should in principle never be called. The only cases where it would be called are with the old-style
 * "content-available:1" pushes if there is no "voip" token registered
 *
 */

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      completionHandler(UIBackgroundFetchResultNewData);
    });
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
    if (threadId && [TSThread fetchObjectWithUniqueID:threadId]) {
        [Environment messageThreadId:threadId];
    }
}

- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)())completionHandler {
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

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
             completionHandler:(void (^)())completionHandler
{
    DDLogInfo(@"%@ handling action with identifier: %@", self.tag, identifier);

    if ([identifier isEqualToString:Signal_Message_Reply_Identifier]) {
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];

        if (threadId) {
            TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
            NSString *replyText = responseInfo[UIUserNotificationActionResponseTypedTextKey];

            [ThreadUtil sendMessageWithText:replyText
                inThread:thread
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
                        [NSString stringWithFormat:NSLocalizedString(@"NOTIFICATION_SEND_FAILED", nil), [thread name]];
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
            DDLogError(@"%@ missing localIdString.", self.tag);
            return;
        }

        NSUUID *localId = [[NSUUID alloc] initWithUUIDString:localIdString];
        if (!localId) {
            DDLogError(@"%@ localIdString failed to parse as UUID.", self.tag);
            return;
        }

        [self.callUIAdapter answerCallWithLocalId:localId];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsDeclineCall]) {
        NSString *localIdString = notification.userInfo[PushManagerUserInfoKeysLocalCallId];
        if (!localIdString) {
            DDLogError(@"%@ missing localIdString.", self.tag);
            return;
        }

        NSUUID *localId = [[NSUUID alloc] initWithUUIDString:localIdString];
        if (!localId) {
            DDLogError(@"%@ localIdString failed to parse as UUID.", self.tag);
            return;
        }

        [self.callUIAdapter declineCallWithLocalId:localId];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsCallBack]) {
        NSString *recipientId = notification.userInfo[PushManagerUserInfoKeysCallBackSignalRecipientId];
        if (!recipientId) {
            DDLogError(@"%@ missing call back id", self.tag);
            return;
        }

        [self.callUIAdapter startAndShowOutgoingCallWithRecipientId:recipientId];
        completionHandler();
    } else if ([identifier isEqualToString:PushManagerActionsShowThread]) {
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        [Environment messageThreadId:threadId];
        completionHandler();
    } else {
        OWSFail(@"%@ Unhandled action with identifier: %@", self.tag, identifier);
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        [Environment messageThreadId:threadId];
        completionHandler();
    }
}

- (void)markAllInThreadAsRead:(NSDictionary *)userInfo completionHandler:(void (^)())completionHandler {
    NSString *threadId = userInfo[Signal_Thread_UserInfo_Key];

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    [[TSStorageManager sharedManager].dbReadWriteConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            // TODO: I suspect we only want to mark the message in
            // question as read.
            [thread markAllAsReadWithTransaction:transaction];
        }
        completionBlock:^{
            [[[Environment getCurrent] signalsViewController] updateInboxCountLabel];
            [self cancelNotificationsWithThreadId:threadId];

            completionHandler();
        }];
}

#pragma mark PushKit

- (void)pushRegistry:(PKPushRegistry *)registry
    didUpdatePushCredentials:(PKPushCredentials *)credentials
                     forType:(NSString *)type {
    [[PushManager sharedManager].pushKitNotificationFutureSource trySetResult:[credentials.token ows_tripToken]];
}

- (void)pushRegistry:(PKPushRegistry *)registry
    didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
                              forType:(NSString *)type {

    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:payload.dictionaryPayload];
}

- (TOCFuture *)registerPushKitNotificationFuture {
    if ([self supportsVOIPPush]) {
        self.pushKitNotificationFutureSource = [TOCFutureSource new];
        PKPushRegistry *voipRegistry         = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
        voipRegistry.delegate                = self;
        voipRegistry.desiredPushTypes        = [NSSet setWithObject:PKPushTypeVoIP];
        return self.pushKitNotificationFutureSource.future;
    } else {
        TOCFutureSource *futureSource = [TOCFutureSource new];
        [futureSource trySetResult:nil];
        [Environment.preferences setHasRegisteredVOIPPush:FALSE];
        return futureSource.future;
    }
}

- (BOOL)supportsVOIPPush {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(8, 2)) {
        return YES;
    } else {
        return NO;
    }
}

#pragma mark Register device for Push Notification locally

- (TOCFuture *)registerPushNotificationFuture {
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerForRemoteNotifications];
    return self.pushNotificationFutureSource.future;
}

- (void)requestPushTokenWithSuccess:(pushTokensSuccessBlock)success failure:(failedPushRegistrationBlock)failure {
    if (!self.wantRemoteNotifications) {
        DDLogWarn(@"%@ Using fake push tokens", self.tag);
        success(@"fakePushToken", @"fakeVoipToken");
        return;
    }

    TOCFuture *requestPushTokenFuture = [self registerPushNotificationFuture];

    [requestPushTokenFuture thenDo:^(NSData *pushTokenData) {
      NSString *pushToken = [pushTokenData ows_tripToken];
      TOCFuture *pushKit  = [self registerPushKitNotificationFuture];

      [pushKit thenDo:^(NSString *voipToken) {
        success(pushToken, voipToken);
      }];

      [pushKit catchDo:^(NSError *error) {
        failure(error);
      }];
    }];

    [requestPushTokenFuture catchDo:^(NSError *error) {
      failure(error);
    }];
}

- (UIUserNotificationCategory *)fullNewMessageNotificationCategory {
    UIMutableUserNotificationAction *action_markRead = [self markAsReadAction];

    UIMutableUserNotificationAction *action_reply = [UIMutableUserNotificationAction new];
    action_reply.identifier                       = Signal_Message_Reply_Identifier;
    action_reply.title                            = NSLocalizedString(@"PUSH_MANAGER_REPLY", @"");
    action_reply.destructive                      = NO;
    action_reply.authenticationRequired           = NO;
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        action_reply.behavior       = UIUserNotificationActionBehaviorTextInput;
        action_reply.activationMode = UIUserNotificationActivationModeBackground;
    } else {
        action_reply.activationMode = UIUserNotificationActivationModeForeground;
    }

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

- (BOOL)wantRemoteNotifications {
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else
    return YES;
#endif
}

- (int)allNotificationTypes {
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
}

- (void)validateUserNotificationSettings
{
    UIUserNotificationSettings *settings = [UIUserNotificationSettings
        settingsForTypes:(UIUserNotificationType)[self allNotificationTypes]
              categories:[NSSet setWithObjects:[self fullNewMessageNotificationCategory],
                                [self fullNewMessageNoLongerVerifiedNotificationCategory],
                                [self signalIncomingCallCategory],
                                [self signalMissedCallCategory],
                                [self signalMissedCallWithNoLongerVerifiedIdentityChangeCategory],
                                nil]];

    [UIApplication.sharedApplication registerUserNotificationSettings:settings];
}

- (BOOL)applicationIsActive {
    UIApplication *app = [UIApplication sharedApplication];

    if (app.applicationState == UIApplicationStateActive) {
        return YES;
    }

    return NO;
}

- (void)presentNotification:(UILocalNotification *)notification checkForCancel:(BOOL)checkForCancel
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        if (checkForCancel && threadId != nil) {
            // The longer we wait, the more obsolete notifications we can suppress -
            // but the more lag we introduce to notification delivery.
            const CGFloat kDelaySeconds = 0.5f;
            notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:kDelaySeconds];
            notification.timeZone = [NSTimeZone localTimeZone];
        }

        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
        [self.currentNotifications addObject:notification];
    });
}

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

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
