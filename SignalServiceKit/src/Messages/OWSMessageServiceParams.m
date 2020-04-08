//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageServiceParams.h"
#import "TSConstants.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageServiceParams

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    return [NSDictionary mtl_identityPropertyMapWithModel:[self class]];
}

- (instancetype)initWithType:(TSWhisperMessageType)type
                     address:(SignalServiceAddress *)address
                      device:(int)deviceId
                     content:(NSData *)content
                    isSilent:(BOOL)isSilent
                    isOnline:(BOOL)isOnline
              registrationId:(int)registrationId
{
    OWSAssertDebug(address.isValid);
    self = [super init];

    if (!self) {
        return self;
    }

    _type = (int) type;
    _destination = address.serviceIdentifier;
    OWSAssertDebug(_destination != nil);
    _destinationDeviceId = deviceId;
    _destinationRegistrationId = registrationId;
    _content = [content base64EncodedString];
    _silent = isSilent;
    _online = isOnline;

    return self;
}

@end

NS_ASSUME_NONNULL_END
