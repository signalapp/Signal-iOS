//  Created by Michael Kirk on 12/19/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSGetMessagesRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSGetMessagesRequest

- (instancetype)init
{
    NSURL *url = [NSURL URLWithString:@"v1/messages"];
    return [super initWithURL:url];
}

@end

NS_ASSUME_NONNULL_END
