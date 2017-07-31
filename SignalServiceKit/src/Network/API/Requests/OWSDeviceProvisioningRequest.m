//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDeviceProvisioningRequest.h"
#import "TSConstants.h"
#import <SignalServiceKit/NSData+Base64.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDeviceProvisioningRequest

- (instancetype)initWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId
{
    NSString *path = [NSString stringWithFormat:textSecureDeviceProvisioningAPIFormat, deviceId];
    self = [super initWithURL:[NSURL URLWithString:path]];
    if (!self) {
        return self;
    }

    self.HTTPMethod = @"PUT";
    [self.parameters addEntriesFromDictionary:@{ @"body" : [messageBody base64EncodedString] }];

    return self;
}

@end

NS_ASSUME_NONNULL_END
