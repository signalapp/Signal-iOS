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
	sqlite3_stmt *findManualEdgeStatement;
	sqlite3_stmt *insertEdgeStatement;
	sqlite3_stmt *updateEdgeStatement;
	sqlite3_stmt *deleteEdgeStatement;
	sqlite3_stmt *deleteEdgesWithNodeStatement;
	sqlite3_stmt *enumerateAllDstFilePathStatement;
	sqlite3_stmt *enumerateForSrcStatement;
	sqlite3_stmt *enumerateForDstStatement;
	sqlite3_stmt *enumerateForSrcNameStatement;
	sqlite3_stmt *enumerateForDstNameStatement;
	sqlite3_stmt *enumerateForNameStatement;
	sqlite3_stmt *enumerateForSrcDstStatement;
	sqlite3_stmt *enumerateForSrcDstNameStatement;
	sqlite3_stmt *countForSrcNameExcludingDstStatement;
	sqlite3_stmt *countForDstNameExcludingSrcStatement;
	sqlite3_stmt *countForNameStatement;
	sqlite3_stmt *countForSrcStatement;
	sqlite3_stmt *countForSrcNameStatement;
	sqlite3_stmt *countForDstStatement;
	sqlite3_stmt *countForDstNameStatement;
	sqlite3_stmt *countForSrcDstStatement;
	sqlite3_stmt *countForSrcDstNameStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *removeAllProtocolStatement;
}

@synthesize relationship = relationship;

- (id)initWithRelationship:(YapDatabaseRelationship *)inRelationship databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		relationship = inRelationship;
		databaseConnection = inDbC;
	}
	return self;
}

- (void)dealloc
{
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&findManualEdgeStatement);
	sqlite_finalize_null(&insertEdgeStatement);
	sqlite_finalize_null(&updateEdgeStatement);
	sqlite_finalize_null(&deleteEdgeStatement);
	sqlite_finalize_null(&deleteEdgesWithNodeStatement);
	sqlite_finalize_null(&enumerateAllDstFilePathStatement);
	sqlite_finalize_null(&enumerateForSrcStatement);
	sqlite_finalize_null(&enumerateForDstStatement);
	sqlite_finalize_null(&enumerateForSrcNameStatement);
	sqlite_finalize_null(&enumerateForDstNameStatement);
	sqlite_finalize_null(&enumerateForNameStatement);
	sqlite_finalize_null(&enumerateForSrcDstStatement);
	sqlite_finalize_null(&enumerateForSrcDstNameStatement);
	sqlite_finalize_null(&countForSrcNameExcludingDstStatement);
	sqlite_finalize_null(&countForDstNameExcludingSrcStatement);
	sqlite_finalize_null(&countForNameStatement);
	sqlite_finalize_null(&countForSrcStatement);
	sqlite_finalize_null(&countForSrcNameStatement);
	sqlite_finalize_null(&countForDstStatement);
	sqlite_finalize_null(&countForDstNameStatement);
	sqlite_finalize_null(&countForSrcDstStatement);
	sqlite_finalize_null(&countForSrcDstNameStatement);
	sqlite_finalize_null(&removeAllStatement);
	sqlite_finalize_null(&removeAllProtocolStatement);
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
	if (protocolChanges == nil)
		protocolChanges = [[NSMutableDictionary alloc] init];
	if (manualChanges == nil)
		manualChanges = [[NSMutableDictionary alloc] init];
	if (inserted == nil)
		inserted = [[NSMutableSet alloc] init];
	if (deletedOrder == nil)
		deletedOrder = [[NSMutableArray alloc] init];
	if (deletedInfo == nil)
		deletedInfo = [[NSMutableDictionary alloc] init];
	if (filesToDelete == nil)
		filesToDelete = [[NSMutableSet alloc] init];
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	[protocolChanges removeAllObjects];
	[manualChanges removeAllObjects];
	[inserted removeAllObjects];
	[deletedOrder removeAllObjects];
	[deletedInfo removeAllObjects];
	
	// By nil'ing this out (instead of removing all objects)
	// we can avoid a copy of this object.
	if ([filesToDelete count] > 0)
		filesToDelete = nil;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[protocolChanges removeAllObjects];
	[manualChanges removeAllObjects];
	[inserted removeAllObjects];
	[deletedOrder removeAllObjects];
	[deletedInfo removeAllObjects];
	[filesToDelete removeAllObjects];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	// In the future we may want to store a changeset that specifies which edges were added & removed.
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	// Nothing to do here.
	// This method is required to be overriden by YapDatabaseExtensionConnection.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)findManualEdgeStatement
{
	if (findManualEdgeStatement == NULL)
	{
		NSString *tableName = [relationship tableName];
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"rules\" FROM \"%@\" "
		  @" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ? AND \"manual\" = 1 LIMIT 1;",
		  tableName];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &findManualEdgeStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return findManualEdgeStatement;
}

- (sqlite3_stmt *)insertEdgeStatement
{
	if (insertEdgeStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\" (\"name\", \"src\", \"dst\", \"rules\", \"manual\") VALUES (?, ?, ?, ?, ?);",
		  [relationship tableName]];
		
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

- (sqlite3_stmt *)enumerateAllDstFilePathStatement
{
	if (enumerateAllDstFilePathStatement == NULL)
	{
		// The 'dst' column stores both integers and text.
		// If the edge has a destination key & column, then the 'dst' affinity of row is integer (rowid of dst).
		// If the edge has a destinationFilePath, the the 'dst' affinity of row is text.
		//
		// We've set the affinity of the 'dst' column to be none.
		// Which means that we can easily find all 'dst' rows with text affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because TEXT is always greater than INTEGER
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"dst\" FROM \"%@\" WHERE \"dst\" > ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &enumerateAllDstFilePathStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	if (enumerateAllDstFilePathStatement)
	{
		// We do this outside of the if statement above
		// just in case we accidentally call sqlite3_clear_bindings.
		
		sqlite3_bind_int64(enumerateAllDstFilePathStatement, 1, INT64_MAX);
	}
	
	return enumerateAllDstFilePathStatement;
}

- (sqlite3_stmt *)enumerateForSrcStatement
{
	if (enumerateForSrcStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ?;",
		  [relationship tableName]];
		
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
		  @"SELECT \"rowid\", \"name\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ?;",
		  [relationship tableName]];
		
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
		  @"SELECT \"rowid\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
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
		  @"SELECT \"rowid\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
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
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"name\" = ?;",
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
		  @"SELECT \"rowid\", \"name\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
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
		  @"SELECT \"rowid\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
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

- (sqlite3_stmt *)countForNameStatement
{
	if (countForNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForNameStatement;
}

- (sqlite3_stmt *)countForSrcStatement
{
	if (countForSrcStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForSrcStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForSrcStatement;
}

- (sqlite3_stmt *)countForSrcNameStatement
{
	if (countForSrcNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForSrcNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForSrcNameStatement;
}

- (sqlite3_stmt *)countForDstStatement
{
	if (countForDstStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForDstStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForDstStatement;
}

- (sqlite3_stmt *)countForDstNameStatement
{
	if (countForDstNameStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
		  [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &countForDstNameStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return countForDstNameStatement;
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

- (sqlite3_stmt *)removeAllProtocolStatement
{
	if (removeAllProtocolStatement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"manual\" = 0;", [relationship tableName]];
		
		sqlite3 *db = databaseConnection->db;
		YapDatabaseString stmt; MakeYapDatabaseString(&stmt, string);
		
		int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, &removeAllProtocolStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		FreeYapDatabaseString(&stmt);
	}
	
	return removeAllProtocolStatement;
}

@end
