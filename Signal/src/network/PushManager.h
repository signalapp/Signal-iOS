//
//  PushManager.h
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <CollapsingFutures.h>
#import <Foundation/Foundation.h>

#define Signal_Thread_UserInfo_Key @"Signal_Thread_Id"
#define Signal_Message_UserInfo_Key @"Signal_Message_Id"

#define Signal_Call_UserInfo_Key @"Signal_Call_Id"

#define Signal_Call_Accept_Identifier @"Signal_Call_Accept"
#define Signal_Call_Decline_Identifier @"Signal_Call_Decline"

#define Signal_CallBack_Identifier @"Signal_CallBack"

#define Signal_Call_Category @"Signal_IncomingCall"
#define Signal_Full_New_Message_Category @"Signal_Full_New_Message"
#define Signal_CallBack_Category @"Signal_CallBack"

#define Signal_Message_Reply_Identifier @"Signal_New_Message_Reply"
#define Signal_Message_MarkAsRead_Identifier @"Signal_Message_MarkAsRead"

typedef void (^failedPushRegistrationBlock)(NSError *error);
typedef void (^pushTokensSuccessBlock)(NSString *pushToken, NSString *voipToken);

/**
 *  The Push Manager is responsible for registering the device for Signal push notifications.
 */

@interface PushManager : NSObject

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

@property TOCFutureSource *pushNotificationFutureSource;
@property TOCFutureSource *userNotificationFutureSource;
@property TOCFutureSource *pushKitNotificationFutureSource;

- (TOCFuture *)registerPushKitNotificationFuture;
- (BOOL)supportsVOIPPush;
- (UILocalNotification *)closeVOIPBackgroundTask;
- (void)presentNotification:(UILocalNotification *)notification;

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

@end
