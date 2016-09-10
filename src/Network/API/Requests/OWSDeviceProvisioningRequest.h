//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDeviceProvisioningRequest : TSRequest

- (instancetype)initWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId;

@end

NS_ASSUME_NONNULL_END
