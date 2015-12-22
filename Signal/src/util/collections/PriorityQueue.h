#import <CoreFoundation/CoreFoundation.h>
#import "Constraints.h"

@interface PriorityQueue : NSObject {
   @private
    NSMutableArray *items;
}

@property (readonly, nonatomic, copy) NSComparator comparator;

+ (PriorityQueue *)priorityQueueAscendingWithComparator:(NSComparator)comparator;
- (void)enqueue:(id)item;
- (id)peek;
- (id)dequeue;
- (NSUInteger)count;
@end
