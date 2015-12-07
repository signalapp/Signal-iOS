//
//  TSServerMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSServerMessage.h"

#import "NSData+Base64.h"

@interface TSServerMessage ()

@property int type;
@property NSString *destination;
@property int destinationDeviceId;
@property int destinationRegistrationId;
@property NSString *body;

@end

@implementation TSServerMessage

+ (NSDictionary *)JSONKeyPathsByPropertyKey {
    return [NSDictionary mtl_identityPropertyMapWithModel:[TSServerMessage class]];
}

- (instancetype)initWithType:(TSWhisperMessageType)type
                 destination:(NSString *)destination
                      device:(int)deviceId
                        body:(NSData *)body
              registrationId:(int)registrationId {
    self = [super init];

    if (self) {
        _type                      = type;
        _destination               = destination;
        _destinationDeviceId       = deviceId;
        _destinationRegistrationId = registrationId;
        _body                      = [body base64EncodedString];
    }

    return self;
}

@end
