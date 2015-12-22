#import <Foundation/Foundation.h>
#import "PriorityQueue.h"

@interface EventWindow : NSObject {
   @private
    NSTimeInterval windowDuration;
   @private
    PriorityQueue *events;
   @private
    NSTimeInterval lastWindowEnding;
}

+ (EventWindow *)eventWindowWithWindowDuration:(NSTimeInterval)windowDuration;
- (void)addEventAtTime:(NSTimeInterval)eventTime;
- (NSUInteger)countAfterRemovingEventsBeforeWindowEndingAt:(NSTimeInterval)endOfWindowTime;

@end
