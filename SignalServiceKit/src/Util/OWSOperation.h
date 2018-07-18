//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OWSOperationState) {
    OWSOperationStateNew,
    OWSOperationStateExecuting,
    OWSOperationStateFinished
};

// A base class for implementing retryable operations.
// To utilize the retryable behavior:
// Set remainingRetries to something greater than 0, and when you're reporting an error,
// set `error.isRetryable = YES`.
// If the failure is one that will not succeed upon retry, set `error.isFatal = YES`.
//
// isRetryable and isFatal are opposites but not redundant.
//
// If a group message send fails, the send will be retried if any of the errors were retryable UNLESS
// any of the errors were fatal. Fatal errors trump retryable errors.
@interface OWSOperation : NSOperation

@property (readonly, nullable) NSError *failingError;

// Defaults to 0, set to greater than 0 in init if you'd like the operation to be retryable.
@property NSUInteger remainingRetries;

#pragma mark - Mandatory Subclass Overrides

// Called every retry, this is where the bulk of the operation's work should go.
- (void)run;

#pragma mark - Optional Subclass Overrides

// Called one time only
- (nullable NSError *)checkForPreconditionError;

// Called at most one time.
- (void)didSucceed;

// Called at most one time, once retry is no longer possible.
- (void)didFailWithError:(NSError *)error NS_SWIFT_NAME(didFail(error:));

#pragma mark - Success/Error - Do Not Override

// Complete the operation successfully.
// Should be called at most once per operation instance.
// You must ensure that `run` cannot fail after calling `reportSuccess`.
- (void)reportSuccess;

// Should be called at most once per `run`.
// You must ensure that `run` cannot succeed after calling `reportError`, e.g. generally you'll write something like
// this:
//
//     [self reportError:someError];
//     return;
//
// If the error is terminal, and you want to avoid retry, report an error with `error.isFatal = YES` otherwise the
// operation will retry if possible.
- (void)reportError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
