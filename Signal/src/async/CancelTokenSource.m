#import "CancelTokenSource.h"
#import "Constraints.h"
#import "FutureSource.h"
#import "Terminable.h"

@interface CancelTokenSourceToken : NSObject<CancelToken> {
@private NSMutableArray* callbacks;
@private bool isImmortal;
@private bool isCancelled;
}

+(CancelTokenSourceToken*) cancelTokenSourceToken;
-(void) cancel;
-(void) tryMakeImmortal;

@end

@implementation CancelTokenSource

+(CancelTokenSource*) cancelTokenSource {
    CancelTokenSource* c = [CancelTokenSource new];
    c->token = [CancelTokenSourceToken cancelTokenSourceToken];
    return c;
}

-(void) cancel {
    [token cancel];
}

-(NSString*) description {
    return [[self getToken] description];
}

-(void) dealloc {
    [token tryMakeImmortal];
}
-(id<CancelToken>) getToken {
    return token;
}

@end

@implementation CancelTokenSourceToken

+(CancelTokenSourceToken*) cancelTokenSourceToken {
    CancelTokenSourceToken* c = [CancelTokenSourceToken new];
    c->callbacks = [NSMutableArray array];
    return c;
}

-(void) whenCancelled:(void (^)())callback {
    @synchronized(self) {
        if (isImmortal) return;
        if (!isCancelled) {
            [callbacks addObject:[callback copy]];
            return;
        }
    }
    callback();
}
-(void) whenCancelledTryCancel:(FutureSource*)futureSource {
    require(futureSource != nil);
    [self whenCancelled:^{
        [futureSource trySetFailure:self];
    }];
}
-(void) whenCancelledTerminate:(id<Terminable>)terminable {
    require(terminable != nil);
    [self whenCancelled:^{
        [terminable terminate];
    }];
}

-(void) cancel {
    NSArray* callbacksToRun;
    @synchronized(self) {
        requireState(!isImmortal);
        if (isCancelled) return;
        isCancelled = true;
        callbacksToRun = callbacks;
        callbacks = nil;
    }
    for (void (^callback)() in callbacksToRun) {
        callback();
    }
}
-(void) tryMakeImmortal {
    @synchronized(self) {
        if (isCancelled) return;
        callbacks = nil;
        isImmortal = true;
    }
}
-(bool) isAlreadyCancelled {
    @synchronized(self) {
        return isCancelled;
    }
}

-(NSString*) description {
    if ([self isAlreadyCancelled]) return @"Cancelled";
    if (isImmortal) return @"Immortal";
    return @"Not Cancelled Yet";
}
-(Future*)asCancelledFuture {
    FutureSource* result = [FutureSource new];
    __unsafe_unretained id weakSelf = self;
    [self whenCancelled:^{
        [result trySetFailure:weakSelf];
    }];
    return result;
}

@end
