//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <CollapsingFutures.h>
#import <PushKit/PushKit.h>
#import <UIKit/UIApplication.h>

NS_ASSUME_NONNULL_BEGIN

@class UILocalNotification;

#define Signal_Thread_UserInfo_Key @"Signal_Thread_Id"
#define Signal_Message_UserInfo_Key @"Signal_Message_Id"

#define Signal_Full_New_Message_Category @"Signal_Full_New_Message"

#define Signal_Message_Reply_Identifier @"Signal_New_Message_Reply"
#define Signal_Message_MarkAsRead_Identifier @"Signal_Message_MarkAsRead"

#pragma mark Signal Calls constants

FOUNDATION_EXPORT NSString *const PushManagerCategoriesIncomingCall;
FOUNDATION_EXPORT NSString *const PushManagerCategoriesMissedCall;

FOUNDATION_EXPORT NSString *const PushManagerActionsAcceptCall;
FOUNDATION_EXPORT NSString *const PushManagerActionsDeclineCall;
FOUNDATION_EXPORT NSString *const PushManagerActionsCallBack;

FOUNDATION_EXPORT NSString *const PushManagerUserInfoKeysCallBackSignalRecipientId;
FOUNDATION_EXPORT NSString *const PushManagerUserInfoKeysLocalCallId;

typedef void (^failedPushRegistrationBlock)(NSError *error);
typedef void (^pushTokensSuccessBlock)(NSString *pushToken, NSString *voipToken);

/**
 *  The Push Manager is responsible for registering the device for Signal push notifications.
 */

@interface PushManager : NSObject <PKPushRegistryDelegate>

- (instancetype)init NS_UNAVAILABLE;

+ (PushManager *)sharedManager;

/**
 *  Returns the Push Notification Token of this device
 *
 *  @param success Completion block that is passed the token as a parameter
 *  @param failure Failure block, executed when failed to get push token
 */
- (void)requestPushTokenWithSuccess:(pushTokensSuccessBlock)success failure:(void (^)(NSError *))failure;

/**
 *  Registers for Users Notifications. By doing this on launch, we are sure that the correct categories of user
 * notifications is registered.
 */
- (void)validateUserNotificationSettings;

/**
 *  The pushNotification and userNotificationFutureSource are accessed by the App Delegate after requested permissions.
 */
@property (nullable, atomic, readwrite, strong) TOCFutureSource *pushNotificationFutureSource;
@property (nullable, atomic, readwrite, strong) TOCFutureSource *userNotificationFutureSource;
@property (nullable, atomic, readwrite, strong) TOCFutureSource *pushKitNotificationFutureSource;

- (TOCFuture *)registerPushKitNotificationFuture;
- (BOOL)supportsVOIPPush;
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
