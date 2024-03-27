//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

@property (nonatomic, readonly, nullable) NSError *failingError;

@property (nonatomic, readonly) NSUInteger errorCount;

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

// Called at most one time.
- (void)didCancel;

// Called zero or more times, retry may be possible
- (void)didReportError:(NSError *)error;

// Called at most one time, once retry is no longer possible.
- (void)didFailWithError:(NSError *)error NS_SWIFT_NAME(didFail(error:));

// Called exactly once after operation has moved to OWSOperationStateFinished
- (void)didComplete;

// How long to wait before retry, if possible
- (NSTimeInterval)retryInterval;

#pragma mark - Success/Error - Do Not Override

// Runs now if a retry timer has been set by a previous failure,
// otherwise assumes we're currently running and does nothing.
- (void)runAnyQueuedRetry;

// Report that the operation completed successfully.
//
// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
- (void)reportSuccess;

// Call this when you abort before completion due to being cancelled.
//
// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
- (void)reportCancelled;

// Report that the operation failed to complete due to an error.
//
// Each invocation of `run` must make exactly one call to one of: `reportSuccess`, `reportCancelled`, or `reportError:`
// You must ensure that `run` cannot succeed after calling `reportError`, e.g. generally you'll write something like
// this:
//
//     [self reportError:someError];
//     return;
//
// If the error is terminal, and you want to avoid retry, report an error with `error.isFatal = YES` otherwise the
// operation will retry if possible.
- (void)reportError:(NSError *)error NS_REFINED_FOR_SWIFT;

@end

NS_ASSUME_NONNULL_END
