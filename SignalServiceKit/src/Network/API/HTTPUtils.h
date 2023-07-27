//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

dispatch_queue_t NetworkManagerQueue(void);

#define OWSFailDebugUnlessNetworkFailure(error)                                                                        \
    if (error.isNetworkFailureOrTimeout) {                                                                             \
        OWSLogWarn(@"Error: %@", error);                                                                               \
    } else {                                                                                                           \
        OWSFailDebug(@"Error: %@", error);                                                                             \
    }

#pragma mark -

@interface HTTPUtils : NSObject

#if TESTABLE_BUILD
+ (void)logCurlForTask:(NSURLSessionTask *)task;
+ (void)logCurlForURLRequest:(NSURLRequest *)originalRequest;
#endif

@end

NS_ASSUME_NONNULL_END
