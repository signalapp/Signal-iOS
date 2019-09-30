
@interface NSArray (Functional)

- (NSArray *)filtered:(BOOL (^)(NSObject *))isIncluded;

@end
