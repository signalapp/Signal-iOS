//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"
#import "NSError+MessageSending.h"
#import "NSTimer+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOperationKeyIsExecuting = @"isExecuting";
NSString *const OWSOperationKeyIsFinished = @"isFinished";

@interface OWSOperation ()

@property (nullable) NSError *failingError;
@property (atomic) OWSOperationState operationState;
@property (nonatomic) OWSBackgroundTask *backgroundTask;
@property (nonatomic) NSTimer *_Nullable retryTimer;
@property (nonatomic, readonly) dispatch_queue_t retryTimerSerialQueue;

@end

@implementation OWSOperation

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _operationState = OWSOperationStateNew;
    _backgroundTask = [OWSBackgroundTask backgroundTaskWithLabel:self.logTag];
    _retryTimerSerialQueue = dispatch_queue_create("SignalServiceKit.OWSOperation.retryTimer", DISPATCH_QUEUE_SERIAL);

    // Operations are not retryable by default.
    _remainingRetries = 0;

    return self;
}

- (void)dealloc
{
    OWSLogDebug(@"in dealloc");
}

#pragma mark - Subclass Overrides

// Called one time only
- (nullable NSError *)checkForPreconditionError
{
    // OWSOperation have a notion of failure, which is inferred by the presence of a `failingError`.
    //
    // By default, any failing dependency cascades that failure to it's dependent.
    // If you'd like different behavior, override this method (`checkForPreconditionError`) without calling `super`.
    for (NSOperation *dependency in self.dependencies) {
        if (![dependency isKindOfClass:[OWSOperation class]]) {
            // Native operations, like NSOperation and NSBlockOperation have no notion of "failure".
            // So there's no `failingError` to cascade.
            continue;
        }

        OWSOperation *dependentOperation = (OWSOperation *)dependency;

        // Don't proceed if dependency failed - surface the dependency's error.
        NSError *_Nullable dependencyError = dependentOperation.failingError;
        if (dependencyError != nil) {
            return dependencyError;
        }
    }

    return nil;
}

// Called every retry, this is where the bulk of the operation's work should go.
- (void)run
{
    OWSAbstractMethod();
}

// Called at most one time.
- (void)didSucceed
{
    // no-op
    // Override in subclass if necessary
}

// Called at most one time.
- (void)didCancel
{
    // no-op
    // Override in subclass if necessary
}

// Called zero or more times, retry may be possible
- (void)didReportError:(NSError *)error
{
    // no-op
    // Override in subclass if necessary
}

// Called at most one time, once retry is no longer possible.
- (void)didFailWithError:(NSError *)error
{
    // no-op
    // Override in subclass if necessary
}

#pragma mark - NSOperation overrides

// Do not override this method in a subclass instead, override `run`
- (void)main
{
    OWSLogDebug(@"started.");
    NSError *_Nullable preconditionError = [self checkForPreconditionError];
    if (preconditionError) {
        [self failOperationWithError:preconditionError];
        return;
    }

    if (self.isCancelled) {
        [self reportCancelled];
        return;
    }
    
    [self run];
}

- (void)runAnyQueuedRetry
{
    __block NSTimer *_Nullable retryTimer;
    dispatch_sync(self.retryTimerSerialQueue, ^{
        retryTimer = self.retryTimer;
        self.retryTimer = nil;
        [retryTimer invalidate];
    });

    if (retryTimer != nil) {
        [self run];
    } else {
        OWSLogVerbose(@"not re-running since operation is already running.");
    }
}

#pragma mark - Public Methods

// These methods are not intended to be subclassed
- (void)reportSuccess
{
    OWSLogDebug(@"succeeded.");
    [self didSucceed];
    [self markAsComplete];
}

// These methods are not intended to be subclassed
- (void)reportCancelled
{
    OWSLogDebug(@"cancelled.");
    [self didCancel];
    [self markAsComplete];
}

- (void)reportError:(NSError *)error
{
    OWSLogDebug(@"reportError: %@, fatal?: %d, retryable?: %d, remainingRetries: %lu",
        error,
        error.isFatal,
        error.isRetryable,
        (unsigned long)self.remainingRetries);

    [self didReportError:error];

    if (error.isFatal) {
        [self failOperationWithError:error];
        return;
    }

    if (!error.isRetryable) {
        [self failOperationWithError:error];
        return;
    }

    if (self.remainingRetries == 0) {
        [self failOperationWithError:error];
        return;
    }

    self.remainingRetries--;

    dispatch_sync(self.retryTimerSerialQueue, ^{
        OWSAssertDebug(self.retryTimer == nil);
        [self.retryTimer invalidate];
        self.retryTimer = [NSTimer weakScheduledTimerWithTimeInterval:self.retryInterval
                                                               target:self
                                                             selector:@selector(runAnyQueuedRetry)
                                                             userInfo:nil
                                                              repeats:NO];
    });
}

// Override in subclass if you want something more sophisticated, e.g. exponential backoff
- (NSTimeInterval)retryInterval
{
    return 0.1;
}

#pragma mark - Life Cycle

- (void)failOperationWithError:(NSError *)error
{
    OWSLogDebug(@"failed terminally.");
    self.failingError = error;

    [self didFailWithError:error];
    [self markAsComplete];
}

- (BOOL)isExecuting
{
    return self.operationState == OWSOperationStateExecuting;
}

- (BOOL)isFinished
{
    return self.operationState == OWSOperationStateFinished;
}

- (void)start
{
    [self willChangeValueForKey:OWSOperationKeyIsExecuting];
    self.operationState = OWSOperationStateExecuting;
    [self didChangeValueForKey:OWSOperationKeyIsExecuting];

    [self main];
}

- (void)markAsComplete
{
    [self willChangeValueForKey:OWSOperationKeyIsExecuting];
    [self willChangeValueForKey:OWSOperationKeyIsFinished];

    // Ensure we call the success or failure handler exactly once.
    @synchronized(self)
    {
        OWSAssertDebug(self.operationState != OWSOperationStateFinished);

        self.operationState = OWSOperationStateFinished;
    }

    [self didChangeValueForKey:OWSOperationKeyIsExecuting];
    [self didChangeValueForKey:OWSOperationKeyIsFinished];
}

@end

NS_ASSUME_NONNULL_END
