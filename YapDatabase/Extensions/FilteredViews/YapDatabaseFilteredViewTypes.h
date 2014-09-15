#import <Foundation/Foundation.h>
#import "YapDatabaseViewTypes.h"

/**
 * The filtering block removes items from this view that are in the parent view.
 *
 * A YapDatabaseFilteredView will have the same groups and same sort order as the parent,
 * with the exception of those groups/rows that the filter block returned NO for.
 *
 * Here's how it works:
 * When you initialize a YapDatabaseFilteredView instance, it will enumerate the parentView
 * and invoke the filter block for every row in every group. So it can quickly copy a parentView as it
 * doesn't have to perform any sorting.
 * 
 * After its initialization, the filterView will automatically run for inserted / updated rows
 * after the parentView has processed them. It then gets the group from parentView,
 * and invokes the filterBlock again (if needed).
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The filterView can make various optimizations based on required parameters of the block.
**/
@interface YapDatabaseViewFiltering : NSObject

typedef id YapDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapDatabaseViewFilteringWithKeyBlock)     \
                                        (NSString *group, NSString *collection, NSString *key);
typedef BOOL (^YapDatabaseViewFilteringWithObjectBlock)  \
                                        (NSString *group, NSString *collection, NSString *key, id object);
typedef BOOL (^YapDatabaseViewFilteringWithMetadataBlock)\
                                        (NSString *group, NSString *collection, NSString *key, id metadata);
typedef BOOL (^YapDatabaseViewFilteringWithRowBlock)     \
                                        (NSString *group, NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseViewFilteringWithKeyBlock)filteringBlock;
+ (instancetype)withObjectBlock:(YapDatabaseViewFilteringWithObjectBlock)filteringBlock;
+ (instancetype)withMetadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)filteringBlock;
+ (instancetype)withRowBlock:(YapDatabaseViewFilteringWithRowBlock)filteringBlock;

@property (nonatomic, strong, readonly) YapDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType filteringBlockType;

@end
