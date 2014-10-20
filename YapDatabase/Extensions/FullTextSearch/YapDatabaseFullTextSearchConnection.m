#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

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



@implementation YapDatabaseFullTextSearchConnection {
@private
	
	sqlite3_stmt *insertRowidStatement;
	sqlite3_stmt *setRowidStatement;
	sqlite3_stmt *removeRowidStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *queryStatement;
	sqlite3_stmt *querySnippetStatement;
	sqlite3_stmt *rowidQueryStatement;
	sqlite3_stmt *rowidQuerySnippetStatement;
}

@synthesize fullTextSearch = fts;

- (id)initWithFTS:(YapDatabaseFullTextSearch *)inFTS
   databaseConnection:(YapDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super init]))
	{
		fts = inFTS;
		databaseConnection = inDatabaseConnection;
	}
	return self;
}

- (void)dealloc
{
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&insertRowidStatement);
	sqlite_finalize_null(&setRowidStatement);
	sqlite_finalize_null(&removeRowidStatement);
	sqlite_finalize_null(&removeAllStatement);
	sqlite_finalize_null(&queryStatement);
	sqlite_finalize_null(&querySnippetStatement);
	sqlite_finalize_null(&rowidQueryStatement);
	sqlite_finalize_null(&rowidQuerySnippetStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Statements)
	{
		[self _flushStatements];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (YapDatabaseExtension *)extension
{
	return fts;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseFullTextSearchTransaction *transaction =
	  [[YapDatabaseFullTextSearchTransaction alloc] initWithFTSConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseFullTextSearchTransaction *transaction =
	  [[YapDatabaseFullTextSearchTransaction alloc] initWithFTSConnection:self
	                                                  databaseTransaction:databaseTransaction];
	
	if (blockDict == nil)
		blockDict = [NSMutableDictionary dictionaryWithSharedKeySet:fts->columnNamesSharedKeySet];
	
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension rows a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension rows a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)insertRowidStatement
{
	sqlite3_stmt **statement = &insertRowidStatement;
	if (*statement == NULL)
	{
		NSMutableString *string = [NSMutableString stringWithCapacity:100];
		[string appendFormat:@"INSERT INTO \"%@\" (\"rowid\"", [fts tableName]];
		
		for (NSString *columnName in fts->columnNames)
		{
			[string appendFormat:@", \"%@\"", columnName];
		}
		
		[string appendString:@") VALUES (?"];
		
		NSUInteger count = [fts->columnNames count];
		NSUInteger i;
		for (i = 0; i < count; i++)
		{
			[string appendString:@", ?"];
		}
		
		[string appendString:@");"];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)setRowidStatement
{
	sqlite3_stmt **statement = &setRowidStatement;
	if (*statement == NULL)
	{
		NSMutableString *string = [NSMutableString stringWithCapacity:100];
		[string appendFormat:@"INSERT OR REPLACE INTO \"%@\" (\"rowid\"", [fts tableName]];
		
		for (NSString *columnName in fts->columnNames)
		{
			[string appendFormat:@", \"%@\"", columnName];
		}
		
		[string appendString:@") VALUES (?"];
		
		NSUInteger count = [fts->columnNames count];
		NSUInteger i;
		for (i = 0; i < count; i++)
		{
			[string appendString:@", ?"];
		}
		
		[string appendString:@");"];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeRowidStatement
{
	sqlite3_stmt **statement = &removeRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeAllStatement
{
	sqlite3_stmt **statement = &removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\";", [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)queryStatement
{
	sqlite3_stmt **statement = &queryStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\" FROM \"%1$@\" WHERE \"%1$@\" MATCH ?;", [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)querySnippetStatement
{
	sqlite3_stmt **statement = &querySnippetStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", snippet(\"%1$@\", ?, ?, ?, ?, ?) FROM \"%1$@\" WHERE \"%1$@\" MATCH ?;",
		  [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)rowidQueryStatement
{
	sqlite3_stmt **statement = &rowidQueryStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\" FROM \"%1$@\" WHERE \"rowid\" = ? AND \"%1$@\" MATCH ?;", [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

- (sqlite3_stmt *)rowidQuerySnippetStatement
{
	sqlite3_stmt **statement = &rowidQuerySnippetStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", snippet(\"%1$@\", ?, ?, ?, ?, ?) FROM \"%1$@\" WHERE \"rowid\" = ? AND \"%1$@\" MATCH ?;",
		  [fts tableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return *statement;
}

@end
