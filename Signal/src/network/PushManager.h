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

typedef void(^failedPushRegistrationBlock)(NSError *error);

/**
 *  The Push Manager is responsible for registering the device for Signal push notifications.
 */

@interface PushManager : NSObject

+ (PushManager*)sharedManager;

/**
 *  Registers the push token with the RedPhone server, then returns the push token and a signup token to be used to register with TextSecure.
 *
 *  @param success Success completion block - registering with TextSecure server
 *  @param failure Failure completion block
 */

- (void)registrationAndRedPhoneTokenRequestWithSuccess:(void (^)(NSData* pushToken, NSString* signupToken))success failure:(failedPushRegistrationBlock)failure;

/**
 *  Returns the Push Notification Token of this device
 *
 *  @param success Completion block that is passed the token as a parameter
 *  @param failure Failure block, executed when failed to get push token
 */

- (void)requestPushTokenWithSuccess:(void (^)(NSData* pushToken))success failure:(void(^)(NSError *))failure;

/**
 *  Registers for Users Notifications. By doing this on launch, we are sure that the correct categories of user notifications is registered.
 */

- (void)validateUserNotificationSettings;

/**
 *  The pushNotification and userNotificationFutureSource are accessed by the App Delegate after requested permissions.
 */

@property TOCFutureSource *pushNotificationFutureSource;
@property TOCFutureSource *userNotificationFutureSource;

@end
