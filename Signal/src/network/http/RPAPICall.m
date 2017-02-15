//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSAccountManager.h>
#import "CryptoTools.h"
#import "PhoneNumber.h"
#import "RPAPICall.h"
#import "SignalKeyingStorage.h"
#import "Util.h"

NS_ASSUME_NONNULL_BEGIN

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1


NSString *const RPAPICallPushTokenKey = @"apnRegistrationId";
NSString *const RPAPICallVoipTokenKey = @"voipRegistrationId";
NSString *const RPAPICallSignalingKeyKey = @"signalingKey";

@interface RPAPICall ()

@property (nonatomic, readwrite) NSString *endPoint;
@property (nonatomic, readwrite) HTTPMethod method;
@property (nonatomic, readwrite) NSMutableDictionary *parameters;
@property (nonatomic, readwrite) AFHTTPRequestSerializer<AFURLRequestSerialization> *requestSerializer;
@property (nonatomic, readwrite) AFHTTPResponseSerializer<AFURLResponseSerialization> *responseSerializer;

@end

@implementation RPAPICall

+ (RPAPICall *)defaultAPICall {
    RPAPICall *apiCall         = [[RPAPICall alloc] init];
    apiCall.parameters = [NSMutableDictionary new];
    apiCall.requestSerializer  = [self basicAuthenticationSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}

+ (RPAPICall *)verifyWithTSToken:(NSString *)tsToken signalingKey:(NSData *)signalingKey
{
    RPAPICall *apiCall = [self defaultAPICall];

    apiCall.method     = HTTP_PUT;
    apiCall.endPoint   = [NSString stringWithFormat:@"/api/v1/accounts/token/%@", tsToken];
    apiCall.parameters[RPAPICallSignalingKeyKey] = [signalingKey encodedAsBase64];
    return apiCall;
}

+ (RPAPICall *)registerPushNotificationWithPushToken:(NSString *)pushToken voipToken:(NSString *)voipToken
{
    RPAPICall *apiCall = [self defaultAPICall];
    apiCall.method   = HTTP_PUT;

    apiCall.parameters[RPAPICallPushTokenKey] = pushToken;
    apiCall.parameters[RPAPICallVoipTokenKey] = voipToken;
    apiCall.endPoint = @"/api/v1/accounts/apn";

    return apiCall;
}

+ (RPAPICall *)unregisterWithPushToken:(NSData *)pushToken {
    RPAPICall *apiCall        = [self defaultAPICall];
    apiCall.method            = HTTP_DELETE;
    apiCall.endPoint          = [NSString stringWithFormat:@"/apn/%@", pushToken.encodedAsHexString];
    apiCall.requestSerializer = [self basicAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall *)requestToOpenPortWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall         = [self defaultAPICall];
    apiCall.method             = HTTP_GET;
    apiCall.endPoint           = [NSString stringWithFormat:@"/open/%lld", sessionId];
    apiCall.requestSerializer  = [self unauthenticatedSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}

+ (RPAPICall *)requestToRingWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall        = [self defaultAPICall];
    apiCall.method            = SIGNAL_RING;
    apiCall.endPoint          = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall *)requestToSignalBusyWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall        = [self defaultAPICall];
    apiCall.method            = SIGNAL_BUSY;
    apiCall.endPoint          = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall *)requestToInitiateToRemoteNumber:(PhoneNumber *)remoteNumber {
    RPAPICall *apiCall = [self defaultAPICall];

    ows_require(remoteNumber != nil);

    NSString *formattedRemoteNumber = remoteNumber.toE164;
    NSString *interopVersionInsert =
        (CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0)
            ? @""
            : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];

    apiCall.method   = HTTP_GET;
    apiCall.endPoint = [NSString stringWithFormat:@"/session%@/%@", interopVersionInsert, formattedRemoteNumber];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

#pragma mark Authorization Headers

+ (AFHTTPRequestSerializer *)basicAuthenticationSerializer {
    AFHTTPRequestSerializer *serializer = [AFJSONRequestSerializer serializerWithWritingOptions:0];
    [serializer setValue:[self computeBasicAuthorizationTokenForLocalNumber:[TSAccountManager localNumber]
                                                                andPassword:SignalKeyingStorage.serverAuthPassword]
        forHTTPHeaderField:@"Authorization"];
    return serializer;
}

+ (AFHTTPRequestSerializer *)otpAuthenticationSerializer {
    AFHTTPRequestSerializer *serializer = [AFJSONRequestSerializer serializerWithWritingOptions:0];
    [serializer setValue:[self computeOtpAuthorizationTokenForLocalNumber:[TSAccountManager localNumber]
                                                          andCounterValue:[SignalKeyingStorage
                                                                              getAndIncrementOneTimeCounter]
                                                              andPassword:SignalKeyingStorage.serverAuthPassword]
        forHTTPHeaderField:@"Authorization"];
    return serializer;
}

+ (AFHTTPRequestSerializer *)unauthenticatedSerializer {
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    return serializer;
}

+ (NSString *)computeOtpAuthorizationTokenForLocalNumber:(NSString *)localNumber
                                         andCounterValue:(int64_t)counterValue
                                             andPassword:(NSString *)password {
    ows_require(localNumber != nil);
    ows_require(password != nil);

    NSString *rawToken =
        [NSString stringWithFormat:@"%@:%@:%lld",
                                   localNumber,
                                   [CryptoTools computeOtpWithPassword:password andCounter:counterValue],
                                   counterValue];
    return [@"OTP " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

+ (NSString *)computeBasicAuthorizationTokenForLocalNumber:(NSString *)localNumber andPassword:(NSString *)password {
    NSString *rawToken = [NSString stringWithFormat:@"%@:%@", localNumber, password];
    return [@"Basic " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

/* <---> Registering with on RP server is soon going to be deprecated

 + (RPAPICall*)requestVerificationCode {
 [SignalKeyingStorage generateServerAuthPassword];
 RPAPICall *apiCall = [self defaultAPICall];
 apiCall.method = HTTP_GET;
 apiCall.endPoint = @"/users/verification/sms?client=ios";
 return apiCall;
 }

 + (RPAPICall*)requestVerificationCodeWithVoice {
 RPAPICall *apiCall = [self requestVerificationCode];
 apiCall.endPoint   = @"/users/verification/voice?client=ios";
 return apiCall;
 }



 + (RPAPICall *)verifyVerificationCode:(NSString *)verificationCode {
 RPAPICall *apiCall = [self defaultAPICall];
 [SignalKeyingStorage generateSignaling];
 apiCall.method   = HTTP_PUT;
 apiCall.endPoint = [NSString stringWithFormat:@"/users/verification/%@", SignalKeyingStorage.localNumber];

 NSData *signalingCipherKey    = SignalKeyingStorage.signalingCipherKey;
 NSData *signalingMacKey       = SignalKeyingStorage.signalingMacKey;
 NSData *signalingExtraKeyData = SignalKeyingStorage.signalingExtraKey;
 NSString *encodedSignalingKey =
 @[ signalingCipherKey, signalingMacKey, signalingExtraKeyData ].ows_concatDatas.encodedAsBase64;
 apiCall.parameters = @{ @"key" : encodedSignalingKey, @"challenge" : verificationCode };

 return apiCall;
 }

 + (RPAPICall *)requestTextSecureVerificationCode {
 RPAPICall *apiCall = [self defaultAPICall];
 apiCall.method     = HTTP_GET;
 apiCall.endPoint   = [NSString stringWithFormat:@"/users/verification/textsecure"];
 return apiCall;
 }
 */

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@", [super description], self.endPoint];
}

@end

NS_ASSUME_NONNULL_END
