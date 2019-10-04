
@interface NSArray (Functional)

- (BOOL)contains:(BOOL (^)(NSObject *))predicate;
- (NSArray *)filtered:(BOOL (^)(NSObject *))isIncluded;
- (NSArray *)map:(NSObject *(^)(NSObject *))transform;

@end
