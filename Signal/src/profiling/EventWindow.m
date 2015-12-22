#import "EventWindow.h"

@implementation EventWindow

+ (EventWindow *)eventWindowWithWindowDuration:(NSTimeInterval)windowDuration {
    ows_require(windowDuration >= 0);

    EventWindow *w    = [EventWindow new];
    w->windowDuration = windowDuration;
    w->events         = [PriorityQueue priorityQueueAscendingWithComparator:^NSComparisonResult(id obj1, id obj2) {
      return [(NSNumber *)obj1 compare:(NSNumber *)obj2];
    }];
    w->lastWindowEnding = -INFINITY;
    return w;
}

- (void)addEventAtTime:(NSTimeInterval)eventTime {
    [events enqueue:@(eventTime)];
}

- (NSUInteger)countAfterRemovingEventsBeforeWindowEndingAt:(NSTimeInterval)endOfWindowTime {
    // because values are removed, going backwards will give misleading results.
    // checking for this case so callers don't get silent bad results
    // includes a small leeway in case of non-monotonic time source or extended precision lose
    requireState(endOfWindowTime >= lastWindowEnding - 0.03);
    lastWindowEnding = endOfWindowTime;

    NSTimeInterval startOfWindowTime = endOfWindowTime - windowDuration;
    while (events.count > 0 && [events.peek doubleValue] < startOfWindowTime) {
        [events dequeue];
    }
    return events.count;
}

@end
