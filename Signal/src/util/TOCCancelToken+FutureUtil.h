#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "Terminable.h"

@interface TOCCancelToken (FutureUtil)

- (void)whenCancelledTerminate:(id<Terminable>)terminable;

@end


