#import <TwistedOakCollapsingFutures/CollapsingFutures.h>
#import <XCTest/XCTest.h>
#import "FutureUtil.h"
#import "TestUtil.h"
#import "ThreadManager.h"

@interface FutureUtilTest : XCTestCase
@end

@implementation FutureUtilTest

- (void)testOperationTry {
    TOCFuture *f = [TOCFuture operationTry:^TOCFuture *(TOCCancelToken *_) {
      @throw @"Fail";
    }](nil);
    test([f isEqualToFuture:[TOCFuture futureWithFailure:@"Fail"]]);
}

- (void)testThenValue {
    test([[[TOCFuture futureWithFailure:@0] thenValue:@""] isEqualToFuture:[TOCFuture futureWithFailure:@0]]);
    test([[[TOCFuture futureWithResult:@1] thenValue:@""] isEqualToFuture:[TOCFuture futureWithResult:@""]]);
    test([[TOCFutureSource new].future thenValue:@""].isIncomplete);
}

- (void)testFinallyTry {
    test([[[TOCFuture futureWithResult:@1] finallyTry:^(TOCFuture *f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@""]]);
    test([[[TOCFuture futureWithFailure:@0] finallyTry:^(TOCFuture *f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@""]]);
    test([[TOCFutureSource new]
                 .future finallyTry:^(TOCFuture *f) {
           return @"";
         }].isIncomplete);

    test([[[TOCFuture futureWithResult:@1] finallyTry:^id(TOCFuture *f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@""]]);
    test([[[TOCFuture futureWithFailure:@0] finallyTry:^id(TOCFuture *f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@""]]);
    test([[TOCFutureSource new]
                 .future finallyTry:^id(TOCFuture *f) {
           @throw @"";
         }].isIncomplete);
}
- (void)testThenTry {
    test([[[TOCFuture futureWithResult:@1] thenTry:^(id f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@""]]);
    test([[[TOCFuture futureWithFailure:@0] thenTry:^(id f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@0]]);
    test([[TOCFutureSource new]
                 .future thenTry:^(id f) {
           return @"";
         }].isIncomplete);

    test([[[TOCFuture futureWithResult:@1] thenTry:^id(id f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@""]]);
    test([[[TOCFuture futureWithFailure:@0] thenTry:^id(id f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@0]]);
    test([[TOCFutureSource new]
                 .future thenTry:^id(id f) {
           @throw @"";
         }].isIncomplete);
}
- (void)testCatchTry {
    test([[[TOCFuture futureWithResult:@1] catchTry:^(id f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@1]]);
    test([[[TOCFuture futureWithFailure:@0] catchTry:^(id f) {
      return @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@""]]);
    test([[TOCFutureSource new]
                 .future catchTry:^(id f) {
           return @"";
         }].isIncomplete);

    test([[[TOCFuture futureWithResult:@1] catchTry:^id(id f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithResult:@1]]);
    test([[[TOCFuture futureWithFailure:@0] catchTry:^id(id f) {
      @throw @"";
    }] isEqualToFuture:[TOCFuture futureWithFailure:@""]]);
    test([[TOCFutureSource new]
                 .future catchTry:^id(id f) {
           @throw @"";
         }].isIncomplete);
}

- (void)testRetry_pass {
    __block NSUInteger repeat    = 0;
    __block NSUInteger evalCount = 0;
    TOCUntilOperation op         = ^(TOCCancelToken *c) {
      repeat += 1;
      return [TimeUtil scheduleEvaluate:^id {
        evalCount++;
        return @YES;
      }
                             afterDelay:0.35
                              onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                        unlessCancelled:c];
    };
    TOCFuture *f = [TOCFuture retry:op upToNTimes:4 withBaseTimeout:0.5 / 8 andRetryFactor:2 untilCancelled:nil];
    testChurnUntil(!f.isIncomplete, 500.0);

    test(repeat == 3 || repeat == 4);
    test(evalCount == 1);
    test(f.hasResult);
    test([[f forceGetResult] isEqual:@YES]);
}
- (void)testRetry_fail {
    __block NSUInteger repeat    = 0;
    __block NSUInteger evalCount = 0;
    TOCUntilOperation op         = ^(TOCCancelToken *c) {
      repeat += 1;
      return [TimeUtil scheduleEvaluate:^{
        evalCount++;
        return [TOCFuture futureWithFailure:@13];
      }
                             afterDelay:0.1
                              onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                        unlessCancelled:c];
    };
    TOCFuture *f = [TOCFuture retry:op upToNTimes:4 withBaseTimeout:0.5 / 8 andRetryFactor:2 untilCancelled:nil];
    testChurnUntil(!f.isIncomplete, 5.0);

    test(repeat >= 1);
    test(evalCount >= 1);
    test(f.hasFailed);
    test([f.forceGetFailure isEqual:@13]);
}
- (void)testRetry_timeout {
    __block NSUInteger repeat    = 0;
    __block NSUInteger evalCount = 0;
    TOCUntilOperation op         = ^(TOCCancelToken *c) {
      repeat += 1;
      return [TimeUtil scheduleEvaluate:^id {
        evalCount++;
        return @YES;
      }
                             afterDelay:0.5
                              onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                        unlessCancelled:c];
    };
    TOCFuture *f = [TOCFuture retry:op upToNTimes:2 withBaseTimeout:0.5 / 8 andRetryFactor:2 untilCancelled:nil];
    testChurnUntil(!f.isIncomplete, 5.0);

    test(repeat == 2);
    test(evalCount == 0);
    test(f.hasFailedWithTimeout);
}
- (void)testRetry_cancel {
    TOCCancelTokenSource *s      = [TOCCancelTokenSource new];
    __block NSUInteger repeat    = 0;
    __block NSUInteger evalCount = 0;
    TOCUntilOperation op         = ^(TOCCancelToken *c) {
      repeat += 1;
      [TimeUtil scheduleRun:^{
        [s cancel];
      }
                 afterDelay:0.1
                  onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
            unlessCancelled:nil];
      return [TimeUtil scheduleEvaluate:^id {
        evalCount++;
        return @YES;
      }
                             afterDelay:0.5
                              onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
                        unlessCancelled:c];
    };
    TOCFuture *f = [TOCFuture retry:op upToNTimes:2 withBaseTimeout:0.5 / 8 andRetryFactor:2 untilCancelled:s.token];
    testChurnUntil(!f.isIncomplete, 5.0);

    test(repeat == 2);
    test(evalCount == 0);
    test(f.hasFailedWithCancel);
}

@end
