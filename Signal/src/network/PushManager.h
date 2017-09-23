//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class UILocalNotification;

extern NSString *const Signal_Thread_UserInfo_Key;
extern NSString *const Signal_Message_UserInfo_Key;

extern NSString *const Signal_Full_New_Message_Category;
extern NSString *const Signal_Full_New_Message_Category_No_Longer_Verified;

extern NSString *const Signal_Message_Reply_Identifier;
extern NSString *const Signal_Message_MarkAsRead_Identifier;

#pragma mark Signal Calls constants

extern NSString *const PushManagerCategoriesIncomingCall;
extern NSString *const PushManagerCategoriesMissedCall;
extern NSString *const PushManagerCategoriesMissedCallFromNoLongerVerifiedIdentity;

extern NSString *const PushManagerActionsAcceptCall;
extern NSString *const PushManagerActionsDeclineCall;
extern NSString *const PushManagerActionsCallBack;
extern NSString *const PushManagerActionsShowThread;

extern NSString *const PushManagerUserInfoKeysCallBackSignalRecipientId;
extern NSString *const PushManagerUserInfoKeysLocalCallId;

typedef void (^failedPushRegistrationBlock)(NSError *error);
typedef void (^pushTokensSuccessBlock)(NSString *pushToken, NSString *voipToken);

/**
 * The Push Manager is responsible for handling received push notifications.
 */
@interface PushManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (PushManager *)sharedManager;

///**
// *  Registers for Users Notifications. By doing this on launch, we are sure that the correct categories of user
// * notifications is registered.
// */
// TODO: move this to sync tokens job?
- (void)validateUserNotificationSettings;


// If checkForCancel is set, the notification will be delayed for
// a moment.  If a relevant cancel notification is received in that window,
// the notification will not be displayed.
- (void)presentNotification:(UILocalNotification *)notification checkForCancel:(BOOL)checkForCancel;
- (void)cancelNotificationsWithThreadId:(NSString *)threadId;

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo;
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
             completionHandler:(void (^)())completionHandler;
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification;
- (void)application:(UIApplication *)application
    handleActionWithIdentifier:(NSString *)identifier
          forLocalNotification:(UILocalNotification *)notification
              withResponseInfo:(NSDictionary *)responseInfo
             completionHandler:(void (^)())completionHandler;
- (void)applicationDidBecomeActive;

@end

NS_ASSUME_NONNULL_END
