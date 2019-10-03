
@interface NSSet (Functional)

- (BOOL)contains:(BOOL (^)(NSObject *))predicate;
- (NSSet *)filtered:(BOOL (^)(NSObject *))isIncluded;

@end
