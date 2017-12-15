//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSBackgroundTask.h"
#import "AppContext.h"

@interface OWSBackgroundTask ()

@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
@property (nonatomic, readonly) NSString *label;

@end

#pragma mark -

@implementation OWSBackgroundTask

- (instancetype)initWithLabelStr:(const char *)labelStr
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(labelStr);

    _label = [NSString stringWithFormat:@"%s", labelStr];

    [self startBackgroundTask];

    return self;
}

- (void)dealloc
{
    [self endBackgroundTask];
}

- (void)startBackgroundTask
{
    @synchronized(self)
    {
        __weak typeof(self) weakSelf = self;

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
            }
        }];
    }
}

- (void)endBackgroundTask
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        @synchronized(strongSelf)
        {
            if (strongSelf.backgroundTaskId == UIBackgroundTaskInvalid) {
                return;
            }
            DDLogInfo(@"%@ %@ background task completed", strongSelf.logTag, strongSelf.label);
            [CurrentAppContext() endBackgroundTask:strongSelf.backgroundTaskId];
            strongSelf.backgroundTaskId = UIBackgroundTaskInvalid;
        }
    });
}

@end
