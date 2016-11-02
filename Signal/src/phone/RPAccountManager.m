//
//  RPAccountManager.m
//  Signal
//
//  Created by Frederic Jacobs on 19/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <Mantle/Mantle.h>
#import <SignalServiceKit/NSData+Base64.h>
#import "ArrayUtil.h"
#import "DataUtil.h"
#import "RPAPICall.h"
#import "RPAccountManager.h"
#import "RPServerRequestsManager.h"
#import "SignalKeyingStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface RPAccountManager ()

@property (nonatomic, readonly, strong) RPServerRequestsManager *requestManager;

@end

@implementation RPAccountManager

- (instancetype)initWithRequestManager:(RPServerRequestsManager *)requestManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _requestManager = requestManager;

    return self;
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static RPAccountManager *sharedInstance;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithRequestManager:[RPServerRequestsManager sharedManager]];
    });
    return sharedInstance;
}

- (NSData *)generateSignalingKey
{
    [SignalKeyingStorage generateServerAuthPassword];
    [SignalKeyingStorage generateSignaling];

    NSData *signalingCipherKey    = SignalKeyingStorage.signalingCipherKey;
    NSData *signalingMacKey       = SignalKeyingStorage.signalingMacKey;
    NSData *signalingExtraKey = SignalKeyingStorage.signalingExtraKey;

    return @[ signalingCipherKey, signalingMacKey, signalingExtraKey ].ows_concatDatas;
}

- (void)registerWithTsToken:(NSString *)tsToken
                    success:(void (^)())success
                    failure:(void (^)(NSError *))failure
{
    RPAPICall *request = [RPAPICall verifyWithTSToken:tsToken signalingKey:[self generateSignalingKey]];
    [self.requestManager performRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully verified RedPhone account.", self.tag);
            success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"%@ Failed to verify RedPhone account with error: %@", self.tag, error);
            failure(error);
        }];
}


- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)())successHandler
                                          failure:(void (^)(NSError *error))failureHandler
{
    RPAPICall *request = [RPAPICall registerPushNotificationWithPushToken:pushToken voipToken:voipToken];
    [self.requestManager performRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully updated push tokens.", self.tag);
            successHandler();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"%@ Failed to update push tokens: %@", self.tag, error);
            failureHandler(error);
        }];
}


#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
