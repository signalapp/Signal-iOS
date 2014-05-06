#import "AsyncUtilTest.h"
#import "TestUtil.h"
#import "AsyncUtil.h"
#import "FutureSource.h"
#import "CancelTokenSource.h"
#import "CancelledToken.h"
#import "ThreadManager.h"

@implementation AsyncUtilTest

-(void) testRaceCancellableOperations_Winner {
    __block int f = 0;
    __block int s = 0;
    __block int i = 0;
    CancellableOperationStarter (^makeStarter)(Future*) = ^(Future* future) {
        return ^(id<CancelToken> c) {
            [c whenCancelled:^{
                if ([future hasFailed]) f += 1;
                if ([future hasSucceeded]) s += 1;
                if ([future isIncomplete]) i += 1;
            }];
            return future;
        };
    };
    
    FutureSource* v1 = [FutureSource new];
    FutureSource* v2 = [FutureSource new];
    FutureSource* v3 = [FutureSource new];
    
    Future* r = [AsyncUtil raceCancellableOperations:(@[makeStarter(v1),makeStarter(v2),makeStarter(v3)])
                                      untilCancelled:nil];
    
    [v2 trySetFailure:@1];
    test([r isIncomplete]);
    test(f == 0 && s == 0 && i == 0);
    
    [v3 trySetResult:@2];
    test([r hasSucceeded]);
    test([[r forceGetResult] isEqual:@2]);
    test(f == 1 && s == 0 && i == 1);
    
    [v1 trySetResult:@3];
    test(f == 1 && s == 0 && i == 1);
}
-(void) testRaceCancellableOperations_Cancel {
    __block int i = 0;
    CancellableOperationStarter (^makeStarter)(FutureSource*) = ^(FutureSource* future) {
        return ^(id<CancelToken> c) {
            [c whenCancelled:^{
                i += 1;
                [future trySetFailure:c];
            }];
            return future;
        };
    };
    
    Future* r = [AsyncUtil raceCancellableOperations:(@[
                                                      makeStarter([FutureSource new]),
                                                      makeStarter([FutureSource new]),
                                                      makeStarter([FutureSource new])])
                                      untilCancelled:[CancelledToken cancelledToken]];
    
    test(i == 3);
    test([r hasFailed]);
    test([(NSArray*)[r forceGetFailure] count] == 3);
}
-(void) testRaceCancellableOperations_Losers {
    test([[AsyncUtil raceCancellableOperations:@[]
                                untilCancelled:nil] hasFailed]);
    
    CancellableOperationStarter s = ^(id<CancelToken> c) {
        return [Future failed:@1];
    };
    
    Future* r = [AsyncUtil raceCancellableOperations:(@[s,s,s])
                                      untilCancelled:nil];
    test([r hasFailed]);
    test([[r forceGetFailure] isEqual:(@[@1,@1,@1])]);
}

-(void) testRaceCancellableOperationAgainstTimeout_WinFail {
    test([[AsyncUtil raceCancellableOperations:@[]
                                untilCancelled:nil] hasFailed]);
    CancelTokenSource* cts = [CancelTokenSource cancelTokenSource];
    
    __block int n = 0;
    CancellableOperationStarter s = ^(id<CancelToken> c) {
        [c whenCancelled:^{
            @synchronized(churnLock()) {
                n += 1;
            }
        }];
        return [Future failed:@1];
    };
    
    Future* f = [AsyncUtil raceCancellableOperation:s
                                     againstTimeout:1.0
                                     untilCancelled:[cts getToken]];
    test([f hasFailed]);
    test([[f forceGetFailure] isEqual:@1]);
    test(n == 0);
}
-(void) testRaceCancellableOperationAgainstTimeout_Win {
    test([[AsyncUtil raceCancellableOperations:@[]
                                untilCancelled:nil] hasFailed]);
    CancelTokenSource* cts = [CancelTokenSource cancelTokenSource];
    
    __block int n = 0;
    CancellableOperationStarter s = ^(id<CancelToken> c) {
        [c whenCancelled:^{
            @synchronized(churnLock()) {
                n += 1;
            }
        }];
        return [Future finished:@1];
    };
    
    Future* f = [AsyncUtil raceCancellableOperation:s
                                     againstTimeout:1.0
                                     untilCancelled:[cts getToken]];
    test([f hasSucceeded]);
    test([[f forceGetResult] isEqual:@1]);
    test(n == 0);
}
-(void) testRaceCancellableOperationAgainstTimeout_Timeout {
    test([[AsyncUtil raceCancellableOperations:@[]
                                untilCancelled:nil] hasFailed]);
    CancelTokenSource* cts = [CancelTokenSource cancelTokenSource];
    
    __block int n = 0;
    CancellableOperationStarter s = ^(id<CancelToken> c) {
        [c whenCancelled:^{
            @synchronized(churnLock()) {
                n += 1;
            }
        }];
        return [FutureSource new];
    };
    
    Future* f = [AsyncUtil raceCancellableOperation:s
                                     againstTimeout:0.1
                                     untilCancelled:[cts getToken]];
    
    test(n == 0);
    testChurnUntil([f hasFailed], 1.0);
    test(n == 1);
    test([[f forceGetFailure] isKindOfClass:[TimeoutFailure class]]);
}
-(void) testRaceCancellableOperationAgainstTimeout_Cancel {
    test([[AsyncUtil raceCancellableOperations:@[]
                                untilCancelled:nil] hasFailed]);
    CancelTokenSource* cts = [CancelTokenSource cancelTokenSource];
    
    __block int n = 0;
    CancellableOperationStarter s = ^(id<CancelToken> c) {
        [c whenCancelled:^{
            @synchronized(churnLock()) {
                n += 1;
            }
        }];
        return [FutureSource new];
    };
    
    Future* f = [AsyncUtil raceCancellableOperation:s
                                     againstTimeout:1.0
                                     untilCancelled:[cts getToken]];
    
    test(n == 0);
    [cts cancel];
    test(n == 1);
    testChurnUntil([f hasFailed], 1.0);
    test([[f forceGetFailure] conformsToProtocol:@protocol(CancelToken)]);
}

