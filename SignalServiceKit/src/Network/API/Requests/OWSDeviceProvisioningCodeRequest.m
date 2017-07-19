//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDeviceProvisioningCodeRequest.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDeviceProvisioningCodeRequest

- (instancetype)init
{
    self = [super initWithURL:[NSURL URLWithString:textSecureDeviceProvisioningCodeAPI]];
    if (!self) {
        return self;
    }

    [self setHTTPMethod:@"GET"];

    return self;
}

@end

NS_ASSUME_NONNULL_END
