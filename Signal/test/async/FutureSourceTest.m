#import "FutureSourceTest.h"
#import "TestUtil.h"
#import "FutureSource.h"
#import "Util.h"

@implementation FutureSourceTest

-(void) testConstructors {
    FutureSource* inc = [FutureSource new];
    test([inc isIncomplete]);
    test(![inc hasSucceeded]);
    test(![inc hasFailed]);
    testThrows([inc forceGetResult]);
    testThrows([inc forceGetFailure]);

    FutureSource* done = [FutureSource finished:@1];
    test(![done isIncomplete]);
    test([done hasSucceeded]);
    test(![done hasFailed]);
    testDoesNotThrow([done forceGetResult]);
    testThrows([done forceGetFailure]);

    Future* done2 = [Future finished:@2];
    test(![done2 isIncomplete]);
    test([done2 hasSucceeded]);
    test(![done2 hasFailed]);
    testDoesNotThrow([done2 forceGetResult]);
    testThrows([done2 forceGetFailure]);

    FutureSource* fail3 = [FutureSource failed:@3];
    test(![fail3 isIncomplete]);
    test(![fail3 hasSucceeded]);
    test([fail3 hasFailed]);
    testThrows([fail3 forceGetResult]);
    testDoesNotThrow([fail3 forceGetFailure]);

    Future* fail4 = [Future failed:@4];
    test(![fail4 isIncomplete]);
    test(![fail4 hasSucceeded]);
    test([fail4 hasFailed]);
    testThrows([fail4 forceGetResult]);
    testDoesNotThrow([fail4 forceGetFailure]);    
}
-(void) testAutoUnwrap {
    Future* f = [Future finished:[Future finished:[Future failed:@1]]];
    test([f hasFailed]);
    test([[f forceGetFailure] isEqual:@1]);
    
    Future* f2 = [Future finished:[Future finished:[Future finished:@2]]];
    test([f2 hasSucceeded]);
    test([[f2 forceGetResult] isEqual:@2]);

    test([[[[Future finished:@1] then:^id(id value) {
        return [Future finished:@3];
    }] forceGetResult] isEqual:@3]);

    test([[[[Future failed:@1] catch:^id(id value) {
        return [Future finished:@3];
    }] forceGetResult] isEqual:@3]);
}
-(void) testTrySet {
    FutureSource* setR = [FutureSource new];
    FutureSource* setF = [FutureSource new];
    FutureSource* setWR = [FutureSource new];
    FutureSource* setWF = [FutureSource new];
    FutureSource* wr = [FutureSource new];
    FutureSource* wf = [FutureSource new];
    
    // set result
    test([setR trySetResult:@1]);
    test([setR hasSucceeded]);
    test(![setR trySetResult:@0]);
    test(![setR trySetFailure:@0]);
    test(![setR trySetResult:wr]);
    test(![setR trySetResult:wf]);
    test([[setR forceGetResult] isEqual:@1]);

    // set fail
    test([setF trySetFailure:@2]);
    test([setF hasFailed]);
    test(![setF trySetResult:@0]);
    test(![setF trySetFailure:@0]);
    test(![setF trySetResult:wr]);
    test(![setF trySetResult:wf]);
    test([[setF forceGetFailure] isEqual:@2]);

    // wire result
    test([setWR trySetResult:wr]);
    test([setWR isIncomplete]);
    test(![setWR trySetResult:@0]);
    test(![setWR trySetFailure:@0]);
    test(![setWR trySetResult:wf]);
    test(![setWR trySetResult:wr]);
    
    // wire failure
    test([setWF trySetResult:wf]);
    test([setWF isIncomplete]);
    test(![setWF trySetResult:@0]);
    test(![setWF trySetFailure:@0]);
    test(![setWF trySetResult:wf]);
    test(![setWF trySetResult:wr]);

    // set result via wire
    test([setWR isIncomplete]);
    [wr trySetResult:@3];
    test([setWR hasSucceeded]);
    test([[setWR forceGetResult] isEqual:@3]);

    // set failure via wire
    test([setWF isIncomplete]);
    [wf trySetFailure:@4];
    test([setWF hasFailed]);
    test([[setWF forceGetFailure] isEqual:@4]);
}

-(void) testThenDo_OnSuccess {
    FutureSource* f = [FutureSource new];
    __block int ready = 0;
    
    // before completed, waits to run
    [f thenDo:^(NSNumber* result) {
        test(ready == 1);
        ready = 2;
        test([result isEqual:@1]);
    }];
    test(ready == 0);
    
    ready = 1;
    [f trySetResult:@1];
    test(ready == 2);

    // after completed, runs inline
    [f thenDo:^(NSNumber* result) {
        test(ready == 2);
        ready = 3;
        test([result isEqual:@1]);
    }];
    test(ready == 3);
}
-(void) testThenDo_OnFail {
    FutureSource* f = [FutureSource new];
    [f thenDo:^(NSNumber* result) {
        test(false);
    }];
    [f trySetFailure:@1];
    [f thenDo:^(NSNumber* result) {
        test(false);
    }];
}

