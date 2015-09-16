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
#pragma unused(ydbLogLevel)

@interface YapDatabaseFilteredView ()

/**
 * This method is designed exclusively for YapDatabaseFilteredViewConnection.
 * All subclasses and transactions are required to use our version of the same method.
 *
 * So we declare it here, as opposed to within YapDatabaseViewPrivate.
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
          filtering:(YapDatabaseViewFiltering **)filteringPtr;

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
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	filtering = nil;
	filteringChanged = NO;
	
	[super postRollbackCleanup];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	filtering = nil;
	filteringChanged = NO;
	
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
	
	if (filteringChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		internalChangeset[changeset_key_filtering] = filtering;
		
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
- (void)setGrouping:(YapDatabaseViewGrouping *)newGrouping
            sorting:(YapDatabaseViewSorting *)newSorting
{
	grouping = newGrouping;
	groupingChanged = YES;
	
	sorting = newSorting;
	sortingChanged = YES;
}

- (void)setFiltering:(YapDatabaseViewFiltering *)newFiltering
          versionTag:(NSString *)newVersionTag
{
	filtering = newFiltering;
	filteringChanged = YES;
	
	versionTag = newVersionTag;
	versionTagChanged = YES;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
          filtering:(YapDatabaseViewFiltering **)filteringPtr
{
	if (!grouping || !sorting || !filtering)
	{
		// Fetch & Cache
		
		__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)view;
		
		YapDatabaseViewGrouping  * mostRecentGrouping  = nil;
		YapDatabaseViewSorting   * mostRecentSorting   = nil;
		YapDatabaseViewFiltering * mostRecentFiltering = nil;
		
		BOOL needsGrouping  = (grouping == nil);
		BOOL needsSorting   = (sorting == nil);
		BOOL needsFiltering = (filtering == nil);
		
		[filteredView getGrouping:(needsGrouping  ? &mostRecentGrouping  : NULL)
		                  sorting:(needsSorting   ? &mostRecentSorting   : NULL)
		                filtering:(needsFiltering ? &mostRecentFiltering : NULL)];
		
		if (needsGrouping) {
			grouping = mostRecentGrouping;
		}
		if (needsSorting) {
			sorting = mostRecentSorting;
		}
		if (needsFiltering) {
			filtering = mostRecentFiltering;
		}
	}
	
	if (groupingPtr)  *groupingPtr  = grouping;
	if (sortingPtr)   *sortingPtr   = sorting;
	if (filteringPtr) *filteringPtr = filtering;
}

/**
 * Overrides method in YapDatabaseView
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sortingBlock:(YapDatabaseViewSorting **)sortingPtr
{
	[self getGrouping:groupingPtr
	          sorting:sortingPtr
	        filtering:NULL];
}

- (void)getFiltering:(YapDatabaseViewFiltering **)filteringPtr
{
	[self getGrouping:NULL
	          sorting:NULL
	        filtering:filteringPtr];
}

@end
