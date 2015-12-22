#import "Constraints.h"
#import "FutureUtil.h"

@implementation TOCCancelToken (FutureUtil)

- (void)whenCancelledTerminate:(id<Terminable>)terminable {
    ows_require(terminable != nil);
    [self whenCancelledDo:^{
      [terminable terminate];
    }];
}

@end

@implementation TOCFuture (FutureUtil)

+ (TOCUntilOperation)operationTry:(TOCUntilOperation)operation {
    ows_require(operation != nil);
    return ^(TOCCancelToken *until) {
      @try {
          return operation(until);
      } @catch (id ex) {
          return [TOCFuture futureWithFailure:ex];
      }
    };
}

- (TOCFuture *)thenValue:(id)value {
    return [self then:^(id _) {
      return value;
    }];
}

- (TOCFuture *)finallyTry:(TOCFutureFinallyContinuation)completionContinuation {
    ows_require(completionContinuation != nil);

    return [self finally:^id(TOCFuture *completed) {
      @try {
          return completionContinuation(completed);
      } @catch (id ex) {
          return [TOCFuture futureWithFailure:ex];
      }
    }];
}

- (TOCFuture *)thenTry:(TOCFutureThenContinuation)resultContinuation {
    ows_require(resultContinuation != nil);

    return [self then:^id(id result) {
      @try {
          return resultContinuation(result);
      } @catch (id ex) {
          return [TOCFuture futureWithFailure:ex];
      }
    }];
}

- (TOCFuture *)catchTry:(TOCFutureCatchContinuation)failureContinuation {
    ows_require(failureContinuation != nil);

    return [self catch:^id(id failure) {
      @try {
          return failureContinuation(failure);
      } @catch (id ex) {
          return [TOCFuture futureWithFailure:ex];
      }
    }];
}

+ (TOCFuture *)retry:(TOCUntilOperation)operation
          upToNTimes:(NSUInteger)maxTryCount
     withBaseTimeout:(NSTimeInterval)baseTimeout
      andRetryFactor:(NSTimeInterval)timeoutRetryFactor
      untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(operation != nil);
    ows_require(maxTryCount >= 0);
    ows_require(baseTimeout >= 0);
    ows_require(timeoutRetryFactor >= 0);

    if (maxTryCount == 0)
        return TOCFuture.futureWithTimeoutFailure;

    TOCFuture *futureResult =
        [TOCFuture futureFromUntilOperation:operation withOperationTimeout:baseTimeout until:untilCancelledToken];

    return [futureResult catchTry:^(id error) {
      bool operationCancelled     = untilCancelledToken.isAlreadyCancelled;
      bool operationDidNotTimeout = !futureResult.hasFailedWithTimeout;
      if (operationCancelled || operationDidNotTimeout) {
          return [TOCFuture futureWithFailure:error];
      }

      return [self retry:operation
               upToNTimes:maxTryCount - 1
          withBaseTimeout:baseTimeout * timeoutRetryFactor
           andRetryFactor:timeoutRetryFactor
           untilCancelled:untilCancelledToken];
    }];
}

@end
