//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeNetworkManager.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation OWSFakeNetworkManager

- (instancetype)init
{
    return [super initDefault];
}

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure
{
    NSLog(@"[OWSFakeNetworkManager] Ignoring unhandled request: %@", request);
}

@end

#endif

NS_ASSUME_NONNULL_END
