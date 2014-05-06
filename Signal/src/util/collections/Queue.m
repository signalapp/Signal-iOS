#import "Queue.h"
#import "Constraints.h"

@implementation Queue {
@private NSMutableArray* items;
}
-(id) init {
    if (self = [super init]) {
        self->items = [NSMutableArray array];
    }
    return self;
}
-(void) enqueue:(id)item {
    [items addObject:item];
}
-(id) tryDequeue {
    if ([self count] == 0) return nil;
    return [self dequeue];
}
-(id) dequeue {
    requireState([self count] > 0);
    id result = [items objectAtIndex:0];
    [items removeObjectAtIndex:0];
    return result;
}
-(id) peek {
    requireState([self count] > 0);
    return [items objectAtIndex:0];
}
-(id) peekAt:(NSUInteger)offset {
    require(offset < [self count]);
    return [items objectAtIndex:offset];
}
-(NSUInteger) count {
    return [items count];
}
@end
