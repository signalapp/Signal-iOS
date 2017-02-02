//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "PushManager.h"
#import "AppDelegate.h"
#import "InCallViewController.h"
#import "NSData+ows_StripToken.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NotificationTracker.h"
#import "OWSContactsManager.h"
#import "PropertyListPreferences.h"
#import "RPServerRequestsManager.h"
#import "Signal-Swift.h"
#import "TSMessagesManager.h"
#import "TSAccountManager.h"
#import "TSOutgoingMessage.h"
#import "TSSocketManager.h"
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSSignalService.h>

#define pushManagerDomain @"org.whispersystems.pushmanager"

@interface PushManager ()

@property TOCFutureSource *registerWithServerFutureSource;
@property UIAlertView *missingPermissionsAlertView;
@property (nonatomic, strong) NotificationTracker *notificationTracker;
@property UILocalNotification *lastCallNotification;
@property (nonatomic, retain) NSMutableArray *currentNotifications;
@property (nonatomic) UIBackgroundTaskIdentifier callBackgroundTask;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
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
    return [self initWithContactsManager:[Environment getCurrent].contactsManager
                     notificationTracker:[NotificationTracker notificationTracker]
                          networkManager:[Environment getCurrent].networkManager
                          storageManager:[TSStorageManager sharedManager]
                      callMessageHandler:[Environment getCurrent].callMessageHandler
                             callService:[Environment getCurrent].callService
                         contactsUpdater:[Environment getCurrent].contactsUpdater];
}

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                    notificationTracker:(NotificationTracker *)notificationTracker
                         networkManager:(TSNetworkManager *)networkManager
                         storageManager:(TSStorageManager *)storageManager
                     callMessageHandler:(OWSWebRTCCallMessageHandler *)callMessageHandler
                            callService:(CallService *)callService
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = contactsManager;
    _callUIAdapter = callService.callUIAdapter;

    // DEPRECATED Redphone uses notification tracker.
    _notificationTracker = notificationTracker;
    _messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                       storageManager:storageManager
                                                      contactsManager:contactsManager
                                                      contactsUpdater:contactsUpdater];

    TSMessagesManager *messagesManager = [[TSMessagesManager alloc] initWithNetworkManager:networkManager
                                                                            storageManager:storageManager
                                                                        callMessageHandler:callMessageHandler
                                                                           contactsManager:contactsManager
                                                                           contactsUpdater:contactsUpdater
                                                                             messageSender:_messageSender];

    OWSSignalService *signalService = [OWSSignalService new];
    _messageFetcherJob = [[OWSMessageFetcherJob alloc] initWithMessagesManager:messagesManager
                                                                 messageSender:_messageSender
                                                                networkManager:networkManager
                                                                 signalService:signalService];

    _missingPermissionsAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                              message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                                             delegate:nil
                                                    cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                    otherButtonTitles:nil, nil];
    _callBackgroundTask = UIBackgroundTaskInvalid;
    _currentNotifications = [NSMutableArray array];

    return self;
}

#pragma mark Manage Incoming Push

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    // DEPRECATED redphone
    if ([self isRedPhonePush:userInfo]) {
        ResponderSessionDescriptor *call;
        if (![self.notificationTracker shouldProcessNotification:userInfo]) {
            return;
        }

        @try {
            call = [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:userInfo];
            DDLogDebug(@"Received remote notification. Parsed session descriptor: %@.", call);
        } @catch (OperationFailed *ex) {
            DDLogError(@"Error parsing remote notification. Error: %@.", ex);
            return;
        }

        if (!call) {
            DDLogError(@"Decryption of session descriptor failed");
            return;
        }

        [Environment.phoneManager incomingCallWithSession:call];

        if (![self applicationIsActive]) {
            UILocalNotification *notification = [[UILocalNotification alloc] init];

            NSString *callerId   = call.initiatorNumber.toE164;
            NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:callerId];
            PropertyListPreferences *prefs = [Environment preferences];

            notification.alertBody = @"☎️ ";

            if ([prefs notificationPreviewType] == NotificationNoNameNoPreview) {
                notification.alertBody =
                    [notification.alertBody stringByAppendingString:NSLocalizedString(@"INCOMING_CALL", nil)];
            } else {
                notification.alertBody = [notification.alertBody
                    stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"INCOMING_CALL_FROM", nil),
                                                                       displayName]];
            }

            notification.category  = Signal_Call_Category;
            notification.soundName = @"r.caf";

            [self presentNotification:notification];
            _lastCallNotification = notification;

            if (_callBackgroundTask == UIBackgroundTaskInvalid) {
                _callBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                  [Environment.phoneManager backgroundTimeExpired];
                  [self closeVOIPBackgroundTask];
                }];
            }
        }
    } else {
        [self.messageFetcherJob runAsync];
    }
}

