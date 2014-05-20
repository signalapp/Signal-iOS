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

static NSString *const key_query = @"query";


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
#pragma mark Query
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
	
	[keys addObject:key_query];
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
		
		[internalChangeset setObject:query forKey:key_query];
		hasDiskChanges = YES;
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	[super processChangeset:changeset];
	
	NSString *changeset_query = [changeset objectForKey:key_query];
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
	NSAssert(view->options.isPersistent, @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_getForRowidStatement;
	if (*statement == NULL)
	{
		NSString *snippetTableName = [(YapDatabaseSearchResultsView *)view snippetTableName];
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"snippet\" FROM \"%@\" WHERE \"rowid\" = ?;", snippetTableName];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_setForRowidStatement
{
	NSAssert(view->options.isPersistent, @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_setForRowidStatement;
	if (*statement == NULL)
	{
		NSString *snippetTableName = [(YapDatabaseSearchResultsView *)view snippetTableName];
		
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\" (\"rowid\", \"snippet\") VALUES (?, ?);", snippetTableName];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_removeForRowidStatement
{
	NSAssert(view->options.isPersistent, @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_removeForRowidStatement;
	if (*statement == NULL)
	{
		NSString *snippetTableName = [(YapDatabaseSearchResultsView *)view snippetTableName];
		
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"rowid\" = ? ;", snippetTableName];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return *statement;
}

- (sqlite3_stmt *)snippetTable_removeAllStatement
{
	NSAssert(view->options.isPersistent, @"In-memory view accessing sqlite");
	
	sqlite3_stmt **statement = &snippetTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *snippetTableName = [(YapDatabaseSearchResultsView *)view snippetTableName];
		
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\";", snippetTableName];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return *statement;
}

@end
