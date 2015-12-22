//
//  RPAccountManager.m
//  Signal
//
//  Created by Frederic Jacobs on 19/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <Mantle/Mantle.h>
#import <TextSecureKit/NSData+Base64.h>
#import "ArrayUtil.h"
#import "DataUtil.h"
#import "RPAPICall.h"
#import "RPAccountManager.h"
#import "RPServerRequestsManager.h"
#import "SignalKeyingStorage.h"

@interface RedPhoneAccountAttributes : MTLModel

@property (nonatomic, copy, readonly) NSString *signalingKey;
@property (nonatomic, copy, readonly) NSString *apnRegistrationId;
@property (nonatomic, copy, readonly) NSString *voipRegistrationId;


- (instancetype)initWithSignalingCipherKey:(NSData *)signalingCipherKey
                           signalingMacKey:(NSData *)signalingMacKey
                         signalingExtraKey:(NSData *)signalingExtraKey
                         apnRegistrationId:(NSString *)apnRegistrationId
                        voipRegistrationId:(NSString *)voipRegistrationId;

@end

@implementation RedPhoneAccountAttributes

- (instancetype)initWithSignalingCipherKey:(NSData *)signalingCipherKey
                           signalingMacKey:(NSData *)signalingMacKey
                         signalingExtraKey:(NSData *)signalingExtraKey
                         apnRegistrationId:(NSString *)apnRegistrationId
                        voipRegistrationId:(NSString *)voipRegistrationId {
    self = [super init];

    if (self) {
        _signalingKey = @[ signalingCipherKey, signalingMacKey, signalingExtraKey ].ows_concatDatas.encodedAsBase64;
        _apnRegistrationId  = apnRegistrationId;
        _voipRegistrationId = voipRegistrationId;
    }

    return self;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dictionaryValue = [[super dictionaryValue] mutableCopy];
    if (!_voipRegistrationId) {
        [dictionaryValue removeObjectForKey:@"voipRegistrationId"];
    }

    return dictionaryValue;
}

@end

@implementation RPAccountManager

+ (void)generateKeyingMaterial {
    [SignalKeyingStorage generateServerAuthPassword];
    [SignalKeyingStorage generateSignaling];
}

+ (NSDictionary *)attributesWithPushToken:(NSString *)pushToken voipToken:(NSString *)voipPushToken {
    NSData *signalingCipherKey    = SignalKeyingStorage.signalingCipherKey;
    NSData *signalingMacKey       = SignalKeyingStorage.signalingMacKey;
    NSData *signalingExtraKeyData = SignalKeyingStorage.signalingExtraKey;


    return [[RedPhoneAccountAttributes alloc] initWithSignalingCipherKey:signalingCipherKey
                                                         signalingMacKey:signalingMacKey
                                                       signalingExtraKey:signalingExtraKeyData
                                                       apnRegistrationId:pushToken
                                                      voipRegistrationId:voipPushToken]
        .dictionaryValue;
}

+ (void)registrationWithTsToken:(NSString *)tsToken
                      pushToken:(NSString *)pushToken
                      voipToken:(NSString *)voipPushToken
                        success:(void (^)())success
                        failure:(void (^)(NSError *))failure {
    [self generateKeyingMaterial];

    [[RPServerRequestsManager sharedManager]
        performRequest:[RPAPICall verifyWithTSToken:tsToken
                               attributesParameters:[self attributesWithPushToken:pushToken voipToken:voipPushToken]]
        success:^(NSURLSessionDataTask *task, id responseObject) {
          success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failure(error);
        }];
}

+ (void)unregister {
}

@end
