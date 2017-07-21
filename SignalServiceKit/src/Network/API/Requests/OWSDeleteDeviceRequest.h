//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDevice;

@interface OWSDeleteDeviceRequest : TSRequest

- (instancetype)initWithDevice:(OWSDevice *)device;

@end

NS_ASSUME_NONNULL_END