//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"
#import "NSError+MessageSending.h"
#import "OWSBackgroundTask.h"
#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOperationKeyIsExecuting = @"isExecuting";
NSString *const OWSOperationKeyIsFinished = @"isFinished";

@interface OWSOperation ()

@property (nullable) NSError *failingError;
@property (atomic) OWSOperationState operationState;
@property (nonatomic) OWSBackgroundTask *backgroundTask;

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

    // TODO Do we want some kind of exponential backoff?
    // I'm not sure that there is a one-size-fits all backoff approach
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self run];
    });
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
