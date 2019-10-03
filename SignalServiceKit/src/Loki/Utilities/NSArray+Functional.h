
@interface NSArray (Functional)

- (NSArray *)filtered:(BOOL (^)(NSObject *))isIncluded;
- (NSArray *)map:(NSObject *(^)(NSObject *))transform;

@end
