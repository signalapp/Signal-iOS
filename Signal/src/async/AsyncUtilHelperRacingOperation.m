#import "AsyncUtilHelperRacingOperation.h"
#import "FutureSource.h"
#import "Util.h"

@implementation AsyncUtilHelperRacingOperation

@synthesize cancelSource, futureResult;

+(AsyncUtilHelperRacingOperation *)racingOperationFromCancellableOperationStarter:(CancellableOperationStarter)cancellableOperationStarter
                                                                   untilCancelled:(id<CancelToken>)untilCancelledToken {
    require(cancellableOperationStarter != nil);
    
    AsyncUtilHelperRacingOperation* instance = [AsyncUtilHelperRacingOperation new];
    
    instance->cancelSource = [CancelTokenSource cancelTokenSource];
    [untilCancelledToken whenCancelled:^{
        [instance.cancelSource cancel];
    }];
    
    @try {
        instance->futureResult = cancellableOperationStarter([instance.cancelSource getToken]);
    } @catch (OperationFailed* ex) {
        instance->futureResult = [Future failed:ex];
    }
    
    return instance;
}

+(NSArray*) racingOperationsFromCancellableOperationStarters:(NSArray*)cancellableOperationStarters
                                              untilCancelled:(id<CancelToken>)untilCancelledToken {
    return [cancellableOperationStarters map:^(CancellableOperationStarter cancellableOperationStarter) {
        return [AsyncUtilHelperRacingOperation racingOperationFromCancellableOperationStarter:cancellableOperationStarter
                                                                               untilCancelled:untilCancelledToken];
    }];
}

+(Future*) asyncWinnerFromRacingOperations:(NSArray*)racingOperations {
    require(racingOperations != nil);
    
    FutureSource* futureWinner = [FutureSource new];
    
    NSUInteger totalCount = racingOperations.count;
    NSMutableArray* failures = [NSMutableArray array];
    void(^failIfAllFailed)(id) = ^(id failure) {
        @synchronized(failures) {
            [failures addObject:failure];
            if (failures.count < totalCount) return;
        }
        
        [futureWinner trySetFailure:failures];
    };
    
    for (AsyncUtilHelperRacingOperation* contender in racingOperations) {
        Future* futureResult = [contender futureResult];
        [futureResult thenDo:^(id result) {
            [futureWinner trySetResult:contender];
        }];
        
        [futureResult catchDo:failIfAllFailed];
    }
    
    return futureWinner;
}

-(void) cancelAndTerminate {
    [cancelSource cancel];
    
    // in case cancellation is too late, terminate any eventual result
    [futureResult thenDo:^(id result) {
        if ([result conformsToProtocol:@protocol(Terminable)]) {
            [result terminate];
        }
    }];
}

@end
