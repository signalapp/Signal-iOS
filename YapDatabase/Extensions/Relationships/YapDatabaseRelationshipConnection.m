#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapCollectionKey.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#import "NSDictionary+YapDatabase.h"

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
	sqlite3_stmt *findEdgesWithNodeStatement;
	sqlite3_stmt *findManualEdgeWithDstStatement;
	sqlite3_stmt *findManualEdgeWithDstFileURLStatement;
	sqlite3_stmt *insertEdgeStatement;
	sqlite3_stmt *updateEdgeStatement;
	sqlite3_stmt *deleteEdgeStatement;
	sqlite3_stmt *deleteEdgesWithNodeStatement;
	sqlite3_stmt *enumerateDstFileURLWithSrcStatement;
	sqlite3_stmt *enumerateDstFileURLWithSrcNameStatement;
	sqlite3_stmt *enumerateDstFileURLWithNameStatement;
	sqlite3_stmt *enumerateDstFileURLWithNameExcludingSrcStatement;
	sqlite3_stmt *enumerateAllDstFileURLStatement;
	sqlite3_stmt *enumerateForSrcStatement;
	sqlite3_stmt *enumerateForDstStatement;
	sqlite3_stmt *enumerateForSrcNameStatement;
	sqlite3_stmt *enumerateForDstNameStatement;
	sqlite3_stmt *enumerateForNameStatement;
	sqlite3_stmt *enumerateForSrcDstStatement;
	sqlite3_stmt *enumerateForSrcDstNameStatement;
	sqlite3_stmt *countForSrcStatement;
	sqlite3_stmt *countForDstStatement;
	sqlite3_stmt *countForSrcNameStatement;
	sqlite3_stmt *countForDstNameStatement;
	sqlite3_stmt *countForNameStatement;
	sqlite3_stmt *countForSrcDstStatement;
	sqlite3_stmt *countForSrcDstNameStatement;
	sqlite3_stmt *countForSrcNameExcludingDstStatement;
	sqlite3_stmt *countForDstNameExcludingSrcStatement;
	sqlite3_stmt *removeAllStatement;
	sqlite3_stmt *removeAllProtocolStatement;
}

@synthesize relationship = parent;

- (id)initWithParent:(YapDatabaseRelationship *)inParent databaseConnection:(YapDatabaseConnection *)inDbConnection
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDbConnection;
		
		edgeCache = [[YapCache alloc] initWithCountLimit:500];
		edgeCache.allowedKeyClasses = [NSSet setWithObject:[NSNumber class]];
		edgeCache.allowedObjectClasses = [NSSet setWithObject:[YapDatabaseRelationshipEdge class]];
		
		sharedKeySetForInternalChangeset = [NSDictionary sharedKeySetForKeys:[self internalChangesetKeys]];
	}
	return self;
}

- (void)dealloc
{
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&findEdgesWithNodeStatement);
	sqlite_finalize_null(&findManualEdgeWithDstStatement);
	sqlite_finalize_null(&findManualEdgeWithDstFileURLStatement);
	sqlite_finalize_null(&insertEdgeStatement);
	sqlite_finalize_null(&updateEdgeStatement);
	sqlite_finalize_null(&deleteEdgeStatement);
	sqlite_finalize_null(&deleteEdgesWithNodeStatement);
	sqlite_finalize_null(&enumerateDstFileURLWithSrcStatement);
	sqlite_finalize_null(&enumerateDstFileURLWithSrcNameStatement);
	sqlite_finalize_null(&enumerateDstFileURLWithNameStatement);
	sqlite_finalize_null(&enumerateDstFileURLWithNameExcludingSrcStatement);
	sqlite_finalize_null(&enumerateAllDstFileURLStatement);
	sqlite_finalize_null(&enumerateForSrcStatement);
	sqlite_finalize_null(&enumerateForDstStatement);
	sqlite_finalize_null(&enumerateForSrcNameStatement);
	sqlite_finalize_null(&enumerateForDstNameStatement);
	sqlite_finalize_null(&enumerateForNameStatement);
	sqlite_finalize_null(&enumerateForSrcDstStatement);
	sqlite_finalize_null(&enumerateForSrcDstNameStatement);
	sqlite_finalize_null(&countForSrcStatement);
	sqlite_finalize_null(&countForSrcNameStatement);
	sqlite_finalize_null(&countForDstStatement);
	sqlite_finalize_null(&countForDstNameStatement);
	sqlite_finalize_null(&countForNameStatement);
	sqlite_finalize_null(&countForSrcDstStatement);
	sqlite_finalize_null(&countForSrcDstNameStatement);
	sqlite_finalize_null(&countForSrcNameExcludingDstStatement);
	sqlite_finalize_null(&countForDstNameExcludingSrcStatement);
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
	
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
	{
		[edgeCache removeAllObjects];
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
	
	if (deletedEdges == nil)
		deletedEdges = [[NSMutableSet alloc] init];
	
	if (modifiedEdges == nil)
		modifiedEdges = [[NSMutableDictionary alloc] init];
	
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
	
	reset = NO;
	
	// The following may be stored in the changeset notification:
	// - deletedEdges
	// - modifiedEdges
	// - reset
	//
	// The following are used post-transaction:
	// - filesToDelete
	//
	// By nil'ing these out here (instead of clearing them) we can avoid copying them when adding to changeset.
	
	if (deletedEdges.count > 0)
		deletedEdges = nil;
	
	if (modifiedEdges.count > 0)
		modifiedEdges = nil;
	
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
	
	reset = NO;
	
	[deletedEdges removeAllObjects];
	[modifiedEdges removeAllObjects];
	[filesToDelete removeAllObjects];
}

