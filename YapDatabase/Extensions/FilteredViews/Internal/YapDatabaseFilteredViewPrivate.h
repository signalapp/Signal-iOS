#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"

#import "YapDatabaseViewPrivate.h"

/**
 * Changeset keys (for changeset notification dictionary)
**/
static NSString *const changeset_key_filteringBlock     = @"filteringBlock";
static NSString *const changeset_key_filteringBlockType = @"filteringBlockType";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewFiltering ()

+ (instancetype)withBlock:(YapDatabaseViewFilteringBlock)block blockType:(YapDatabaseViewBlockType)blockType;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFilteredView () {
@private
	
	YapDatabaseViewFilteringBlock filteringBlock;
	YapDatabaseViewBlockType filteringBlockType;
	
@public
	
	NSString *parentViewName;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFilteredViewConnection () {
@protected
	
	YapDatabaseViewFilteringBlock filteringBlock;
	YapDatabaseViewBlockType filteringBlockType;
	
	BOOL filteringBlockChanged;
}

- (void)setGroupingBlock:(YapDatabaseViewGroupingBlock)newGroupingBlock
       groupingBlockType:(YapDatabaseViewBlockType)newGroupingBlockType
            sortingBlock:(YapDatabaseViewSortingBlock)newSortingBlock
        sortingBlockType:(YapDatabaseViewBlockType)newSortingBlockType;

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)newFilteringBlock
	   filteringBlockType:(YapDatabaseViewBlockType)newFilteringBlockType
               versionTag:(NSString *)newVersionTag;

- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
	   groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
			sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
		sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
          filteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
      filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr;

- (void)getFilteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
       filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr;

@end
