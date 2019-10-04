#import "NSArray+Functional.h"

@implementation NSArray (Functional)

- (BOOL)contains:(BOOL (^)(NSObject *))predicate {
    for (NSObject *object in self) {
        BOOL isPredicateSatisfied = predicate(object);
        if (isPredicateSatisfied) { return YES; }
    }
    return NO;
}

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
