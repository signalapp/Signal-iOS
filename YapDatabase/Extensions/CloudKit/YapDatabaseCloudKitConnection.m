#import "YapDatabaseCloudKitPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseCloudKitConnection
{
	sqlite3_stmt *mappingTable_insertStatement;
	sqlite3_stmt *mappingTable_updateForRowidStatement;
	sqlite3_stmt *mappingTable_getInfoForRowidStatement;
	sqlite3_stmt *mappingTable_enumerateForHashStatement;
	sqlite3_stmt *mappingTable_removeForRowidStatement;
	sqlite3_stmt *mappingTable_removeAllStatement;
	
	sqlite3_stmt *recordTable_insertStatement;
	sqlite3_stmt *recordTable_updateOwnerCountStatement;
	sqlite3_stmt *recordTable_updateMetadataStatement;
	sqlite3_stmt *recordTable_updateRecordStatement;
	sqlite3_stmt *recordTable_getInfoForHashStatement;
	sqlite3_stmt *recordTable_getOwnerCountForHashStatement;
	sqlite3_stmt *recordTable_getCountForHashStatement;
	sqlite3_stmt *recordTable_enumerateStatement;
	sqlite3_stmt *recordTable_removeForHashStatement;
	sqlite3_stmt *recordTable_removeAllStatement;
	
	sqlite3_stmt *queueTable_insertStatement;
	sqlite3_stmt *queueTable_updateDeletedRecordIDsStatement;
	sqlite3_stmt *queueTable_updateModifiedRecordsStatement;
	sqlite3_stmt *queueTable_updateBothStatement;
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
		
		cleanMappingTableInfoCache = [[YapCache alloc] initWithCountLimit:100];
		cleanMappingTableInfoCache.allowedKeyClasses = [NSSet setWithObject:[NSNumber class]];
		cleanMappingTableInfoCache.allowedObjectClasses =
		  [NSSet setWithObjects:[YDBCKCleanMappingTableInfo class], [NSNull class], nil];
		
		cleanRecordTableInfoCache  = [[YapCache alloc] initWithCountLimit:100];
		cleanRecordTableInfoCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
		cleanRecordTableInfoCache.allowedObjectClasses =
		  [NSSet setWithObjects:[YDBCKCleanRecordTableInfo class], [NSNull class], nil];
		
		recordKeysCache = [[YapCache alloc] initWithCountLimit:20];
		recordKeysCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
		recordKeysCache.allowedObjectClasses = [NSSet setWithObject:[NSArray class]];
		
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
	sqlite_finalize_null(&mappingTable_insertStatement);
	sqlite_finalize_null(&mappingTable_updateForRowidStatement);
	sqlite_finalize_null(&mappingTable_getInfoForRowidStatement);
	sqlite_finalize_null(&mappingTable_enumerateForHashStatement);
	sqlite_finalize_null(&mappingTable_removeForRowidStatement);
	sqlite_finalize_null(&mappingTable_removeAllStatement);
	
	sqlite_finalize_null(&recordTable_insertStatement);
	sqlite_finalize_null(&recordTable_updateOwnerCountStatement);
	sqlite_finalize_null(&recordTable_updateMetadataStatement);
	sqlite_finalize_null(&recordTable_updateRecordStatement);
	sqlite_finalize_null(&recordTable_getInfoForHashStatement);
	sqlite_finalize_null(&recordTable_getOwnerCountForHashStatement);
	sqlite_finalize_null(&recordTable_getCountForHashStatement);
	sqlite_finalize_null(&recordTable_enumerateStatement);
	sqlite_finalize_null(&recordTable_removeForHashStatement);
	sqlite_finalize_null(&recordTable_removeAllStatement);
	
	sqlite_finalize_null(&queueTable_insertStatement);
	sqlite_finalize_null(&queueTable_updateDeletedRecordIDsStatement);
	sqlite_finalize_null(&queueTable_updateModifiedRecordsStatement);
	sqlite_finalize_null(&queueTable_updateBothStatement);
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
		[cleanMappingTableInfoCache removeAllObjects];
		[cleanRecordTableInfoCache removeAllObjects];
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
	if (dirtyMappingTableInfoDict == nil)
		dirtyMappingTableInfoDict = [[NSMutableDictionary alloc] init];
	
	if (dirtyRecordTableInfoDict == nil)
		dirtyRecordTableInfoDict = [[NSMutableDictionary alloc] init];
}

