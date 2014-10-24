#import "YapDatabaseCloudKitPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

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


@implementation YapDatabaseCloudKitConnection
{
	sqlite3_stmt *recordTable_insertStatement;
	sqlite3_stmt *recordTable_updateForRowidStatement;
	sqlite3_stmt *recordTable_getRowidForRecordStatement;
	sqlite3_stmt *recordTable_getInfoForRowidStatement;
	sqlite3_stmt *recordTable_getInfoForAllStatement;
	sqlite3_stmt *recordTable_removeForRowidStatement;
	sqlite3_stmt *recordTable_removeAllStatement;
	
	sqlite3_stmt *queueTable_insertStatement;
	sqlite3_stmt *queueTable_updateStatement;
	sqlite3_stmt *queueTable_removeForUuidStatement;
	sqlite3_stmt *queueTable_removeAllStatement;
}

@synthesize cloudKit = parent;

- (id)initWithParent:(YapDatabaseCloudKit *)inCloudKit databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		parent = inCloudKit;
		databaseConnection = inDbC;
		
		cleanRecordInfo = [[YapCache alloc] initWithKeyClass:[NSNumber class] countLimit:100];
		
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
	sqlite_finalize_null(&recordTable_insertStatement);
	sqlite_finalize_null(&recordTable_updateForRowidStatement);
	sqlite_finalize_null(&recordTable_getRowidForRecordStatement);
	sqlite_finalize_null(&recordTable_getInfoForRowidStatement);
	sqlite_finalize_null(&recordTable_getInfoForAllStatement);
	sqlite_finalize_null(&recordTable_removeForRowidStatement);
	sqlite_finalize_null(&recordTable_removeAllStatement);
	
	sqlite_finalize_null(&queueTable_insertStatement);
	sqlite_finalize_null(&queueTable_updateStatement);
	sqlite_finalize_null(&queueTable_removeForUuidStatement);
	sqlite_finalize_null(&queueTable_removeAllStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
	{
		[cleanRecordInfo removeAllObjects];
	}
	
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
	YDBLogAutoTrace();
	
	YapDatabaseCloudKitTransaction *transaction =
	  [[YapDatabaseCloudKitTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseCloudKitTransaction *transaction =
	  [[YapDatabaseCloudKitTransaction alloc] initWithParentConnection:self
	                                               databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction];
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	if (dirtyRecordInfo == nil)
		dirtyRecordInfo = [[NSMutableDictionary alloc] init];
	
	reset = NO;
	isUploadCompletionTransaction = NO;
}

/**
 * Invoked by our YapDatabaseCloudKitTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	dirtyRecordInfo = nil;
	pendingQueue = nil;
	deletedRowids = nil;
	modifiedRecords = nil;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[cleanRecordInfo removeAllObjects];
	
	dirtyRecordInfo = nil;
	pendingQueue = nil;
	deletedRowids = nil;
	modifiedRecords = nil;
}

- (NSArray *)internalChangesetKeys
{
	return @[ changeset_key_deletedRowids,
	          changeset_key_modifiedRecords,
	          changeset_key_reset ];
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	YDBLogAutoTrace();
	
	NSMutableDictionary *internalChangeset = nil;
	BOOL hasDiskChanges = NO;
	
	if (isUploadCompletionTransaction)
		hasDiskChanges = YES;
	
	if (([deletedRowids count] > 0) || ([modifiedRecords count] > 0) || reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if ([deletedRowids count] > 0)
		{
			internalChangeset[changeset_key_deletedRowids] = deletedRowids;
		}
		
		if ([modifiedRecords count] > 0)
		{
			internalChangeset[changeset_key_modifiedRecords] = modifiedRecords;
		}
		
		if (reset)
		{
			internalChangeset[changeset_key_reset] = @(reset);
		}
		
		hasDiskChanges = YES;
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = nil;
	*hasDiskChangesPtr = hasDiskChanges;
}

- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	NSArray *changeset_deletedRowids = changeset[changeset_key_deletedRowids];
	NSDictionary *changeset_modifiedRecords = changeset[changeset_key_modifiedRecords];
	
	BOOL changeset_reset = [changeset[changeset_key_reset] boolValue];
	
	if (changeset_reset && ([changeset_modifiedRecords count] == 0))
	{
		// Shortcut
		
		[cleanRecordInfo removeAllObjects];
	}
	else if (changeset_reset || ([changeset_deletedRowids count] > 0) || ([changeset_modifiedRecords count] > 0))
	{
		// Enumerate the objects in the cache, and update them as needed
		
		NSUInteger removeCapacity = changeset_reset ? [cleanRecordInfo count] : [changeset_deletedRowids count];
		NSUInteger updateCapacity = MIN([cleanRecordInfo count], [changeset_modifiedRecords count]);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[cleanRecordInfo enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([changeset_modifiedRecords objectForKey:key])
				[keysToUpdate addObject:key];
			else if (changeset_reset || [changeset_deletedRowids containsObject:key])
				[keysToRemove addObject:key];
		}];
		
		[cleanRecordInfo removeObjectsForKeys:keysToRemove];
		
		for (NSString *key in keysToUpdate)
		{
			YDBCKCleanRecordInfo *recordInfo = [changeset_modifiedRecords objectForKey:key];
			
			if (recordInfo)
				[cleanRecordInfo setObject:recordInfo forKey:key];
			else
				[cleanRecordInfo removeObjectForKey:key];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - Utilities
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - RecordTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "recordTableName" (
 *   "rowid" INTEGER PRIMARY KEY,
 *   "recordIDHash" INTEGER NOT NULL,
 *   "databaseIdentifier" TEXT,
 *   "record" BLOB
 * );
**/

- (sqlite3_stmt *)recordTable_insertStatement
{
	sqlite3_stmt **statement = &recordTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\""
		  @" (\"rowid\", \"recordIDHash\", \"databaseIdentifier\", \"record\") VALUES (?, ?, ?, ?);",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_updateForRowidStatement
{
	sqlite3_stmt **statement = &recordTable_updateForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"record\" = ? WHERE \"rowid\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getRowidForRecordStatement
{
	sqlite3_stmt **statement = &recordTable_getRowidForRecordStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\" FROM \"%@\" WHERE \"recordIDHash\" = ? AND \"databaseIdentifier\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getInfoForRowidStatement
{
	sqlite3_stmt **statement = &recordTable_getInfoForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"databaseIdentifier\", \"record\" FROM \"%@\" WHERE \"rowid\" = ?;", [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getInfoForAllStatement
{
	sqlite3_stmt **statement = &recordTable_getInfoForAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"databaseIdentifier\", \"record\" FROM \"%@\";", [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_removeForRowidStatement
{
	sqlite3_stmt **statement = &recordTable_removeForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_removeAllStatement
{
	sqlite3_stmt **statement = &recordTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - QueueTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "queueTableName" (
 *   "uuid" TEXT PRIMARY KEY NOT NULL,
 *   "prev" TEXT,
 *   "databaseIdentifier" TEXT,
 *   "deletedRecordIDs" BLOB,
 *   "modifiedRecords" BLOB
 * );
**/

- (sqlite3_stmt *)queueTable_insertStatement
{
	sqlite3_stmt **statement = &queueTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\""
		  @" (\"uuid\", \"prev\", \"databaseIdentifier\", \"deletedRecordIDs\", \"modifiedRecords\")"
		  @" VALUES (?, ?, ?, ?, ?);",
		  [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_updateStatement
{
	sqlite3_stmt **statement = &queueTable_updateStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"modifiedRecords\" = ? WHERE \"uuid\" = ?;",
		  [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_removeForUuidStatement
{
	sqlite3_stmt **statement = &queueTable_removeForUuidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"uuid\" = ?;", [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_removeAllStatement
{
	sqlite3_stmt **statement = &queueTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

@end
