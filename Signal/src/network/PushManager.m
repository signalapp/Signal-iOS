#import "PreferencesUtil.h"
#import "PushManager.h"
#import "Environment.h"
#import "CallServerRequestsManager.h"
#import "Util.h"
#import "DDLog.h"

#define REQUEST_PUSH_NOTIFICATION_ATTEMPTS 3

@interface PushManager ()

@property (nonatomic, copy) TOCFutureSource* pushRegistrationResult;

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

-(UIRemoteNotificationType) desiredNotificationTypeMask {
    return UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound;
}

- (void)verifyPushActivated{
    UIRemoteNotificationType notificationTypes = UIApplication.sharedApplication.enabledRemoteNotificationTypes;
    
    BOOL needsPushSettingChangeAlert = (self.desiredNotificationTypeMask & notificationTypes) != self.desiredNotificationTypeMask;
    
    if (needsPushSettingChangeAlert) {
        Environment.preferences.haveReceivedPushNotifications = NO;
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                                            message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                  otherButtonTitles:nil, nil];
        [alertView show];
    } else if (!needsPushSettingChangeAlert && !Environment.preferences.haveReceivedPushNotifications) {
        [self askForPushRegistrationWithoutSettingFuture];
    }
    
}

-(TOCFuture*) askForPushRegistration {
    [self.pushRegistrationResult trySetFailedWithCancel];
    self.pushRegistrationResult = [TOCFutureSource new];
    [self askForPushRegistrationWithoutSettingFuture];
    return self.pushRegistrationResult.future;
}

-(void) askForPushRegistrationWithoutSettingFuture {
    // This should result in didRegisterForPushNotificationsToDevice or didFailToRegisterForPushNotificationsWithError being invoked
    if (SYSTEM_VERSION_LESS_THAN(_iOS_8_0)) {
        [UIApplication.sharedApplication registerForRemoteNotificationTypes:self.desiredNotificationTypeMask];
    } else {
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_7_1
        UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
        action_accept.identifier = @"Signal_Call_Accept";
        action_accept.title      = @"Pick up";
        action_accept.activationMode = UIUserNotificationActivationModeForeground;
        action_accept.destructive    = YES;
        action_accept.authenticationRequired = NO;
        
        UIMutableUserNotificationAction *action_decline = [UIMutableUserNotificationAction new];
        action_decline.identifier = @"Signal_Call_Decline";
        action_decline.title      = @"Pick up";
        action_decline.activationMode = UIUserNotificationActivationModeForeground;
        action_decline.destructive    = YES;
        action_decline.authenticationRequired = NO;
        
        UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
        callCategory.identifier = @"Signal_IncomingCall";
        [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextDefault];
        
        NSSet *categories = @{callCategory};
        
        [UIApplication.sharedApplication registerForRemoteNotifications];
        [UIApplication.sharedApplication registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:self.desiredNotificationTypeMask
                                                                                                            categories:categories]];
#endif
    }
}

-(void)didFailToRegisterForPushNotificationsWithError:(NSError *)error {
    DDLogError(@"Failed to register for push notifications: %@", error);
    [self verifyPushActivated];
}

-(void)didRegisterForPushNotificationsToDevice:(NSData*)deviceToken {
    [self tellServerDeviceToken:deviceToken];
}

-(void)tellServerDeviceToken:(NSData*)deviceToken {

    TOCUntilOperation attemptPushRequestOperation = ^(TOCCancelToken* operationUntil) {
        TOCFuture* futureResponse = [CallServerRequestsManager.sharedInstance asyncRequestPushNotificationToDevice:deviceToken];
        
        return [futureResponse then:^id(NSHTTPURLResponse *response) {
            if (![response isKindOfClass:NSHTTPURLResponse.class]) {
                return [TOCFuture futureWithFailure:response];
            }
            
            if (response.statusCode != 200) {
                return [TOCFuture futureWithFailure:response];
            }
            
            return @YES;
        }];
    };
    
    TOCFuture* futureRequestedPush = [TOCFuture attempt:attemptPushRequestOperation
                                             upToNTimes:REQUEST_PUSH_NOTIFICATION_ATTEMPTS
                                         untilCancelled:nil];
    
    [futureRequestedPush thenDo:^(id _) {
        DDLogInfo(@"Device sent push ID to server");
        Environment.preferences.haveReceivedPushNotifications = YES;
        [self.pushRegistrationResult trySetResult:nil];
    }];
     
    [futureRequestedPush catchDo:^(id error) {
        DDLogInfo(([NSString stringWithFormat:@"Failed to send device token to server. Error: %@", error]));
        [self.pushRegistrationResult trySetFailure:nil];
    }];
}

@end
