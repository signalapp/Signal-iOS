#import "Future.h"
#import "FutureSource.h"
#import "Util.h"
#import "CancelTokenSource.h"

@implementation Future

+(Future*) finished:(id)value {
    FutureSource* v = [FutureSource new];
    [v trySetResult:value];
    return v;
}
+(Future*) failed:(id)value {
    DDLogVerbose(@"Future failed: %@", value);
    FutureSource* v = [FutureSource new];
    [v trySetFailure:value];
    return v;
}
+(Future*) delayed:(id)value untilAfter:(Future*)future {
    require(future != nil);
    return [future then:^(id _) {
        return value;
    }];
}

-(void) finallyDo:(void(^)(Future* completed))callback {
    require(callback != nil);
    @synchronized(self) {
        if (self.isIncomplete) {
            [callbacks addObject:[callback copy]];
            return;
        }
    }
    callback(self);
}

-(bool) isIncomplete {
    @synchronized(self) {
        return callbacks != nil;
    }
}

-(bool) hasSucceeded {
    @synchronized(self) {
        return hasResult;
    }
}

-(bool) hasFailed {
    @synchronized(self) {
        return hasFailure;
    }
}

-(id) forceGetResult {
    @synchronized(self) {
        requireState(self.hasSucceeded);
    }
    return result;
}

-(id) forceGetFailure {
    @synchronized(self) {
        requireState(self.hasFailed);
    }
    return failure;
}

-(id<CancelToken>)completionAsCancelToken {
    CancelTokenSource* cancelTokenSource = [CancelTokenSource cancelTokenSource];
    [self finallyDo:^(Future*_) {
        [cancelTokenSource cancel];
    }];
    return [cancelTokenSource getToken];
}

@end
