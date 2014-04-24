#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
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
//	sqlite3_stmt *mapTable_getPageKeyForRowidStatement;
//	sqlite3_stmt *mapTable_setPageKeyForRowidStatement;
//	sqlite3_stmt *mapTable_removeForRowidStatement;
	sqlite3_stmt *snippetTable_removeAllStatement;
}

- (void)_flushStatements
{
	[super _flushStatements];
	
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
#pragma mark Statements - SnippetTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)snippetTable_removeAllStatement
{
	NSAssert(view->options.isPersistent, @"In-memory view accessing sqlite");
	
	if (snippetTable_removeAllStatement == NULL)
	{
		__unsafe_unretained YapDatabaseSearchResultsView *searchResultsView = (YapDatabaseSearchResultsView *)view;
		
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\";", [searchResultsView snippetTableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &snippetTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return snippetTable_removeAllStatement;
}

@end
