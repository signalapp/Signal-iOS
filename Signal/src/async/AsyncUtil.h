#import <Foundation/Foundation.h>
#import "Future.h"
#import "CancelToken.h"
#import "Terminable.h"
#import "TimeoutFailure.h"

/**
 *
 * A CancellableOperationStarter launches an operation when called.
 * The asynchronous result of the operation is returned as a Future.
 *
 * The operation should be cancelled when the token passed into the starter is cancelled.
 * If the operation has not completed, cancelling the token should fail the returned future right away.
 * If the operation has completed, cancelling the token should terminate the successful result.
 *
 **/
typedef Future* (^CancellableOperationStarter)(id<CancelToken> untilCancelledToken);

/**
 *
 * AsyncUtil contains utitility methods used for aggregating and otherwise dealing with asynchronous operations.
 *
 */
@interface AsyncUtil : NSObject

+(Future*) raceCancellableOperations:(NSArray*)cancellableOperationStarters
                      untilCancelled:(id<CancelToken>)untilCancelledToken;

+(Future*) raceCancellableOperation:(CancellableOperationStarter)operation
                     againstTimeout:(NSTimeInterval)timeoutPeriod
                     untilCancelled:(id<CancelToken>)untilCancelledToken;

+(Future*) asyncTry:(CancellableOperationStarter)operation
         upToNTimes:(NSUInteger)maxTryCount
    withBaseTimeout:(NSTimeInterval)baseTimeout
     andRetryFactor:(NSTimeInterval)timeoutRetryFactor
     untilCancelled:(id<CancelToken>)untilCancelledToken;

@end
