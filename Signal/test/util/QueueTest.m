#import "Queue.h"
#import "QueueTest.h"
#import "TestUtil.h"

@implementation QueueTest

- (void)testQueue {
    Queue *q = [Queue new];
    test(q.count == 0);
    testThrows(q.peek);
    testThrows([q dequeue]);

    [q enqueue:@5];
    test(q.count == 1);
    test([q.peek isEqualToNumber:@5]);

    [q enqueue:@23];
    test(q.count == 2);
    test([q.peek isEqualToNumber:@5]);

    test([[q dequeue] isEqualToNumber:@5]);
    test(q.count == 1);
    test([q.peek isEqualToNumber:@23]);

    test([[q dequeue] isEqualToNumber:@23]);
    test(q.count == 0);
    testThrows(q.peek);
    testThrows([q dequeue]);
}

@end
