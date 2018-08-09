//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageServiceParams.h"
#import "NSData+OWS.h"
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
                    isSilent:(BOOL)isSilent
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
    _silent = isSilent;

    return self;
}

@end
