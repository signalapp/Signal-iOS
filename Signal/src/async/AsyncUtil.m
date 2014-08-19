#import "AsyncUtil.h"
#import "Environment.h"
#import "Constraints.h"
#import "FutureSource.h"
#import "FunctionalUtil.h"
#import "CancelTokenSource.h"
#import "TimeUtil.h"
#import "FutureUtil.h"
#import "ThreadManager.h"
#import "AsyncUtilHelperRacingOperation.h"

@implementation AsyncUtil

+(Future*) raceCancellableOperations:(NSArray*)cancellableOperationStarters
                      untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(cancellableOperationStarters != nil);
    if (cancellableOperationStarters.count == 0) return [Future failed:@[]];
    
    NSArray* racingOperations = [AsyncUtilHelperRacingOperation racingOperationsFromCancellableOperationStarters:cancellableOperationStarters
                                                                                                  untilCancelled:untilCancelledToken];
    
    Future* futureWinner = [AsyncUtilHelperRacingOperation asyncWinnerFromRacingOperations:racingOperations];
    
    // cancel and terminate losers
    [futureWinner thenDo:^(AsyncUtilHelperRacingOperation* winner) {
        for (AsyncUtilHelperRacingOperation* contender in racingOperations) {
            if (contender != winner) {
                [contender cancelAndTerminate];
            }
        }
    }];
    
    return [futureWinner then:^(AsyncUtilHelperRacingOperation* winner) {
        return [winner futureResult];
    }];
}

+(Future*) raceCancellableOperation:(CancellableOperationStarter)operation
                     againstTimeout:(NSTimeInterval)timeoutPeriod
                     untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(operation != nil);
    require(timeoutPeriod >= 0);
    
    FutureSource* futureResultSource = [FutureSource new];
    
    AsyncUtilHelperRacingOperation* racer = [AsyncUtilHelperRacingOperation racingOperationFromCancellableOperationStarter:operation
                                                                                                            untilCancelled:untilCancelledToken];
    [[racer futureResult] finallyDo:^(Future *completed) {
        [futureResultSource trySetResult:completed];
    }];
    
    void(^tryFail)(id failure) = ^(id failure){
        if ([futureResultSource trySetFailure:failure]) {
            [racer cancelAndTerminate];
        }
    };
    
    [TimeUtil scheduleRun:^{ tryFail([TimeoutFailure new]); }
               afterDelay:timeoutPeriod
                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
          unlessCancelled:[futureResultSource completionAsCancelToken]];
    
    [untilCancelledToken whenCancelled:^{ tryFail(untilCancelledToken); }];
    
    return futureResultSource;
}


+(Future*) asyncTry:(CancellableOperationStarter)operation
         upToNTimes:(NSUInteger)maxTryCount
    withBaseTimeout:(NSTimeInterval)baseTimeout
     andRetryFactor:(NSTimeInterval)timeoutRetryFactor
     untilCancelled:(id<CancelToken>)untilCancelledToken {
    
    require(operation != nil);
    require(maxTryCount >= 0);
    require(baseTimeout >= 0);
    require(timeoutRetryFactor >= 0);
    
    if (maxTryCount == 0) return [Future failed:[TimeoutFailure new]];
    
    Future* futureResult = [AsyncUtil raceCancellableOperation:operation
                                                againstTimeout:baseTimeout
                                                untilCancelled:untilCancelledToken];
    
    return [futureResult catch:^(id error) {
        bool operationCancelled = untilCancelledToken.isAlreadyCancelled;
        bool operationDidNotTimeout = ![error isKindOfClass:[TimeoutFailure class]];
        if (operationCancelled || operationDidNotTimeout) {
            return [Future failed:error];
        }
        
        return [self asyncTry:operation
                   upToNTimes:maxTryCount - 1
              withBaseTimeout:baseTimeout * timeoutRetryFactor
               andRetryFactor:timeoutRetryFactor
               untilCancelled:untilCancelledToken];
    }];
}

@end
