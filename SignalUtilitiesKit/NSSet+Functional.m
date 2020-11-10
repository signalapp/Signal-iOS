#import "NSSet+Functional.h"

@implementation NSSet (Functional)

- (BOOL)contains:(BOOL (^)(id))predicate {
    for (id object in self) {
        BOOL isPredicateSatisfied = predicate(object);
        if (isPredicateSatisfied) { return YES; }
    }
    return NO;
}

- (NSSet *)filtered:(BOOL (^)(id))isIncluded {
    NSMutableSet *result = [NSMutableSet new];
    for (id object in self) {
        if (isIncluded(object)) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSSet *)map:(id (^)(id))transform {
    NSMutableSet *result = [NSMutableSet new];
    for (id object in self) {
        id transformedObject = transform(object);
        [result addObject:transformedObject];
    }
    return result;
}

@end