/**
 * Invoked by our YapDatabaseCloudKitTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	// Now that the commit has hit the disk,
	// we can create all the NSOperation(s) with all the changes, and hand them to CloudKit.
	
	if (isOperationCompletionTransaction)
	{
		BOOL forceNotification = YES; // inFlightChangeSet is changing (new changeSet or nil)
		
		[parent->masterQueue removeCompletedInFlightChangeSet];
		[parent asyncMaybeDispatchNextOperation:forceNotification];
	}
	else if (isOperationPartialCompletionTransaction)
	{
		BOOL forceNotification = YES; // inFlightChangeSet is changing (no longer inFlight)
		
		[parent->masterQueue resetFailedInFlightChangeSet];
		[parent asyncMaybeDispatchNextOperation:forceNotification];
	}
	else if (changeset_deletedRowids.count    > 0 ||
	         changeset_deletedHashes.count    > 0 ||
	         changeset_mappingTableInfo.count > 0 ||
	         changeset_recordTableInfo.count  > 0 ||
	         reset)
	{
		BOOL forceNotification = NO;
		[parent asyncMaybeDispatchNextOperation:forceNotification];
	}
	
	dirtyMappingTableInfoDict = nil;
	dirtyRecordTableInfoDict = nil;
	pendingAttachRequests = nil;
	
	reset = NO;
	isOperationCompletionTransaction = NO;
	isOperationPartialCompletionTransaction = NO;
	
	changeset_deletedRowids = nil;
	changeset_deletedHashes = nil;
	changeset_mappingTableInfo = nil;
	changeset_recordTableInfo = nil;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[cleanMappingTableInfoCache removeAllObjects];
	[cleanRecordTableInfoCache removeAllObjects];
	
	dirtyMappingTableInfoDict = nil;
	dirtyRecordTableInfoDict = nil;
	pendingAttachRequests = nil;
	
	reset = NO;
	isOperationCompletionTransaction = NO;
	isOperationPartialCompletionTransaction = NO;
	
	changeset_deletedRowids = nil;
	changeset_deletedHashes = nil;
	changeset_mappingTableInfo = nil;
	changeset_recordTableInfo = nil;
}

- (NSArray *)internalChangesetKeys
{
	return @[ changeset_key_deletedRowids,
	          changeset_key_deletedHashes,
	          changeset_key_mappingTableInfo,
	          changeset_key_recordTableInfo,
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
	
	if (isOperationCompletionTransaction || isOperationPartialCompletionTransaction)
		hasDiskChanges = YES;
	
	if (changeset_deletedRowids.count    > 0 ||
	    changeset_deletedHashes.count    > 0 ||
	    changeset_mappingTableInfo.count > 0 ||
	    changeset_recordTableInfo.count  > 0 ||
	    reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if (changeset_deletedRowids.count > 0)
		{
			internalChangeset[changeset_key_deletedRowids] = changeset_deletedRowids;
		}
		
		if (changeset_deletedHashes.count > 0)
		{
			internalChangeset[changeset_key_deletedHashes] = changeset_deletedHashes;
		}
		
		if (changeset_mappingTableInfo.count > 0)
		{
			internalChangeset[changeset_key_mappingTableInfo] = changeset_mappingTableInfo;
		}
		
		if (changeset_recordTableInfo.count > 0)
		{
			internalChangeset[changeset_key_recordTableInfo] = changeset_recordTableInfo;
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
	
	NSSet *in_changeset_deletedRowids = changeset[changeset_key_deletedRowids];
	NSSet *in_changeset_deletedHashes = changeset[changeset_key_deletedHashes];
	
	NSDictionary *in_changeset_mappingTableInfo = changeset[changeset_key_mappingTableInfo];
	NSDictionary *in_changeset_recordTableInfo  = changeset[changeset_key_recordTableInfo];
	
	BOOL in_changeset_reset = [changeset[changeset_key_reset] boolValue];
	
	// Update cleanMappingTableInfo
	
	if (in_changeset_reset && (in_changeset_mappingTableInfo.count == 0))
	{
		// Shortcut
		
		[cleanMappingTableInfoCache removeAllObjects];
	}
	else if (in_changeset_reset || (in_changeset_deletedRowids.count > 0) || (in_changeset_mappingTableInfo.count > 0))
	{
		// Enumerate the objects in the cache, and update them as needed
		
		NSUInteger removeCapacity;
		NSUInteger updateCapacity;
		
		removeCapacity = in_changeset_reset ? cleanMappingTableInfoCache.count : in_changeset_deletedRowids.count;
		updateCapacity = MIN(cleanMappingTableInfoCache.count, in_changeset_mappingTableInfo.count);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[cleanMappingTableInfoCache enumerateKeysWithBlock:^(NSNumber *rowid, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([in_changeset_mappingTableInfo objectForKey:rowid])
				[keysToUpdate addObject:rowid];
			else if (in_changeset_reset || [in_changeset_deletedRowids containsObject:rowid])
				[keysToRemove addObject:rowid];
		}];
		
		[cleanMappingTableInfoCache removeObjectsForKeys:keysToRemove];
		
		for (NSNumber *rowid in keysToUpdate)
		{
			YDBCKCleanMappingTableInfo *cleanMappingTableInfo = [in_changeset_mappingTableInfo objectForKey:rowid];
			
			if (cleanMappingTableInfo)
				[cleanMappingTableInfoCache setObject:cleanMappingTableInfo forKey:rowid];
			else
				[cleanMappingTableInfoCache removeObjectForKey:rowid];
		}
	}
	
	// Update cleanRecordTableInfo
	
	if (in_changeset_reset && (in_changeset_recordTableInfo.count == 0))
	{
		// Shortcut
		
		[cleanRecordTableInfoCache removeAllObjects];
	}
	else if (in_changeset_reset || (in_changeset_deletedHashes.count > 0) || (in_changeset_recordTableInfo.count > 0))
	{
		// Enumerate the objects in the cache, and update them as needed
		
		NSUInteger removeCapacity;
		NSUInteger updateCapacity;
		
		removeCapacity = in_changeset_reset ? cleanRecordTableInfoCache.count : in_changeset_deletedHashes.count;
		updateCapacity = MIN(cleanRecordTableInfoCache.count, in_changeset_recordTableInfo.count);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		[cleanRecordTableInfoCache enumerateKeysWithBlock:^(NSString *hash, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			if ([in_changeset_recordTableInfo objectForKey:hash])
				[keysToUpdate addObject:hash];
			else if (in_changeset_reset || [in_changeset_deletedHashes containsObject:hash])
				[keysToRemove addObject:hash];
		}];
		
		[cleanRecordTableInfoCache removeObjectsForKeys:keysToRemove];
		
		for (NSString *hash in keysToUpdate)
		{
			YDBCKCleanRecordTableInfo *cleanRecordTableInfo = [in_changeset_recordTableInfo objectForKey:hash];
			
			if (cleanRecordTableInfo)
				[cleanRecordTableInfoCache setObject:cleanRecordTableInfo forKey:hash];
			else
				[cleanRecordTableInfoCache removeObjectForKey:hash];
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
#pragma mark Statements - MappingTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "mappingTableName" (
 *   "rowid" INTEGER PRIMARY KEY,
 *   "recordTable_hash" TEXT NOT NULL
 * );
**/

