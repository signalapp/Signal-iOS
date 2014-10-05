#import "PreferencesUtil.h"
#import "PushManager.h"
#import "Environment.h"
#import "CallServerRequestsManager.h"
#import "Util.h"

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

-(void) checkAndTryToFixNotificationPermissionsWithAlertsOnFailure {
    if (self.isMissingMandatoryNotificationTypes || self.needToRegisterForRemoteNotifications) {
        TOCFuture* fixed = [self asyncRegisterForPushAndUserNotificationsWithAlertsOnFailure];
        [fixed thenDo:^(id value) {
            DDLogInfo(@"Push/user notifications were succesfully re-enabled");
        }];
        [fixed catchDo:^(id failure) {
            DDLogInfo(@"Failed to fix notification registration issue. Failure: %@", failure);
        }];
    }
}

-(BOOL) needToRegisterForRemoteNotifications {
    return self.wantRemoteNotifications && !UIApplication.sharedApplication.isRegisteredForRemoteNotifications;
}

-(BOOL) wantRemoteNotifications {
    BOOL isSimulator = [UIDevice.currentDevice.model.lowercaseString rangeOfString:@"simulator"].location != NSNotFound;

    if (isSimulator) {
        // Simulator is used for debugging but can't receive push notifications, so don't bother trying to get them
        return NO;
    }
    
    return YES;
}

-(TOCFuture*) asyncRegisterForPushAndUserNotificationsWithAlertsOnFailure {
    TOCFuture* pushRegistered = [self asyncRegisterForPushNotificationsWithAlertsOnFailure];
    return [pushRegistered thenTry:^id(id value) {
        return [self asyncRegisterForUserNotificationWithAlertsOnFailure];
    }];
}


#pragma mark Private Methods

#pragma mark Register Push Notification Token with server

-(TOCFuture*) asyncRegisterForPushWithToken:(NSData*)token {
    require(token != nil);
    self.registerWithServerFutureSource = [TOCFutureSource new];
    
    [CallServerRequestsManager.sharedInstance registerPushToken:token success:^(NSURLSessionDataTask *task, id responseObject) {
        if ([task.response isKindOfClass: NSHTTPURLResponse.class]) {
            NSHTTPURLResponse* response = (NSHTTPURLResponse*)task.response;
            if (response.statusCode == 200) {
                [self.registerWithServerFutureSource trySetResult:nil];
            } else {
                DDLogError(@"The server returned %@ instead of a 200 status code", response);
                [self.registerWithServerFutureSource trySetFailure:response];
            }
        } else {
            [self.registerWithServerFutureSource trySetFailure:task.response];
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [self.registerWithServerFutureSource trySetFailure:error];
    }];
    
    return self.registerWithServerFutureSource.future;
}

#pragma mark Register device for Push Notification locally

-(TOCFuture*) asyncRegisterForPushNotificationsToken {
    self.pushNotificationFutureSource = [TOCFutureSource new];
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        [UIApplication.sharedApplication registerForRemoteNotificationTypes:(UIRemoteNotificationType)self.mandatoryNotificationTypes];
    } else {
        [UIApplication.sharedApplication registerForRemoteNotifications];
    }
    return self.pushNotificationFutureSource.future;
}

-(TOCFuture*) asyncRegisterForUserNotifications {
    self.userNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)self.allNotificationTypes
                                                                                                        categories:[NSSet setWithObject:self.userNotificationsCallCategory]]];
    return [self.userNotificationFutureSource.future thenTry:^id(id value) {
        if (self.isMissingMandatoryNotificationTypes) {
            return [TOCFuture futureWithFailure:@"(Register succeeded, but missing mandatory notification types?)"];
        }
        return value;
    }];
}

-(TOCFuture*) asyncRegisterForPushNotificationsWithAlertsOnFailure {
    if (!self.wantRemoteNotifications) {
        return [TOCFuture futureWithResult:@"don't want remote notifications (e.g. due to being in simulator, which can't receive them)"];
    }

    TOCFuture *registeredToken = [self asyncRegisterForPushNotificationsToken];
    
    [registeredToken catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
    }];
    
    return [registeredToken thenTry:^(NSData* pushToken) {
        TOCFuture *registerPushTokenFuture = [self asyncRegisterForPushWithToken:pushToken];
        
        [registerPushTokenFuture catchDo:^(id failureObj) {
            UIAlertView *failureToRegisterWithServerAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", @"")
                                                                                       message:NSLocalizedString(@"REGISTRATION_BODY", nil)
                                                                                      delegate:nil
                                                                             cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                                                             otherButtonTitles:nil, nil];
            [failureToRegisterWithServerAlert show];
        }];
        
        return registerPushTokenFuture;
    }];
}

-(TOCFuture*) asyncRegisterForUserNotificationWithAlertsOnFailure {
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        // On iOS7, user notifications come with push notification permissions, so we don't need to register for them.
        // (Implicit assumption: we asked for push notifications)
        return [TOCFuture futureWithResult:@"(user notifications should come with push notifications before iOS8)"];
    }
    
    TOCFuture *registered = [self asyncRegisterForUserNotifications];
    
    [registered catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
    }];
    
    return registered;
}

-(UIUserNotificationCategory*)userNotificationsCallCategory {
    UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
    action_accept.identifier     = Signal_Accept_Identifier;
    action_accept.title          = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    action_accept.activationMode = UIUserNotificationActivationModeForeground;
    action_accept.destructive    = NO;
    action_accept.authenticationRequired = NO;
    
    UIMutableUserNotificationAction *action_decline = [UIMutableUserNotificationAction new];
    action_decline.identifier     = Signal_Decline_Identifier;
    action_decline.title          = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
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
    int currentTypes;
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        currentTypes = UIApplication.sharedApplication.enabledRemoteNotificationTypes;
    } else {
        currentTypes = UIApplication.sharedApplication.currentUserNotificationSettings.types;
    }
    return (mandatoryTypes & currentTypes) != mandatoryTypes;
}

-(int)allNotificationTypes{
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
}

-(int)mandatoryNotificationTypes{
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound;
}

@end
