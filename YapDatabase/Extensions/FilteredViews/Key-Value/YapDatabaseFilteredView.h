#import <Foundation/Foundation.h>
#import "YapDatabaseView.h"


typedef id YapDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapDatabaseViewFilteringWithKeyBlock)(NSString *group, NSString *key);
typedef BOOL (^YapDatabaseViewFilteringWithObjectBlock)(NSString *group, NSString *key, id object);
typedef BOOL (^YapDatabaseViewFilteringWithMetadataBlock)(NSString *group, NSString *key, id metadata);
typedef BOOL (^YapDatabaseViewFilteringWithRowBlock)(NSString *group, NSString *key, id object, id metadata);


@interface YapDatabaseFilteredView : YapDatabaseView

/**
 * @param parentViewName
 * 
 *   The parentViewName must be the registered name of a YapDatabaseView or YapDatabaseFilteredView extension.
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
 * @param filteringBlockType
 * 
 *   This parameter identifies the type of filtering block being used.
 *   It must be one of the following (and must match the filteringBlock being passed):
 *    - YapDatabaseViewBlockTypeWithKey
 *    - YapDatabaseViewBlockTypeWithObject
 *    - YapDatabaseViewBlockTypeWithMetadata
 *    - YapDatabaseViewBlockTypeWithRow
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

- (id)initWithParentViewName:(NSString *)parentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType;

- (id)initWithParentViewName:(NSString *)parentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                         tag:(NSString *)tag;

- (id)initWithParentViewName:(NSString *)parentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                         tag:(NSString *)tag
                     options:(YapDatabaseViewOptions *)options;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType filteringBlockType;

/**
 * The tag assists you in updating the filteringBlock.
 *
 * Whenever you change the filteringBlock, just specify a tag to associate with the block.
 * The tag can be used as a versioning scheme, or perhaps helps to identify the filtering criteria.
 * 
 * Here's how it works:
 * When you first create a filteredView, you specify a filteringBlock and associated tag.
 * If you later need to change the filteringBlock, then you change the associated tag simultaneously.
 * If the database notices the tag has changed since last time,
 * it will automatically flush the view and re-populate it using the new filteringBlock.
**/
@property (nonatomic, copy, readonly) NSString *tag;

/**
 * The options allow you to specify things like creating an IN-MEMORY-ONLY VIEW (non persistent).
**/
@property (nonatomic, copy, readonly) YapDatabaseViewOptions *options;

@end
