#import "Constraints.h"
#import "TOCCancelToken+FutureUtil.h"
#import "Operation.h"

@implementation TOCCancelToken (FutureUtil)

- (void)whenCancelledTerminate:(id<Terminable>)terminable {
    require(terminable != nil);
    [self whenCancelledDo:^{ [terminable terminate]; }];
}

@end


