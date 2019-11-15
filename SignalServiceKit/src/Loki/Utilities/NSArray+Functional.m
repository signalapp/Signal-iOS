#import "NSArray+Functional.h"

@implementation NSArray (Functional)

- (BOOL)contains:(BOOL (^)(id))predicate {
    for (id object in self) {
        BOOL isPredicateSatisfied = predicate(object);
        if (isPredicateSatisfied) { return YES; }
    }
    return NO;
}

- (NSArray *)filtered:(BOOL (^)(id))isIncluded {
    NSMutableArray *result = [NSMutableArray new];
    for (id object in self) {
        if (isIncluded(object)) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)map:(id (^)(id))transform {
    NSMutableArray *result = [NSMutableArray new];
    for (id object in self) {
        id transformedObject = transform(object);
        [result addObject:transformedObject];
    }
    return result;
}

@end
