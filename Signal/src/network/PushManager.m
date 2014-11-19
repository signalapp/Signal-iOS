//
//  PushManager.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "PropertyListPreferences+Util.h"
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
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
#warning Deprecated method
        self.missingPermissionsAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                                      message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                                                     delegate:nil
                                                            cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                            otherButtonTitles:nil, nil];
    }
    return self;
}

- (void)verifyPushPermissions {
    if (self.isMissingMandatoryNotificationTypes || self.needToRegisterForRemoteNotifications) {
        [self registrationWithSuccess:^{
            DDLogError(@"Re-enabled push succesfully");
        } failure:^{
            DDLogError(@"Failed to re-enable push.");
        }];
    }
}

- (void)registrationWithSuccess:(void (^)())success failure:(void (^)())failure {
    
    if (!self.wantRemoteNotifications) {
        success();
        return;
    }
    
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        
        // On iOS7, we just need to register for Push Notifications (user notifications are enabled with them)
        [self registrationForPushWithSuccess:success failure:failure];
        
    } else {
        
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

- (TOCFuture*)registerForPushFutureWithToken:(NSData*)token {
    self.registerWithServerFutureSource = [[TOCFutureSource alloc] init];
    
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall registerPushNotificationWithPushToken:token] success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
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

- (TOCFuture*)registerPushNotificationFuture {
    self.pushNotificationFutureSource = [[TOCFutureSource alloc] init];
    
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationType)self.mandatoryNotificationTypes];
        if ([self isMissingMandatoryNotificationTypes]) {
            [self.pushNotificationFutureSource trySetFailure:@"Missing Types"];
        }
    } else {
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    return self.pushNotificationFutureSource.future;
}

- (TOCFuture*)registerForUserNotificationsFuture {
    self.userNotificationFutureSource = [[TOCFutureSource alloc] init];
    [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)[self allNotificationTypes] categories:[NSSet setWithObject:[self userNotificationsCallCategory]]]];
    return self.userNotificationFutureSource.future;
}

- (void)registrationForPushWithSuccess:(void (^)())success failure:(void (^)())failure {
    TOCFuture* requestPushTokenFuture = [self registerPushNotificationFuture];
    
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
            success();
        }];
    }];
}

- (void)registrationForUserNotificationWithSuccess:(void (^)())success failure:(void (^)())failure {
    TOCFuture *registrerUserNotificationFuture = [self registerForUserNotificationsFuture];
    
    [registrerUserNotificationFuture catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
        failure();
    }];
    
    [registrerUserNotificationFuture thenDo:^(id types) {
        if (self.isMissingMandatoryNotificationTypes) {
            [self.missingPermissionsAlertView show];
            failure();
        } else {
            success();
        }
    }];
}

- (BOOL)needToRegisterForRemoteNotifications {
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        return self.wantRemoteNotifications;
    } else {
        return self.wantRemoteNotifications && (![UIApplication sharedApplication].isRegisteredForRemoteNotifications);
    }
}

- (BOOL)wantRemoteNotifications {
    BOOL isSimulator = [[UIDevice currentDevice].model.lowercaseString rangeOfString:@"simulator"].location != NSNotFound;
    
    if (isSimulator) {
        // Simulator is used for debugging but can't receive push notifications, so don't bother trying to get them
        return NO;
    }
    
    return YES;
}

- (UIUserNotificationCategory*)userNotificationsCallCategory {
    UIMutableUserNotificationAction *action_accept = [[UIMutableUserNotificationAction alloc] init];
    action_accept.identifier             = Signal_Accept_Identifier;
    action_accept.title                  = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    action_accept.activationMode         = UIUserNotificationActivationModeForeground;
    action_accept.destructive            = NO;
    action_accept.authenticationRequired = NO;
    
    UIMutableUserNotificationAction *action_decline = [[UIMutableUserNotificationAction alloc] init];
    action_decline.identifier             = Signal_Decline_Identifier;
    action_decline.title                  = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
    action_decline.activationMode         = UIUserNotificationActivationModeBackground;
    action_decline.destructive            = NO;
    action_decline.authenticationRequired = NO;
    
    UIMutableUserNotificationCategory *callCategory = [[UIMutableUserNotificationCategory alloc] init];
    callCategory.identifier = @"Signal_IncomingCall";
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextDefault];
    
    return callCategory;
}

- (BOOL)isMissingMandatoryNotificationTypes {
    int mandatoryTypes = self.mandatoryNotificationTypes;
    int currentTypes;
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        currentTypes = [UIApplication sharedApplication].enabledRemoteNotificationTypes;
    } else {
        currentTypes = [UIApplication sharedApplication].currentUserNotificationSettings.types;
    }
    return (mandatoryTypes & currentTypes) != mandatoryTypes;
}

- (int)allNotificationTypes {
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        return UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeBadge;
    } else {
        return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
    }
}

- (int)mandatoryNotificationTypes {
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        return UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound;
    } else {
        return UIUserNotificationTypeAlert | UIUserNotificationTypeSound;
    }
}

@end