- (sqlite3_stmt *)mappingTable_insertStatement
{
	sqlite3_stmt **statement = &mappingTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\""
		  @" (\"rowid\", \"recordTable_hash\") VALUES (?, ?);",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_updateForRowidStatement
{
	sqlite3_stmt **statement = &mappingTable_updateForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"recordTable_hash\" = ? WHERE \"rowid\" = ?;",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_getInfoForRowidStatement
{
	sqlite3_stmt **statement = &mappingTable_getInfoForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"recordTable_hash\" FROM \"%@\" WHERE \"rowid\" = ?;",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_enumerateForHashStatement
{
	sqlite3_stmt **statement = &mappingTable_enumerateForHashStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"rowid\" FROM \"%@\" WHERE \"recordTable_hash\" = ?;",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_removeForRowidStatement
{
	sqlite3_stmt **statement = &mappingTable_removeForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_removeAllStatement
{
	sqlite3_stmt **statement = &mappingTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - RecordTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "recordTableName" (
 *   "hash" TEXT PRIMARY KEY,
 *   "databaseIdentifier" TEXT,
 *   "ownerCount" INTEGER,
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
		  @" (\"hash\", \"databaseIdentifier\", \"ownerCount\", \"record\")"
		  @" VALUES (?, ?, ?, ?);",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_updateOwnerCountStatement
{
	sqlite3_stmt **statement = &recordTable_updateOwnerCountStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"ownerCount\" = ? WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_updateMetadataStatement
{
	sqlite3_stmt **statement = &recordTable_updateMetadataStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"ownerCount\" = ? WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_updateRecordStatement
{
	sqlite3_stmt **statement = &recordTable_updateRecordStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"record\" = ? WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getInfoForHashStatement
{
	sqlite3_stmt **statement = &recordTable_getInfoForHashStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"databaseIdentifier\", \"ownerCount\", \"record\""
		  @" FROM \"%@\""
		  @" WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getOwnerCountForHashStatement
{
	sqlite3_stmt **statement = &recordTable_getOwnerCountForHashStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"ownerCount\" FROM \"%@\" WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_getCountForHashStatement
{
	sqlite3_stmt **statement = &recordTable_getCountForHashStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"hash\" = ?;",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_enumerateStatement
{
	sqlite3_stmt **statement = &recordTable_enumerateStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"hash\", \"databaseIdentifier\", \"ownerCount\", \"recordTable_hash\", \"record\" FROM \"%@\";",
		  [parent recordTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)recordTable_removeForHashStatement
{
	sqlite3_stmt **statement = &recordTable_removeForHashStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"hash\" = ?;", [parent recordTableName]];
		
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

- (sqlite3_stmt *)queueTable_updateDeletedRecordIDsStatement
{
	sqlite3_stmt **statement = &queueTable_updateDeletedRecordIDsStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"deletedRecordIDs\" = ? WHERE \"uuid\" = ?;",
		  [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_updateBothStatement
{
	sqlite3_stmt **statement = &queueTable_updateBothStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"deletedRecordIDs\" = ?, \"modifiedRecords\" = ? WHERE \"uuid\" = ?;",
		  [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_updateModifiedRecordsStatement
{
	sqlite3_stmt **statement = &queueTable_updateModifiedRecordsStatement;
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
