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
{
	sqlite3_stmt *snippetTable_getForRowidStatement;
	sqlite3_stmt *snippetTable_setForRowidStatement;
	sqlite3_stmt *snippetTable_removeForRowidStatement;
	sqlite3_stmt *snippetTable_removeAllStatement;
}

- (void)_flushStatements
{
	[super _flushStatements];
	
	sqlite_finalize_null(&snippetTable_getForRowidStatement);
	sqlite_finalize_null(&snippetTable_setForRowidStatement);
	sqlite_finalize_null(&snippetTable_removeForRowidStatement);
	sqlite_finalize_null(&snippetTable_removeAllStatement);
}

- (YapDatabaseSearchResultsView *)searchResultsView
{
	return (YapDatabaseSearchResultsView *)view;
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
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithViewConnection:self
	                                                      databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseSearchResultsViewTransaction *transaction =
	  [[YapDatabaseSearchResultsViewTransaction alloc] initWithViewConnection:self
	                                                      databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
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
	[super postRollbackCleanup];
	
	query = nil;
	queryChanged = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	[super postCommitCleanup];
	
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
#pragma mark Statements - SnippetTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)snippetTable_getForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_getForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"snippet\" FROM \"%@\" WHERE \"rowid\" = ?;",
		  [(YapDatabaseSearchResultsView *)view snippetTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_setForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_setForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\" (\"rowid\", \"snippet\") VALUES (?, ?);",
		  [(YapDatabaseSearchResultsView *)view snippetTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_removeForRowidStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_removeForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ? ;", [(YapDatabaseSearchResultsView *)view snippetTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_removeAllStatement
{
	NSAssert([self isPersistentView], @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [(YapDatabaseSearchResultsView *)view snippetTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
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

- (void)setQuery:(NSString *)newQuery isChange:(BOOL)isChange
{
	NSAssert(dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey), @"Expected to be on connectionQueue");
	
	query = [newQuery copy];
	queryChanged = queryChanged || isChange;
}

- (void)getQuery:(NSString **)queryPtr wasChanged:(BOOL *)wasChangedPtr
{
	NSAssert(dispatch_get_specific(databaseConnection->IsOnConnectionQueueKey), @"Expected to be on connectionQueue");
	
	if (queryPtr) *queryPtr = query;
	if (wasChangedPtr) *wasChangedPtr = queryChanged;
}

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

@end
