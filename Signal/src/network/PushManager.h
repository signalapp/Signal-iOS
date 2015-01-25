//
//  PushManager.h
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <CollapsingFutures.h>
#import <Foundation/Foundation.h>

#define Signal_Call_Accept_Identifier        @"Signal_Call_Accept"
#define Signal_Call_Decline_Identifier       @"Signal_Call_Decline"

#define Signal_Call_Category                 @"Signal_IncomingCall"
#define Signal_Message_Category              @"Signal_Message"

#define Signal_Message_View_Identifier       @"Signal_Message_Read"
#define Signal_Message_MarkAsRead_Identifier @"Signal_Message_MarkAsRead"

/**
 *  The Push Manager is responsible for registering the device for Signal push notifications.
 */

@interface PushManager : NSObject

+ (PushManager*)sharedManager;

/**
 *  Push notification token is always registered during signup. User can however revoke notifications.
 *  Therefore, we check on startup if mandatory permissions are granted.
 */

- (void)verifyPushPermissions;

/**
 *  Push notification registration method
 *
 *  @param success Block to execute after succesful push notification registration
 *  @param failure Block to executre if push notification registration fails
 */

- (void)registrationWithSuccess:(void (^)())success failure:(void (^)())failure;

/**
 *  Registers the push token with the RedPhone server, then returns the push token and a signup token to be used to register with TextSecure.
 *
 *  @param success Success completion block - registering with TextSecure server
 *  @param failure Failure completion block
 */

- (void)registrationAndRedPhoneTokenRequestWithSuccess:(void (^)(NSData* pushToken, NSString* signupToken))success failure:(void (^)())failure;

/**
 *  The pushNotification and userNotificationFutureSource are accessed by the App Delegate after requested permissions.
 */

-(TOCFuture*)registerPushNotificationFuture;
- (void)registrationForPushWithSuccess:(void (^)(NSData* pushToken))success failure:(void (^)())failure;
@property TOCFutureSource *pushNotificationFutureSource;
@property TOCFutureSource *userNotificationFutureSource;

@end
