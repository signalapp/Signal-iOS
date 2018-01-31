//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackgroundTask.h"
#import "AppContext.h"
#import "Threading.h"

@interface OWSBackgroundTask ()

@property (nonatomic, readonly) NSString *label;

// This property should only be accessed while synchronized on this instance.
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;

// This property should only be accessed while synchronized on this instance.
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
    // beginBackgroundTaskWithExpirationHandler must be called on the main thread.
    DispatchMainThreadSafe(^{
        __weak typeof(self) weakSelf = self;
        self.backgroundTaskId = [CurrentAppContext() beginBackgroundTaskWithExpirationHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                OWSBackgroundTask *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                // Make a local copy of completionBlock to ensure that it is called
                // exactly once.
                BackgroundTaskCompletionBlock _Nullable completionBlock = nil;

                @synchronized(strongSelf)
                {
                    if (strongSelf.backgroundTaskId == UIBackgroundTaskInvalid) {
                        return;
                    }
                    DDLogInfo(@"%@ %@ background task expired.", strongSelf.logTag, strongSelf.label);
                    strongSelf.backgroundTaskId = UIBackgroundTaskInvalid;

                    completionBlock = strongSelf.completionBlock;
                    strongSelf.completionBlock = nil;
                }

                if (completionBlock) {
                    completionBlock(BackgroundTaskState_Expired);
                }
            });
        }];

        // If a background task could not be begun, call the completion block.
        if (self.backgroundTaskId == UIBackgroundTaskInvalid) {

            DDLogInfo(@"%@ %@ background task could not be started.", self.logTag, self.label);

            // Make a local copy of completionBlock to ensure that it is called
            // exactly once.
            BackgroundTaskCompletionBlock _Nullable completionBlock;
            @synchronized(self)
            {
                completionBlock = self.completionBlock;
                self.completionBlock = nil;
            }
            if (completionBlock) {
                completionBlock(BackgroundTaskState_CouldNotStart);
            }
        }
    });
}

- (void)endBackgroundTask
{
    // Make a local copy of this state, since this method is called by `dealloc`.
    UIBackgroundTaskIdentifier backgroundTaskId;
    BackgroundTaskCompletionBlock _Nullable completionBlock;

    @synchronized(self)
    {
        backgroundTaskId = self.backgroundTaskId;
        completionBlock = self.completionBlock;
        self.completionBlock = nil;
    }

    if (backgroundTaskId == UIBackgroundTaskInvalid) {
        OWSAssert(!completionBlock);
        return;
    }

    // endBackgroundTask must be called on the main thread.
    DispatchMainThreadSafe(^{

        if (completionBlock) {
            completionBlock(BackgroundTaskState_Success);
        }

        if (backgroundTaskId != UIBackgroundTaskInvalid) {
            [CurrentAppContext() endBackgroundTask:backgroundTaskId];
        }
    });
}

@end
