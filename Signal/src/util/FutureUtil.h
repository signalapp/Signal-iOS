#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "Terminable.h"

@interface TOCCancelToken (FutureUtil)

- (void)whenCancelledTerminate:(id<Terminable>)terminable;

@end

@interface TOCFuture (FutureUtil)

/*!
 * Wraps an asynchronous operation in a try-catch block, so it returns a failed future instead of propagating an
 * exception.
 */
+ (TOCUntilOperation)operationTry:(TOCUntilOperation)operation;

/*!
 * Returns a future that completes after the receiving future completes, but replaces its result if it didn't fail.
 */
- (TOCFuture *)thenValue:(id)value;

/*!
 * A variant of `-finally` that wraps a try-catch statement around the continuation.
 *
 * @discussion Registers a continuation to run when the receiving future completes with a result or fails.
 * Exposes the result of the continuation as a future.
 * If the continuation throwns an exception, it is caught and the returned future will fail with the caught exception as
 * its failure.
 */
- (TOCFuture *)finallyTry:(TOCFutureFinallyContinuation)callback;

/*!
 * A variant of `-then` that wraps a try-catch statement around the continuation.
 *
 * @discussion Registers a continuation to run when the receiving future completes with a result.
 * Exposes the result of the continuation as a future.
 * If the receiving future fails, the returned future is given the same failure and the continuation is not run.
 * If the continuation throwns an exception, it is caught and the returned future will fail with the caught exception as
 * its failure.
 */
- (TOCFuture *)thenTry:(TOCFutureThenContinuation)projection;

/*!
 * A variant of `-catch` that wraps a try-catch statement around the continuation.
 *
 * @discussion Registers a continuation to run when the receiving future fails.
 * Exposes the result of the continuation as a future.
 * If the receiving future completes with a result, the returned future is given the same result and the continuation is
 * not run.
 * If the continuation throwns an exception, it is caught and the returned future will fail with the caught exception as
 * its failure.
 */
- (TOCFuture *)catchTry:(TOCFutureCatchContinuation)catcher;

+ (TOCFuture *)retry:(TOCUntilOperation)operation
          upToNTimes:(NSUInteger)maxTryCount
     withBaseTimeout:(NSTimeInterval)baseTimeout
      andRetryFactor:(NSTimeInterval)timeoutRetryFactor
      untilCancelled:(TOCCancelToken *)untilCancelledToken;

@end