- (void)applicationDidBecomeActive {
    [self.messageFetcherJob runAsync];
}

- (UILocalNotification *)closeVOIPBackgroundTask {
    [[UIApplication sharedApplication] endBackgroundTask:_callBackgroundTask];
    _callBackgroundTask = UIBackgroundTaskInvalid;

    UILocalNotification *notif = _lastCallNotification;
    _lastCallNotification      = nil;

    return notif;
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

    if ([self isRedPhonePush:userInfo]) {
        [self application:application didReceiveRemoteNotification:userInfo];
    }

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
    DDLogInfo(@"received: %s", __PRETTY_FUNCTION__);

    if ([identifier isEqualToString:Signal_Message_Reply_Identifier]) {
        DDLogInfo(@"%@ received reply identifier", self.tag);
        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];

        if (threadId) {
            TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
            TSOutgoingMessage *message =
                [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                    inThread:thread
                                                 messageBody:responseInfo[UIUserNotificationActionResponseTypedTextKey]];
            [self.messageSender sendMessage:message
                success:^{
                    [self markAllInThreadAsRead:notification.userInfo completionHandler:completionHandler];
                    [[[[Environment getCurrent] signalsViewController] tableView] reloadData];
                }
                failure:^(NSError *error) {
                    // TODO Surface the specific error in the notification?
                    DDLogError(@"Message send failed with error: %@", error);

                    UILocalNotification *failedSendNotif = [[UILocalNotification alloc] init];
                    failedSendNotif.alertBody =
                        [NSString stringWithFormat:NSLocalizedString(@"NOTIFICATION_SEND_FAILED", nil), [thread name]];
                    failedSendNotif.userInfo = @{ Signal_Thread_UserInfo_Key : thread.uniqueId };
                    [self presentNotification:failedSendNotif];
                    completionHandler();
                }];
        }
    } else if ([identifier isEqualToString:Signal_Call_Accept_Identifier]) {
        DDLogInfo(@"%@ received redphone accept action", self.tag);
        [Environment.phoneManager answerCall];

        completionHandler();
    } else if ([identifier isEqualToString:Signal_Call_Decline_Identifier]) {
        DDLogInfo(@"%@ received redphone decline action", self.tag);
        [Environment.phoneManager hangupOrDenyCall];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
          completionHandler();
        });
    } else if ([identifier isEqualToString:Signal_CallBack_Identifier]) {
        DDLogInfo(@"%@ received redphone callback action", self.tag);
        NSString *contactId = notification.userInfo[Signal_Call_UserInfo_Key];
        PhoneNumber *number = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:contactId];
        Contact *contact = [self.contactsManager latestContactForPhoneNumber:number];
        [Environment.phoneManager initiateOutgoingCallToContact:contact atRemoteNumber:number];
    } else if ([identifier isEqualToString:Signal_Message_MarkAsRead_Identifier]) {
        [self markAllInThreadAsRead:notification.userInfo completionHandler:completionHandler];
    } else if ([identifier isEqualToString:PushManagerActionsAcceptCall]) {
        DDLogInfo(@"%@ received accept call action", self.tag);

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
    } else if ([identifier isEqualToString:PushManagerActionsDeclineCall]) {
        DDLogInfo(@"%@ received decline call action", self.tag);

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
    } else if ([identifier isEqualToString:PushManagerActionsCallBack]) {
        DDLogInfo(@"%@ received call back action", self.tag);

        NSString *recipientId = notification.userInfo[PushManagerUserInfoKeysCallBackSignalRecipientId];
        if (!recipientId) {
            DDLogError(@"%@ missing call back id", self.tag);
            return;
        }

        [self.callUIAdapter startAndShowOutgoingCallWithRecipientId:recipientId];
    } else {
        DDLogDebug(@"%@ Unhandled action with identifier: %@", self.tag, identifier);

        NSString *threadId = notification.userInfo[Signal_Thread_UserInfo_Key];
        [Environment messageThreadId:threadId];
        completionHandler();
    }
}

- (void)markAllInThreadAsRead:(NSDictionary *)userInfo completionHandler:(void (^)())completionHandler {
    NSString *threadId = userInfo[Signal_Thread_UserInfo_Key];

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    [[TSStorageManager sharedManager]
            .dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
      [thread markAllAsReadWithTransaction:transaction];
    }
        completionBlock:^{
          [[[Environment getCurrent] signalsViewController] updateInboxCountLabel];
          [self cancelNotificationsWithThreadId:threadId];

          completionHandler();
        }];
}

