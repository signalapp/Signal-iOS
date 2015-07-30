#import <XCTest/XCTest.h>
#import "TestUtil.h"

@interface PriorityQueueTest : XCTestCase
@end

NSArray* RandomPermutation(uint32_t count);
NSArray* Permutations(uint32_t count);

NSArray* RandomPermutation(uint32_t count) {
    uint32_t d[count];
    for (uint32_t i = 0; i < count; i++)
        d[i] = i;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t j = arc4random_uniform(count - i) + i;
        uint32_t t = d[i];
        d[i] = d[j];
        d[j] = t;
    }
    NSMutableArray* r = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++)
        [r addObject:@(d[i])];
    return r;
}
NSArray* Permutations(uint32_t count) {
    if (count == 0) return @[];
    NSMutableArray* r = [NSMutableArray array];
    for (NSArray* s in Permutations(count - 1)) {
        for (uint32_t e = 0; e < count; e++) {
            NSMutableArray* a = [NSMutableArray array];
            [a addObject:@(e)];
            for (NSNumber* x in s) {
                [a addObject:[x unsignedIntegerValue] < e ? x : @([x unsignedIntegerValue] + 1)];
            }
            [r addObject:a];
        }
    }
    return r;
}

@implementation PriorityQueueTest

-(void) testTrivialPrioritizing {
    PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(NSNumber* obj1, NSNumber* obj2){
        return [obj1 compare:obj2];
    }];
    test(q.count == 0);
    testThrows(q.peek);
    testThrows([q dequeue]);
    
    [q enqueue:@1];
    [q enqueue:@2];
    [q enqueue:@3];
    test(q.count == 3);
    test([q.peek intValue] == 1);
    test([[q dequeue] intValue] == 1);
    test([q.peek intValue] == 2);
    test([[q dequeue] intValue] == 2);
    test([q.peek intValue] == 3);
    test([[q dequeue] intValue] == 3);
    testThrows(q.peek);
    testThrows([q dequeue]);
}
-(void) testOrdersByComparatorInverse {
    PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(NSNumber* obj1, NSNumber* obj2){
        return [obj2 compare:obj1];
    }];
    
    [q enqueue:@1];
    [q enqueue:@2];
    [q enqueue:@3];
    test([[q dequeue] intValue] == 3);
    test([[q dequeue] intValue] == 2);
    test([[q dequeue] intValue] == 1);
}
-(void) testSortsAllSmallPermutations {
    const uint32_t N = 7;
    for (NSArray* permutation in Permutations(N)) {
        PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(NSNumber* obj1, NSNumber* obj2){
            return [obj1 compare:obj2];
        }];
        for (NSNumber* e in permutation) {
            [q enqueue:e];
        }
        
        // dequeues in order
        for (uint32_t i = 0; i < N; i++) {
            test(q.count == N - i);
            test([[q dequeue] unsignedIntegerValue] == i);
        }
        test(q.count == 0);
    }
}
-(void) testSortsRandomLargePermutations {
    const uint32_t Size = 500;
    const uint32_t Repetitions = 50;
    for (uint32_t repeat = 0; repeat < Repetitions; repeat++) {
        PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(NSNumber* obj1, NSNumber* obj2){
            return [obj1 compare:obj2];
        }];
        NSArray* permutation = RandomPermutation(Size);
        for (NSNumber* e in permutation) {
            [q enqueue:e];
        }
        
        // dequeues in order
        for (uint32_t i = 0; i < Size; i++) {
            test(q.count == Size - i);
            test([[q dequeue] unsignedIntegerValue] == i);
        }
        test(q.count == 0);
    }
}


@end
