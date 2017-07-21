//  Created by Michael Kirk on 10/19/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeNetworkManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeNetworkManager

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    NSLog(@"[OWSFakeNetworkManager] Ignoring unhandled request: %@", request);
}

@end

NS_ASSUME_NONNULL_END
