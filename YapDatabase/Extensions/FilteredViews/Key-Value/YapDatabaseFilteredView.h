#import <Foundation/Foundation.h>
#import "YapDatabaseView.h"


typedef id YapDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapDatabaseViewFilteringWithKeyBlock)(NSString *group, NSString *key);
typedef BOOL (^YapDatabaseViewFilteringWithObjectBlock)(NSString *group, NSString *key, id object);
typedef BOOL (^YapDatabaseViewFilteringWithMetadataBlock)(NSString *group, NSString *key, id metadata);
typedef BOOL (^YapDatabaseViewFilteringWithRowBlock)(NSString *group, NSString *key, id object, id metadata);


@interface YapDatabaseFilteredView : YapDatabaseView

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                     version:(int)version;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                     version:(int)version
                     options:(YapDatabaseViewOptions *)options;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType filteringBlockType;

@end
