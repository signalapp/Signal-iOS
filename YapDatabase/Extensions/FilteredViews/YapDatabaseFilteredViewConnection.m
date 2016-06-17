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
 * So we declare it here, as opposed to within YapDatabaseFilteredViewPrivate.
**/
- (void)getFiltering:(YapDatabaseViewFiltering **)filteringPtr;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseFilteredViewConnection

#pragma mark Accessors

- (YapDatabaseFilteredView *)filteredView
{
	return (YapDatabaseFilteredView *)parent;
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
	
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithParentConnection:self
	                                                   databaseTransaction:databaseTransaction];
	
	return filteredViewTransaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseFilteredViewTransaction *filteredViewTransaction =
	  [[YapDatabaseFilteredViewTransaction alloc] initWithParentConnection:self
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

- (void)getFiltering:(YapDatabaseViewFiltering **)filteringPtr
{
	if (!filtering)
	{
		// Fetch & Cache
		
		__unsafe_unretained YapDatabaseFilteredView *filteredView = (YapDatabaseFilteredView *)parent;
		
		YapDatabaseViewFiltering * mostRecentFiltering = nil;
		[filteredView getFiltering:&mostRecentFiltering];
		
		filtering = mostRecentFiltering;
	}
	
	if (filteringPtr) *filteringPtr = filtering;
}

- (void)setFiltering:(YapDatabaseViewFiltering *)newFiltering
			 versionTag:(NSString *)newVersionTag
{
	filtering = newFiltering;
	filteringChanged = YES;
	
	versionTag = newVersionTag;
	versionTagChanged = YES;
}

@end
