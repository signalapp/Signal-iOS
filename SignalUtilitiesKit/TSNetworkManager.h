//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const TSNetworkManagerErrorDomain;
typedef NS_ERROR_ENUM(TSNetworkManagerErrorDomain, TSNetworkManagerError){
    // It's a shame to use 0 as an enum value for anything other than something like default or unknown, because it's
    // indistinguishable from "not set" in Objc.
    // However this value was existing behavior for connectivity errors, and since we might be using this in other
    // places I didn't want to change it out of hand
    TSNetworkManagerErrorFailedConnection = 0,
    // Other TSNetworkManagerError's use HTTP status codes (e.g. 404, etc)
};

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
