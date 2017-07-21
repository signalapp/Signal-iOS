//  Created by Michael Kirk on 11/12/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSTurnServerInfoRequest.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSTurnServerInfoRequestPath = @"v1/accounts/turn";

@implementation OWSTurnServerInfoRequest

- (instancetype)init
{
    self = [super initWithURL:[NSURL URLWithString:OWSTurnServerInfoRequestPath]];
    if (!self) {
        return self;
    }

    [self setHTTPMethod:@"GET"];

    return self;
}

@end

NS_ASSUME_NONNULL_END
