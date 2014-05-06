#import <Foundation/Foundation.h>
#import "Future.h"

/**
 *
 * FutureSource is a future that can be manually completed/failed.
 *
 * You can cause the exposed future to complete via the trySet/Wire methods.
 *
 */

@interface FutureSource : Future

+(FutureSource*) finished:(id)value;
+(FutureSource*) failed:(id)value;

-(bool) trySetResult:(id)finalResult;
-(bool) trySetFailure:(id)failure;
-(bool) isCompletedOrWiredToComplete;

@end
