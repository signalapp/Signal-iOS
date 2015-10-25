#import <Foundation/Foundation.h>

@class YapDatabaseSecondaryIndexColumn;

NS_ASSUME_NONNULL_BEGIN

/**
 * For detailed information on sqlite datatypes & affinity:
 * https://www.sqlite.org/datatype3.html
**/
typedef NS_ENUM(NSInteger, YapDatabaseSecondaryIndexType) {
	YapDatabaseSecondaryIndexTypeInteger,
	YapDatabaseSecondaryIndexTypeReal,
	YapDatabaseSecondaryIndexTypeNumeric,
	YapDatabaseSecondaryIndexTypeText,
	YapDatabaseSecondaryIndexTypeBlob
};

NSString* NSStringFromYapDatabaseSecondaryIndexType(YapDatabaseSecondaryIndexType type);


@interface YapDatabaseSecondaryIndexSetup : NSObject <NSCopying, NSFastEnumeration>

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity;

- (void)addColumn:(NSString *)name withType:(YapDatabaseSecondaryIndexType)type;

- (NSUInteger)count;
- (nullable YapDatabaseSecondaryIndexColumn *)columnAtIndex:(NSUInteger)index;

- (NSArray<NSString *> *)columnNames;

@end

#pragma mark -

@interface YapDatabaseSecondaryIndexColumn : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) YapDatabaseSecondaryIndexType type;

@end

NS_ASSUME_NONNULL_END
