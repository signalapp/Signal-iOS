//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>

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