- (BOOL)isRedPhonePush:(NSDictionary *)pushDict {
    NSDictionary *aps  = pushDict[@"aps"];
    NSString *category = aps[@"category"];

    if ([category isEqualToString:Signal_Call_Category]) {
        return YES;
    } else {
        return NO;
    }
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
    UIMutableUserNotificationAction *action_markRead = [UIMutableUserNotificationAction new];
    action_markRead.identifier                       = Signal_Message_MarkAsRead_Identifier;
    action_markRead.title                            = NSLocalizedString(@"PUSH_MANAGER_MARKREAD", nil);
    action_markRead.destructive                      = NO;
    action_markRead.authenticationRequired           = NO;
    action_markRead.activationMode                   = UIUserNotificationActivationModeBackground;

    UIMutableUserNotificationAction *action_reply = [UIMutableUserNotificationAction new];
    action_reply.identifier                       = Signal_Message_Reply_Identifier;
    action_reply.title                            = NSLocalizedString(@"PUSH_MANAGER_REPLY", @"");
    action_reply.destructive                      = NO;
    action_reply.authenticationRequired           = NO; // Since YES is broken in iOS 9 GM
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        action_reply.behavior       = UIUserNotificationActionBehaviorTextInput;
        action_reply.activationMode = UIUserNotificationActivationModeBackground;
    } else {
        action_reply.activationMode = UIUserNotificationActivationModeForeground;
    }

    UIMutableUserNotificationCategory *messageCategory = [UIMutableUserNotificationCategory new];
    messageCategory.identifier                         = Signal_Full_New_Message_Category;
    [messageCategory setActions:@[ action_markRead, action_reply ] forContext:UIUserNotificationActionContextMinimal];
    [messageCategory setActions:@[] forContext:UIUserNotificationActionContextDefault];

    return messageCategory;
}

#pragma mark Redphone Calls

- (UIUserNotificationCategory *)userNotificationsRPCallCategory
{
    UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
    action_accept.identifier                       = Signal_Call_Accept_Identifier;
    action_accept.title                            = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    action_accept.activationMode                   = UIUserNotificationActivationModeForeground;
    action_accept.destructive                      = NO;
    action_accept.authenticationRequired           = NO;

    UIMutableUserNotificationAction *action_decline = [UIMutableUserNotificationAction new];
    action_decline.identifier                       = Signal_Call_Decline_Identifier;
    action_decline.title                            = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
    action_decline.activationMode                   = UIUserNotificationActivationModeBackground;
    action_decline.destructive                      = NO;
    action_decline.authenticationRequired           = NO;

    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier                         = Signal_Call_Category;
    [callCategory setActions:@[ action_accept, action_decline ] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[ action_accept, action_decline ] forContext:UIUserNotificationActionContextDefault];

    return callCategory;
}

- (UIUserNotificationCategory *)userNotificationsRPCallBackCategory
{
    UIMutableUserNotificationAction *callBackAction = [UIMutableUserNotificationAction new];
    callBackAction.identifier                       = Signal_CallBack_Identifier;
    callBackAction.title                            = [CallStrings callBackButtonTitle];
    callBackAction.activationMode                   = UIUserNotificationActivationModeForeground;
    callBackAction.destructive                      = NO;
    callBackAction.authenticationRequired           = NO;

    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier                         = Signal_CallBack_Category;
    [callCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextDefault];

    return callCategory;
}

#pragma mark - Signal Calls

NSString *const PushManagerCategoriesIncomingCall = @"PushManagerCategoriesIncomingCall";
NSString *const PushManagerCategoriesMissedCall = @"PushManagerCategoriesMissedCall";

NSString *const PushManagerActionsAcceptCall = @"PushManagerActionsAcceptCall";
NSString *const PushManagerActionsDeclineCall = @"PushManagerActionsDeclineCall";
NSString *const PushManagerActionsCallBack = @"PushManagerActionsCallBack";

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

    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier = PushManagerCategoriesMissedCall;
    [callCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[ callBackAction ] forContext:UIUserNotificationActionContextDefault];

    return callCategory;
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
    UIUserNotificationSettings *settings =
        [UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)[self allNotificationTypes]
                                          categories:[NSSet setWithObjects:[self userNotificationsRPCallCategory],
                                                            [self fullNewMessageNotificationCategory],
                                                            [self userNotificationsRPCallBackCategory],
                                                            [self signalIncomingCallCategory],
                                                            [self signalMissedCallCategory],
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

- (void)presentNotification:(UILocalNotification *)notification {
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    [self.currentNotifications addObject:notification];
}

- (void)cancelNotificationsWithThreadId:(NSString *)threadId {
    NSMutableArray *toDelete = [NSMutableArray array];
    [self.currentNotifications enumerateObjectsUsingBlock:^(UILocalNotification *notif, NSUInteger idx, BOOL *stop) {
      if ([notif.userInfo[Signal_Thread_UserInfo_Key] isEqualToString:threadId]) {
          [[UIApplication sharedApplication] cancelLocalNotification:notif];
          [toDelete addObject:notif];
      }
    }];
    [self.currentNotifications removeObjectsInArray:toDelete];
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
