#import "Environment.h"
#import "ObservableValue.h"
#import "Util.h"

@implementation ObservableValue

@synthesize currentValue;

- (ObservableValue *)initWithValue:(id)value {
    callbacks          = [NSMutableSet set];
    queuedActionsToRun = [Queue new];
    currentValue       = value;
    return self;
}

- (void)watchLatestValueOnArbitraryThread:(LatestValueCallback)callback
                           untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(callback != nil);
    if (untilCancelledToken.isAlreadyCancelled)
        return;

    void (^callbackCopy)(id value) = [callback copy];
    [self queueRun:^{
      callbackCopy(self.currentValue);
      [callbacks addObject:callbackCopy];
    }];
    [untilCancelledToken whenCancelledDo:^{
      [self queueRun:^{
        [callbacks removeObject:callbackCopy];
      }];
    }];
}
- (void)watchLatestValue:(LatestValueCallback)callback
                onThread:(NSThread *)thread
          untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(callback != nil);
    ows_require(thread != nil);

    void (^callbackCopy)(id value)     = [callback copy];
    void (^threadedCallback)(id value) = ^(id value) {
      [Operation asyncRun:^{
        callbackCopy(value);
      }
                 onThread:thread];
    };

    [self watchLatestValueOnArbitraryThread:threadedCallback untilCancelled:untilCancelledToken];
}

/// used for avoiding re-entrancy issues (e.g. a callback registering another callback during enumeration)
- (void)queueRun:(void (^)())action {
    @synchronized(self) {
        if (isRunningActions) {
            [queuedActionsToRun enqueue:[action copy]];
            return;
        }
        isRunningActions = true;
    }

    while (true) {
        @try {
            action();
        } @catch (id ex) {
            [[Environment.logging getConditionLoggerForSender:self]
                logError:@"A queued action failed and may have stalled an ObservableValue."];
            @synchronized(self) {
                isRunningActions = false;
            }
            [ex raise];
        }

        @
        synchronized(self) {
            action = [queuedActionsToRun tryDequeue];
            if (action == nil) {
                isRunningActions = false;
                break;
            }
        }
    }
}

- (void)updateValue:(id)value {
    [self queueRun:^{
      if (value == currentValue)
          return;
      requireState(!sealed);

      currentValue = value;
      for (void (^callback)(id value) in callbacks) {
          callback(value);
      }
    }];
}
- (void)adjustValue:(id (^)(id))adjustment {
    ows_require(adjustment != nil);
    [self queueRun:^{
      id oldValue = currentValue;
      id newValue = adjustment(oldValue);
      if (oldValue == newValue)
          return;
      requireState(!sealed);

      currentValue = newValue;
      for (void (^callback)(id value) in callbacks) {
          callback(currentValue);
      }
    }];
}

@end

@implementation ObservableValueController

+ (ObservableValueController *)observableValueControllerWithInitialValue:(id)value {
    return [[ObservableValueController alloc] initWithValue:value];
}

- (void)updateValue:(id)value {
    [super updateValue:value];
}
- (void)adjustValue:(id (^)(id))adjustment {
    [super adjustValue:adjustment];
}
- (void)sealValue {
    [self queueRun:^{
      sealed    = true;
      callbacks = nil;
    }];
}

@end
