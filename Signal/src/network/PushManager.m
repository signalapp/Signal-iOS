//
//  PushManager.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <PushKit/PushKit.h>

#import "ContactsManager.h"
#import "InCallViewController.h"
#import "NotificationTracker.h"

#import "PreferencesUtil.h"
#import "PushManager.h"
#import "RPServerRequestsManager.h"
#import "TSSocketManager.h"

#define pushManagerDomain @"org.whispersystems.pushmanager"

@interface PushManager () <PKPushRegistryDelegate>

@property TOCFutureSource     *registerWithServerFutureSource;
@property UIAlertView         *missingPermissionsAlertView;
@property (nonatomic, strong) NotificationTracker *notificationTracker;
@property UILocalNotification *lastCallNotification;

@property (nonatomic) UIBackgroundTaskIdentifier callBackgroundTask;
@end

@implementation PushManager

+ (instancetype)sharedManager
{
    static PushManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [self new];
    });
    return sharedManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.notificationTracker = [NotificationTracker notificationTracker];
        self.missingPermissionsAlertView =
        [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                   message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                  delegate:nil
                         cancelButtonTitle:NSLocalizedString(@"OK", @"")
                         otherButtonTitles:nil, nil];
        _callBackgroundTask = UIBackgroundTaskInvalid;
    }
    return self;
}

#pragma mark Manage Incoming Push

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    if ([self isRedPhonePush:userInfo]) {
        ResponderSessionDescriptor* call;
        if (![self.notificationTracker shouldProcessNotification:userInfo]){
            return;
        }
        
        @try {
            call = [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:userInfo];
            DDLogDebug(@"Received remote notification. Parsed session descriptor: %@.", call);
        } @catch (OperationFailed* ex) {
            DDLogError(@"Error parsing remote notification. Error: %@.", ex);
            return;
        }
        
        if (!call) {
            DDLogError(@"Decryption of session descriptor failed");
            return;
        }
        
        [Environment.phoneManager incomingCallWithSession:call];
        
        if (![self applicationIsActive]) {
            UILocalNotification *notification = [[UILocalNotification alloc] init];
            
            NSString *callerId = call.initiatorNumber.toE164;
            NSString *nameString = [[Environment getCurrent].contactsManager nameStringForPhoneIdentifier:callerId];
            
            NSString *displayName          = nameString?nameString:callerId;
            PropertyListPreferences *prefs = [Environment preferences];
            
            if ([prefs notificationPreviewType] == NotificationNoNameNoPreview) {
                notification.alertBody = NSLocalizedString(@"INCOMING_CALL", nil);
            } else {
                notification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"INCOMING_CALL_FROM", nil), displayName];
            }
            
            notification.category  = Signal_Call_Category;
            notification.soundName = @"r.caf";
            
            [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
            _lastCallNotification = notification;
            
            if (_callBackgroundTask == UIBackgroundTaskInvalid) {
                _callBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                    [Environment.phoneManager backgroundTimeExpired];
                    [self closeVOIPBackgroundTask];
                }];
            }
        }
    } else {
        if (![self applicationIsActive]) {
            [TSSocketManager becomeActiveFromBackgroundExpectMessage:YES];
        }
    }
}

- (UILocalNotification*)closeVOIPBackgroundTask {
    [[UIApplication sharedApplication] endBackgroundTask:_callBackgroundTask];
    _callBackgroundTask = UIBackgroundTaskInvalid;
    
    UILocalNotification *notif = _lastCallNotification;
    _lastCallNotification      = nil;
    
    return notif;
}

/**
 *  This code should in principle never be called. The only cases where it would be called are with the old-style "content-available:1" pushes if there is no "voip" token registered
 *
 */

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    if ([self isRedPhonePush:userInfo]) {
        [self application:application didReceiveRemoteNotification:userInfo];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                       completionHandler(UIBackgroundFetchResultNewData);
                   });
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    if ([notification.category isEqualToString:Signal_Message_Category]) {
        NSString *threadId = [notification.userInfo objectForKey:Signal_Thread_UserInfo_Key];
        [Environment messageThreadId:threadId];
    }
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification completionHandler:(void (^)())completionHandler {
    
    if ([identifier isEqualToString:Signal_Call_Accept_Identifier]) {
        [Environment.phoneManager answerCall];
        
        completionHandler();
    } else if ([identifier isEqualToString:Signal_Call_Decline_Identifier]){
        [Environment.phoneManager hangupOrDenyCall];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                           completionHandler();
                       });
    } else if([identifier isEqualToString:Signal_CallBack_Identifier]){
        NSString * contactId = [notification.userInfo objectForKeyedSubscript:Signal_Call_UserInfo_Key];
        PhoneNumber *number =  [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:contactId];
        Contact *contact    = [[Environment.getCurrent contactsManager] latestContactForPhoneNumber:number];
        [Environment.phoneManager initiateOutgoingCallToContact:contact atRemoteNumber:number];
    } else{
        NSString *threadId = [notification.userInfo objectForKey:Signal_Thread_UserInfo_Key];
        [Environment messageThreadId:threadId];
        completionHandler();
    }
}

