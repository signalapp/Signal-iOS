#import <Foundation/Foundation.h>

@interface NSSet (Functional)

- (BOOL)contains:(BOOL (^)(id))predicate;
- (NSSet *)filtered:(BOOL (^)(id))isIncluded;
- (NSSet *)map:(id (^)(id))transform;

@end
