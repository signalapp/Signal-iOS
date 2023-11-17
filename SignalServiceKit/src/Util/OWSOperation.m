//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOperation.h"
#import "NSTimer+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSError.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOperationKeyIsExecuting = @"isExecuting";
NSString *const OWSOperationKeyIsFinished = @"isFinished";

@interface OWSOperation ()

@property (nonatomic, nullable) NSError *failingError;
@property (atomic) OWSOperationState operationState;
@property (nonatomic) OWSBackgroundTask *backgroundTask;

// This property should only be accessed on the main queue.
@property (nonatomic) NSTimer *_Nullable retryTimer;

@property (nonatomic) NSUInteger errorCount;

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

    // Operations are not retryable by default.
    _remainingRetries = 0;

    return self;
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

// Called exactly once after the operation is marked complete, either with success, failure, or cancellation
- (void)didComplete
{
    // no-op
    // Override in subclass if necessary
}

#pragma mark - NSOperation overrides

- (NSString *)eventId
{
    return [NSString stringWithFormat:@"operation-%p", self];
}

// Do not override this method in a subclass instead, override `run`
- (void)main
{
    [BenchManager startEventWithTitle:[NSString stringWithFormat:@"%@-%p", self, self] eventId:self.eventId];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *_Nullable retryTimer = self.retryTimer;
        self.retryTimer = nil;
        [retryTimer invalidate];

        if (retryTimer != nil) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self run]; });
        }
    });
}

#pragma mark - Public Methods

// These methods are not intended to be subclassed
- (void)reportSuccess
{
    [self didSucceed];
    [self markAsComplete];
}

// These methods are not intended to be subclassed
- (void)reportCancelled
{
    [self didCancel];
    [self markAsComplete];
}

- (void)reportError:(NSError *)error
{
    self.errorCount += 1;

    [self didReportError:error];

    if (error.isFatalError) {
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

    dispatch_async(dispatch_get_main_queue(), ^{
        OWSAssertDebug(self.retryTimer == nil);
        [self.retryTimer invalidate];

        // The `scheduledTimerWith*` methods add the timer to the current thread's RunLoop.
        // Since Operations typically run on a background thread, that would mean the background
        // thread's RunLoop. However, the OS can spin down background threads if there's no work
        // being done, so we run the risk of the timer's RunLoop being deallocated before it's
        // fired.
        //
        // To ensure the timer's thread sticks around, we schedule it while on the main RunLoop.
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
    [self didComplete];

    [BenchManager completeEventWithEventId:self.eventId];
}

@end

NS_ASSUME_NONNULL_END
