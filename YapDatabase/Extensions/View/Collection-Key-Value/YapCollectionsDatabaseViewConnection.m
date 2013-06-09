#import "YapCollectionsDatabaseViewConnection.h"
#import "YapCollectionsDatabaseViewPrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
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
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapCollectionsDatabaseViewConnection
{
	sqlite3_stmt *keyTable_getPageKeyForCollectionKeyStatement;
	sqlite3_stmt *keyTable_setPageKeyForCollectionKeyStatement;
	sqlite3_stmt *keyTable_enumerateForCollectionStatement;
	sqlite3_stmt *keyTable_removeForCollectionKeyStatement;
	sqlite3_stmt *keyTable_removeForCollectionStatement;
	sqlite3_stmt *keyTable_removeAllStatement;
	
	sqlite3_stmt *pageTable_getDataForPageKeyStatement;
	sqlite3_stmt *pageTable_setAllForPageKeyStatement;
	sqlite3_stmt *pageTable_setMetadataForPageKeyStatement;
	sqlite3_stmt *pageTable_removeForPageKeyStatement;
	sqlite3_stmt *pageTable_removeAllStatement;
}

- (id)initWithExtension:(YapAbstractDatabaseExtension *)inExtension
     databaseConnection:(YapAbstractDatabaseConnection *)inDatabaseConnection
{
	if ((self = [super initWithExtension:inExtension databaseConnection:inDatabaseConnection]))
	{
		keyCache = [[YapCache alloc] init];
		pageCache = [[YapCache alloc] init];
	}
	return self;
}

- (YapCollectionsDatabaseView *)view
{
	return (YapCollectionsDatabaseView *)extension;
}

/**
 * Required override method from YapAbstractDatabaseExtensionConnection.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapCollectionsDatabaseViewTransaction alloc] initWithExtensionConnection:self
	                                                              databaseTransaction:databaseTransaction];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)keyTableName
{
	return [(YapCollectionsDatabaseView *)extension keyTableName];
}

- (NSString *)pageTableName
{
	return [(YapCollectionsDatabaseView *)extension pageTableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	group_pagesMetadata_dict = nil;
	pageKey_group_dict = nil;
	
	[keyCache removeAllObjects];
	[pageCache removeAllObjects];
	
	[dirtyKeys removeAllObjects];
	[dirtyPages removeAllObjects];
	[dirtyMetadata removeAllObjects];
	reset = NO;
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
{
	YDBLogAutoTrace();
	
	// Todo...
	NSAssert(NO, @"Not implemented...");
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	// Todo...
	NSAssert(NO, @"Not implemented...");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - KeyTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)keyTable_getPageKeyForCollectionKeyStatement
{
	if (keyTable_getPageKeyForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"pageKey\" FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ? ;", [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_getPageKeyForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_getPageKeyForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_setPageKeyForCollectionKeyStatement
{
	if (keyTable_setPageKeyForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"INSERT OR REPLACE INTO \"%@\" (\"collection\", \"key\", \"pageKey\") VALUES (?, ?, ?);",
		    [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_setPageKeyForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_setPageKeyForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_enumerateForCollectionStatement
{
	if (keyTable_enumerateForCollectionStatement)
	{
		NSString *string = [NSString stringWithFormat:
		    @"SELECT \"key\", \"pageKey\" FROM \"%@\" WHERE \"collection\" = ?;", [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_enumerateForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_enumerateForCollectionStatement;
}

- (sqlite3_stmt *)keyTable_removeForCollectionKeyStatement
{
	if (keyTable_removeForCollectionKeyStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ? AND \"key\" = ?;", [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForCollectionKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForCollectionKeyStatement;
}

- (sqlite3_stmt *)keyTable_removeForCollectionStatement
{
	if (keyTable_removeForCollectionStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\" WHERE \"collection\" = ?;", [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeForCollectionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeForCollectionStatement;
}

- (sqlite3_stmt *)keyTable_removeAllStatement
{
	if (keyTable_removeAllStatement == nil)
	{
		NSString *string = [NSString stringWithFormat:
		    @"DELETE FROM \"%@\";", [self keyTableName]];
		
		int status;
		sqlite3 *db = databaseConnection->db;
		
		status = sqlite3_prepare_v2(db, [string UTF8String], -1, &keyTable_removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
	}
	
	return keyTable_removeAllStatement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - PageTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)pageTable_getDataForPageKeyStatement
{
	if (pageTable_getDataForPageKeyStatement == NULL)
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
	if (pageTable_setAllForPageKeyStatement == NULL)
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
	if (pageTable_setMetadataForPageKeyStatement == NULL)
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
	if (pageTable_removeForPageKeyStatement == NULL)
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
	if (pageTable_removeAllStatement == NULL)
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
