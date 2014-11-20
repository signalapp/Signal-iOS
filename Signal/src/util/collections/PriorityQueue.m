#import "PriorityQueue.h"
#import <CoreFoundation/CoreFoundation.h>

@interface PriorityQueue ()

@property (strong, nonatomic) NSMutableArray* items;
@property (readwrite, nonatomic, copy) NSComparator comparator;

@end

@implementation PriorityQueue

- (instancetype)initAscendingWithComparator:(NSComparator)comparator {
    self = [super init];
	
    if (self) {
        require(comparator != nil);
        self.comparator = comparator;
    }
    
    return self;
}

- (NSMutableArray*)items {
    if (!_items) {
        _items = [[NSMutableArray alloc] init];
    }
    return _items;
}

- (void)enqueue:(id)item {
    NSUInteger curIndex = self.items.count;
    [self.items addObject:item];
    while (curIndex > 0) {
        NSUInteger parentIndex = (curIndex - 1) >> 1;
        id parentItem = self.items[parentIndex];
        if (self.comparator(item, parentItem) >= 0) break;
        
        [self.items setObject:parentItem atIndexedSubscript:curIndex];
        [self.items setObject:item atIndexedSubscript:parentIndex];
        curIndex = parentIndex;
    }
}

- (id)peek {
    requireState(self.items.count > 0);
    return self.items[0];
}

- (id)dequeue {
    requireState(self.items.count > 0);
    id result = self.items[0];
    
    // iteratively pull up smaller child until we hit the bottom of the heap
    NSUInteger endangeredIndex = self.items.count - 1;
    id endangeredItem = self.items[endangeredIndex];
    NSUInteger i = 0;
    while (true) {
        NSUInteger childIndex1 = i*2+1;
        NSUInteger childIndex2 = i*2+2;
        if (childIndex1 >= endangeredIndex) break;
        
        NSUInteger smallerChildIndex = self.comparator(self.items[childIndex1], self.items[childIndex2]) <= 0 ? childIndex1 : childIndex2;
        id smallerChild = self.items[smallerChildIndex];
        bool useEndangered = self.comparator(endangeredItem, smallerChild) <= 0;
        if (useEndangered) break;
        
        [self.items setObject:smallerChild atIndexedSubscript:i];
        i = smallerChildIndex;
    }
    
    // swap the item at the index to be removed into the new empty space at the bottom of heap
    [self.items setObject:endangeredItem atIndexedSubscript:i];
    [self.items removeObjectAtIndex:endangeredIndex];
    
    return result;
}

- (NSUInteger)count {
    return self.items.count;
}

@end

