//  Created by Michael Kirk on 12/19/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSAcknowledgeMessageDeliveryRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAcknowledgeMessageDeliveryRequest

- (instancetype)initWithSource:(NSString *)source timestamp:(UInt64)timestamp
{
    NSString *path = [NSString stringWithFormat:@"v1/messages/%@/%llu", source, timestamp];
    NSURL *url = [NSURL URLWithString:path];

    self = [super initWithURL:url];
    self.HTTPMethod = @"DELETE";

    return self;
}

@end

NS_ASSUME_NONNULL_END
