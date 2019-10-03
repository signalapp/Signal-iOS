#import "NSArray+Functional.h"

@implementation NSArray (Functional)

- (NSArray *)filtered:(BOOL (^)(NSObject *))isIncluded {
    NSMutableArray *result = [NSMutableArray new];
    for (NSObject *object in self) {
        if (isIncluded(object)) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)map:(NSObject *(^)(NSObject *))transform {
    NSMutableArray *result = [NSMutableArray new];
    for (NSObject *object in self) {
        NSObject *transformedObject = transform(object);
        [result addObject:transformedObject];
    }
    return result;
}

@end
