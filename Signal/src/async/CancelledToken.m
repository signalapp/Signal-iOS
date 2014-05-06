#import "CancelledToken.h"
#import "FutureSource.h"
#import "Util.h"

@implementation CancelledToken

+(CancelledToken*) cancelledToken {
    return [CancelledToken new];
}
-(bool) isAlreadyCancelled {
    return true;
}
-(void) whenCancelled:(void (^)())callback {
    require(callback != nil);
    callback();
}
-(void) whenCancelledTryCancel:(FutureSource*)futureSource {
    require(futureSource != nil);
    [futureSource trySetFailure:self];
}
-(void) whenCancelledTerminate:(id<Terminable>)terminable {
    require(terminable != nil);
    [terminable terminate];
}
-(Future*)asCancelledFuture {
    return [Future failed:self];
}

@end
