//  Created by Frederic Jacobs on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSMessageServiceParams.h"
#import "NSData+Base64.h"
#import "TSConstants.h"

@implementation OWSMessageServiceParams

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    return [NSDictionary mtl_identityPropertyMapWithModel:[self class]];
}

- (instancetype)initWithType:(TSWhisperMessageType)type
                 recipientId:(NSString *)destination
                      device:(int)deviceId
                     content:(NSData *)content
              registrationId:(int)registrationId
{
    self = [super init];

    if (!self) {
        return self;
    }

    _type = type;
    _destination = destination;
    _destinationDeviceId = deviceId;
    _destinationRegistrationId = registrationId;
    _content = [content base64EncodedString];

    return self;
}

@end
