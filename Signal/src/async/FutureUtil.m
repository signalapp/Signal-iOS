#import "FutureUtil.h"
#import "FutureSource.h"
#import "Constraints.h"
#import "Operation.h"

@implementation Future (FutureUtil)

-(void) thenDo:(void(^)(id result))callback {
    require(callback != nil);
    void(^callbackCopy)(id result) = [callback copy];
    
    [self finallyDo:^(Future* completed){
        if ([completed hasSucceeded]) {
            callbackCopy([completed forceGetResult]);
        }
    }];
}
-(void) catchDo:(void(^)(id error))catcher {
    require(catcher != nil);
    void(^callbackCopy)(id result) = [catcher copy];
    
    [self finallyDo:^(Future* completed){
        if ([completed hasFailed]) {
            callbackCopy([completed forceGetFailure]);
        }
    }];
}

-(Future*) finally:(id(^)(Future* completed))callback {
    require(callback != nil);
    id(^callbackCopy)(Future* completed) = [callback copy];
    FutureSource* thenResult = [FutureSource new];
    
    [self finallyDo:^(Future* completed){
        @try {
            [thenResult trySetResult:callbackCopy(completed)];
        } @catch (id ex) {
            [thenResult trySetFailure:ex];
        }
    }];
    
    return thenResult;
}
-(Future*) then:(id(^)(id value))projection {
    require(projection != nil);
    id(^callbackCopy)(id value) = [projection copy];
    
    return [self finally:^id(Future* completed){
        if ([completed hasFailed]) return completed;
        
        return callbackCopy([completed forceGetResult]);
    }];
}
-(Future*) catch:(id(^)(id error))catcher {
    require(catcher != nil);
    id(^callbackCopy)(id value) = [catcher copy];
    
    return [self finally:^id(Future* completed){
        if ([completed hasSucceeded]) return completed;
        
        return callbackCopy([completed forceGetFailure]);
    }];
}

-(Future*) thenCompleteOnMainThread {
    FutureSource* onMainThreadResult = [FutureSource new];
    [self finallyDo:^(Future *completed) {
        [Operation asyncRun:^{
            [onMainThreadResult trySetResult:completed];
        } onThread:[NSThread mainThread]];
    }];
    return onMainThreadResult;
}

@end