- (NSArray *)internalChangesetKeys
{
	return @[ changeset_key_deletedEdges,
	          changeset_key_modifiedEdges,
	          changeset_key_reset ];
}

- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	if (deletedEdges.count  > 0 ||
	    modifiedEdges.count > 0 ||
		reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if (deletedEdges.count > 0)
		{
			internalChangeset[changeset_key_deletedEdges] = deletedEdges;
		}
		
		if (modifiedEdges.count > 0)
		{
			internalChangeset[changeset_key_modifiedEdges] = modifiedEdges;
		}
		
		if (reset)
		{
			internalChangeset[changeset_key_reset] = @(reset);
		}
		
		hasDiskChanges = YES;
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	NSSet        *changeset_deletedEdges  = changeset[changeset_key_deletedEdges];
	NSDictionary *changeset_modifiedEdges = changeset[changeset_key_modifiedEdges];
	
	BOOL changeset_reset = [changeset[changeset_key_reset] boolValue];
	
	// Update edgeCache
	
	if (changeset_reset && (changeset_modifiedEdges.count == 0))
	{
		[edgeCache removeAllObjects];
	}
	else
	{
		NSUInteger removeCapacity = changeset_reset ? [edgeCache count] : 0;
		NSUInteger updateCapacity = MIN([edgeCache count], [changeset_modifiedEdges count]);
		
		NSMutableArray *toRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *toUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[edgeCache enumerateKeysWithBlock:^(NSNumber *edgeRowid, BOOL __unused *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_modifiedEdges ydb_containsKey:edgeRowid]) {
				[toUpdate addObject:edgeRowid];
			}
			else if (changeset_reset || [changeset_deletedEdges containsObject:edgeRowid]) {
				[toRemove addObject:edgeRowid];
			}
		}];
		
		[edgeCache removeObjectsForKeys:toRemove];
		
		for (NSNumber *edgeRowid in toUpdate)
		{
			YapDatabaseRelationshipEdge *edge = changeset_modifiedEdges[edgeRowid];
			
			// Important: each connection should have its own mutable copy of the edge
			[edgeCache setObject:[edge copy] forKey:edgeRowid];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "tableName"
 *   ("rowid" INTEGER PRIMARY KEY,
 *    "name" CHAR NOT NULL,
 *    "src" INTEGER NOT NULL,
 *    "dst" BLOB NOT NULL,
 *    "rules" INTEGER,
 *    "manual" INTEGER
 *   );
**/

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

- (sqlite3_stmt *)findEdgesWithNodeStatement
{
	sqlite3_stmt **statement = &findEdgesWithNodeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\" FROM \"%@\" WHERE \"src\" = ? OR \"dst\" = ?;", [parent tableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}


- (sqlite3_stmt *)findManualEdgeWithDstStatement
{
	sqlite3_stmt **statement = &findManualEdgeWithDstStatement;
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

- (sqlite3_stmt *)findManualEdgeWithDstFileURLStatement
{
	sqlite3_stmt **statement = &findManualEdgeWithDstFileURLStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"dst\", \"rules\" FROM \"%@\" "
		  @" WHERE \"src\" = ? AND \"name\" = ? AND \"dst\" > %lld AND \"manual\" = 1;",
		  [parent tableName], INT64_MAX];
		
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

- (sqlite3_stmt *)enumerateDstFileURLWithSrcStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateDstFileURLWithSrcStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		// The 'dst' column can store either an integer or a blob.
		// If the edge has a destination key & collection,
		//  then the 'dst' column affinity (for the row) is integer (rowid of dst).
		// If the edge has a destinationFileURL,
		//  then the 'dst' column affinity (for the row) is blob (serialized URL).
		//
		// We've set the affinity of the 'dst' column (for the table) to be none.
		// Which means that we can easily find all 'dst' rows with blob affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because BLOB is always greater than INTEGER.
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"dst\", \"rules\", \"manual\" FROM \"%@\""
		  @" WHERE \"dst\" > %lld AND \"src\" = ?;",
		  [parent tableName], INT64_MAX];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateDstFileURLWithSrcNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateDstFileURLWithSrcNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		// The 'dst' column can store either an integer or a blob.
		// If the edge has a destination key & collection,
		//  then the 'dst' column affinity (for the row) is integer (rowid of dst).
		// If the edge has a destinationFileURL,
		//  then the 'dst' column affinity (for the row) is blob (serialized URL).
		//
		// We've set the affinity of the 'dst' column (for the table) to be none.
		// Which means that we can easily find all 'dst' rows with blob affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because BLOB is always greater than INTEGER.
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"dst\", \"rules\", \"manual\" FROM \"%@\""
		  @" WHERE \"dst\" > %lld AND \"src\" = ? AND \"name\" = ?;",
		  [parent tableName], INT64_MAX];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateDstFileURLWithNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateDstFileURLWithNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
	
		// The 'dst' column can store either an integer or a blob.
		// If the edge has a destination key & collection,
		//  then the 'dst' column affinity (for the row) is integer (rowid of dst).
		// If the edge has a destinationFileURL,
		//  then the 'dst' column affinity (for the row) is blob (serialized URL).
		//
		// We've set the affinity of the 'dst' column (for the table) to be none.
		// Which means that we can easily find all 'dst' rows with blob affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because BLOB is always greater than INTEGER.
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\""
		  @" WHERE \"dst\" > %lld AND \"name\" = ?;",
		  [parent tableName], INT64_MAX];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateDstFileURLWithNameExcludingSrcStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateDstFileURLWithNameExcludingSrcStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
	
		// The 'dst' column can store either an integer or a blob.
		// If the edge has a destination key & collection,
		//  then the 'dst' column affinity (for the row) is integer (rowid of dst).
		// If the edge has a destinationFileURL,
		//  then the 'dst' column affinity (for the row) is blob (serialized URL).
		//
		// We've set the affinity of the 'dst' column (for the table) to be none.
		// Which means that we can easily find all 'dst' rows with blob affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because BLOB is always greater than INTEGER.
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\""
		  @" WHERE \"dst\" > %lld AND \"src\" != ? AND \"name\" = ?;",
		  [parent tableName], INT64_MAX];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateAllDstFileURLStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateAllDstFileURLStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
	
		// The 'dst' column can store either an integer or a blob.
		// If the edge has a destination key & collection,
		//  then the 'dst' column affinity (for the row) is integer (rowid of dst).
		// If the edge has a destinationFileURL,
		//  then the 'dst' column affinity (for the row) is blob (serialized URL).
		//
		// We've set the affinity of the 'dst' column (for the table) to be none.
		// Which means that we can easily find all 'dst' rows with blob affinity by searching for those rows
		// where: 'dst' > INT64_MAX
		//
		// This is because BLOB is always greater than INTEGER.
		//
		// For more information, see the documentation: http://www.sqlite.org/datatype3.html
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" > %lld;",
		  [parent tableName], INT64_MAX];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForSrcStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForSrcStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForDstStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForDstStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForSrcNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForSrcNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForDstNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForDstNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"rules\", \"manual\" FROM \"%@\" WHERE \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"src\", \"dst\", \"rules\", \"manual\" FROM \"%@\" WHERE \"name\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForSrcDstStatement:(BOOL *)needsFinalizePtr
{
	NSParameterAssert(needsFinalizePtr != NULL);
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	sqlite3_stmt **statement = &enumerateForSrcDstStatement;
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	*needsFinalizePtr = needsFinalize;
	return result;
}

- (sqlite3_stmt *)enumerateForSrcDstNameStatement:(BOOL *)needsFinalizePtr
{
	sqlite3_stmt **statement = &enumerateForSrcDstNameStatement;
	
	sqlite3_stmt* (^CreateStatement)() = ^{
		
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"rules\", \"manual\" FROM \"%@\" WHERE \"src\" = ? AND \"dst\" = ? AND \"name\" = ?;",
		  [parent tableName]];
		
		sqlite3_stmt *stmt = NULL;
		[self prepareStatement:&stmt withString:string caller:_cmd];
		
		return stmt;
	};
	
	BOOL needsFinalize = NO;
	sqlite3_stmt *result = NULL;
	
	if (*statement == NULL)
	{
		result = *statement = CreateStatement();
	}
	else if (sqlite3_stmt_busy(*statement))
	{
		result = CreateStatement();
		needsFinalize = YES;
	}
	else
	{
		result = *statement;
	}
	
	NSParameterAssert(needsFinalizePtr != NULL);
	*needsFinalizePtr = needsFinalize;
	return result;
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
