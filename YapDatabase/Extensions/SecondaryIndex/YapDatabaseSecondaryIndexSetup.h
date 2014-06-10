#import <Foundation/Foundation.h>

@class YapDatabaseSecondaryIndexColumn;

typedef NS_ENUM(NSInteger, YapDatabaseSecondaryIndexType) {
	YapDatabaseSecondaryIndexTypeInteger,
	YapDatabaseSecondaryIndexTypeReal,
	YapDatabaseSecondaryIndexTypeText
};

@interface YapDatabaseSecondaryIndexSetup : NSObject <NSCopying, NSFastEnumeration>

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity;

- (void)addColumn:(NSString *)name withType:(YapDatabaseSecondaryIndexType)type;

- (NSUInteger)count;
- (YapDatabaseSecondaryIndexColumn *)columnAtIndex:(NSUInteger)index;

- (NSArray *)columnNames;

@end

#pragma mark -

@interface YapDatabaseSecondaryIndexColumn : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) YapDatabaseSecondaryIndexType type;

@end
