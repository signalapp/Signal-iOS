//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AnonymousTerminator.h"

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
