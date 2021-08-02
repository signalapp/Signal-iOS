//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSRequest;

@protocol HTTPResponse;

@class OWSHTTPErrorWrapper;

typedef void (^RESTNetworkManagerSuccess)(id<HTTPResponse> response);
typedef void (^RESTNetworkManagerFailure)(OWSHTTPErrorWrapper *error);

#pragma mark -

@interface RESTNetworkManager : NSObject

- (void)makeRequest:(TSRequest *)request
    completionQueue:(dispatch_queue_t)completionQueue
            success:(RESTNetworkManagerSuccess)success
            failure:(RESTNetworkManagerFailure)failure NS_SWIFT_NAME(makeRequest(_:completionQueue:success:failure:));

@end

NS_ASSUME_NONNULL_END
