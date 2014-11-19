#import "EventWindow.h"
#import "Util.h"

@interface EventWindow ()

@property (nonatomic) NSTimeInterval windowDuration;
@property (nonatomic) NSTimeInterval lastWindowEnding;
@property (strong, nonatomic) PriorityQueue* events;

@end

@implementation EventWindow

- (instancetype)initWithWindowDuration:(NSTimeInterval)windowDuration {
    if (self = [super init]) {
        require(windowDuration >= 0);
        self.windowDuration = windowDuration;
        self.lastWindowEnding = -INFINITY;
        self.events = [[PriorityQueue alloc] initAscendingWithComparator:^NSComparisonResult(id obj1, id obj2) {
            return [(NSNumber*)obj1 compare:(NSNumber*)obj2];
        }];
    }
    
    return self;
}

- (void)addEventAtTime:(NSTimeInterval)eventTime {
    [self.events enqueue:@(eventTime)];
}

- (NSUInteger)countAfterRemovingEventsBeforeWindowEndingAt:(NSTimeInterval)endOfWindowTime {
    // because values are removed, going backwards will give misleading results.
    // checking for this case so callers don't get silent bad results
    // includes a small leeway in case of non-monotonic time source or extended precision lose
    requireState(endOfWindowTime >= self.lastWindowEnding-0.03);
    self.lastWindowEnding = endOfWindowTime;
    
    NSTimeInterval startOfWindowTime = endOfWindowTime - self.windowDuration;
    while (self.events.count > 0 && [self.events.peek  doubleValue] < startOfWindowTime) {
        [self.events dequeue];
    }
    return self.events.count;
}

@end
