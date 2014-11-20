//
//  RedPhoneAPICall.h
//  Signal
//
//  Created by Frederic Jacobs on 05/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>
@class PhoneNumber;

@interface RPAPICall : NSObject

typedef NS_ENUM(NSInteger, HTTPMethod) {
    HTTP_GET,
    HTTP_POST,
    HTTP_PUT,
    HTTP_DELETE,
    SIGNAL_RING,
    SIGNAL_BUSY
};

#pragma mark API Call Properties

@property (nonatomic, readonly) NSString* endPoint;
@property (nonatomic, readonly) HTTPMethod method;
@property (nonatomic, readonly) NSDictionary* parameters;
@property (nonatomic, readonly) AFHTTPRequestSerializer  <AFURLRequestSerialization>*  requestSerializer;
@property (nonatomic, readonly) AFHTTPResponseSerializer <AFURLResponseSerialization>* responseSerializer;

#pragma mark API Call Contstructors

+ (RPAPICall*)requestVerificationCode;
+ (RPAPICall*)requestVerificationCodeWithVoice;
+ (RPAPICall*)verifyVerificationCode:(NSString*)verificationCode;
+ (RPAPICall*)registerPushNotificationWithPushToken:(NSData*)pushToken;
+ (RPAPICall*)unregister;

+ (RPAPICall*)fetchBloomFilter;

//+ (RPAPICall*)requestToOpenPortWithSessionId:(int64_t)sessionId;
//+ (RPAPICall*)requestToRingWithSessionId:(int64_t)sessionId;
//+ (RPAPICall*)requestToSignalBusyWithSessionId:(int64_t)sessionId;
//+ (RPAPICall*)requestToInitiateToRemoteNumber:(PhoneNumber*)remoteNumber;

@end
