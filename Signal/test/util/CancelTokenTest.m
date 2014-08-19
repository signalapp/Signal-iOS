#import "CancelTokenTest.h"
#import "CancelTokenSource.h"
#import "CancelledToken.h"
#import "TestUtil.h"
#import "Util.h"

@interface OnDealloc : NSObject {
@private void (^action)();
}
+(OnDealloc*) onDealloc:(void(^)())action;
@end
@implementation OnDealloc
+(OnDealloc*) onDealloc:(void(^)())action {
    OnDealloc* d = [OnDealloc new];
    d->action = [action copy];
    return d;
}
-(void) dealloc {
    action();
}
@end

@implementation CancelTokenTest

-(void) testCancelTokenSource {
    CancelTokenSource* s = [CancelTokenSource cancelTokenSource];
    id<CancelToken> c = [s getToken];
    __block int n = 0;
    [c whenCancelled:^{n += 1;}];
    [c whenCancelled:^{n += 1;}];
    test(n == 0);
    [s cancel];
    test(n == 2);
    [c whenCancelled:^{n += 1;}];
    test(n == 3);
}
-(void) testCancelledToken {
    __block int n = 0;
    [[CancelledToken cancelledToken] whenCancelled:^{n += 1;}];
    test(n == 1);
}
-(void) testCallbacksDeallocWhenSourceDeallocs {
    __block bool dealloced = false;
    __block id<CancelToken> c = nil;
    NSObject* lock = [NSObject new];
    [Operation asyncRunOnNewThread:^{
        OnDealloc* d = [OnDealloc onDealloc:^{
            @synchronized(lock) {
                dealloced = true;
            }
        }];
        CancelTokenSource* s = [CancelTokenSource cancelTokenSource];
        c = [s getToken];
        
        // hold reference to 'd' in callback
        [c whenCancelled:^{
            if (d != nil) {
                @synchronized(lock) {
                    // should never run
                    test(false);
                    dealloced = true;
                }
            }
        }];
        
        // s goes out of scope, gets dealloced, cancellation becomes impossible
        // local reference to d and callback reference should both go away, causing d to be dealloced
    }];
    
    // spin lock
    while (true) {
        @synchronized(lock) {
            if (dealloced) break;
        }
    }
    test(c != nil);
    test(!c.isAlreadyCancelled);
    test(dealloced);
}

@end
