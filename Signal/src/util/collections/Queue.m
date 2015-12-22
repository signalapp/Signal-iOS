#import "Constraints.h"
#import "Queue.h"

@implementation Queue {
   @private
    NSMutableArray *items;
}
- (id)init {
    if (self = [super init]) {
        self->items = [NSMutableArray array];
    }
    return self;
}
- (void)enqueue:(id)item {
    [items addObject:item];
}
- (id)tryDequeue {
    if (self.count == 0)
        return nil;
    return [self dequeue];
}
- (id)dequeue {
    requireState(self.count > 0);
    id result = items[0];
    [items removeObjectAtIndex:0];
    return result;
}
- (id)peek {
    requireState(self.count > 0);
    return items[0];
}
- (id)peekAt:(NSUInteger)offset {
    ows_require(offset < self.count);
    return items[offset];
}
- (NSUInteger)count {
    return items.count;
}
@end
