#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseViewLocator : NSObject

- (instancetype)initWithGroup:(NSString *)group index:(NSUInteger)index;
- (instancetype)initWithGroup:(NSString *)group index:(NSUInteger)index pageKey:(nullable NSString *)pageKey;

@property (nonatomic, readonly, copy) NSString *group;
@property (nonatomic, readonly, assign) NSUInteger index;

@property (nonatomic, readonly, copy, nullable) NSString *pageKey;

@end

NS_ASSUME_NONNULL_END
