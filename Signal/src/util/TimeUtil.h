#import <Foundation/Foundation.h>
#import "Terminable.h"
#import "CancelToken.h"
#import "Future.h"
#import "Operation.h"

@interface TimeUtil : NSObject

+(NSTimeInterval) time;

/// Result has type Future(TypeOfValueReturnedByFunction)
+(Future*) scheduleEvaluate:(Function)function
                 afterDelay:(NSTimeInterval)delay
                  onRunLoop:(NSRunLoop*)runLoop
            unlessCancelled:(id<CancelToken>)unlessCancelledToken;

/// Result has type Future(TypeOfValueReturnedByFunction)
+(Future*) scheduleEvaluate:(Function)function
                         at:(NSDate*)date
                  onRunLoop:(NSRunLoop*)runLoop
            unlessCancelled:(id<CancelToken>)unlessCancelledToken;

+(void) scheduleRun:(Action)action
         afterDelay:(NSTimeInterval)delay
          onRunLoop:(NSRunLoop*)runLoop
    unlessCancelled:(id<CancelToken>)unlessCancelledToken;

+(void) scheduleRun:(Action)action
                 at:(NSDate*)date
          onRunLoop:(NSRunLoop*)runLoop
    unlessCancelled:(id<CancelToken>)unlessCancelledToken;

+(void) scheduleRun:(Action)action
       periodically:(NSTimeInterval)interval
          onRunLoop:(NSRunLoop*)runLoop
     untilCancelled:(id<CancelToken>)untilCancelledToken
  andRunImmediately:(BOOL)shouldRunImmediately;

@end
