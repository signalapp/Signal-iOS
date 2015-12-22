#import "TimeUtil.h"
#import "Util.h"

@implementation TimeUtil

+ (NSTimeInterval)time {
    return [[NSProcessInfo processInfo] systemUptime];
}

+ (TOCFuture *)scheduleEvaluate:(Function)function
                     afterDelay:(NSTimeInterval)delay
                      onRunLoop:(NSRunLoop *)runLoop
                unlessCancelled:(TOCCancelToken *)unlessCancelledToken {
    ows_require(function != NULL);
    ows_require(runLoop != nil);
    ows_require(delay >= 0);

    TOCFutureSource *result = [TOCFutureSource futureSourceUntil:unlessCancelledToken];
    Action evaler           = ^{
      [result trySetResult:function()];
    };
    [self scheduleHelper:evaler
               withPeriod:delay
                onRunLoop:runLoop
                repeating:false
           untilCancelled:unlessCancelledToken
        andRunImmediately:NO];

    return result.future;
}

+ (TOCFuture *)scheduleEvaluate:(Function)function
                             at:(NSDate *)date
                      onRunLoop:(NSRunLoop *)runLoop
                unlessCancelled:(TOCCancelToken *)unlessCancelledToken {
    ows_require(function != NULL);
    ows_require(runLoop != nil);
    ows_require(date != nil);

    NSTimeInterval delay = [date timeIntervalSinceNow];
    return [self scheduleEvaluate:function
                       afterDelay:MAX(0, delay)
                        onRunLoop:runLoop
                  unlessCancelled:unlessCancelledToken];
}

+ (void)scheduleRun:(Action)action
         afterDelay:(NSTimeInterval)delay
          onRunLoop:(NSRunLoop *)runLoop
    unlessCancelled:(TOCCancelToken *)unlessCancelledToken {
    ows_require(action != NULL);
    ows_require(runLoop != nil);
    ows_require(delay >= 0);
    if (delay == INFINITY)
        return;

    [self scheduleHelper:action
               withPeriod:delay
                onRunLoop:runLoop
                repeating:false
           untilCancelled:unlessCancelledToken
        andRunImmediately:NO];
}

+ (void)scheduleRun:(Action)action
                 at:(NSDate *)date
          onRunLoop:(NSRunLoop *)runLoop
    unlessCancelled:(TOCCancelToken *)unlessCancelledToken {
    ows_require(action != NULL);
    ows_require(runLoop != nil);
    ows_require(date != nil);

    NSTimeInterval delay = [date timeIntervalSinceNow];
    [self scheduleRun:action afterDelay:MAX(0, delay) onRunLoop:runLoop unlessCancelled:unlessCancelledToken];
}

+ (void)scheduleRun:(Action)action
       periodically:(NSTimeInterval)interval
          onRunLoop:(NSRunLoop *)runLoop
     untilCancelled:(TOCCancelToken *)untilCancelledToken
  andRunImmediately:(BOOL)shouldRunImmediately {
    ows_require(action != NULL);
    ows_require(runLoop != nil);
    ows_require(interval > 0);

    [self scheduleHelper:action
               withPeriod:interval
                onRunLoop:runLoop
                repeating:true
           untilCancelled:untilCancelledToken
        andRunImmediately:shouldRunImmediately];
}

+ (void)scheduleHelper:(Action)callback
            withPeriod:(NSTimeInterval)interval
             onRunLoop:(NSRunLoop *)runLoop
             repeating:(bool)repeats
        untilCancelled:(TOCCancelToken *)untilCancelledToken
     andRunImmediately:(BOOL)shouldRunImmediately {
    ows_require(callback != NULL);
    ows_require(runLoop != nil);
    ows_require(interval >= 0);
    ows_require(!repeats || interval > 0);

    if (untilCancelledToken.isAlreadyCancelled) {
        return;
    }
    if (!repeats && interval == 0) {
        callback();
        return;
    }
    if (shouldRunImmediately) {
        callback();
    }

    callback                      = [callback copy];
    __block bool hasBeenCancelled = false;
    __block NSObject *cancelLock  = [NSObject new];

    Operation *callbackUnlessCancelled = [Operation operation:^{
      @synchronized(cancelLock) {
          if (hasBeenCancelled)
              return;
          callback();
      }
    }];

    NSTimer *timer = [NSTimer timerWithTimeInterval:interval
                                             target:callbackUnlessCancelled
                                           selector:[callbackUnlessCancelled selectorToRun]
                                           userInfo:nil
                                            repeats:repeats];
    [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];

    [untilCancelledToken whenCancelledDo:^{
      @synchronized(cancelLock) {
          hasBeenCancelled = true;
          [timer invalidate];
      }
    }];
}

@end
