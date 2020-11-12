#import <Foundation/Foundation.h>

@interface NSArray (Functional)

- (BOOL)contains:(BOOL (^)(id))predicate;
- (NSArray *)filtered:(BOOL (^)(id))isIncluded;
- (NSArray *)map:(id (^)(id))transform;

@end
