#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewPrivate.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif

@interface YapDatabaseFilteredView ()

/**
 * This method is designed exclusively for YapDatabaseFilteredViewConnection.
 * All subclasses and transactions are required to use our version of the same method.
 *
 * So we declare it here, as opposed to within YapDatabaseViewPrivate.
**/
- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
       groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
            sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
        sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
          filteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
      filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseFilteredViewConnection

#pragma mark Accessors

- (YapDatabaseFilteredView *)filteredView
{
	return (YapDatabaseFilteredView *)view;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:databaseTransaction];
	
	return filteredViewTransaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithViewConnection:self
	                                                 databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return filteredViewTransaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	// Don't keep cached blocks in memory.
	// These are loaded on-demand withing readwrite transactions.
	if (filteringBlock) {
		filteringBlock = NULL;
		filteringBlockType = 0;
	}
	
	filteringBlockChanged = NO;
	
	[super postRollbackCleanup];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	// Don't keep cached blocks in memory.
	// These are loaded on-demand withing readwrite transactions.
	filteringBlock = NULL;
	filteringBlockType = 0;
	
	filteringBlockChanged = NO;
	
	[super postCommitCleanup];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	[super getInternalChangeset:&internalChangeset
	          externalChangeset:&externalChangeset
	             hasDiskChanges:&hasDiskChanges];
	
	if (filteringBlockChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		internalChangeset[changeset_key_filteringBlock] = filteringBlock;
		internalChangeset[changeset_key_filteringBlockType] = @(filteringBlockType);
		
		// Note: versionTag & hasDiskChanges handled by superclass
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used when the parentView's groupingBlock/sortingBlock changes.
 *
 * We need to update our groupingBlock/sortingBlock to match,
 * but NOT the versionTag (since it didn't change).
**/
- (void)setGroupingBlock:(YapDatabaseViewGroupingBlock)newGroupingBlock
       groupingBlockType:(YapDatabaseViewBlockType)newGroupingBlockType
            sortingBlock:(YapDatabaseViewSortingBlock)newSortingBlock
        sortingBlockType:(YapDatabaseViewBlockType)newSortingBlockType
{
	groupingBlock        = newGroupingBlock;
	groupingBlockType    = newGroupingBlockType;
	groupingBlockChanged = YES;
	
	sortingBlock        = newSortingBlock;
	sortingBlockType    = newSortingBlockType;
	sortingBlockChanged = YES;
}

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)newFilteringBlock
	   filteringBlockType:(YapDatabaseViewBlockType)newFilteringBlockType
               versionTag:(NSString *)newVersionTag
{
	filteringBlock        = newFilteringBlock;
	filteringBlockType    = newFilteringBlockType;
	filteringBlockChanged = YES;
	
	versionTag        = newVersionTag;
	versionTagChanged = YES;
}

- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
       groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
            sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
        sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
          filteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
      filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr
{
	if (!groupingBlock || !sortingBlock || !filteringBlock)
	{
		// Fetch & Cache
		
		__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)view;
		
		YapDatabaseViewGroupingBlock  mostRecentGroupingBlock  = NULL;
		YapDatabaseViewSortingBlock   mostRecentSortingBlock   = NULL;
		YapDatabaseViewFilteringBlock mostRecentFilteringBlock = NULL;
		YapDatabaseViewBlockType mostRecentGroupingBlockType  = 0;
		YapDatabaseViewBlockType mostRecentSortingBlockType   = 0;
		YapDatabaseViewBlockType mostRecentFilteringBlockType = 0;
		
		BOOL needsGroupingBlock = (groupingBlock == NULL);
		BOOL needsSortingBlock = (sortingBlock == NULL);
		BOOL needsFilteringBlock = (filteringBlock == NULL);
		
		[filteredView getGroupingBlock:(needsGroupingBlock ? &mostRecentGroupingBlock : NULL)
		             groupingBlockType:(needsGroupingBlock ? &mostRecentGroupingBlockType : NULL)
		                  sortingBlock:(needsSortingBlock ? &mostRecentSortingBlock : NULL)
		              sortingBlockType:(needsSortingBlock ? &mostRecentSortingBlockType : NULL)
		                filteringBlock:(needsFilteringBlock ? &mostRecentFilteringBlock : NULL)
		            filteringBlockType:(needsFilteringBlock ? &mostRecentFilteringBlockType : NULL)];
		
		if (needsGroupingBlock) {
			groupingBlock      = mostRecentGroupingBlock;
			groupingBlockType  = mostRecentGroupingBlockType;
		}
		if (needsSortingBlock) {
			sortingBlock       = mostRecentSortingBlock;
			sortingBlockType   = mostRecentSortingBlockType;
		}
		if (needsFilteringBlock) {
			filteringBlock     = mostRecentFilteringBlock;
			filteringBlockType = mostRecentFilteringBlockType;
		}
	}
	
	if (groupingBlockPtr)      *groupingBlockPtr      = groupingBlock;
	if (groupingBlockTypePtr)  *groupingBlockTypePtr  = groupingBlockType;
	if (sortingBlockPtr)       *sortingBlockPtr       = sortingBlock;
	if (sortingBlockTypePtr)   *sortingBlockTypePtr   = sortingBlockType;
	if (filteringBlockPtr)     *filteringBlockPtr     = filteringBlock;
	if (filteringBlockTypePtr) *filteringBlockTypePtr = filteringBlockType;
}

/**
 * Overrides method in YapDatabaseView
**/
- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
       groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
            sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
        sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
{
	[self getGroupingBlock:groupingBlockPtr
	     groupingBlockType:groupingBlockTypePtr
	          sortingBlock:sortingBlockPtr
	      sortingBlockType:sortingBlockTypePtr
	        filteringBlock:NULL
	    filteringBlockType:NULL];
}

- (void)getFilteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
       filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr
{
	[self getGroupingBlock:NULL
	     groupingBlockType:NULL
	          sortingBlock:NULL
	      sortingBlockType:NULL
	        filteringBlock:filteringBlockPtr
	    filteringBlockType:filteringBlockTypePtr];
}

@end
