#import <Foundation/Foundation.h>

@protocol CancelToken;

/**
 *
 * Future is used to represent asynchronous results that will eventually be available or fail.
 * 
 * If the future has already completed, the has/forceGet methods can be used to access it.
 * To register a callback to run on completion (or right away if completed), use the then/catch methods.
 *
 * Note that, whenever a future would have ended with a result that is itself a Future, it instead unwraps the result.
 * That is to say, the eventual result/failure of top-level future will be the same as the bottom-level future.
 * e.g. Future(Future(1)) == Future(1)
 *
 * You can get an already-completed future via the finished/failed static methods.
 * You can manage a manually-completed future via the FutureSource class.
 *
 */

@interface Future : NSObject {
    bool isWiredToComplete;
    
    bool hasResult;
    id result;
    
    bool hasFailure;
    id failure;
    
    NSMutableArray* callbacks;
}

+(Future*) finished:(id)result;
+(Future*) failed:(id)value;
+(Future*) delayed:(id)value untilAfter:(Future*)future;

-(void) finallyDo:(void(^)(Future* completed))callback;

-(bool) isIncomplete;
-(bool) hasSucceeded;
-(bool) hasFailed;

-(id) forceGetResult;
-(id) forceGetFailure;

-(id<CancelToken>) completionAsCancelToken;

@end
