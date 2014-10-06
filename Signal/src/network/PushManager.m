//
//  PushManager.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "PreferencesUtil.h"
#import "PushManager.h"
#import "Environment.h"
#import "RPServerRequestsManager.h"

@interface PushManager ()

@property TOCFutureSource *registerWithServerFutureSource;

@property UIAlertView *missingPermissionsAlertView;

@end

@implementation PushManager

+ (instancetype)sharedManager {
    static PushManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [self new];
        sharedManager.missingPermissionsAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                                               message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                                                              delegate:nil
                                                                     cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                                     otherButtonTitles:nil, nil];
    });
    return sharedManager;
}

- (void)verifyPushPermissions{
    
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        
        // Displaying notifications and ringing
        
        if ([self isMissingMandatoryNotificationTypes:[UIApplication.sharedApplication enabledRemoteNotificationTypes]]) {
            
            [self registrationWithSuccess:^{
                DDLogInfo(@"Push notifications were succesfully re-enabled");
            } failure:^{
                [self.missingPermissionsAlertView show];
            }];
        }
        
    } else{
        
        // UIUserNotificationsSettings
        UIUserNotificationSettings *settings = [UIApplication.sharedApplication currentUserNotificationSettings];
        
        // To use Signal, it is required to have sound notifications and alert types.
        
        if ([self isMissingMandatoryNotificationTypes:settings.types]) {
            
            [self registrationForUserNotificationWithSuccess:^{
                DDLogInfo(@"User notifications were succesfully re-enabled");
            } failure:^{
                [self.missingPermissionsAlertView show];
            }];
            
        }
        
        // Remote Notifications
        if (![UIApplication.sharedApplication isRegisteredForRemoteNotifications]) {
            
            [self registrationForPushWithSuccess:^{
                DDLogInfo(@"Push notification were succesfully re-enabled");
            } failure:^{
                DDLogError(@"The phone could not be re-registered for push notifications."); // Push tokens are not changing on the same phone, just user notification changes so it's not very important.
            }];
            
        }
    }
}

- (void)registrationWithSuccess:(void (^)())success failure:(void (^)())failure{
    
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {

        // On iOS7, we just need to register for Push Notifications (user notifications are enabled with them)
        [self registrationForPushWithSuccess:success failure:failure];
        
    } else{
        
        // On iOS 8+, both Push Notifications and User Notfications need to be registered.
        
        [self registrationForPushWithSuccess:^{
            [self registrationForUserNotificationWithSuccess:success failure:^{
                [self.missingPermissionsAlertView show];
                failure();
            }];
        } failure:failure];
    }
}


#pragma mark Private Methods

#pragma mark Register Push Notification Token with server

-(TOCFuture*)registerForPushFutureWithToken:(NSData*)token{
    self.registerWithServerFutureSource = [TOCFutureSource new];
    
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall registerPushNotificationWithPushToken:token] success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([task.response isKindOfClass: NSHTTPURLResponse.class]){
            NSInteger statusCode = [(NSHTTPURLResponse*) task.response statusCode];
            if (statusCode == 200) {
                [self.registerWithServerFutureSource trySetResult:@YES];
            } else{
                DDLogError(@"The server returned %@ instead of a 200 status code", task.response);
                [self.registerWithServerFutureSource trySetFailure:@NO];
            }
        } else{
            [self.registerWithServerFutureSource trySetFailure:@NO];
        }

    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [self.registerWithServerFutureSource trySetFailure:@NO];
    }];

    return self.registerWithServerFutureSource.future;
}

#pragma mark Register device for Push Notification locally

-(TOCFuture*)registeriOS7PushNotificationFuture{
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerForRemoteNotificationTypes:(UIRemoteNotificationType)[self mandatoryNotificationTypes]];
    return self.pushNotificationFutureSource.future;
}

-(TOCFuture*)registerPushNotificationFuture{
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
    return self.pushNotificationFutureSource.future;
}

-(TOCFuture*)registerForUserNotificationsFuture{
    self.userNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)[self allNotificationTypes] categories:[NSSet setWithObject:[self userNotificationsCallCategory]]]];
    return self.userNotificationFutureSource.future;
}

- (void)registrationForPushWithSuccess:(void (^)())success failure:(void (^)())failure{
    TOCFuture       *requestPushTokenFuture;
    
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        requestPushTokenFuture = [self registeriOS7PushNotificationFuture];
    } else{
        requestPushTokenFuture = [self registerPushNotificationFuture];
    }
    
    [requestPushTokenFuture catchDo:^(id failureObj) {
        failure();
        if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
            [self.missingPermissionsAlertView show];
        } else{
            DDLogError(@"This should not happen on iOS8. No push token was provided");
        }
    }];
    
    [requestPushTokenFuture thenDo:^(NSData* pushToken) {
        TOCFuture *registerPushTokenFuture = [self registerForPushFutureWithToken:pushToken];
        
        [registerPushTokenFuture catchDo:^(id failureObj) {
            UIAlertView *failureToRegisterWithServerAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", @"") message:NSLocalizedString(@"REGISTRATION_BODY", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil, nil];
            [failureToRegisterWithServerAlert show];
            failure();
        }];
        
        [registerPushTokenFuture thenDo:^(id value) {
            success();
        }];
    }];
}

- (void)registrationForUserNotificationWithSuccess:(void (^)())success failure:(void (^)())failure{
    TOCFuture *registrerUserNotificationFuture = [self registerForUserNotificationsFuture];
    
    [registrerUserNotificationFuture catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
        failure();
    }];
    
    [registrerUserNotificationFuture thenDo:^(id types) {
        if ([self isMissingMandatoryNotificationTypes:[UIApplication.sharedApplication currentUserNotificationSettings].types]) {
            [self.missingPermissionsAlertView show];
            failure();
        } else{
            success();
        }
    }];
}


-(UIUserNotificationCategory*)userNotificationsCallCategory{
    UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
    action_accept.identifier = Signal_Accept_Identifier;
    action_accept.title      = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    action_accept.activationMode = UIUserNotificationActivationModeForeground;
    action_accept.destructive    = NO;
    action_accept.authenticationRequired = NO;
    
    UIMutableUserNotificationAction *action_decline = [UIMutableUserNotificationAction new];
    action_decline.identifier = Signal_Decline_Identifier;
    action_decline.title      = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
    action_decline.activationMode = UIUserNotificationActivationModeBackground;
    action_decline.destructive    = NO;
    action_decline.authenticationRequired = NO;
    
    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier = @"Signal_IncomingCall";
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextDefault];
    
    return callCategory;
}

-(BOOL)isMissingMandatoryNotificationTypes:(int)notificationTypes{
    int mandatoryTypes = [self mandatoryNotificationTypes];
    return ((mandatoryTypes & notificationTypes) == mandatoryTypes)?NO:YES;
}

-(int)allNotificationTypes{
    return (UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge);
}

-(int)mandatoryNotificationTypes{
    return (UIUserNotificationTypeAlert | UIUserNotificationTypeSound);
}

@end
