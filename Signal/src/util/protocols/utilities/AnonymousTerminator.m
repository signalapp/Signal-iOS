#import "AnonymousTerminator.h"
#import "Constraints.h"

@implementation AnonymousTerminator

+ (AnonymousTerminator *)cancellerWithCancel:(void (^)(void))terminate {
    ows_require(terminate != nil);
    AnonymousTerminator *c = [AnonymousTerminator new];
    c->_terminateBlock     = terminate;
    return c;
}

- (void)terminate {
    @synchronized(self) {
        if (alreadyCalled)
            return;
        alreadyCalled = true;
    }
    _terminateBlock();
}
@end
