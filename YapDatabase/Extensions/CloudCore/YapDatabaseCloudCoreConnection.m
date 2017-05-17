/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCorePrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/

#if DEBUG && robbie_hanson
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN; // YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#elif DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseCloudCoreConnection
{
	sqlite3_stmt *pipelineTable_insertStatement;
	sqlite3_stmt *pipelineTable_removeStatement;
	sqlite3_stmt *pipelineTable_removeAllStatement;
	
	sqlite3_stmt *queueTable_insertStatement;
	sqlite3_stmt *queueTable_modifyStatement;
	sqlite3_stmt *queueTable_removeStatement;
	sqlite3_stmt *queueTable_removeAllStatement;
	
	sqlite3_stmt *tagTable_setStatement;
	sqlite3_stmt *tagTable_fetchStatement;
	sqlite3_stmt *tagTable_removeForBothStatement;
	sqlite3_stmt *tagTable_removeForCloudURIStatement;
	sqlite3_stmt *tagTable_removeAllStatement;
	
	sqlite3_stmt *mappingTable_insertStatement;
	sqlite3_stmt *mappingTable_fetchStatement;
	sqlite3_stmt *mappingTable_fetchForRowidStatement;
	sqlite3_stmt *mappingTable_fetchForCloudURIStatement;
	sqlite3_stmt *mappingTable_removeStatement;
	sqlite3_stmt *mappingTable_removeAllStatement;
}

@synthesize cloudCore = parent;

- (id)initWithParent:(YapDatabaseCloudCore *)inParent databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDbC;
		
		sharedKeySetForInternalChangeset = [NSDictionary sharedKeySetForKeys:[self internalChangesetKeys]];
		
		if (parent->options.enableTagSupport)
		{
			tagCache = [[YapCache alloc] initWithCountLimit:64];
			tagCache.allowedKeyClasses = [NSSet setWithObject:[YapCollectionKey class]];
		}
		
		if (parent->options.enableAttachDetachSupport)
		{
			cleanMappingCache = [[YapManyToManyCache alloc] initWithCountLimit:64];
		}
	}
	return self;
}

- (void)dealloc
{
	[self _flushStatements];
}

