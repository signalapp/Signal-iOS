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

#define pushManagerDomain @"org.whispersystems.pushmanager"

@interface PushManager ()

@property TOCFutureSource *registerWithServerFutureSource;
@property UIAlertView     *missingPermissionsAlertView;

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
        self.missingPermissionsAlertView =
            [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ACTION_REQUIRED_TITLE", @"")
                                       message:NSLocalizedString(@"PUSH_SETTINGS_MESSAGE", @"")
                                      delegate:nil
                             cancelButtonTitle:NSLocalizedString(@"OK", @"")
                             otherButtonTitles:nil, nil];
    }
    return self;
}

#pragma mark Register device for Push Notification locally

- (TOCFuture *)registerPushNotificationFuture
{
    self.pushNotificationFutureSource = [TOCFutureSource new];
    [UIApplication.sharedApplication registerForRemoteNotifications];

    return self.pushNotificationFutureSource.future;
}

- (void)requestPushTokenWithSuccess:(void (^)(NSData *pushToken))success failure:(failedPushRegistrationBlock)failure
{
    TOCFuture *requestPushTokenFuture = [self registerPushNotificationFuture];

    [requestPushTokenFuture catchDo:^(id failureObj) {
      [self.missingPermissionsAlertView show];
      failure(failureObj);
      DDLogError(@"This should not happen on iOS8. No push token was provided");
    }];

    [requestPushTokenFuture thenDo:^(NSData *pushToken) {
      TOCFuture *registerPushTokenFuture = [self registerForPushFutureWithToken:pushToken];

      [registerPushTokenFuture catchDo:^(id failureObj) {
        failure(failureObj);
      }];

      [registerPushTokenFuture thenDo:^(id value) {
        TOCFuture *userRegistration = [self registerForUserNotificationsFuture];

        [userRegistration thenDo:^(UIUserNotificationSettings *userNotificationSettings) {
          success(pushToken);
        }];
      }];
    }];
}

- (void)registrationAndRedPhoneTokenRequestWithSuccess:(void (^)(NSData *pushToken, NSString *signupToken))success
                                               failure:(failedPushRegistrationBlock)failure
{
    if (!self.wantRemoteNotifications) {
        [self registerTokenWithRedPhoneServer:[@"Fake PushToken" dataUsingEncoding:NSUTF8StringEncoding]
                                  withSuccess:success
                                      failure:failure];
        return;
    }

    [self requestPushTokenWithSuccess:^(NSData *pushToken) {
      [self registerTokenWithRedPhoneServer:pushToken withSuccess:success failure:failure];
    } failure:^(NSError *error) {
      [self.missingPermissionsAlertView show];
      failure([NSError errorWithDomain:pushManagerDomain code:400 userInfo:@{}]);
    }];
}

- (void)registerTokenWithRedPhoneServer:(NSData *)pushToken
                            withSuccess:(void (^)(NSData *pushToken, NSString *signupToken))success
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

          success(pushToken, tsToken);
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
                                          categories:nil];
    [UIApplication.sharedApplication registerUserNotificationSettings:settings];
    return self.userNotificationFutureSource.future;
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

- (TOCFuture *)registerForPushFutureWithToken:(NSData *)token
{
    self.registerWithServerFutureSource = [TOCFutureSource new];

    [RPServerRequestsManager.sharedInstance performRequest:[RPAPICall registerPushNotificationWithPushToken:token]
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

@end
