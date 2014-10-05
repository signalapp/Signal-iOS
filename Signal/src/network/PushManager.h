//
//  PushManager.h
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <TwistedOakCollapsingFutures/CollapsingFutures.h>
#import <Foundation/Foundation.h>


#define Signal_Accept_Identifier  @"Signal_Call_Accept"
#define Signal_Decline_Identifier @"Signal_Call_Decline"

/**
 *  The Push Manager is responsible for registering the device for Signal push notifications.
 */

@interface PushManager : NSObject

+ (instancetype)sharedManager;

/**
 *  Push notification token is always registered during signup. User can however revoke notifications.
 *  Therefore, we check on startup if mandatory permissions are granted.
 */

- (void) checkAndTryToFixNotificationPermissionsWithAlertsOnFailure;

/**
 *  Push notification registration method.
 */

- (TOCFuture*) asyncRegisterForPushAndUserNotificationsWithAlertsOnFailure;

/**
 *  The pushNotification and userNotificationFutureSource are accessed by the App Delegate after requested permissions.
 */

@property TOCFutureSource *pushNotificationFutureSource;
@property TOCFutureSource *userNotificationFutureSource;

@end
