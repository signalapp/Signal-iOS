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
#pragma unused(ydbLogLevel)


@implementation YapDatabaseRelationshipConnection
{
	sqlite3_stmt *findManualEdgeStatement;
	sqlite3_stmt *insertEdgeStatement;
	sqlite3_stmt *updateEdgeStatement;
	sqlite3_stmt *deleteEdgeStatement;
	sqlite3_stmt *deleteEdgesWithNodeStatement;
	sqlite3_stmt *enumerateAllDstFilePathStatement;
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
	
	YapEnumerateStatementFactory *enumerateForSrcFactory;
	YapEnumerateStatementFactory *enumerateForDstFactory;
	YapEnumerateStatementFactory *enumerateForSrcNameFactory;
	YapEnumerateStatementFactory *enumerateForDstNameFactory;
	YapEnumerateStatementFactory *enumerateForNameFactory;
	YapEnumerateStatementFactory *enumerateForSrcDstFactory;
	YapEnumerateStatementFactory *enumerateForSrcDstNameFactory;
}

@synthesize relationship = parent;

- (id)initWithParent:(YapDatabaseRelationship *)inParent databaseConnection:(YapDatabaseConnection *)inDbConnection
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDbConnection;
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
	
	enumerateForSrcFactory        = nil;
	enumerateForDstFactory        = nil;
	enumerateForSrcNameFactory    = nil;
	enumerateForDstNameFactory    = nil;
	enumerateForNameFactory       = nil;
	enumerateForSrcDstFactory     = nil;
	enumerateForSrcDstNameFactory = nil;
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
	return parent;
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
	    [[YapDatabaseRelationshipTransaction alloc] initWithParentConnection:self
	                                                     databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseRelationshipTransaction *transaction =
	    [[YapDatabaseRelationshipTransaction alloc] initWithParentConnection:self
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

- (void)processChangeset:(NSDictionary __unused *)changeset
{
	// Nothing to do here.
	// This method is required to be overriden by YapDatabaseExtensionConnection.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)prepareStatement:(sqlite3_stmt **)statement withString:(NSString *)stmtString caller:(SEL)caller_cmd
{
	sqlite3 *db = databaseConnection->db;
	YapDatabaseString stmt; MakeYapDatabaseString(&stmt, stmtString);
	
	int status = sqlite3_prepare_v2(db, stmt.str, stmt.length+1, statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
					NSStringFromSelector(caller_cmd), status, sqlite3_errmsg(db));
	}
	
	FreeYapDatabaseString(&stmt);
}

- (sqlite3_stmt *)findManualEdgeStatement
{
	sqlite3_stmt **statement = &findManualEdgeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"rules\" FROM \"%@\" "
		  @" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ? AND \"manual\" = 1 LIMIT 1;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)insertEdgeStatement
{
	sqlite3_stmt **statement = &insertEdgeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\" (\"name\", \"src\", \"dst\", \"rules\", \"manual\") VALUES (?, ?, ?, ?, ?);",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)updateEdgeStatement
{
	sqlite3_stmt **statement = &updateEdgeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"rules\" = ? WHERE \"rowid\" = ?;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)deleteEdgeStatement
{
	sqlite3_stmt **statement = &deleteEdgeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)deleteEdgesWithNodeStatement
{
	sqlite3_stmt **statement = &deleteEdgesWithNodeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"src\" = ? OR \"dst\" = ?;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)enumerateAllDstFilePathStatement
{
	sqlite3_stmt **statement = &enumerateAllDstFilePathStatement;
	if (*statement == NULL)
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
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	if (*statement)
	{
		// We do this outside of the if statement above
		// just in case we accidentally call sqlite3_clear_bindings.
		
		sqlite3_bind_int64(*statement, SQLITE_BIND_START, INT64_MAX);
	}
	
	return *statement;
}

- (YapEnumerateStatement *)enumerateForSrcStatement
{
	if (enumerateForSrcFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ?;",
		  [parent tableName]];
		
		enumerateForSrcFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForSrcFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForDstStatement
{
	if (enumerateForDstFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ?;",
		  [parent tableName]];
		
		enumerateForDstFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForDstFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForSrcNameStatement
{
	if (enumerateForSrcNameFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		enumerateForSrcNameFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForSrcNameFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForDstNameStatement
{
	if (enumerateForDstNameFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		enumerateForDstNameFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForDstNameFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForNameStatement
{
	if (enumerateForNameFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"name\" = ?;",
		  [parent tableName]];
		
		enumerateForNameFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForNameFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForSrcDstStatement
{
	if (enumerateForSrcDstFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
		  [parent tableName]];
		
		enumerateForSrcDstFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForSrcDstFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (YapEnumerateStatement *)enumerateForSrcDstNameStatement
{
	if (enumerateForSrcDstNameFactory == nil)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		enumerateForSrcDstNameFactory =
		  [[YapEnumerateStatementFactory alloc] initWithDb:databaseConnection->db statement:string];
	}
	
	int status;
	YapEnumerateStatement *statement = [enumerateForSrcDstNameFactory newStatement:&status];
	
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s",
		             THIS_METHOD, status, sqlite3_errmsg(databaseConnection->db));
	}
	
	return statement;
}

- (sqlite3_stmt *)countForSrcNameExcludingDstStatement
{
	sqlite3_stmt **statement = &countForSrcNameExcludingDstStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" != ? AND \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForDstNameExcludingSrcStatement
{
	sqlite3_stmt **statement = &countForDstNameExcludingSrcStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ? AND \"src\" != ? AND \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForNameStatement
{
	sqlite3_stmt **statement = &countForNameStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForSrcStatement
{
	sqlite3_stmt **statement = &countForSrcStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForSrcNameStatement
{
	sqlite3_stmt **statement = &countForSrcNameStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForDstStatement
{
	sqlite3_stmt **statement = &countForDstStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForDstNameStatement
{
	sqlite3_stmt **statement = &countForDstNameStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForSrcDstStatement
{
	sqlite3_stmt **statement = &countForSrcDstStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)countForSrcDstNameStatement
{
	sqlite3_stmt **statement = &countForSrcDstNameStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeAllStatement
{
	sqlite3_stmt **statement = &removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:@"DELETE FROM \"%@\";", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)removeAllProtocolStatement
{
	sqlite3_stmt **statement = &removeAllProtocolStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"manual\" = 0;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

@end
