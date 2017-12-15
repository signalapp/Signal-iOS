//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSBackgroundTask.h"
#import "AppContext.h"

@interface OWSBackgroundTask ()

@property (nonatomic, readonly) NSString *label;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;

@property (nonatomic, nullable) BackgroundTaskCompletionBlock completionBlock;

@end

#pragma mark -

@implementation OWSBackgroundTask

+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr
{
    OWSAssert(labelStr);

    NSString *label = [NSString stringWithFormat:@"%s", labelStr];
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:nil];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabelStr:(const char *)labelStr
                                  completionBlock:(BackgroundTaskCompletionBlock)completionBlock
{

    OWSAssert(labelStr);

    NSString *label = [NSString stringWithFormat:@"%s", labelStr];
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:completionBlock];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label
{
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:nil];
}

+ (OWSBackgroundTask *)backgroundTaskWithLabel:(NSString *)label
                               completionBlock:(BackgroundTaskCompletionBlock)completionBlock
{
    return [[OWSBackgroundTask alloc] initWithLabel:label completionBlock:completionBlock];
}

- (instancetype)initWithLabel:(NSString *)label completionBlock:(BackgroundTaskCompletionBlock _Nullable)completionBlock
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(label.length > 0);

    _label = label;
    self.completionBlock = completionBlock;

    [self startBackgroundTask];

    return self;
}

- (void)dealloc
{
    [self endBackgroundTask];
}

- (void)startBackgroundTask
{
    __weak typeof(self) weakSelf = self;
    // beginBackgroundTaskWithExpirationHandler must be called on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        self.backgroundTaskId = [CurrentAppContext() beginBackgroundTaskWithExpirationHandler:^{
            OWSAssert([NSThread isMainThread]);
            __strong typeof(self) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            @synchronized(strongSelf)
            {
                if (strongSelf.backgroundTaskId == UIBackgroundTaskInvalid) {
                    return;
                }
                DDLogInfo(@"%@ %@ background task expired", strongSelf.logTag, strongSelf.label);
                strongSelf.backgroundTaskId = UIBackgroundTaskInvalid;

                if (strongSelf.completionBlock) {
                    strongSelf.completionBlock(BackgroundTaskState_Expired);
                    strongSelf.completionBlock = nil;
                }
            }
        }];

        // If a background task could not be begun, call the completion block.
        if (self.backgroundTaskId == UIBackgroundTaskInvalid) {
            BackgroundTaskCompletionBlock _Nullable completionBlock;
            @synchronized(self)
            {
                completionBlock = self.completionBlock;
                self.completionBlock = nil;
            }
            if (completionBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(BackgroundTaskState_CouldNotStart);
                });
            }
        }
    });
}

- (void)endBackgroundTask
{
    // Make a local copy of this state, since this method is called by `dealloc`.
    UIBackgroundTaskIdentifier backgroundTaskId;
    NSString *logTag = self.logTag;
    NSString *label = self.label;
    BackgroundTaskCompletionBlock _Nullable completionBlock = self.completionBlock;

    @synchronized(self)
    {
        backgroundTaskId = self.backgroundTaskId;
    }

    if (backgroundTaskId == UIBackgroundTaskInvalid) {
        return;
    }

    // endBackgroundTask must be called on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogInfo(@"%@ %@ background task completed", logTag, label);
        [CurrentAppContext() endBackgroundTask:backgroundTaskId];

        if (completionBlock) {
            completionBlock(BackgroundTaskState_Success);
        }
    });
}

@end
