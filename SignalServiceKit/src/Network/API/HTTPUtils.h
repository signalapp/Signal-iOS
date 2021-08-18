//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

BOOL IsNetworkConnectivityFailure(NSError *_Nullable error);
NSNumber *_Nullable HTTPStatusCodeForError(NSError *_Nullable error);
NSDate *_Nullable HTTPRetryAfterDateForError(NSError *_Nullable error);
NSData *_Nullable HTTPResponseDataForError(NSError *_Nullable error);

dispatch_queue_t NetworkManagerQueue(void);

#define OWSFailDebugUnlessNetworkFailure(error)                                                                        \
    if (IsNetworkConnectivityFailure(error)) {                                                                         \
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