- (BOOL)isRedPhonePush:(NSDictionary*)pushDict {
    NSDictionary *aps  = [pushDict objectForKey:@"aps"];
    NSString *category = [aps      objectForKey:@"category"];
    
    if ([category isEqualToString:Signal_Call_Category]) {
        return YES;
    } else{
        return NO;
    }
}

#pragma mark PushKit

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type
{
    [[PushManager sharedManager].pushKitNotificationFutureSource trySetResult:credentials.token];
}

-(void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:payload.dictionaryPayload];
}

- (TOCFuture*)registerPushKitNotificationFuture{
    if ([self supportsVOIPPush]) {
        self.pushKitNotificationFutureSource = [TOCFutureSource new];
        PKPushRegistry* voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
        voipRegistry.delegate = self;
        voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
        return self.pushKitNotificationFutureSource.future;
    } else {
        TOCFutureSource *futureSource = [TOCFutureSource new];
        [futureSource trySetResult:nil];
        [Environment.preferences setHasRegisteredVOIPPush:FALSE];
        return futureSource.future;
    }
}

- (BOOL)supportsVOIPPush {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(_iOS_8_2_0)) {
        return YES;
    } else {
        return NO;
    }
}

#pragma mark Register device for Push Notification locally

- (TOCFuture *)registerPushNotificationFuture
{
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerForRemoteNotifications];
    
    return self.pushNotificationFutureSource.future;
}

- (void)requestPushTokenWithSuccess:(pushTokensSuccessBlock)success failure:(failedPushRegistrationBlock)failure
{
    TOCFuture *requestPushTokenFuture = [self registerPushNotificationFuture];
    
    [requestPushTokenFuture catchDo:^(id failureObj) {
        [self.missingPermissionsAlertView show];
        failure(failureObj);
        DDLogError(@"This should not happen on iOS8. No push token was provided");
    }];
    
    [requestPushTokenFuture thenDo:^(NSData *pushToken) {
        TOCFuture *voipPushTokenFuture = [self registerPushKitNotificationFuture];
        
        [voipPushTokenFuture finallyDo:^(TOCFuture *completed) {
            NSData *voipPushToken = completed.hasResult?completed.forceGetResult:nil;
            
            TOCFuture *registerPushTokenFuture = [self registerForPushFutureWithToken:pushToken voipToken:voipPushToken];
            
            [registerPushTokenFuture catchDo:^(id failureObj) {
                failure(failureObj);
            }];
            
            [registerPushTokenFuture thenDo:^(id value) {
                TOCFuture *userRegistration = [self registerForUserNotificationsFuture];
                
                [userRegistration thenDo:^(UIUserNotificationSettings *userNotificationSettings) {
                    success(pushToken, voipPushToken);
                }];
            }];
        }];
    }];
}

- (void)registrationAndRedPhoneTokenRequestWithSuccess:(registrationTokensSuccessBlock)success
                                               failure:(failedPushRegistrationBlock)failure
{
    if (!self.wantRemoteNotifications) {
        NSData *fakeToken = [@"Fake PushToken" dataUsingEncoding:NSUTF8StringEncoding];
        [self registerTokenWithRedPhoneServer:fakeToken
                                    voipToken:fakeToken
                                  withSuccess:success
                                      failure:failure];
        
        return;
    }
    
    [self requestPushTokenWithSuccess:^(NSData *pushToken, NSData *voipToken) {
        [self registerTokenWithRedPhoneServer:pushToken voipToken:voipToken withSuccess:success failure:failure];
    } failure:^(NSError *error) {
        [self.missingPermissionsAlertView show];
        failure([NSError errorWithDomain:pushManagerDomain code:400 userInfo:@{}]);
    }];
}

- (void)registerTokenWithRedPhoneServer:(NSData*)pushToken
                              voipToken:(NSData*)voipToken
                            withSuccess:(registrationTokensSuccessBlock)success
                                failure:(failedPushRegistrationBlock)failure
{
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall requestTextSecureVerificationCode]
                                                   success:^(NSURLSessionDataTask *task, id responseObject) {
                                                       NSError *error;
                                                       
                                                       NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:&error];
                                                       NSString *tsToken = [dictionary objectForKey:@"token"];
                                                       
                                                       if (!tsToken || !pushToken || error) {
                                                           failure(error);
                                                           return;
                                                       }
                                                       
                                                       success(pushToken, voipToken, tsToken);
                                                   }
                                                   failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                       failure(error);
                                                   }];
}

- (TOCFuture *)registerForUserNotificationsFuture
{
    self.userNotificationFutureSource = [TOCFutureSource new];
    
    UIUserNotificationSettings *settings =
    [UIUserNotificationSettings settingsForTypes:(UIUserNotificationType)[self allNotificationTypes]
                                      categories:[NSSet setWithObjects:[self userNotificationsCallCategory],
                                                                       [self userNotificationsMessageCategory],
                                                                       [self userNotificationsCallBackCategory], nil]];
    
    [UIApplication.sharedApplication registerUserNotificationSettings:settings];
    return self.userNotificationFutureSource.future;
}

