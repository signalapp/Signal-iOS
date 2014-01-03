#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapCollectionKey.h"
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


@implementation YapDatabaseRelationshipConnection
{
	sqlite3_stmt *insertEdgeStatement;
	sqlite3_stmt *updateEdgeStatement;
	sqlite3_stmt *deleteEdgeStatement;
	sqlite3_stmt *deleteEdgesWithNodeStatement;
	sqlite3_stmt *enumerateForSrcStatement;
	sqlite3_stmt *enumerateForDstStatement;
	sqlite3_stmt *enumerateForSrcNameStatement;
	sqlite3_stmt *enumerateForDstNameStatement;
	sqlite3_stmt *enumerateForNameStatement;
	sqlite3_stmt *enumerateForSrcDstStatement;
	sqlite3_stmt *enumerateForSrcDstNameStatement;
	sqlite3_stmt *countForSrcDstStatement;
	sqlite3_stmt *countForSrcDstNameStatement;
	sqlite3_stmt *countForSrcNameExcludingDstStatement;
	sqlite3_stmt *countForDstNameExcludingSrcStatement;
	sqlite3_stmt *removeAllStatement;
}

@synthesize relationship = relationship;

- (id)initWithRelationship:(YapDatabaseRelationship *)inRelationship databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		relationship = inRelationship;
		databaseConnection = inDbC;
		
		srcCache = [[YapCache alloc] initWithKeyClass:[NSNumber class]];
		dstCache = [[YapCache alloc] initWithKeyClass:[NSNumber class]];
	}
	return self;
}

