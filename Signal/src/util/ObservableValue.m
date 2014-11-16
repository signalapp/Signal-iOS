#import "ObservableValue.h"
#import "Util.h"
#import "Environment.h"

@interface ObservableValue ()

@property (strong, readwrite, atomic) id currentValue;

@property (strong, nonatomic) Queue* queuedActionsToRun;
@property (nonatomic) bool isRunningActions;

@property (nonatomic) bool sealed;
@property (strong, nonatomic) NSMutableSet* callbacks;

@end

@implementation ObservableValue

- (instancetype)initWithValue:(id)value {
    if (self = [super init]) {
        self.currentValue = value;
    }
    
    return self;
}

- (NSMutableSet*)callbacks {
    if (!_callbacks) _callbacks = [[NSMutableSet alloc] init];
    return _callbacks;
}

- (Queue*)queuedActionsToRun {
    if (!_queuedActionsToRun) _queuedActionsToRun = [[Queue alloc] init];
    return _queuedActionsToRun;
}

- (void)watchLatestValueOnArbitraryThread:(LatestValueCallback)callback
                           untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    require(callback != nil);
    if (untilCancelledToken.isAlreadyCancelled) return;
    
    void(^callbackCopy)(id value) = [callback copy];
    [self queueRun:^{
        callbackCopy(self.currentValue);
        [self.callbacks addObject:callbackCopy];
    }];
    [untilCancelledToken whenCancelledDo:^{
        [self queueRun:^{
            [self.callbacks removeObject:callbackCopy];
        }];
    }];
}

- (void)watchLatestValue:(LatestValueCallback)callback
                onThread:(NSThread*)thread
          untilCancelled:(TOCCancelToken*)untilCancelledToken {
    
    require(callback != nil);
    require(thread != nil);
    
    void(^callbackCopy)(id value) = [callback copy];
    void(^threadedCallback)(id value) = ^(id value) {
        [Operation asyncRun:^{callbackCopy(value);} onThread:thread];
    };
    
    [self watchLatestValueOnArbitraryThread:threadedCallback
                             untilCancelled:untilCancelledToken];
}

/// used for avoiding re-entrancy issues (e.g. a callback registering another callback during enumeration)
- (void)queueRun:(void(^)())action {
    @synchronized(self) {
        if (self.isRunningActions) {
            [self.queuedActionsToRun enqueue:[action copy]];
            return;
        }
        self.isRunningActions = true;
    }
    
    while (true) {
        @try {
            action();
        } @catch (id ex) {
            [[Environment.logging getConditionLoggerForSender:self]
             logError:@"A queued action failed and may have stalled an ObservableValue."];
            @synchronized(self) {
                self.isRunningActions = false;
            }
            [ex raise];
        }
        
        @synchronized(self) {
            action = [self.queuedActionsToRun tryDequeue];
            if (action == nil) {
                self.isRunningActions = false;
                break;
            }
        }
    }
}

- (void)updateValue:(id)value {
    [self queueRun:^{
        if (value == self.currentValue) return;
        requireState(!self.sealed);
        
        self.currentValue = value;
        for (void(^callback)(id value) in self.callbacks) {
            callback(value);
        }
    }];
}

- (void)adjustValue:(id(^)(id))adjustment {
    require(adjustment != nil);
    [self queueRun:^{
        id oldValue = self.currentValue;
        id newValue = adjustment(oldValue);
        if (oldValue == newValue) return;
        requireState(!self.sealed);
        
        self.currentValue = newValue;
        for (void(^callback)(id value) in self.callbacks) {
            callback(self.currentValue);
        }
    }];
}

@end

@implementation ObservableValueController

- (instancetype)initWithInitialValue:(id)value {
    return [self initWithValue:value];
}

- (void)updateValue:(id)value {
    [super updateValue:value];
}

- (void)adjustValue:(id(^)(id))adjustment {
    [super adjustValue:adjustment];
}

-( void) sealValue {
    [self queueRun:^{
        self.sealed = true;
        self.callbacks = nil;
    }];
}

@end
