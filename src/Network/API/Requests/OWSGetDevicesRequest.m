//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSGetDevicesRequest.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGetDevicesRequest

- (instancetype)init
{
    NSString *getDevicesPath = [NSString stringWithFormat:textSecureDevicesAPIFormat, @""];
    self = [super initWithURL:[NSURL URLWithString:getDevicesPath]];
    if (!self) {
        return self;
    }

    [self setHTTPMethod:@"GET"];

    return self;
}

@end

NS_ASSUME_NONNULL_END
