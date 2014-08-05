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
#import "CallServerRequestsManager.h"

@interface PushManager ()

@property (nonatomic, copy) void (^PushRegisteringSuccessBlock)();
@property (nonatomic, copy) void (^PushRegisteringFailureBlock)();

@property int retries;

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

- (void)verifyPushActivated{
    UIRemoteNotificationType notificationTypes = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    
    BOOL needsPushSettingChangeAlert = NO;

    if (notificationTypes == UIRemoteNotificationTypeNone) {
        needsPushSettingChangeAlert = YES;
    } else if (notificationTypes == UIRemoteNotificationTypeBadge) {
        needsPushSettingChangeAlert = YES;
    } else if (notificationTypes == UIRemoteNotificationTypeAlert) {
        needsPushSettingChangeAlert = YES;
    } else if (notificationTypes == UIRemoteNotificationTypeSound) {
        needsPushSettingChangeAlert = YES;
    } else if (notificationTypes == (UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert)) {
        needsPushSettingChangeAlert = YES;
    } else if (notificationTypes == (UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)) {
        needsPushSettingChangeAlert = YES;
    }
    
    if (needsPushSettingChangeAlert) {
        [[Environment preferences] setRevokedPushPermission:YES];
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")  message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"") delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil, nil];
        [alertView show];
    } else if (!needsPushSettingChangeAlert){
        if ([[Environment preferences] encounteredRevokedPushPermission]) {
            [self askForPushRegistration];
        }
    }
    
}

- (void)askForPushRegistrationWithSuccess:(void (^)())success failure:(void (^)())failure{
    self.PushRegisteringSuccessBlock  = success;
    self.PushRegisteringFailureBlock = failure;
    [self askForPushRegistration];
}

- (void)askForPushRegistration{
    
    if(SYSTEM_VERSION_LESS_THAN(_iOS_8_0)){
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeBadge)];
    } else{
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_7_1
        UIMutableUserNotificationAction *action_accept = [[UIMutableUserNotificationAction alloc]init];
        action_accept.identifier = @"Signal_Call_Accept";
        action_accept.title      = @"Pick up";
        action_accept.activationMode = UIUserNotificationActivationModeForeground;
        action_accept.destructive    = YES;
        action_accept.authenticationRequired = NO;
        
        UIMutableUserNotificationAction *action_decline = [[UIMutableUserNotificationAction alloc]init];
        action_decline.identifier = @"Signal_Call_Decline";
        action_decline.title      = @"Pick up";
        action_decline.activationMode = UIUserNotificationActivationModeForeground;
        action_decline.destructive    = YES;
        action_decline.authenticationRequired = NO;
        
        UIMutableUserNotificationCategory *callCategory = [[UIMutableUserNotificationCategory alloc] init];
        callCategory.identifier = @"Signal_IncomingCall";
        [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextDefault];
        
        NSSet *categories = [NSSet setWithObject:callCategory];
        
        [[UIApplication sharedApplication] registerForRemoteNotifications];
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIRemoteNotificationTypeAlert|UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeSound) categories:categories]];
        
#endif

    }
    
    self.retries = 3;
}

- (void)registerForPushWithToken:(NSData*)token{
    [[CallServerRequestsManager sharedManager] registerPushToken:token success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([task.response isKindOfClass: [NSHTTPURLResponse class]]){
            NSInteger statusCode = [(NSHTTPURLResponse*) task.response statusCode];
            if (statusCode == 200) {
                DDLogInfo(@"Device sent push ID to server");
                [[Environment preferences] setRevokedPushPermission:NO];
                if (self.PushRegisteringSuccessBlock) {
                    self.PushRegisteringSuccessBlock();
                    self.PushRegisteringSuccessBlock = nil;
                }
            } else{
                [self registerFailureWithToken:token];
            }
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [self registerForPushWithToken:token];
    }];
}


/**
 *  Token was not sucessfully register. Try again / deal with failure
 *
 *  @param token Token to register
 */

- (void)registerFailureWithToken:(NSData*)token{
    if (self.retries > 0) {
        [self registerForPushWithToken:token];
        self.retries--;
    } else{
        if (self.PushRegisteringFailureBlock) {
            self.PushRegisteringFailureBlock();
            self.PushRegisteringFailureBlock = nil;
        }
        [[Environment preferences] setRevokedPushPermission:YES];
    }
}



@end
