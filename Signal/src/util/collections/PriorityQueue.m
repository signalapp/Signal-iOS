#import "PriorityQueue.h"

@implementation PriorityQueue

+ (PriorityQueue *)priorityQueueAscendingWithComparator:(NSComparator)comparator {
    ows_require(comparator != nil);
    PriorityQueue *q = [PriorityQueue new];
    q->_comparator   = comparator;
    q->items         = [NSMutableArray array];
    return q;
}

- (void)enqueue:(id)item {
    NSUInteger curIndex = items.count;
    [items addObject:item];
    while (curIndex > 0) {
        NSUInteger parentIndex = (curIndex - 1) >> 1;
        id parentItem          = items[parentIndex];
        if (_comparator(item, parentItem) >= 0)
            break;

        [items setObject:parentItem atIndexedSubscript:curIndex];
        [items setObject:item atIndexedSubscript:parentIndex];
        curIndex = parentIndex;
    }
}

- (id)peek {
    requireState(items.count > 0);
    return items[0];
}

- (id)dequeue {
    requireState(items.count > 0);
    id result = items[0];

    // iteratively pull up smaller child until we hit the bottom of the heap
    NSUInteger endangeredIndex = items.count - 1;
    id endangeredItem          = items[endangeredIndex];
    NSUInteger i               = 0;
    while (true) {
        NSUInteger childIndex1 = i * 2 + 1;
        NSUInteger childIndex2 = i * 2 + 2;
        if (childIndex1 >= endangeredIndex)
            break;

        NSUInteger smallerChildIndex =
            _comparator(items[childIndex1], items[childIndex2]) <= 0 ? childIndex1 : childIndex2;
        id smallerChild    = items[smallerChildIndex];
        bool useEndangered = _comparator(endangeredItem, smallerChild) <= 0;
        if (useEndangered)
            break;

        [items setObject:smallerChild atIndexedSubscript:i];
        i = smallerChildIndex;
    }

    // swap the item at the index to be removed into the new empty space at the bottom of heap
    [items setObject:endangeredItem atIndexedSubscript:i];
    [items removeObjectAtIndex:endangeredIndex];

    return result;
}

- (NSUInteger)count {
    return items.count;
}
@end
