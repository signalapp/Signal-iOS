#import "PriorityQueueTest.h"
#import "PriorityQueue.h"
#import "Util.h"
#import "TestUtil.h"

NSArray* RandomPermutation(NSUInteger count);
NSArray* Permutations(NSUInteger count);

NSArray* RandomPermutation(NSUInteger count) {
    NSUInteger d[count];
    for (NSUInteger i = 0; i < count; i++)
        d[i] = i;
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger j = arc4random_uniform(count - i) + i;
        NSUInteger t = d[i];
        d[i] = d[j];
        d[j] = t;
    }
    NSMutableArray* r = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++)
        [r addObject:[NSNumber numberWithUnsignedInteger:d[i]]];
    return r;
}
NSArray* Permutations(NSUInteger count) {
    if (count == 0) return [NSArray array];
    NSMutableArray* r = [NSMutableArray array];
    for (NSArray* s in Permutations(count - 1)) {
        for (NSUInteger e = 0; e < count; e++) {
            NSMutableArray* a = [NSMutableArray array];
            [a addObject:[NSNumber numberWithUnsignedInteger:e]];
            for (NSNumber* x in s) {
                [a addObject:[x unsignedIntegerValue] < e ? x : [NSNumber numberWithUnsignedInteger:[x unsignedIntegerValue] + 1]];
            }
            [r addObject:a];
        }
    }
    return r;
}

@implementation PriorityQueueTest

-(void) testTrivialPrioritizing {
    PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(id obj1, id obj2){
        int diff =[obj2 intValue] - [obj1 intValue];
        if (diff > 0 ) {
            return (NSComparisonResult)NSOrderedAscending;
        } else if (diff < 0){
            return (NSComparisonResult)NSOrderedDescending;
        } else{
            return (NSComparisonResult)NSOrderedSame;
        }
    }];
    test([q count] == 0);
    testThrows([q peek]);
    testThrows([q dequeue]);
    
    [q enqueue:@1];
    [q enqueue:@2];
    [q enqueue:@3];
    test([q count] == 3);
    test([[q peek] intValue] == 1);
    test([[q dequeue] intValue] == 1);
    test([[q peek] intValue] == 2);
    test([[q dequeue] intValue] == 2);
    test([[q peek] intValue] == 3);
    test([[q dequeue] intValue] == 3);
    testThrows([q peek]);
    testThrows([q dequeue]);
}
-(void) testOrdersByComparatorInverse {
    PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(NSNumber* obj1, NSNumber* obj2){
        int diff =[obj1 intValue] - [obj2 intValue];
        if (diff > 0) {
            return (NSComparisonResult)NSOrderedAscending;
        } else if (diff < 0){
            return (NSComparisonResult)NSOrderedDescending;
        } else{
            return (NSComparisonResult)NSOrderedSame;
        }
    }];
                        
    [q enqueue:@1];
    [q enqueue:@2];
    [q enqueue:@3];
    test([[q dequeue] intValue] == 3);
    test([[q dequeue] intValue] == 2);
    test([[q dequeue] intValue] == 1);
}
-(void) testSortsAllSmallPermutations {
    const NSUInteger N = 7;
    for (NSArray* permutation in Permutations(N)) {
        PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(id obj1, id obj2){
            int diff =[obj2 intValue] - [obj1 intValue];
            if (diff > 0 ) {
                return (NSComparisonResult)NSOrderedAscending;
            } else if (diff < 0){
                return (NSComparisonResult)NSOrderedDescending;
            } else{
                return (NSComparisonResult)NSOrderedSame;
            }
        }];
        for (NSNumber* e in permutation) {
            [q enqueue:e];
        }
        
        // dequeues in order
        for (NSUInteger i = 0; i < N; i++) {
            test([q count] == N - i);
            test([[q dequeue] unsignedIntegerValue] == i);
        }
        test([q count] == 0);
    }
}
-(void) testSortsRandomLargePermutations {
    const NSUInteger Size = 500;
    const NSUInteger Repetitions = 50;
    for (NSUInteger repeat = 0; repeat < Repetitions; repeat++) {
        PriorityQueue* q = [PriorityQueue priorityQueueAscendingWithComparator:^(id obj1, id obj2){
            int diff =[obj2 intValue] - [obj1 intValue];
            if (diff > 0 ) {
                return (NSComparisonResult)NSOrderedAscending;
            } else if (diff < 0){
                return (NSComparisonResult)NSOrderedDescending;
            } else{
                return (NSComparisonResult)NSOrderedSame;
            }
        }];
        NSArray* permutation = RandomPermutation(Size);
        for (NSNumber* e in permutation) {
            [q enqueue:e];
        }
        
        // dequeues in order
        for (NSUInteger i = 0; i < Size; i++) {
            test([q count] == Size - i);
            test([[q dequeue] unsignedIntegerValue] == i);
        }
        test([q count] == 0);
    }
}


@end
