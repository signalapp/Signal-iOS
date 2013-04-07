#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseView.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yaptv/YapDatabase/wiki
**/

typedef id YapDatabaseViewFilterBlock; // One of the YapDatabaseViewFilterX types below.

typedef BOOL (^YapDatabaseViewFilterWithObjectBlock)(NSString *key, id object, NSUInteger *sectionOut);
typedef BOOL (^YapDatabaseViewFilterWithMetadataMetadataBlock)(NSString *key, id metadata, NSUInteger *sectionOut);
typedef BOOL (^YapDatabaseViewFilterWithBothBlock)(NSString *key, id object, id metadata, NSUInteger *sectionOut);

typedef id YapDatabaseViewSortBlock; // One of the YapDatabaseViewSortX types below.

typedef NSComparisonResult (^YapDatabaseViewSortWithObjectBlock) \
                           (NSString *key1, id object1, NSString *key2, id object2);
typedef NSComparisonResult (^YapDatabaseViewSortWithMetadataBlock) \
                           (NSString *key1, id metadata, NSString *key2, id metadata2);
typedef NSComparisonResult (^YapDatabaseViewSortWithBothBlock) \
                           (NSString *key1, id object1, id metadata1, NSString *key2, id object2, id metadata2);


typedef enum {
	BlockWithObject,
	BlockWithMetadata,
	BlockWithBoth
} YapDatabaseViewBlockType;


@interface YapDatabaseView : YapAbstractDatabaseView

/* Inherited from YapAbstractDatabaseView

@property (nonatomic, strong, readonly) NSString *name;

*/

- (id)initWithName:(NSString *)name
       filterBlock:(YapDatabaseViewFilterBlock)filterBlock
        filterType:(YapDatabaseViewBlockType)filterBlockType
         sortBlock:(YapDatabaseViewSortBlock)sortBlock
          sortType:(YapDatabaseViewBlockType)sortBlockType;

@property (nonatomic, strong, readonly) YapDatabaseViewFilterBlock filterBlock;
@property (nonatomic, strong, readonly) YapDatabaseViewSortBlock sortBlock;

@property (nonatomic, assign, readonly) YapDatabaseViewBlockType filterBlockType;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType sortBlockType;

@end
