#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"

#import "YapDatabaseViewPrivate.h"


/**
 * Keys for yap2 extension configuration table.
**/

// Defined in YapDatabaseViewPrivate.h
//
//static NSString *const ext_key_classVersion = @"classVersion";
//static NSString *const ext_key_versionTag   = @"versionTag";

static NSString *const ext_key_parentViewName = @"parentViewName";

/**
 * Changeset keys (for changeset notification dictionary)
**/
static NSString *const changeset_key_filteringBlock     = @"filteringBlock";
static NSString *const changeset_key_filteringBlockType = @"filteringBlockType";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseFilteredView () {
@private
	
	YapDatabaseViewFilteringBlock filteringBlock;
	YapDatabaseBlockType filteringBlockType;
	
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
	YapDatabaseBlockType filteringBlockType;
	
	BOOL filteringBlockChanged;
}

- (void)setGroupingBlock:(YapDatabaseViewGroupingBlock)newGroupingBlock
       groupingBlockType:(YapDatabaseBlockType)newGroupingBlockType
            sortingBlock:(YapDatabaseViewSortingBlock)newSortingBlock
        sortingBlockType:(YapDatabaseBlockType)newSortingBlockType;

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)newFilteringBlock
	   filteringBlockType:(YapDatabaseBlockType)newFilteringBlockType
               versionTag:(NSString *)newVersionTag;

- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
	   groupingBlockType:(YapDatabaseBlockType *)groupingBlockTypePtr
			sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
		sortingBlockType:(YapDatabaseBlockType *)sortingBlockTypePtr
          filteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
      filteringBlockType:(YapDatabaseBlockType *)filteringBlockTypePtr;

- (void)getFilteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
       filteringBlockType:(YapDatabaseBlockType *)filteringBlockTypePtr;

@end