-(void) testAsyncTryPass {
    __block NSUInteger repeat = 0;
    __block NSUInteger evalCount = 0;
    CancellableOperationStarter op = ^(id<CancelToken> c) {
        repeat += 1;
        return [TimeUtil scheduleEvaluate:^id{ evalCount++; return @YES; }
                               afterDelay:0.5
                                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                          unlessCancelled:c];
    };
    Future* f = [AsyncUtil asyncTry:op
                         upToNTimes:4
                    withBaseTimeout:0.5/8
                     andRetryFactor:2
                     untilCancelled:nil];
    testChurnUntil(![f isIncomplete], 5.0);

    test(repeat == 3 || repeat == 4);
    test(evalCount == 1);
    test([f hasSucceeded]);
    test([[f forceGetResult] isEqual:@YES]);
}
-(void) testAsyncTryFail {
    __block NSUInteger repeat = 0;
    __block NSUInteger evalCount = 0;
    CancellableOperationStarter op = ^(id<CancelToken> c) {
        repeat += 1;
        return [TimeUtil scheduleEvaluate:^id{ evalCount++; return [Future failed:@13]; }
                               afterDelay:0.1
                                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                          unlessCancelled:c];
    };
    Future* f = [AsyncUtil asyncTry:op
                         upToNTimes:4
                    withBaseTimeout:0.5/8
                     andRetryFactor:2
                     untilCancelled:nil];
    testChurnUntil(![f isIncomplete], 5.0);
    
    test(repeat >= 1);
    test(evalCount >= 1);
    test([f hasFailed]);
    test([[f forceGetFailure] isEqual:@13]);
}
-(void) testAsyncTryTimeout {
    __block NSUInteger repeat = 0;
    __block NSUInteger evalCount = 0;
    CancellableOperationStarter op = ^(id<CancelToken> c) {
        repeat += 1;
        return [TimeUtil scheduleEvaluate:^id{ evalCount++; return @YES; }
                               afterDelay:0.5
                                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                          unlessCancelled:c];
    };
    Future* f = [AsyncUtil asyncTry:op
                         upToNTimes:2
                    withBaseTimeout:0.5/8
                     andRetryFactor:2
                     untilCancelled:nil];
    testChurnUntil(![f isIncomplete], 5.0);
    
    test(repeat == 2);
    test(evalCount == 0);
    test([f hasFailed]);
    test([[f forceGetFailure] isKindOfClass:[TimeoutFailure class]]);
}
-(void) testAsyncTryCancel {
    CancelTokenSource* s = [CancelTokenSource cancelTokenSource];
    __block NSUInteger repeat = 0;
    __block NSUInteger evalCount = 0;
    CancellableOperationStarter op = ^(id<CancelToken> c) {
        repeat += 1;
        [TimeUtil scheduleRun:^{ [s cancel]; }
                   afterDelay:0.1
                    onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
              unlessCancelled:nil];
        return [TimeUtil scheduleEvaluate:^id{ evalCount++; return @YES; }
                               afterDelay:0.5
                                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                          unlessCancelled:c];
    };
    Future* f = [AsyncUtil asyncTry:op
                         upToNTimes:2
                    withBaseTimeout:0.5/8
                     andRetryFactor:2
                     untilCancelled:[s getToken]];
    testChurnUntil(![f isIncomplete], 5.0);
    
    test(repeat == 2);
    test(evalCount == 0);
    test([f hasFailed]);
    test([[f forceGetFailure] conformsToProtocol:@protocol(CancelToken)]);
}

@end
