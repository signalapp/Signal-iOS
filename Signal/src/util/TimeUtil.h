#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "Operation.h"
#import "Terminable.h"

@interface TimeUtil : NSObject

+ (NSTimeInterval)time;

/// Result has type Future(TypeOfValueReturnedByFunction)
+ (TOCFuture *)scheduleEvaluate:(Function)function
                     afterDelay:(NSTimeInterval)delay
                      onRunLoop:(NSRunLoop *)runLoop
                unlessCancelled:(TOCCancelToken *)unlessCancelledToken;

/// Result has type Future(TypeOfValueReturnedByFunction)
+ (TOCFuture *)scheduleEvaluate:(Function)function
                             at:(NSDate *)date
                      onRunLoop:(NSRunLoop *)runLoop
                unlessCancelled:(TOCCancelToken *)unlessCancelledToken;

+ (void)scheduleRun:(Action)action
         afterDelay:(NSTimeInterval)delay
          onRunLoop:(NSRunLoop *)runLoop
    unlessCancelled:(TOCCancelToken *)unlessCancelledToken;

+ (void)scheduleRun:(Action)action
                 at:(NSDate *)date
          onRunLoop:(NSRunLoop *)runLoop
    unlessCancelled:(TOCCancelToken *)unlessCancelledToken;

+ (void)scheduleRun:(Action)action
       periodically:(NSTimeInterval)interval
          onRunLoop:(NSRunLoop *)runLoop
     untilCancelled:(TOCCancelToken *)untilCancelledToken
  andRunImmediately:(BOOL)shouldRunImmediately;

@end
