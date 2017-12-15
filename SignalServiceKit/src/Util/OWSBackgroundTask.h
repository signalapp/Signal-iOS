//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

typedef NS_ENUM(NSUInteger, BackgroundTaskState) {
    BackgroundTaskState_Success,
    BackgroundTaskState_CouldNotStart,
    BackgroundTaskState_Expired,
};

typedef void (^BackgroundTaskCompletionBlock)(BackgroundTaskState backgroundTaskState);

@interface OWSBackgroundTask : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr;

// completionBlock will be called exactly once on the main thread.
+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr
                                  completionBlock:(BackgroundTaskCompletionBlock)completionBlock;

+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label;

// completionBlock will be called exactly once on the main thread.
+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label
                               completionBlock:(BackgroundTaskCompletionBlock)completionBlock;

@end
