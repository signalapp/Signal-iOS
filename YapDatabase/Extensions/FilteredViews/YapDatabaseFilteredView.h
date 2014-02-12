#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"

#import "YapDatabaseFilteredViewTypes.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"


@interface YapDatabaseFilteredView : YapDatabaseView

/**
 * @param parentViewName
 *
 *   The parentViewName must be the registered name of a YapDatabaseView or
 *   YapDatabaseFilteredView extension.
 *   That is, you must first register the parentView, and then use that registered name here.
 *
 * @param filteringBlock
 *
 *   The filteringBlock type is one of the following typedefs:
 *    - YapDatabaseViewFilteringWithKeyBlock
 *    - YapDatabaseViewFilteringWithObjectBlock
 *    - YapDatabaseViewFilteringWithMetadataBlock
 *    - YapDatabaseViewFilteringWithRowBlock
 *   It allows you to filter items from this view that exist in the parent view.
 *   You should pick a block type that requires the minimum number of parameters that you need.
 *
 *   @see YapDatabaseViewTypes.h for block type definition(s).
 *
 * @param filteringBlockType
 *
 *   This parameter identifies the type of filtering block being used.
 *   It must be one of the following (and must match the filteringBlock being passed):
 *    - YapDatabaseViewBlockTypeWithKey
 *    - YapDatabaseViewBlockTypeWithObject
 *    - YapDatabaseViewBlockTypeWithMetadata
 *    - YapDatabaseViewBlockTypeWithRow
 * 
 *   @see YapDatabaseViewTypes.h for block type definition(s).
 *
 * @param tag
 *
 *   The filteringBlock may be changed after the filteredView is created (see YapDatabaseFilteredViewTransaction).
 *   This is often in association with user events.
 *   The tag helps to identify the filteringBlock being used.
 *   During initialization of the view, the view will compare the passed tag to what it has stored from a previous
 *   app session. If the tag matches, then the filteredView is already setup. Otherwise the view will automatically
 *   flush its tables, and re-populate itself.
 *
 * @param options
 *
 *   The options allow you to specify things like creating an IN-MEMORY-ONLY VIEW (non persistent).
**/

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                  versionTag:(NSString *)versionTag;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                  versionTag:(NSString *)versionTag
                     options:(YapDatabaseViewOptions *)options;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType filteringBlockType;

/**
 * The options allow you to specify things like creating an IN-MEMORY-ONLY VIEW (non persistent).
**/
@property (nonatomic, copy, readonly) YapDatabaseViewOptions *options;

@end