- (void)_flushStatements
{
	sqlite_finalize_null(&pipelineTable_insertStatement);
	sqlite_finalize_null(&pipelineTable_removeStatement);
	sqlite_finalize_null(&pipelineTable_removeAllStatement);
	
	sqlite_finalize_null(&queueTable_insertStatement);
	sqlite_finalize_null(&queueTable_modifyStatement);
	sqlite_finalize_null(&queueTable_removeStatement);
	sqlite_finalize_null(&queueTable_removeAllStatement);
	
	sqlite_finalize_null(&tagTable_setStatement);
	sqlite_finalize_null(&tagTable_fetchStatement);
	sqlite_finalize_null(&tagTable_removeForBothStatement);
	sqlite_finalize_null(&tagTable_removeForCloudURIStatement);
	sqlite_finalize_null(&tagTable_removeAllStatement);
	
	sqlite_finalize_null(&mappingTable_insertStatement);
	sqlite_finalize_null(&mappingTable_fetchStatement);
	sqlite_finalize_null(&mappingTable_fetchForRowidStatement);
	sqlite_finalize_null(&mappingTable_fetchForCloudURIStatement);
	sqlite_finalize_null(&mappingTable_removeStatement);
	sqlite_finalize_null(&mappingTable_removeAllStatement);
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
	{
		[tagCache removeAllObjects];
		[cleanMappingCache removeAllItems];
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
	
	NSAssert(NO, @"Missing required method(%@) in subclass(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
	
/* Subclasses should do something like this:
 
	MYCloudTransaction *transaction =
	  [[MYCloudTransaction alloc] initWithParentConnection:self
	                                   databaseTransaction:databaseTransaction];
	
	return transaction;
*/
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	NSAssert(NO, @"Missing required method(%@) in subclass(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
	
/* Subclasses should do something like this:
 
	MYCloudTransaction *transaction =
	  [[MYCloudTransaction alloc] initWithParentConnection:self
	                                   databaseTransaction:databaseTransaction];
	
	[self prepareForReadWriteTransaction]; // <-- Do NOT forget this step !!
	return transaction;
*/
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Architecture
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes any ivars that a read-write transaction may need.
**/
- (void)prepareForReadWriteTransaction
{
	if (operations_added == nil)
		operations_added = [[NSMutableDictionary alloc] init];
	
	if (operations_inserted == nil)
		operations_inserted = [[NSMutableDictionary alloc] init];
	
	if (operations_modified == nil)
		operations_modified = [[NSMutableDictionary alloc] init];
	
	if (graphs_added == nil)
		graphs_added = [[NSMutableDictionary alloc] init];
	
	if (parent->options.enableTagSupport)
	{
		if (dirtyTags == nil)
			dirtyTags = [[NSMutableDictionary alloc] init];
	}
	
	if (parent->options.enableAttachDetachSupport)
	{
		if (dirtyMappingInfo == nil)
			dirtyMappingInfo = [[YapManyToManyCache alloc] initWithCountLimit:0];
	}
}

/**
 * Invoked by our YapDatabaseCloudCoreTransaction at the completion of the commitTransaction method.
**/
- (void)postCommitCleanup
{
	YDBLogAutoTrace();
	
	[operations_added removeAllObjects];
	
	if (operations_inserted.count > 0)
		operations_inserted = nil;      // variable passed to pipeline for processing
	
	if (operations_modified.count > 0)
		operations_modified = nil;      // variable passed to pipeline for processing
	
	if (graphs_added.count > 0)
		graphs_added = nil;             // variable passed to pipeline for processing
	
	[pendingAttachRequests removeAllItems];
	
	if (dirtyTags.count > 0)
		dirtyTags = nil;             // variable passed to other connections via changeset
	
	if (dirtyMappingInfo.count > 0)
		dirtyMappingInfo = nil;      // variable passed to other connections via changeset
	
	reset = NO;
}

/**
 * Invoked by our YapDatabaseViewTransaction at the completion of the rollbackTransaction method.
**/
- (void)postRollbackCleanup
{
	YDBLogAutoTrace();
	
	[operations_added removeAllObjects];
	[operations_inserted removeAllObjects];
	[operations_modified removeAllObjects];
	
	[graphs_added removeAllObjects];
	
	[pendingAttachRequests removeAllItems];
	
	[dirtyTags removeAllObjects];
	[dirtyMappingInfo removeAllItems];
	
	reset = NO;
}

- (NSArray *)internalChangesetKeys
{
	return @[ changeset_key_modifiedMappings,
	          changeset_key_modifiedTags,
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
	
	if (dirtyMappingInfo.count > 0 ||
	    dirtyTags.count        > 0 ||
	    reset)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySetForInternalChangeset];
		
		if (dirtyMappingInfo.count > 0)
		{
			internalChangeset[changeset_key_modifiedMappings] = dirtyMappingInfo;
		}
		
		if (dirtyTags.count > 0)
		{
			internalChangeset[changeset_key_modifiedTags] = dirtyTags;
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
	
	YapManyToManyCache *modifiedMappings = changeset[changeset_key_modifiedMappings];
	NSDictionary *modifiedTags           = changeset[changeset_key_modifiedTags];
	
	BOOL in_changeset_reset = [changeset[changeset_key_reset] boolValue];
	
	// Update cleanMappingsCache
	
	if (in_changeset_reset)
	{
		[cleanMappingCache removeAllItems];
	}
	else
	{
		[modifiedMappings enumerateWithBlock:^(NSNumber *rowid, NSString *path, id metadata, BOOL *stop) {
			
			if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsRemove)
			{
				[cleanMappingCache removeItemWithKey:rowid value:path];
			}
		}];
	}
	
	// Update tagCache
	
	if (in_changeset_reset && (modifiedTags.count == 0))
	{
		// Shortcut
		
		[tagCache removeAllObjects];
	}
	else if (in_changeset_reset || (modifiedTags.count > 0))
	{
		// Enumerate the objects in the cache, and update them as needed
		
		NSUInteger removeCapacity;
		NSUInteger updateCapacity;
		
		removeCapacity = in_changeset_reset ? tagCache.count : modifiedTags.count;
		updateCapacity = MIN(tagCache.count, modifiedTags.count);
		
		NSMutableArray *keysToRemove = [NSMutableArray arrayWithCapacity:removeCapacity];
		NSMutableArray *keysToUpdate = [NSMutableArray arrayWithCapacity:updateCapacity];
		
		NSNull *nsnull = [NSNull null];
		
		[tagCache enumerateKeysWithBlock:^(id key, BOOL *stop) {
			
			// Order matters.
			// Consider the following database change:
			//
			// [transaction removeAllObjects];
			// [transaction setObject:obj forKey:key];
			
			id newChangeTag = [modifiedTags objectForKey:key];
			if (newChangeTag)
			{
				if (newChangeTag == nsnull)
					[keysToRemove addObject:key];
				else
					[keysToUpdate addObject:key];
			}
			else if (in_changeset_reset)
			{
				[keysToRemove addObject:key];
			}
		}];
		
		[tagCache removeObjectsForKeys:keysToRemove];
		
		for (YapCollectionKey *tuple in keysToUpdate)
		{
			NSString *newTag = [modifiedTags objectForKey:tuple];
			
			if (newTag)
				[tagCache setObject:newTag forKey:tuple];
			else
				[tagCache removeObjectForKey:tuple];
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
#pragma mark Statements - Pipeline Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "pipelineTableName"
 *  ("rowid" INTEGER PRIMARY KEY,
 *   "name" TEXT NOT NULL
 *  );
**/

- (sqlite3_stmt *)pipelineTable_insertStatement
{
	sqlite3_stmt **statement = &pipelineTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\" (\"name\") VALUES (?);", [parent pipelineTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pipelineTable_removeStatement
{
	sqlite3_stmt **statement = &pipelineTable_removeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent pipelineTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)pipelineTable_removeAllStatement
{
	sqlite3_stmt **statement = &pipelineTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [parent pipelineTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - Queue Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "queueTableName"
 *  ("rowid" INTEGER PRIMARY KEY,
 *   "pipelineID" INTEGER,
 *   "graphID" BLOB NOT NULL,
 *   "prevGraphID" BLOB,
 *   "operation" BLOB
 *  );
*/

- (sqlite3_stmt *)queueTable_insertStatement
{
	sqlite3_stmt **statement = &queueTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT INTO \"%@\""
		  @" (\"pipelineID\", \"graphID\", \"prevGraphID\", \"operation\")"
		  @" VALUES (?, ?, ?, ?);",
		  [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_modifyStatement
{
	sqlite3_stmt **statement = &queueTable_modifyStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"UPDATE \"%@\" SET \"operation\" = ? WHERE \"rowid\" = ?;", [parent queueTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)queueTable_removeStatement
{
	sqlite3_stmt **statement = &queueTable_removeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"rowid\" = ?;", [parent queueTableName]];
		
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - Tag Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "tagTableName"
 *  ("key" TEXT NOT NULL,
 *   "identifier" TEXT NOT NULL,
 *   "changeTag" BLOB NOT NULL,
 *   PRIMARY KEY ("key", "identifier")
 *  );
**/

- (sqlite3_stmt *)tagTable_setStatement
{
	sqlite3_stmt **statement = &tagTable_setStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\" (\"key\", \"identifier\", \"tag\") VALUES (?, ?, ?);",
		  [parent tagTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)tagTable_fetchStatement
{
	sqlite3_stmt **statement = &tagTable_fetchStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"tag\" FROM \"%@\" WHERE \"key\" = ? AND \"identifier\" = ?;", [parent tagTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)tagTable_removeForBothStatement
{
	sqlite3_stmt **statement = &tagTable_removeForBothStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"key\" = ? AND \"identifier\" = ?;", [parent tagTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)tagTable_removeForCloudURIStatement
{
	sqlite3_stmt **statement = &tagTable_removeForCloudURIStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"key\" = ?;", [parent tagTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)tagTable_removeAllStatement
{
	sqlite3_stmt **statement = &tagTable_removeAllStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\";", [parent tagTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements - Mapping Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * CREATE TABLE IF NOT EXISTS "mappingTableName"
 *  ("database_rowid" INTEGER NOT NULL,
 *   "cloudURI" TEXT NOT NULL,
 *   PRIMARY KEY ("database_rowid", "cloudURI")
 *  );
**/

- (sqlite3_stmt *)mappingTable_insertStatement
{
	sqlite3_stmt **statement = &mappingTable_insertStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"INSERT OR REPLACE INTO \"%@\" (\"database_rowid\", \"cloudURI\") VALUES (?, ?);",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_fetchStatement
{
	sqlite3_stmt **statement = &mappingTable_fetchStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT COUNT(*) AS NumberOfRows FROM \"%@\" WHERE \"database_rowid\" = ? AND \"cloudURI\" = ?;",
		  [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_fetchForRowidStatement
{
	sqlite3_stmt **statement = &mappingTable_fetchForRowidStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"cloudURI\" FROM \"%@\" WHERE \"database_rowid\" = ?;", [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_fetchForCloudURIStatement
{
	sqlite3_stmt **statement = &mappingTable_fetchForCloudURIStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"SELECT \"database_rowid\" FROM \"%@\" WHERE \"cloudURI\" = ?;", [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

- (sqlite3_stmt *)mappingTable_removeStatement
{
	sqlite3_stmt **statement = &mappingTable_removeStatement;
	if (*statement == NULL)
	{
		NSString *string = [NSString stringWithFormat:
		  @"DELETE FROM \"%@\" WHERE \"database_rowid\" = ? AND \"cloudURI\" = ?;", [parent mappingTableName]];
		
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
		  @"DELETE FROM \"%@\";", [parent mappingTableName]];
		
		[self prepareStatement:statement withString:string caller:_cmd];
	}
	
	return *statement;
}

@end
