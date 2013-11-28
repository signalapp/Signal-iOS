#import <Foundation/Foundation.h>

#import "YapCollectionsDatabaseView.h"
#import "YapCollectionsDatabaseFilteredViewConnection.h"
#import "YapCollectionsDatabaseFilteredViewTransaction.h"


#ifndef YapCollectionsDatabaseViewFilteringBlockDefined
#define YapCollectionsDatabaseViewFilteringBlockDefined 1

typedef id YapCollectionsDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapCollectionsDatabaseViewFilteringWithKeyBlock)     \
                                        (NSString *group, NSString *collection, NSString *key);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithObjectBlock)  \
                                        (NSString *group, NSString *collection, NSString *key, id object);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithMetadataBlock)\
                                        (NSString *group, NSString *collection, NSString *key, id metadata);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithRowBlock)     \
                                        (NSString *group, NSString *collection, NSString *key, id object, id metadata);

#endif

@interface YapCollectionsDatabaseFilteredView : YapCollectionsDatabaseView

/**
 * @param parentViewName
 *
 *   The parentViewName must be the registered name of a YapCollectionsDatabaseView or
 *   YapCollectionsDatabaseFilteredView extension.
 *   That is, you must first register the parentView, and then use that registered name here.
 *
 * @param filteringBlock
 *
 *   The filteringBlock type is one of the following typedefs:
 *    - YapCollectionsDatabaseViewFilteringWithKeyBlock
 *    - YapCollectionsDatabaseViewFilteringWithObjectBlock
 *    - YapCollectionsDatabaseViewFilteringWithMetadataBlock
 *    - YapCollectionsDatabaseViewFilteringWithRowBlock
 *   It allows you to filter items from this view that exist in the parent view.
 *   You should pick a block type that requires the minimum number of parameters that you need.
 *
 * @param filteringBlockType
 *
 *   This parameter identifies the type of filtering block being used.
 *   It must be one of the following (and must match the filteringBlock being passed):
 *    - YapCollectionsDatabaseViewBlockTypeWithKey
 *    - YapCollectionsDatabaseViewBlockTypeWithObject
 *    - YapCollectionsDatabaseViewBlockTypeWithMetadata
 *    - YapCollectionsDatabaseViewBlockTypeWithRow
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
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType
                         tag:(NSString *)tag;

- (id)initWithParentViewName:(NSString *)viewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType
                         tag:(NSString *)tag
                     options:(YapCollectionsDatabaseViewOptions *)options;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapCollectionsDatabaseViewFilteringBlock filteringBlock;
@property (nonatomic, assign, readonly) YapCollectionsDatabaseViewBlockType filteringBlockType;

/**
 * The tag assists you in updating the filteringBlock.
 *
 * Whenever you change the filteringBlock, just specify a tag to associate with the block.
 * The tag can help you to identify the filtering criteria, or perhaps be used as a versioning scheme.
 *
 * Here's how it works:
 * The very first time you create the filteredView, it will populate itself from the parentView + filteringBlock.
 * On subsequent app launches, when you re-register the filteredView, it will check the passed tag with
 * the tag it has stored from the previous app session. If the tags match then the filteredView knows it doesn't
 * have to do anything. (It's already setup from last app session.) However, if the tags don't match, then
 * the filteredView will re-populate itself.
 * 
 * It works the same way if you change the filteringBlock on-the-fly. (See setFilteringBlock:filteringBlockType:tag:)
**/
@property (nonatomic, copy, readonly) NSString *tag;

/**
 * The options allow you to specify things like creating an IN-MEMORY-ONLY VIEW (non persistent).
**/
@property (nonatomic, copy, readonly) YapCollectionsDatabaseViewOptions *options;

@end
