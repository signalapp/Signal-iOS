//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSNetworkManagerDomain;

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error);

typedef void (^TSNetworkManagerSuccess)(NSURLSessionDataTask *task, _Nullable id responseObject);
typedef void (^TSNetworkManagerFailure)(NSURLSessionDataTask *task, NSError *error);

@class TSRequest;

@interface TSNetworkManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault;

+ (instancetype)sharedManager;

- (void)makeRequest:(TSRequest *)request
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure NS_SWIFT_NAME(makeRequest(_:success:failure:));

- (void)makeRequest:(TSRequest *)request
    completionQueue:(dispatch_queue_t)completionQueue
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure NS_SWIFT_NAME(makeRequest(_:completionQueue:success:failure:));

@end

NS_ASSUME_NONNULL_END
