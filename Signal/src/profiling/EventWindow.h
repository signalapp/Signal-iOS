#import <Foundation/Foundation.h>
#import "PriorityQueue.h"

@interface EventWindow : NSObject

- (instancetype)initWithWindowDuration:(NSTimeInterval)windowDuration;
- (void)addEventAtTime:(NSTimeInterval)eventTime;
- (NSUInteger)countAfterRemovingEventsBeforeWindowEndingAt:(NSTimeInterval)endOfWindowTime;

@end
