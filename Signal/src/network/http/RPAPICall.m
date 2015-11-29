//
//  RedPhoneAPICall.m
//  Signal
//
//  Created by Frederic Jacobs on 05/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Constraints.h"
#import "CryptoTools.h"
#import "PhoneNumber.h"
#import "RPAPICall.h"
#import "SignalKeyingStorage.h"
#import "Util.h"
#import "NSData+ows_StripToken.h"

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1

@interface RPAPICall ()
@property (nonatomic, readwrite) NSString *endPoint;
@property (nonatomic, readwrite) HTTPMethod method;
@property (nonatomic, readwrite) NSDictionary *parameters;
@property (nonatomic, readwrite) AFHTTPRequestSerializer  <AFURLRequestSerialization>  *requestSerializer;
@property (nonatomic, readwrite) AFHTTPResponseSerializer <AFURLResponseSerialization> *responseSerializer;
@end

@implementation RPAPICall

+ (RPAPICall*)defaultAPICall {
    RPAPICall *apiCall         = [[RPAPICall alloc] init];
    apiCall.parameters         = @{};
    apiCall.requestSerializer  = [self basicAuthenticationSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}


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

+ (RPAPICall*)verifyVerificationCode:(NSString*)verificationCode {
    RPAPICall *apiCall = [self defaultAPICall];
    [SignalKeyingStorage generateSignaling];
    apiCall.method = HTTP_PUT;
    apiCall.endPoint = [NSString stringWithFormat:@"/users/verification/%@", SignalKeyingStorage.localNumber];
    
    NSData* signalingCipherKey    = SignalKeyingStorage.signalingCipherKey;
    NSData* signalingMacKey       = SignalKeyingStorage.signalingMacKey;
    NSData* signalingExtraKeyData = SignalKeyingStorage.signalingExtraKey;
    NSString* encodedSignalingKey = @[signalingCipherKey, signalingMacKey, signalingExtraKeyData].ows_concatDatas.encodedAsBase64;
    apiCall.parameters            = @{@"key" : encodedSignalingKey, @"challenge" : verificationCode};

    return apiCall;
}

+ (RPAPICall*)registerPushNotificationWithPushToken:(NSData*)pushToken voipToken:(NSData*)voipToken {
    RPAPICall *apiCall = [self defaultAPICall];
    if (voipToken) {
        apiCall.parameters = @{@"voip":[voipToken ows_tripToken]};
    } else {
        DDLogWarn(@"No VoIP push token registered, might experience some issues while in background.");
    }
    apiCall.method     = HTTP_PUT;
    apiCall.endPoint   = [NSString stringWithFormat:@"/apn/%@", [pushToken ows_tripToken]];
    return apiCall;
}

+ (RPAPICall*)requestTextSecureVerificationCode{
    RPAPICall *apiCall = [self defaultAPICall];
    apiCall.method     = HTTP_GET;
    apiCall.endPoint   = [NSString stringWithFormat:@"/users/verification/textsecure"];
    return apiCall;
}

+ (RPAPICall*)unregisterWithPushToken:(NSData*)pushToken {
    RPAPICall *apiCall         = [self defaultAPICall];
    apiCall.method             = HTTP_DELETE;
    apiCall.endPoint           = [NSString stringWithFormat:@"/apn/%@", pushToken.encodedAsHexString];
    apiCall.parameters         = nil;
    apiCall.requestSerializer  = [self basicAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToOpenPortWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall         = [self defaultAPICall];
    apiCall.method             = HTTP_GET;
    apiCall.endPoint           = [NSString stringWithFormat:@"/open/%lld", sessionId];
    apiCall.requestSerializer  = [self unauthenticatedSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}

+ (RPAPICall*)requestToRingWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall         = [self defaultAPICall];
    apiCall.method             = SIGNAL_RING;
    apiCall.endPoint           = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer  = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToSignalBusyWithSessionId:(int64_t)sessionId {
    RPAPICall *apiCall         = [self defaultAPICall];
    apiCall.method             = SIGNAL_BUSY;
    apiCall.endPoint           = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer  = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber {
    RPAPICall *apiCall              = [self defaultAPICall];

    require(remoteNumber != nil);

    NSString* formattedRemoteNumber = remoteNumber.toE164;
    NSString* interopVersionInsert  = (CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0)? @"" : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];

    apiCall.method                  = HTTP_GET;
    apiCall.endPoint                = [NSString stringWithFormat:@"/session%@/%@", interopVersionInsert, formattedRemoteNumber];
    apiCall.requestSerializer       = [self otpAuthenticationSerializer];
    return apiCall;
}

#pragma mark Authorization Headers

+ (AFHTTPRequestSerializer*)basicAuthenticationSerializer {
    AFHTTPRequestSerializer *serializer = [AFJSONRequestSerializer serializerWithWritingOptions:0];
    [serializer setValue:[self computeBasicAuthorizationTokenForLocalNumber:SignalKeyingStorage.localNumber andPassword:SignalKeyingStorage.serverAuthPassword]forHTTPHeaderField:@"Authorization"];
    return serializer;
}

+ (AFHTTPRequestSerializer*)otpAuthenticationSerializer {
    AFHTTPRequestSerializer *serializer = [AFJSONRequestSerializer serializerWithWritingOptions:0];
    [serializer setValue:[self computeOtpAuthorizationTokenForLocalNumber:SignalKeyingStorage.localNumber andCounterValue:[SignalKeyingStorage getAndIncrementOneTimeCounter] andPassword:SignalKeyingStorage.serverAuthPassword] forHTTPHeaderField:@"Authorization"];
    return serializer;
}

+ (AFHTTPRequestSerializer*)unauthenticatedSerializer {
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    return serializer;
}

+ (NSString*) computeOtpAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                        andCounterValue:(int64_t)counterValue
                                            andPassword:(NSString*)password {
    require(localNumber != nil);
    require(password != nil);
    
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@:%lld",
                          localNumber.toE164,
                          [CryptoTools computeOtpWithPassword:password andCounter:counterValue],
                          counterValue];
    return [@"OTP " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

+ (NSString*) computeBasicAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber andPassword:(NSString*)password {
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@",
                          localNumber.toE164,
                          password];
    return [@"Basic " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

@end
