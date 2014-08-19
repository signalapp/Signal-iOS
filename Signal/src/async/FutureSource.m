#import "FutureSource.h"
#import "Constraints.h"
#import "Util.h"

@implementation FutureSource

+(FutureSource*) finished:(id)value {
    FutureSource* v = [FutureSource new];
    [v trySetResult:value];
    return v;
}
+(FutureSource*) failed:(id)value {
    FutureSource* v = [FutureSource new];
    [v trySetFailure:value];
    return v;
}

-(id) init {
    if (self = [super init]) {
        self->callbacks = [NSMutableArray array];
    }
    return self;
}

-(bool) isCompletedOrWiredToComplete {
    @synchronized(self) {
        return callbacks == nil || isWiredToComplete;
    }
}
-(bool) canBeCompleted {
    @synchronized(self) {
        return callbacks != nil && !isWiredToComplete;
    }
}

-(bool) trySet:(id)value failed:(bool)failed isUnwiring:(bool)unwiring {
    NSArray* oldCallbacks;
    @synchronized(self) {
        if (!unwiring && ![self canBeCompleted]) return false;
        
        oldCallbacks = callbacks;
        callbacks = nil;
        hasResult = !failed;
        hasFailure = failed;
        isWiredToComplete = false;
        result = hasResult ? value : nil;
        failure = hasFailure ? value : nil;
    }
    
    for (void (^callback)(Future* completed) in oldCallbacks) {
        callback(self);
    }
    return true;
}
-(bool) trySetResult:(id)value {
    if ([value isKindOfClass:[Future class]]) {
        return [self tryWireForFutureCompletion:value];
    }
    
    return [self trySet:value
                 failed:false
             isUnwiring:false];
}
-(bool) trySetFailure:(id)value {
    require(![value isKindOfClass:[Future class]]);
    return [self trySet:value
                 failed:true
             isUnwiring:false];
}

-(bool) tryWireForFutureCompletion:(Future*)futureResult {
    require(futureResult != nil);
    
    @synchronized(self) {
        if (![self canBeCompleted]) return false;
        isWiredToComplete = true;
    }
    
    [futureResult finallyDo:^(Future* completed) {
        if (completed.hasSucceeded) {
            [self trySet:[completed forceGetResult]
                  failed:false
              isUnwiring:true];
        } else {
            [self trySet:[completed forceGetFailure]
                  failed:true
              isUnwiring:true];
        }
    }];
    
    return true;
}

-(NSString*) description {
    @synchronized(self) {
        if (isWiredToComplete) return @"Incomplete Future [Wired to Complete]";
        if (self.isIncomplete) return @"Incomplete Future";
        if (self.hasSucceeded) return [NSString stringWithFormat:@"Completed: %@", result];
        return [NSString stringWithFormat:@"Failed: %@", failure];
    }
}

@end
