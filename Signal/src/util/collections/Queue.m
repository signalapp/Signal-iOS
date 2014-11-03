#import "Queue.h"
#import "Constraints.h"

@interface Queue ()

@property (strong, nonatomic) NSMutableArray* items;

@end

@implementation Queue

- (NSMutableArray*)items {
    if (!_items) {
        _items = [[NSMutableArray alloc] init];
    }
    return _items;
}

- (void)enqueue:(id)item {
    [self.items addObject:item];
}

- (id)tryDequeue {
    if (self.count == 0) return nil;
    return [self dequeue];
}

- (id)dequeue {
    requireState(self.count > 0);
    id result = self.items[0];
    [self.items removeObjectAtIndex:0];
    return result;
}

- (id)peek {
    requireState(self.count > 0);
    return self.items[0];
}

- (id)peekAt:(NSUInteger)offset {
    require(offset < self.count);
    return self.items[offset];
}

- (NSUInteger)count {
    return self.items.count;
}

@end
