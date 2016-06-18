#import "YapDatabaseAutoViewConnection.h"

#import "YapDatabaseAutoViewPrivate.h"
#import "YapDatabaseViewPrivate.h"
#import "YapDatabasePrivate.h"

#import "YapCollectionKey.h"
#import "YapCache.h"
#import "YapDatabaseString.h"
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


@interface YapDatabaseAutoView ()

/**
 * This method is designed exclusively for YapDatabaseViewConnection.
 * All subclasses and transactions are required to use our version of the same method.
 *
 * So we declare it here, as opposed to within YapDatabaseViewPrivate.
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseAutoViewConnection

#pragma mark Properties

- (YapDatabaseAutoView *)autoView
{
	return (YapDatabaseAutoView *)parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseAutoViewTransaction *transaction =
	  [[YapDatabaseAutoViewTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseAutoViewTransaction *transaction =
	  [[YapDatabaseAutoViewTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	[super postCommitCleanup];
	
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	grouping = nil;
	sorting = nil;
	
	groupingChanged = NO;
	sortingChanged = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	[super postRollbackCleanup];
	
	// Don't keep cached configuration in memory.
	// These are loaded on-demand within readwrite transactions.
	
	grouping = nil;
	sorting = nil;
	
	groupingChanged = NO;
	sortingChanged = NO;
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
	
	if (groupingChanged || sortingChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if (groupingChanged) {
			internalChangeset[changeset_key_grouping] = grouping;
		}
		if (sortingChanged) {
			internalChangeset[changeset_key_sorting] = sorting;
		}
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setGrouping:(YapDatabaseViewGrouping *)newGrouping
            sorting:(YapDatabaseViewSorting *)newSorting
         versionTag:(NSString *)newVersionTag
{
	grouping = newGrouping;
	groupingChanged = YES;
	
	sorting = newSorting;
	sortingChanged = YES;
	
	versionTag = newVersionTag;
	versionTagChanged = YES;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
{
	if (!grouping || !sorting)
	{
		// Fetch & Cache
		
		__unsafe_unretained YapDatabaseAutoView *view = (YapDatabaseAutoView *)parent;
		
		YapDatabaseViewGrouping *mostRecentGrouping = nil;
		YapDatabaseViewSorting  *mostRecentSorting  = nil;
		
		BOOL needsGrouping = (grouping == nil);
		BOOL needsSorting = (sorting == nil);
		
		[view getGrouping:(needsGrouping ? &mostRecentGrouping : NULL)
		          sorting:(needsSorting  ? &mostRecentSorting  : NULL)];
		
		if (needsGrouping) {
			grouping = mostRecentGrouping;
		}
		if (needsSorting) {
			sorting = mostRecentSorting;
		}
	}
	
	if (groupingPtr) *groupingPtr = grouping;
	if (sortingPtr)  *sortingPtr  = sorting;
}

- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
{
	[self getGrouping:groupingPtr
	          sorting:NULL];
}

- (void)getSorting:(YapDatabaseViewSorting **)sortingPtr
{
	[self getGrouping:NULL
	          sorting:sortingPtr];
}

@end
