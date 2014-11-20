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
#import "HTTPRequest+SignalUtil.h"
#import "SGNKeychainUtil.h"
#import "Util.h"

#define CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL 1

@interface RPAPICall ()
@property (nonatomic, readwrite) NSString* endPoint;
@property (nonatomic, readwrite) HTTPMethod method;
@property (nonatomic, readwrite) NSDictionary* parameters;
@property (nonatomic, readwrite) AFHTTPRequestSerializer  <AFURLRequestSerialization>*  requestSerializer;
@property (nonatomic, readwrite) AFHTTPResponseSerializer <AFURLResponseSerialization>* responseSerializer;
@end

@implementation RPAPICall

+ (RPAPICall*)defaultAPICall {
    RPAPICall* apiCall = [[RPAPICall alloc] init];
    apiCall.parameters = @{};
    apiCall.requestSerializer  = [self basicAuthenticationSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}


+ (RPAPICall*)requestVerificationCode {
    [SGNKeychainUtil generateServerAuthPassword];
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = HTTP_GET;
    apiCall.endPoint = @"/users/verification";
    return apiCall;
}

+ (RPAPICall*)requestVerificationCodeWithVoice {
    RPAPICall* apiCall = [self requestVerificationCode];
    apiCall.endPoint = [apiCall.endPoint stringByAppendingString:@"/voice"];
    return apiCall;
}

+ (RPAPICall*)verifyVerificationCode:(NSString*)verificationCode {
    RPAPICall* apiCall = [self defaultAPICall];
    [SGNKeychainUtil generateSignaling];
    apiCall.method = HTTP_PUT;
    apiCall.endPoint = [NSString stringWithFormat:@"/users/verification/%@", SGNKeychainUtil.localNumber];
    
    NSData* signalingCipherKey = SGNKeychainUtil.signalingCipherKey;
    NSData* signalingMacKey = SGNKeychainUtil.signalingMacKey;
    NSData* signalingExtraKeyData = SGNKeychainUtil.signalingCipherKey;
    NSString* encodedSignalingKey = @[signalingCipherKey, signalingMacKey, signalingExtraKeyData].concatDatas.encodedAsBase64;
    apiCall.parameters = @{@"key" : encodedSignalingKey, @"challenge" : verificationCode};
    return apiCall;
}

+ (RPAPICall*)registerPushNotificationWithPushToken:(NSData*)pushToken {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method   = HTTP_PUT;
    apiCall.endPoint = [NSString stringWithFormat:@"/apn/%@", pushToken.encodedAsHexString];
    return apiCall;
}

+ (RPAPICall*)fetchBloomFilter {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = HTTP_GET;
    apiCall.endPoint = @"/users/directory";
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)unregister {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = HTTP_GET;
    apiCall.endPoint = @"/users/directory";
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToOpenPortWithSessionId:(int64_t)sessionId {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = HTTP_GET;
    apiCall.endPoint = [NSString stringWithFormat:@"/open/%lld", sessionId];
    apiCall.requestSerializer = [self unauthenticatedSerializer];
    apiCall.responseSerializer = [AFHTTPResponseSerializer serializer];
    return apiCall;
}

+ (RPAPICall*)requestToRingWithSessionId:(int64_t)sessionId {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = SIGNAL_RING;
    apiCall.endPoint = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToSignalBusyWithSessionId:(int64_t)sessionId {
    RPAPICall* apiCall = [self defaultAPICall];
    apiCall.method = SIGNAL_BUSY;
    apiCall.endPoint = [NSString stringWithFormat:@"/session/%lld", sessionId];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

+ (RPAPICall*)requestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber {
    RPAPICall* apiCall = [self defaultAPICall];
    
    require(remoteNumber != nil);
    
    NSString* formattedRemoteNumber = remoteNumber.toE164;
    NSString* interopVersionInsert = (CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL == 0)? @"" : [NSString stringWithFormat:@"/%d", CLAIMED_INTEROP_VERSION_IN_INITIATE_SIGNAL];
    
    apiCall.method = HTTP_GET;
    apiCall.endPoint = [NSString stringWithFormat:@"/session%@/%@",
                        interopVersionInsert,
                        formattedRemoteNumber];
    apiCall.requestSerializer = [self otpAuthenticationSerializer];
    return apiCall;
}

#pragma mark Authorization Headers

+ (AFHTTPRequestSerializer*)basicAuthenticationSerializer {
    AFHTTPRequestSerializer* serializer = [AFJSONRequestSerializer serializer];
    [serializer setAuthorizationHeaderFieldWithUsername:SGNKeychainUtil.localNumber.toE164 password:SGNKeychainUtil.serverAuthPassword];
    return serializer;
}

+ (AFHTTPRequestSerializer*)otpAuthenticationSerializer {
    AFHTTPRequestSerializer* serializer = [AFJSONRequestSerializer serializer];
    [serializer setAuthorizationHeaderFieldWithUsername:SGNKeychainUtil.localNumber.toE164 password:SGNKeychainUtil.serverAuthPassword];
    return serializer;
}

+ (AFHTTPRequestSerializer*)unauthenticatedSerializer {
    return [AFHTTPRequestSerializer serializer];
}

+ (NSString*)computeOTPAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                        andCounterValue:(int64_t)counterValue
                                            andPassword:(NSString*)password {
    require(localNumber != nil);
    require(password != nil);
    
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@:%lld",
                          localNumber.toE164,
                          [CryptoTools computeOTPWithPassword:password andCounter:counterValue],
                          counterValue];
    return [@"OTP " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

+ (NSString*)computeBasicAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber andPassword:(NSString*)password {
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@",
                          localNumber.toE164,
                          password];
    return [@"Basic " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

@end
