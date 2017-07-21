//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDeleteDeviceRequest.h"
#import "OWSDevice.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDeleteDeviceRequest

- (instancetype)initWithDevice:(OWSDevice *)device
{
    NSString *deleteDevicePath = [NSString
        stringWithFormat:textSecureDevicesAPIFormat, [NSString stringWithFormat:@"%ld", (long)device.deviceId]];
    self = [super initWithURL:[NSURL URLWithString:deleteDevicePath]];
    if (!self) {
        return self;
    }

    [self setHTTPMethod:@"DELETE"];

    return self;
}

@end

NS_ASSUME_NONNULL_END