- (UIUserNotificationCategory*)userNotificationsMessageCategory{
    UIMutableUserNotificationAction *action_view  = [UIMutableUserNotificationAction new];
    action_view.identifier                        = Signal_Message_View_Identifier;
    action_view.title                             = NSLocalizedString(@"PUSH_MANAGER_VIEW", @"");
    action_view.activationMode                    = UIUserNotificationActivationModeForeground;
    action_view.destructive                       = NO;
    action_view.authenticationRequired            = YES;
    
    UIMutableUserNotificationCategory *messageCategory = [UIMutableUserNotificationCategory new];
    messageCategory.identifier = Signal_Message_Category;
    [messageCategory setActions:@[action_view] forContext:UIUserNotificationActionContextMinimal];
    [messageCategory setActions:@[action_view] forContext:UIUserNotificationActionContextDefault];
    
    return messageCategory;
}

- (UIUserNotificationCategory*)userNotificationsCallCategory{
    UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
    action_accept.identifier                       = Signal_Call_Accept_Identifier;
    action_accept.title                            = NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"");
    action_accept.activationMode                   = UIUserNotificationActivationModeForeground;
    action_accept.destructive                      = NO;
    action_accept.authenticationRequired           = NO;
    
    UIMutableUserNotificationAction *action_decline = [UIMutableUserNotificationAction new];
    action_decline.identifier                       = Signal_Call_Decline_Identifier;
    action_decline.title                            = NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"");
    action_decline.activationMode                   = UIUserNotificationActivationModeBackground;
    action_decline.destructive                      = NO;
    action_decline.authenticationRequired           = NO;
    
    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier = Signal_Call_Category;
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[action_accept, action_decline] forContext:UIUserNotificationActionContextDefault];
    
    return callCategory;
}

- (UIUserNotificationCategory*)userNotificationsCallBackCategory{
    UIMutableUserNotificationAction *action_accept = [UIMutableUserNotificationAction new];
    action_accept.identifier                       = Signal_CallBack_Identifier;
    action_accept.title                            = NSLocalizedString(@"CALLBACK_BUTTON_TITLE", @"");
    action_accept.activationMode                   = UIUserNotificationActivationModeForeground;
    action_accept.destructive                      = NO;
    action_accept.authenticationRequired           = NO;
    
    UIMutableUserNotificationCategory *callCategory = [UIMutableUserNotificationCategory new];
    callCategory.identifier = Signal_CallBack_Category;
    [callCategory setActions:@[action_accept] forContext:UIUserNotificationActionContextMinimal];
    [callCategory setActions:@[action_accept] forContext:UIUserNotificationActionContextDefault];
    
    return callCategory;
}

- (BOOL)needToRegisterForRemoteNotifications
{
    return self.wantRemoteNotifications && (!UIApplication.sharedApplication.isRegisteredForRemoteNotifications);
}

- (BOOL)wantRemoteNotifications
{
    BOOL isSimulator = [UIDevice.currentDevice.model.lowercaseString rangeOfString:@"simulator"].location != NSNotFound;
    
    if (isSimulator) {
        // Simulator is used for debugging but can't receive push notifications, so don't bother trying to get them
        return NO;
    }
    
    return YES;
}

- (int)allNotificationTypes
{
    return UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge;
}

- (void)validateUserNotificationSettings
{
    [[self registerForUserNotificationsFuture] thenDo:^(id value){
        // Nothing to do, just making sure we are registered for User Notifications.
    }];
}

#pragma mark Register Push Notification Token with RedPhone server

- (TOCFuture *)registerForPushFutureWithToken:(NSData *)pushToken voipToken:(NSData*)voipToken
{
    self.registerWithServerFutureSource = [TOCFutureSource new];
    
    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall registerPushNotificationWithPushToken:pushToken voipToken:voipToken]
                                                   success:^(NSURLSessionDataTask *task, id responseObject) {
                                                       if ([task.response isKindOfClass:NSHTTPURLResponse.class]) {
                                                           NSInteger statusCode = [(NSHTTPURLResponse *)task.response statusCode];
                                                           if (statusCode == 200) {
                                                               [self.registerWithServerFutureSource trySetResult:@YES];
                                                           } else {
                                                               DDLogError(@"The server returned %@ instead of a 200 status code", task.response);
                                                               [self.registerWithServerFutureSource
                                                                trySetFailure:[NSError errorWithDomain:pushManagerDomain code:500 userInfo:nil]];
                                                           }
                                                       } else {
                                                           [self.registerWithServerFutureSource trySetFailure:task.response];
                                                       }
                                                       
                                                   }
                                                   failure:^(NSURLSessionDataTask *task, NSError *error) {
                                                       [self.registerWithServerFutureSource trySetFailure:error];
                                                   }];
    
    return self.registerWithServerFutureSource.future;
}

- (BOOL)applicationIsActive {
    UIApplication *app = [UIApplication sharedApplication];
    
    if (app.applicationState == UIApplicationStateActive) {
        return YES;
    }
    
    return NO;
}

@end
