#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewPrivate.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapCache.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseViewConnection
{
	sqlite3_stmt *keyTable_getPageKeyForKeyStatement;
	sqlite3_stmt *keyTable_setPageKeyForKeyStatement;
	sqlite3_stmt *keyTable_removeForKeyStatement;
	sqlite3_stmt *keyTable_removeAllStatement;
	
	sqlite3_stmt *pageTable_getDataForPageKeyStatement;
	sqlite3_stmt *pageTable_setAllForPageKeyStatement;
	sqlite3_stmt *pageTable_setMetadataForPageKeyStatement;
	sqlite3_stmt *pageTable_removeForPageKeyStatement;
	sqlite3_stmt *pageTable_removeAllStatement;
}

- (id)initWithView:(YapAbstractDatabaseView *)view databaseConnection:(YapAbstractDatabaseConnection *)connection
{
	if ((self = [super initWithView:view databaseConnection:connection]))
	{
		keyCache = [[YapCache alloc] init];
		pageCache = [[YapCache alloc] init];
	}
	return self;
}

/**
 * Required override method from YapAbstractDatabaseViewConnection.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapDatabaseViewTransaction alloc] initWithViewConnection:self
	                                              databaseTransaction:databaseTransaction];
}

- (BOOL)isOpen
{
	return (groupPagesDict != nil);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)keyTableName
{
	return [(YapDatabaseView *)abstractView keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapDatabaseView *)abstractView pageTableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)keyTable_getPageKeyForKeyStatement
{
	if (keyTable_getPageKeyForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"key\" = ? ;", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_getPageKeyForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_getPageKeyForKeyStatement;
}

- (sqlite3_stmt *)keyTable_setPageKeyForKeyStatement
{
	if (keyTable_setPageKeyForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"key\", \"pageKey\") VALUES (?, ?);", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_setPageKeyForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_setPageKeyForKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeForKeyStatement
{
	if (keyTable_removeForKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"key\" = ?;", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeAllStatement
{
	if (keyTable_removeAllStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [self keyTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeAllStatement;
}

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement
{
	if (pageTable_getDataForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"data\" FROM \"%@\" WHERE \"pageKey\" = ? ;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_getDataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setAllForPageKeyStatement
{
	if (pageTable_setAllForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"pageKey\", \"data\", \"metadata\") VALUES (?, ?, ?);",
		    [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_setAllForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setAllForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_setMetadataForPageKeyStatement
{
	if (pageTable_setMetadataForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"UPDATE \"%@\" SET \"metadata\" = ? WHERE \"pageKey\" = ?;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_getDataForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_setMetadataForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeForPageKeyStatement
{
	if (pageTable_removeForPageKeyStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"pageKey\" = ?;", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeForPageKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}

	}
	
	return pageTable_removeForPageKeyStatement;
}

- (sqlite3_stmt *)pageTable_removeAllStatement
{
	if (pageTable_removeAllStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [self pageTableName]];
		
		sqlite3 *db = databaseConnection->db;
		
		int status = sqlite3_prepare_v2(db, [string UTF8String], -1, &pageTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return pageTable_removeAllStatement;
}

@end