-(void) testCatchDo_OnFail {
    FutureSource* f = [FutureSource new];
    __block int ready = 0;
    
    // before completed, waits to run
    [f catchDo:^(NSNumber* result) {
        test(ready == 1);
        ready = 2;
        test([result isEqual:@1]);
    }];
    test(ready == 0);
    
    ready = 1;
    [f trySetFailure:@1];
    test(ready == 2);
    
    // after completed, runs inline
    [f catchDo:^(NSNumber* result) {
        test(ready == 2);
        ready = 3;
        test([result isEqual:@1]);
    }];
    test(ready == 3);
}
-(void) testCatchDo_OnSuccess {
    FutureSource* f = [FutureSource new];
    [f catchDo:^(NSNumber* result) {
        test(false);
    }];
    [f trySetResult:@1];
    [f catchDo:^(NSNumber* result) {
        test(false);
    }];
}

-(void) testThenOrCatchDo_OnSuccess {
    FutureSource* f = [FutureSource new];
    __block int ready = 0;
    
    // before completed, waits to run
    [f finallyDo:^(Future* completed) {
        test(ready == 1);
        ready = 2;
        test([[completed forceGetResult] isEqual:@1]);
    }];
    test(ready == 0);
    
    ready = 1;
    [f trySetResult:@1];
    test(ready == 2);
    
    // after completed, runs inline
    [f finallyDo:^(Future* completed) {
        test(ready == 2);
        ready = 3;
        test([[completed forceGetResult] isEqual:@1]);
    }];
    test(ready == 3);
}
-(void) testThenOrCatchDo_OnFail {
    FutureSource* f = [FutureSource new];
    __block int ready = 0;
    
    // before completed, waits to run
    [f finallyDo:^(Future* completed) {
        test(ready == 1);
        ready = 2;
        test([[completed forceGetResult] isEqual:@1]);
    }];
    test(ready == 0);
    
    ready = 1;
    [f trySetResult:@1];
    test(ready == 2);
    
    // after completed, runs inline
    [f finallyDo:^(Future* completed) {
        test(ready == 2);
        ready = 3;
        test([[completed forceGetResult] isEqual:@1]);
    }];
    test(ready == 3);
}

-(void) testThen {
    // pre-completed
    bool b = [[[[Future finished:@3] then:^id(id value) {
        test([value isEqual:@3]);
        return @4;
    }] forceGetResult] isEqual:@4];
    test(b);

    // pre-failed
    bool b2 = [[[[Future failed:@-1] then:^id(id value) {
        test(false);
        return nil;
    }] forceGetFailure] isEqual:@-1];
    test(b2);

    // post-completed
    FutureSource* f = [FutureSource new];
    Future* f2 = [f then:^id(id value) {
        test([value isEqual:@1]);
        return @2;
    }];
    test([f2 isIncomplete]);
    [f trySetResult:@1];
    test([[f2 forceGetResult] isEqual:@2]);

    // exceptional
    bool b3 = [[[[Future finished:nil] finally:^id(Future* completed) {
        checkOperation(false);
        return nil;
    }] forceGetFailure] isKindOfClass:[OperationFailed class]];
    test(b3);
}

-(void) testCatch {
    // pre-failed
    bool b = [[[[Future failed:@3] catch:^id(id value) {
        test([value isEqual:@3]);
        return @4;
    }] forceGetResult] isEqual:@4];
    test(b);
    
    // pre-completed
    bool b2 = [[[[Future finished:@-1] catch:^id(id value) {
        test(false);
        return nil;
    }] forceGetResult] isEqual:@-1];
    test(b2);
    
    // post-failed
    FutureSource* f = [FutureSource new];
    Future* f2 = [f catch:^id(id value) {
        test([value isEqual:@1]);
        return @2;
    }];
    test([f2 isIncomplete]);
    [f trySetFailure:@1];
    test([[f2 forceGetResult] isEqual:@2]);
    
    // exceptional
    bool b3 = [[[[Future failed:nil] finally:^id(Future* completed) {
        checkOperation(false);
        return nil;
    }] forceGetFailure] isKindOfClass:[OperationFailed class]];
    test(b3);
}

-(void) testThenOrCatch {
    // pre-completed
    bool b = [[[[Future finished:@3] finally:^id(Future* completed) {
        test([[completed forceGetResult] isEqual:@3]);
        return @4;
    }] forceGetResult] isEqual:@4];
    test(b);
    
    // pre-failed
    bool b2 = [[[[Future failed:@-1] finally:^id(Future* completed) {
        test([[completed forceGetFailure] isEqual:@-1]);
        return @5;
    }] forceGetResult] isEqual:@5];
    test(b2);
    
    // post-completed
    FutureSource* f = [FutureSource new];
    Future* f2 = [f finally:^id(Future* completed) {
        test([[completed forceGetResult] isEqual:@1]);
        return @2;
    }];
    test([f2 isIncomplete]);
    [f trySetResult:@1];
    test([[f2 forceGetResult] isEqual:@2]);
    
    // exceptional
    bool b3 = [[[[Future finished:nil] finally:^id(Future* completed) {
        checkOperation(false);
        return nil;
    }] forceGetFailure] isKindOfClass:[OperationFailed class]];
    test(b3);
}

-(void) completedAsCancelToken_OnSuccess {
    FutureSource* f = [FutureSource new];
    id<CancelToken> c = [f completionAsCancelToken];
    test(![c isAlreadyCancelled]);
    [f trySetResult:nil];
    test([c isAlreadyCancelled]);
}
-(void) completedAsCancelToken_OnFailure {
    FutureSource* f = [FutureSource new];
    id<CancelToken> c = [f completionAsCancelToken];
    test(![c isAlreadyCancelled]);
    [f trySetFailure:nil];
    test([c isAlreadyCancelled]);
}

@end
