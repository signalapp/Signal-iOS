//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSFakeNetworkManager.h>

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
    OWSLogInfo(@"[OWSFakeNetworkManager] Ignoring unhandled request: %@", request);
}

@end

#endif

NS_ASSUME_NONNULL_END
