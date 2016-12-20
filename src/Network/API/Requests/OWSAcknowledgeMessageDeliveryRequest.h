//  Created by Michael Kirk on 12/19/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSAcknowledgeMessageDeliveryRequest : TSRequest

- (instancetype)initWithSource:(NSString *)source timestamp:(UInt64)timestamp;

@end

NS_ASSUME_NONNULL_END