- (void)dealloc
{
	sqlite_finalize_null(&insertEdgeStatement);
	sqlite_finalize_null(&updateEdgeStatement);
	sqlite_finalize_null(&deleteEdgeStatement);
	sqlite_finalize_null(&deleteEdgesWithNodeStatement);
	sqlite_finalize_null(&enumerateForSrcStatement);
	sqlite_finalize_null(&enumerateForDstStatement);
	sqlite_finalize_null(&enumerateForSrcNameStatement);
	sqlite_finalize_null(&enumerateForDstNameStatement);
	sqlite_finalize_null(&enumerateForNameStatement);
	sqlite_finalize_null(&enumerateForSrcDstStatement);
	sqlite_finalize_null(&enumerateForSrcDstNameStatement);
	sqlite_finalize_null(&countForSrcDstStatement);
	sqlite_finalize_null(&countForSrcDstNameStatement);
	sqlite_finalize_null(&countForSrcNameExcludingDstStatement);
	sqlite_finalize_null(&countForDstNameExcludingSrcStatement);
	sqlite_finalize_null(&removeAllStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithLevel:(int)level
{
	if (level >= YapDatabaseConnectionFlushMemoryLevelMild)
	{
		[srcCache removeAllObjects];
		[dstCache removeAllObjects];
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&insertEdgeStatement);
		sqlite_finalize_null(&updateEdgeStatement);
		sqlite_finalize_null(&deleteEdgeStatement);
		sqlite_finalize_null(&deleteEdgesWithNodeStatement);
	//	sqlite_finalize_null(&enumerateForSrcStatement);
		sqlite_finalize_null(&enumerateForDstStatement);
		sqlite_finalize_null(&enumerateForSrcNameStatement);
		sqlite_finalize_null(&enumerateForDstNameStatement);
		sqlite_finalize_null(&enumerateForNameStatement);
		sqlite_finalize_null(&enumerateForSrcDstStatement);
		sqlite_finalize_null(&enumerateForSrcDstNameStatement);
		sqlite_finalize_null(&countForSrcDstStatement);
		sqlite_finalize_null(&countForSrcDstNameStatement);
		sqlite_finalize_null(&countForSrcNameExcludingDstStatement);
		sqlite_finalize_null(&countForDstNameExcludingSrcStatement);
		sqlite_finalize_null(&removeAllStatement);
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
		sqlite_finalize_null(&enumerateForSrcStatement);
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
	return relationship;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseRelationshipTransaction *transaction =
	    [[YapDatabaseRelationshipTransaction alloc] initWithRelationshipConnection:self
	                                                           databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseRelationshipTransaction *transaction =
	    [[YapDatabaseRelationshipTransaction alloc] initWithRelationshipConnection:self
	                                                           databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	if (changes == nil)
		changes = [[NSMutableDictionary alloc] init];
	if (inserted == nil)
		inserted = [[NSMutableSet alloc] init];
	if (deletedOrder == nil)
		deletedOrder = [[NSMutableArray alloc] init];
	if (deletedInfo == nil)
		deletedInfo = [[NSMutableDictionary alloc] init];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[srcCache removeAllObjects];
	[dstCache removeAllObjects];
	
	[changes removeAllObjects];
	[inserted removeAllObjects];
	[deletedOrder removeAllObjects];
	[deletedInfo removeAllObjects];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	[changes removeAllObjects];
	[inserted removeAllObjects];
	[deletedOrder removeAllObjects];
	[deletedInfo removeAllObjects];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	// Todo... ?
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	// Todo... ?
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)insertEdgeStatement
{
	if (insertEdgeStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\" (\"name\", \"src\", \"dst\", \"rules\") VALUES (?, ?, ?, ?);", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &insertEdgeStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return insertEdgeStatement;
}

- (sqlite3_stmt *)updateEdgeStatement
{
	if (updateEdgeStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"rules\" = ? WHERE \"rowid\" = ?;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &updateEdgeStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return updateEdgeStatement;
}

- (sqlite3_stmt *)deleteEdgeStatement
{
	if (deleteEdgeStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &deleteEdgeStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return deleteEdgeStatement;
}

- (sqlite3_stmt *)deleteEdgesWithNodeStatement
{
	if (deleteEdgesWithNodeStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"src\" = ? OR \"dst\" = ?;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &deleteEdgesWithNodeStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return deleteEdgesWithNodeStatement;
}

- (sqlite3_stmt *)enumerateForSrcStatement
{
	if (enumerateForSrcStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"dst\", \"rules\" FROM \"%@\" WHERE \"src\" = ?;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForSrcStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForSrcStatement;
}

- (sqlite3_stmt *)enumerateForDstStatement
{
	if (enumerateForDstStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"src\", \"rules\" FROM \"%@\" WHERE \"dst\" = ?;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForDstStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForDstStatement;
}

- (sqlite3_stmt *)enumerateForSrcNameStatement
{
	if (enumerateForSrcNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"dst\", \"rules\" FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForSrcNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForSrcNameStatement;
}

- (sqlite3_stmt *)enumerateForDstNameStatement
{
	if (enumerateForDstNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"rules\" FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForDstNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForDstNameStatement;
}

- (sqlite3_stmt *)enumerateForNameStatement
{
	if (enumerateForNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\" FROM \"%@\" WHERE \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForNameStatement;
}

- (sqlite3_stmt *)enumerateForSrcDstStatement
{
	if (enumerateForSrcDstStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"rules\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForSrcDstStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForSrcDstStatement;
}

- (sqlite3_stmt *)enumerateForSrcDstNameStatement
{
	if (enumerateForSrcDstNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"rules\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateForSrcDstNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return enumerateForSrcDstNameStatement;
}

- (sqlite3_stmt *)countForSrcDstStatement
{
	if (countForSrcDstStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForSrcDstStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForSrcDstStatement;
}

- (sqlite3_stmt *)countForSrcDstNameStatement
{
	if (countForSrcDstNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForSrcDstNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForSrcDstNameStatement;
}

- (sqlite3_stmt *)countForSrcNameExcludingDstStatement
{
	if (countForSrcNameExcludingDstStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" != ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForSrcNameExcludingDstStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForSrcNameExcludingDstStatement;
}

- (sqlite3_stmt *)countForDstNameExcludingSrcStatement
{
	if (countForDstNameExcludingSrcStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ? AND \"src\" != ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForDstNameExcludingSrcStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForDstNameExcludingSrcStatement;
}

- (sqlite3_stmt *)removeAllStatement
{
	if (removeAllStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\";", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &removeAllStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return removeAllStatement;
}

@end
