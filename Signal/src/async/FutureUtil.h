#import <Foundation/Foundation.h>
#import "Future.h"

@interface Future (FutureUtil)

-(void) thenDo:(void(^)(id result))callback;
-(void) catchDo:(void(^)(id error))catcher;

-(Future*) finally:(id(^)(Future* completed))callback;
-(Future*) then:(id(^)(id value))projection;
-(Future*) catch:(id(^)(id error))catcher;

-(Future*) thenCompleteOnMainThread;

@end
