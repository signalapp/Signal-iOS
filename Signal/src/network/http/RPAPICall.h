//
//  RedPhoneAPICall.h
//  Signal
//
//  Created by Frederic Jacobs on 05/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>
#import <Foundation/Foundation.h>
@class PhoneNumber;

@interface RPAPICall : NSObject

typedef NS_ENUM(NSInteger, HTTPMethod) { HTTP_GET, HTTP_POST, HTTP_PUT, HTTP_DELETE, SIGNAL_RING, SIGNAL_BUSY };

#pragma mark API Call Properties

@property (nonatomic, readonly) NSString *endPoint;
@property (nonatomic, readonly) HTTPMethod method;
@property (nonatomic, readonly) NSDictionary *parameters;
@property (nonatomic, readonly) AFHTTPRequestSerializer<AFURLRequestSerialization> *requestSerializer;
@property (nonatomic, readonly) AFHTTPResponseSerializer<AFURLResponseSerialization> *responseSerializer;

#pragma mark API Call Contstructors

+ (RPAPICall *)registerPushNotificationWithPushToken:(NSData *)pushToken voipToken:(NSData *)voipToken;
+ (RPAPICall *)unregisterWithPushToken:(NSData *)pushToken;
+ (RPAPICall *)verifyWithTSToken:(NSString *)tsToken attributesParameters:(NSDictionary *)attributes;

@end
