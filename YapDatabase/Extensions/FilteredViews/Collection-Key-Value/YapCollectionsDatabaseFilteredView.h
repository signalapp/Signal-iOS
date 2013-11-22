#import <Foundation/Foundation.h>
#import "YapCollectionsDatabaseView.h"


typedef id YapCollectionsDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapCollectionsDatabaseViewFilteringWithKeyBlock)     \
                                        (NSString *group, NSString *collection, NSString *key);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithObjectBlock)  \
                                        (NSString *group, NSString *collection, NSString *key, id object);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithMetadataBlock)\
                                        (NSString *group, NSString *collection, NSString *key, id metadata);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithRowBlock)     \
                                        (NSString *group, NSString *collection, NSString *key, id object, id metadata);


@interface YapCollectionsDatabaseFilteredView : YapCollectionsDatabaseView

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType
                     version:(int)version;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType
                     version:(int)version
                     options:(YapCollectionsDatabaseViewOptions *)options;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapCollectionsDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapCollectionsDatabaseViewBlockType filteringBlockType;

@end
