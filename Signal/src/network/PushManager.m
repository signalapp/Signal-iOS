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
#import "TSAccountManager.h"

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
    });
    return sharedManager;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        self.missingPermissionsAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                                      message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                                                     delegate:nil
                                                            cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                            otherButtonTitles:nil, nil];
    }
    return self;
}

- (void)verifyPushPermissions{
    if (self.isMissingMandatoryNotificationTypes || self.needToRegisterForRemoteNotifications){
        [self registrationWithSuccess:^{
            DDLogError(@"Re-enabled push succesfully");
        } failure:^{
            DDLogError(@"Failed to re-enable push.");
        }];
    }
}

- (void)registrationWithSuccess:(void (^)())success failure:(void (^)())failure{
    
    if (!self.wantRemoteNotifications) {
        success();
        return;
    }
    
    [self registrationForPushWithSuccess:^(NSData* pushToken){
        [self registrationForUserNotificationWithSuccess:success failure:^{
            [self.missingPermissionsAlertView show];
            failure();
        }];
    } failure:failure];
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
                [self.registerWithServerFutureSource trySetFailure:nil];
            }
        } else{
            [self.registerWithServerFutureSource trySetFailure:task.response];
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [self.registerWithServerFutureSource trySetFailure:error];
    }];
    
    return self.registerWithServerFutureSource.future;
}

#pragma mark Register device for Push Notification locally

-(TOCFuture*)registerPushNotificationFuture{
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerForRemoteNotifications];
    
    return self.pushNotificationFutureSource.future;
}

-(TOCFuture*)registerForUserNotificationsFuture{
    self.userNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)[self allNotificationTypes] categories:[NSSet setWithObject:[self userNotificationsCallCategory]]]];
    return self.userNotificationFutureSource.future;
}

- (void)registrationForPushWithSuccess:(void (^)(NSData* pushToken))success failure:(void (^)())failure{
    TOCFuture       *requestPushTokenFuture = [self registerPushNotificationFuture];
    
    [requestPushTokenFuture catchDo:^(id failureObj) {
        failure();
        [self.missingPermissionsAlertView show];
        DDLogError(@"This should not happen on iOS8. No push token was provided");
    }];
    
    [requestPushTokenFuture thenDo:^(NSData* pushToken) {
        TOCFuture *registerPushTokenFuture = [self registerForPushFutureWithToken:pushToken];
        
        [registerPushTokenFuture catchDo:^(id failureObj) {
            UIAlertView *failureToRegisterWithServerAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", @"")
                                                                                       message:NSLocalizedString(@"REGISTRATION_BODY", nil)
                                                                                      delegate:nil
                                                                             cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                                                             otherButtonTitles:nil, nil];
            [failureToRegisterWithServerAlert show];
            failure();
        }];
        
        [registerPushTokenFuture thenDo:^(id value) {
            success(pushToken);
        }];
    }];
}


- (void)registrationAndRedPhoneTokenRequestWithSuccess:(void (^)(NSData* pushToken, NSString* signupToken))success failure:(void (^)())failure{
    [self registrationForPushWithSuccess:^(NSData *pushToken) {        
        [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall requestTextSecureVerificationCode] success:^(NSURLSessionDataTask *task, id responseObject) {
            NSError *error;
            
            NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:&error];
            NSString* tsToken = [dictionary objectForKey:@"token"];
            
            if (!tsToken || !pushToken || error) {
                failure();
                return;
            }
            
            success(pushToken, tsToken);
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            failure();
        }];
    } failure:^{
        failure();
    }];
    
}

- (void)registrationForUserNotificationWithSuccess:(void (^)())success failure:(void (^)())failure{
    TOCFuture *registrerUserNotificationFuture = [self registerForUserNotificationsFuture];
    
    [registrerUserNotificationFuture catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
        failure();
    }];
    
    [registrerUserNotificationFuture thenDo:^(id types) {
        if (self.isMissingMandatoryNotificationTypes) {
            [self.missingPermissionsAlertView show];
            failure();
        } else{
            success();
        }
    }];
}

-(BOOL) needToRegisterForRemoteNotifications {
    return self.wantRemoteNotifications && (!UIApplication.sharedApplication.isRegisteredForRemoteNotifications);
}

-(BOOL) wantRemoteNotifications {
    BOOL isSimulator = [UIDevice.currentDevice.model.lowercaseString rangeOfString:@"simulator"].location != NSNotFound;
    
    if (isSimulator) {
        // Simulator is used for debugging but can't receive push notifications, so don't bother trying to get them
        return NO;
    }
    
    return YES;
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

-(BOOL)isMissingMandatoryNotificationTypes {
    int mandatoryTypes = self.mandatoryNotificationTypes;
    int currentTypes = UIApplication.sharedApplication.currentUserNotificationSettings.types;
    
    return (mandatoryTypes & currentTypes) != mandatoryTypes;
}

-(int)allNotificationTypes{
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
}

-(int)mandatoryNotificationTypes{
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound;
}

@end
