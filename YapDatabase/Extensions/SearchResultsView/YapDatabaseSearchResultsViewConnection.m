#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
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


@implementation YapDatabaseSearchResultsViewConnection

- (YapDatabaseSearchResultsView *)searchResultsView
{
	return (YapDatabaseSearchResultsView *)parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsViewTransaction *transaction =
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithParentConnection:self
	                                                        databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsViewTransaction *transaction =
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithParentConnection:self
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
	
	queryChanged = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	[super postRollbackCleanup];
	
	query = nil;
	queryChanged = NO;
}

- (NSArray *)internalChangesetKeys
{
	NSMutableArray *keys = [[super internalChangesetKeys] mutableCopy];
	
	[keys addObject:changeset_key_query];
	return keys;
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	[super getInternalChangeset:&internalChangeset
	          externalChangeset:&externalChangeset
	             hasDiskChanges:&hasDiskChanges];
	
	if (queryChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		internalChangeset[changeset_key_query] = query;
		
		hasDiskChanges = hasDiskChanges || [self isPersistentView];
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	[super processChangeset:changeset];
	
	NSString *changeset_query = changeset[changeset_key_query];
	if (changeset_query)
	{
		query = [changeset_query copy];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)query
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		
		result = query;
	};
	
	if (dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(databaseConnection->connectionQueue, block);
	
	return result;
}

- (void)getQuery:(NSString **)queryPtr wasChanged:(BOOL *)wasChangedPtr
{
	NSAssert(dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey), @"Expected to be on connectionQueue");
	
	if (queryPtr) *queryPtr = query;
	if (wasChangedPtr) *wasChangedPtr = queryChanged;
}

- (void)setQuery:(NSString *)newQuery isChange:(BOOL)isChange
{
	NSAssert(dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey), @"Expected to be on connectionQueue");
	
	query = [newQuery copy];
	queryChanged = queryChanged || isChange;
}

@end
