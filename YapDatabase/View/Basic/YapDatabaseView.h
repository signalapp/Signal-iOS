#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseView.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yaptv/YapDatabase/wiki
 * 
 * 
**/

typedef id YapDatabaseViewGroupingBlock; // One of the YapDatabaseViewGroupingX types below.

typedef NSString* (^YapDatabaseViewGroupingWithObjectBlock)(NSString *key, id object);
typedef NSString* (^YapDatabaseViewGroupingWithMetadataBlock)(NSString *key, id metadata);
typedef NSString* (^YapDatabaseViewGroupingWithBothBlock)(NSString *key, id object, id metadata);

typedef id YapDatabaseViewSortingBlock; // One of the YapDatabaseViewSortingX types below.

typedef NSComparisonResult (^YapDatabaseViewSortingWithObjectBlock) \
                 (NSString *group, NSString *key1, id object1, NSString *key2, id object2);
typedef NSComparisonResult (^YapDatabaseViewSortingWithMetadataBlock) \
                 (NSString *group, NSString *key1, id metadata, NSString *key2, id metadata2);
typedef NSComparisonResult (^YapDatabaseViewSortingWithBothBlock) \
                 (NSString *group, NSString *key1, id object1, id metadata1, NSString *key2, id object2, id metadata2);


typedef enum {
	YapDatabaseViewBlockTypeWithObject,
	YapDatabaseViewBlockTypeWithMetadata,
	YapDatabaseViewBlockTypeWithBoth
} YapDatabaseViewBlockType;



@interface YapDatabaseView : YapAbstractDatabaseView

/* Inherited from YapAbstractDatabaseView

@property (nonatomic, strong, readonly) NSString *name;

*/

/**
 * To create a view you 
**/
- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)groupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)groupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)sortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)sortingBlockType;

@property (nonatomic, strong, readonly) YapDatabaseViewGroupingBlock groupingBlock;
@property (nonatomic, strong, readonly) YapDatabaseViewSortingBlock sortingBlock;

@property (nonatomic, assign, readonly) YapDatabaseViewBlockType groupingBlockType;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType sortingBlockType;

@end
