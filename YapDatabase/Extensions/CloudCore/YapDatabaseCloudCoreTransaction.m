/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCorePrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "LumberjackUser.h"
/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG && robbie_hanson
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE; // | YDB_LOG_FLAG_TRACE;
#elif DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

/**
 * Keys for yap2 extension configuration table.
**/
static NSString *const ext_key_classVersion = @"classVersion";
static NSString *const ext_key_versionTag   = @"versionTag";


typedef NS_ENUM(int32_t, YapDatabaseCloudCoreQueueTableType) {
	YapDatabaseCloudCoreQueueTableType_Record     = 0, // Do NOT change ! Value stored to disk.
	YapDatabaseCloudCoreQueueTableType_FilePut    = 1, // Do NOT change ! Value stored to disk.
	YapDatabaseCloudCoreQueueTableType_FileDelete = 2, // Do NOT change ! Value stored to disk.
};

typedef NS_ENUM(uint8_t, YDBCloudCore_UpdatedValuesPrefix) {
	YDBCloudCore_UpdatedValuesPrefix_KeysOnly  = 0, // Do NOT change ! Value stored to disk.
	YDBCloudCore_UpdatedValuesPrefix_Full      = 1, // Do NOT change ! Value stored to disk.
};

typedef NS_OPTIONS(uint8_t, YDBCloudCore_EnumOps) {
	YDBCloudCore_EnumOps_Existing = 1 << 0,
	YDBCloudCore_EnumOps_Inserted = 1 << 1,
	YDBCloudCore_EnumOps_Added    = 1 << 2,
	YDBCloudCore_EnumOps_All      = YDBCloudCore_EnumOps_Existing |
	                                YDBCloudCore_EnumOps_Inserted |
	                                YDBCloudCore_EnumOps_Added,
};


@implementation YapDatabaseCloudCoreTransaction

- (id)initWithParentConnection:(YapDatabaseCloudCoreConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		parentConnection = inParentConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called to create any necessary tables,
 * as well as populate the view by enumerating over the existing rows in the database.
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)createIfNeeded
{
	YDBLogAutoTrace();
	
	// Capture NEW values
	//
	// classVersion - the internal version number of YapDatabaseView implementation
	// versionTag - user specified versionTag, used to force upgrade mechanisms
	
	int classVersion = YAPDATABASE_OWNCLOUD_CLASS_VERSION;
	
	NSString *versionTag = parentConnection->parent->versionTag;
	
	// Fetch OLD values
	//
	// - hasOldClassVersion - will be YES if the extension exists from a previous run of the app
	
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ext_key_classVersion persistent:YES];
	
	NSString *oldVersionTag = [self stringValueForExtensionKey:ext_key_versionTag persistent:YES];
	
	if (!hasOldClassVersion)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self populateTables]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ext_key_classVersion persistent:YES];
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
	}
	else if (oldClassVersion != classVersion)
	{
		// Upgrading from older codebase
		//
		// Reserved for potential future use.
		// Code would likely need to do something similar to the following:
		//
		// - migrateTables
		// - restorePreviousOperations
		// - populateTables
		
		NSAssert(NO, @"Attempting invalid upgrade path !");
		return NO;
	}
	else if (![versionTag isEqualToString:oldVersionTag])
	{
		// Handle user-indicated change
		
		if (![self restorePreviousOperations]) return NO;
		if (![self populateTables]) return NO;
		
		[self setStringValue:versionTag forExtensionKey:ext_key_versionTag persistent:YES];
	}
	else
	{
		// Restoring an up-to-date extension from a previous run.
		
		if (![self restorePreviousOperations]) return NO;
	}
	
	return YES;
}

/**
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	YDBLogAutoTrace();
	
	// Nothing to do here for this extension.
	
	return YES;
}

- (BOOL)createTables
{
	YDBLogAutoTrace();
	
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *pipelineTableName = [self pipelineTableName];
	NSString *mappingTableName  = [self mappingTableName];
	NSString *queueTableName    = [self queueTableName];
	NSString *tagTableName      = [self tagTableName];
	
	int status;
	
	// Pipeline Table
	//
	// | rowid | name |
	
	YDBLogVerbose(@"Creating ownCloud table for registeredName(%@): %@", [self registeredName], pipelineTableName);
	
	NSString *createPipelineTable = [NSString stringWithFormat:
	  @"CREATE TABLE IF NOT EXISTS \"%@\""
	  @" (\"rowid\" INTEGER PRIMARY KEY,"
	  @"  \"name\" TEXT NOT NULL"
	  @" );", pipelineTableName];
	
	YDBLogVerbose(@"%@", createPipelineTable);
	status = sqlite3_exec(db, [createPipelineTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, pipelineTableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Queue Table
	//
	// | rowid | pipelineID | graphID | prevGraphID | operation |
	
	YDBLogVerbose(@"Creating ownCloud table for registeredName(%@): %@", [self registeredName], queueTableName);
	
	NSString *createQueueTable = [NSString stringWithFormat:
	  @"CREATE TABLE IF NOT EXISTS \"%@\""
	  @" (\"rowid\" INTEGER PRIMARY KEY,"
	  @"  \"pipelineID\" INTEGER,"         // Foreign key for pipeline table (may be null)
	  @"  \"graphID\" BLOB NOT NULL,"      // UUID in raw form (128 bits)
	  @"  \"prevGraphID\" BLOB,"           // UUID in raw form (128 bits)
	  @"  \"operation\" BLOB"              // Serialized operation
	  @" );", queueTableName];
	
	YDBLogVerbose(@"%@", createQueueTable);
	status = sqlite3_exec(db, [createQueueTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, queueTableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	if (parentConnection->parent->options.enableAttachDetachSupport)
	{
		// Mapping Table
		//
		// | database_rowid | cloudURI |
		//
		// Many-To-Many:
		// - a single database_rowid might map to multiple identifiers
		// - a single identifier might be retained by multiple database_rowid's
		
		YDBLogVerbose(@"Creating ownCloud table for registeredName(%@): %@", [self registeredName], mappingTableName);
		
		NSString *createMappingTable = [NSString stringWithFormat:
		  @"CREATE TABLE IF NOT EXISTS \"%@\""
		  @" (\"database_rowid\" INTEGER NOT NULL,"
		  @"  \"cloudURI\" TEXT NOT NULL"
		  @" );", mappingTableName];
		
		NSString *createMappingTableIndex_rowid = [NSString stringWithFormat:
		  @"CREATE INDEX IF NOT EXISTS \"database_rowid\" ON \"%@\" (\"database_rowid\");", mappingTableName];
		
		NSString *createMappingTableIndex_cloudURI = [NSString stringWithFormat:
		  @"CREATE INDEX IF NOT EXISTS \"cloudURI\" ON \"%@\" (\"cloudURI\");", mappingTableName];
		
		YDBLogVerbose(@"%@", createMappingTable);
		status = sqlite3_exec(db, [createMappingTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating table (%@): %d %s",
			            THIS_METHOD, mappingTableName, status, sqlite3_errmsg(db));
			return NO;
		}
		
		YDBLogVerbose(@"%@", createMappingTableIndex_rowid);
		status = sqlite3_exec(db, [createMappingTableIndex_rowid UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating index (database_rowid) on table (%@): %d %s",
						THIS_METHOD, mappingTableName, status, sqlite3_errmsg(db));
			return NO;
		}
		
		YDBLogVerbose(@"%@", createMappingTableIndex_cloudURI);
		status = sqlite3_exec(db, [createMappingTableIndex_cloudURI UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating index (cloudURI) on table (%@): %d %s",
						THIS_METHOD, mappingTableName, status, sqlite3_errmsg(db));
			return NO;
		}
	}
	
	if (parentConnection->parent->options.enableTagSupport)
	{
		// Tag Table
		//
		// | cloudURI | identifier | tag |
		
		YDBLogVerbose(@"Creating ownCloud table for registeredName(%@): %@", [self registeredName], tagTableName);
		
		NSString *createTagTable = [NSString stringWithFormat:
		  @"CREATE TABLE IF NOT EXISTS \"%@\""
		  @" (\"cloudURI\" TEXT NOT NULL,"
		  @"  \"identifier\" TEXT NOT NULL,"
		  @"  \"tag\" BLOB NOT NULL,"
		  @"  PRIMARY KEY (\"cloudURI\", \"identifier\")"
		  @" );", tagTableName];
		
		YDBLogVerbose(@"%@", createTagTable);
		status = sqlite3_exec(db, [createTagTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed creating table (%@): %d %s",
			            THIS_METHOD, createTagTable, status, sqlite3_errmsg(db));
			return NO;
		}
	}
	
	return YES;
}

/**
 * Restores
**/
- (BOOL)restorePreviousOperations
{
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSMutableDictionary *rowidToPipelineName = [NSMutableDictionary dictionary];
	NSMutableDictionary *sortedGraphsPerPipeline = [NSMutableDictionary dictionary];
	
	// Step 1 of 7:
	//
	// Read pipeline table
	{
		sqlite3_stmt *statement;
		int status;
		
		NSString *enumerate = [NSString stringWithFormat:
		  @"SELECT \"rowid\", \"name\" FROM \"%@\";", [self pipelineTableName]];
		
		int const column_idx_rowid = SQLITE_COLUMN_START + 0;
		int const column_idx_name  = SQLITE_COLUMN_START + 1;
		
		status = sqlite3_prepare_v2(db, [enumerate UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement (A): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
			return NO;
		}
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, column_idx_rowid);
			
			const unsigned char *text = sqlite3_column_text(statement, column_idx_name);
			int textSize = sqlite3_column_bytes(statement, column_idx_name);
			
			NSString *name = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			if (name) {
				rowidToPipelineName[@(rowid)] = name;
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error executing statement (A): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
	}
	
	// Step 2 of 7:
	//
	// Update pipeline table
	{
		NSSet *existing = [NSSet setWithArray:[rowidToPipelineName allValues]];
		NSSet *needed   = [NSSet setWithArray:[parentConnection->parent registeredPipelineNamesExcludingDefault]];
		
		// pipelineNamesToRemove == existing - needed
		// pipelineNamesToInsert == needed - existing
		
		NSMutableSet *pipelineNamesToRemove = [existing mutableCopy];
		[pipelineNamesToRemove minusSet:needed];
		
		NSMutableSet *pipelineNamesToInsert = [needed mutableCopy];
		[pipelineNamesToInsert minusSet:existing];
		
		if (pipelineNamesToRemove.count > 0)
		{
			NSMutableArray *pipelineRowidsToRemove = [NSMutableArray arrayWithCapacity:pipelineNamesToRemove.count];
			
			[rowidToPipelineName enumerateKeysAndObjectsUsingBlock:^(NSNumber *rowid, NSString *name, BOOL *stop) {
				
				if ([pipelineNamesToRemove containsObject:name])
				{
					[pipelineRowidsToRemove addObject:rowid];
				}
			}];
			
			[rowidToPipelineName removeObjectsForKeys:pipelineRowidsToRemove];
			
			sqlite3_stmt *statement = [parentConnection pipelineTable_removeStatement];
			if (statement == NULL){
				return NO;
			}
			
			// DELETE FROM "pipelineTableName" WHERE "rowid" = ?;
			
			for (NSNumber *rowid in pipelineRowidsToRemove)
			{
				sqlite3_bind_int64(statement, SQLITE_BIND_START, [rowid longLongValue]);
				
				int status = sqlite3_step(statement);
				if (status != SQLITE_DONE)
				{
					YDBLogError(@"%@: Error executing statement (B1): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
				}
				
				sqlite3_reset(statement);
				sqlite3_clear_bindings(statement);
			}
		}
		
		if (pipelineNamesToInsert.count > 0)
		{
			sqlite3_stmt *statement = [parentConnection pipelineTable_insertStatement];
			if (statement == NULL) {
				return NO;
			}
			
			// INSERT INTO "pipelineTableName" ("name") VALUES (?);
			
			for (NSString *name in pipelineNamesToInsert)
			{
				sqlite3_bind_text(statement, SQLITE_BIND_START, [name UTF8String], -1, SQLITE_TRANSIENT);
				
				int status = sqlite3_step(statement);
				if (status == SQLITE_DONE)
				{
					int64_t rowid = sqlite3_last_insert_rowid(db);
					rowidToPipelineName[@(rowid)] = name;
				}
				else
				{
					YDBLogError(@"%@: Error executing statement (B2): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
				}
				
				sqlite3_reset(statement);
				sqlite3_clear_bindings(statement);
			}
		}
	}
	
	// Step 3 of 7:
	//
	// Set pipeline.rowid properties
	
	[parentConnection->parent restorePipelineRowids:rowidToPipelineName];
	
	// Step 4 of 7:
	//
	// Read queue table
	
	NSMutableDictionary *graphOrderPerPipeline = [NSMutableDictionary dictionary];
	NSMutableDictionary *operationsPerPipeline = [NSMutableDictionary dictionary];
	
	{
		sqlite3_stmt *statement;
		int status;
		
		NSString *enumerate = [NSString stringWithFormat:@"SELECT * FROM \"%@\";", [self queueTableName]];
		
		int const column_idx_rowid       = SQLITE_COLUMN_START +  0; // INTEGER PRIMARY KEY
		int const column_idx_pipelineID  = SQLITE_COLUMN_START +  1; // INTEGER
		int const column_idx_graphID     = SQLITE_COLUMN_START +  2; // BLOB NOT NULL        (UUID in raw form)
		int const column_idx_prevGraphID = SQLITE_COLUMN_START +  3; // BLOB                 (UUID in raw form)
		int const column_idx_operation   = SQLITE_COLUMN_START +  4; // BLOB
		
		status = sqlite3_prepare_v2(db, [enumerate UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@: Error creating prepared statement (B): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
			return NO;
		}
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			// - Extract pipeline information
			
			NSString *pipelineName = nil;
			
			int column_type = sqlite3_column_type(statement, column_idx_pipelineID);
			if (column_type != SQLITE_NULL)
			{
				int64_t pipelineRowid = sqlite3_column_int64(statement, column_idx_pipelineID);
				
				pipelineName = rowidToPipelineName[@(pipelineRowid)];
			}
			
			// ensure pipelineName is valid (and convert from alias if needed)
			if (pipelineName) {
				pipelineName = [[parentConnection->parent pipelineWithName:pipelineName] name];
			}
			
			if (pipelineName == nil) {
				pipelineName = YapDatabaseCloudCoreDefaultPipelineName;
			}
			
			// - Extract graphUUID information
			// - Add to graphOrderPerPipeline
			
			NSUUID *graphUUID = nil;
			{
				int blobSize = sqlite3_column_bytes(statement, column_idx_graphID);
				if (blobSize == sizeof(uuid_t))
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_graphID);
					graphUUID = [[NSUUID alloc] initWithUUIDBytes:(const unsigned char *)blob];
				}
				else
				{
					NSAssert(NO, @"Invalid UUID blobSize: graphUUID");
				}
			}
			
			NSUUID *prevGraphUUID = nil;
			{
				int blobSize = sqlite3_column_bytes(statement, column_idx_prevGraphID);
				if (blobSize == sizeof(uuid_t))
				{
					const void *blob = sqlite3_column_blob(statement, column_idx_prevGraphID);
					prevGraphUUID = [[NSUUID alloc] initWithUUIDBytes:(const unsigned char *)blob];
				}
				else if (blobSize > 0)
				{
					NSAssert(NO, @"Invalid UUID blobSize: prevGraphUUID");
				}
			}
			
			NSMutableDictionary *graphOrder = graphOrderPerPipeline[pipelineName];
			if (graphOrder == nil)
			{
				graphOrder = [NSMutableDictionary dictionary];
				graphOrderPerPipeline[pipelineName] = graphOrder;
			}
			
			if (prevGraphUUID)
				graphOrder[prevGraphUUID] = graphUUID;
			else
				graphOrder[[NSNull null]] = graphUUID;
			
			// - Extract operation information
			// - Create operation instance
			
			const void *blob = sqlite3_column_blob(statement, column_idx_operation);
			int blobSize = sqlite3_column_bytes(statement, column_idx_operation);
			
			NSData *operationBlob = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			YapDatabaseCloudCoreOperation *operation = [self deserializeOperation:operationBlob];
			
			operation.operationRowid = sqlite3_column_int64(statement, column_idx_rowid);
			operation.pipeline = pipelineName;
			
			// - Add to operationsPerPipeline
			
			NSMutableDictionary *operationsPerGraph = operationsPerPipeline[pipelineName];
			
			if (operationsPerGraph == nil)
			{
				operationsPerGraph = [NSMutableDictionary dictionary];
				operationsPerPipeline[pipelineName] = operationsPerGraph;
			}
			
			NSMutableArray *operations = operationsPerGraph[graphUUID];
			if (operations == nil)
			{
				operations = [NSMutableArray array];
				operationsPerGraph[graphUUID] = operations;
			}
			
			[operations addObject:operation];
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@: Error executing statement (A): %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
	}
	
	// Step 5 of 7:
	//
	// Order the graphs (per pipeline)
	
	// NSMutableDictionary *graphOrderPerPipeline = [NSMutableDictionary dictionary];
	// NSMutableDictionary *operationsPerPipeline = [NSMutableDictionary dictionary];
	
	[graphOrderPerPipeline enumerateKeysAndObjectsUsingBlock:
	    ^(NSString *pipelineName, NSMutableDictionary *graphOrder, BOOL *stop)
	{
		NSMutableDictionary *operationsPerGraph = operationsPerPipeline[pipelineName];
		
		__block NSUUID *oldestGraphUUID = nil;
		
		[graphOrder enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			
			// key           -> value
			// prevGraphUUID -> graphUUID
			
			__unsafe_unretained id prevGraphUUID = key;
			__unsafe_unretained id graphUUID = value;
			
			if (prevGraphUUID == [NSNull null])
			{
				oldestGraphUUID = (NSUUID *)graphUUID;
				*stop = YES;
			}
			else
			{
				if (operationsPerGraph[prevGraphUUID] == nil)
				{
					// No operations for the referenced prevGraphUUID.
					// This is because we finished that graph, and thus deleted all its operations.
					
					oldestGraphUUID = (NSUUID *)graphUUID;
					*stop = YES;
				}
			}
		}];
		
		NSMutableArray *sortedGraphs = [NSMutableArray arrayWithCapacity:[graphOrder count]];
		
		NSUUID *graphUUID = oldestGraphUUID;
		while (graphUUID)
		{
			NSArray *operations = operationsPerGraph[graphUUID];
			
			YapDatabaseCloudCoreGraph *graph =
			  [[YapDatabaseCloudCoreGraph alloc] initWithUUID:graphUUID operations:operations];
			
			[sortedGraphs addObject:graph];
			
			graphUUID = graphOrder[graphUUID];
		}
		
		sortedGraphsPerPipeline[pipelineName] = sortedGraphs;
	}];
	
	// Step 6 of 7:
	//
	// Restore each operation using the handler
	
	__unsafe_unretained YapDatabaseCloudCoreOptions *options = parentConnection->parent->options;
	
	[sortedGraphsPerPipeline enumerateKeysAndObjectsUsingBlock:
	    ^(NSString *pipelineName, NSArray *sortedGraphs, BOOL *stop)
	{
		for (YapDatabaseCloudCoreGraph *graph in sortedGraphs)
		{
			for (YapDatabaseCloudCoreOperation *operation in graph.operations)
			{
				[operation import:options];
				[operation makeImmutable];
			}
		}
	}];
	
	// Step 7 of 7:
	//
	// Send operations off to pipeline(s)
	
	[parentConnection->parent restorePipelineGraphs:sortedGraphsPerPipeline];
	
	return YES;
}

- (BOOL)populateTables
{
	YDBLogAutoTrace();
	
	void (^ProcessResultsBlock)(int64_t rowid) = ^(int64_t rowid){ @autoreleasepool {
	
		if ([parentConnection->operations_block count] > 0)
		{
			for (YapDatabaseCloudCoreOperation *operation in parentConnection->operations_block)
			{
				[self importOperation:operation withDatabaseRowid:@(rowid) graphIdx:nil];
			}
			
			[parentConnection->operations_block removeAllObjects];
		}
	}};
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	if (handler->blockType == YapDatabaseBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseCloudCoreHandlerWithKeyBlock HandlerBlock =
		                   (YapDatabaseCloudCoreHandlerWithKeyBlock)handler->block;
		
		void (^EnumBlock)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop);
		EnumBlock = ^(int64_t rowid, NSString *collection, NSString *key, BOOL *stop) {
			
			HandlerBlock(databaseTransaction, parentConnection->operations_block, collection, key);
			ProcessResultsBlock(rowid);
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysInCollections:@[ collection ] usingBlock:EnumBlock];
				}
			}];
		}
		else
		{
			[databaseTransaction _enumerateKeysInAllCollectionsUsingBlock:EnumBlock];
		}
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseCloudCoreHandlerWithObjectBlock HandlerBlock =
		                   (YapDatabaseCloudCoreHandlerWithObjectBlock)handler->block;
		
		void (^EnumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop);
		EnumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			HandlerBlock(databaseTransaction, parentConnection->operations_block, collection, key, object);
			ProcessResultsBlock(rowid);
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysAndObjectsInCollections:@[ collection ] usingBlock:EnumBlock];
				}
			}];
		}
		else
		{
			[databaseTransaction _enumerateKeysAndObjectsInAllCollectionsUsingBlock:EnumBlock];
		}
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseCloudCoreHandlerWithMetadataBlock HandlerBlock =
		                   (YapDatabaseCloudCoreHandlerWithMetadataBlock)handler->block;
		
		void (^EnumBlock)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop);
		EnumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			HandlerBlock(databaseTransaction, parentConnection->operations_block, collection, key, metadata);
			ProcessResultsBlock(rowid);
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateKeysAndMetadataInCollections:@[ collection ] usingBlock:EnumBlock];
				}
			}];
		}
		else
		{
			[databaseTransaction _enumerateKeysAndMetadataInAllCollectionsUsingBlock:EnumBlock];
		}
	}
	else
	{
		__unsafe_unretained YapDatabaseCloudCoreHandlerWithRowBlock HandlerBlock =
		                   (YapDatabaseCloudCoreHandlerWithRowBlock)handler->block;
		
		void (^EnumBlock)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop);
		EnumBlock = ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			HandlerBlock(databaseTransaction, parentConnection->operations_block, collection, key, object, metadata);
			ProcessResultsBlock(rowid);
		};
		
		if (allowedCollections)
		{
			[databaseTransaction enumerateCollectionsUsingBlock:^(NSString *collection, BOOL *stop) {
				
				if ([allowedCollections isAllowed:collection])
				{
					[databaseTransaction _enumerateRowsInCollections:@[ collection ] usingBlock:EnumBlock];
				}
			}];
		}
		else
		{
			[databaseTransaction _enumerateRowsInAllCollectionsUsingBlock:EnumBlock];
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	return databaseTransaction;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	return parentConnection;
}

- (NSString *)registeredName
{
	return [parentConnection->parent registeredName];
}

- (NSString *)pipelineTableName
{
	return [parentConnection->parent pipelineTableName];
}

- (NSString *)mappingTableName
{
	return [parentConnection->parent mappingTableName];
}

- (NSString *)queueTableName
{
	return [parentConnection->parent queueTableName];
}

- (NSString *)tagTableName
{
	return [parentConnection->parent tagTableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - serialization & deserialization
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)serializeOperation:(YapDatabaseCloudCoreOperation *)operation
{
	if (operation == nil) return nil;
	
	return parentConnection->parent->operationSerializer(operation);
}

- (YapDatabaseCloudCoreOperation *)deserializeOperation:(NSData *)operationBlob
{
	if (operationBlob.length == 0) return nil;
	
	return parentConnection->parent->operationDeserializer(operationBlob);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - Operations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method sets common properties on an operation, and adds it to the pending array.
**/
- (BOOL)importOperation:(YapDatabaseCloudCoreOperation *)operation
      withDatabaseRowid:(NSNumber *)databaseRowid
               graphIdx:(NSNumber *)graphIdx
{
	__unsafe_unretained YapDatabaseCloudCoreOptions *options = parentConnection->parent->options;
	
	if (![operation import:options])
	{
		YDBLogError(@"Unable to import operation with name (%@). "
		            @"The operation has been imported previously.", operation);
		
		return NO;
	}
	
	// Check to make sure the given pipeline name actually corresponds to a registered pipeline.
	// If not, we need to fallback to the default pipeline.
	//
	// Also we should make sure the pipelineName is standardized.
	// That is, it shouldn't be an alias.
	
	YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:operation.pipeline];
	if (pipeline == nil)
	{
		YDBLogWarn(@"No registered pipeline for name: %@. "
		           @"The operation will be scheduled in the default pipeline.", operation.pipeline);
		
		pipeline = [parentConnection->parent defaultPipeline];
	}
	
	NSString *pipelineName = pipeline.name;
	operation.pipeline = pipelineName; // enforce standardized name (not nil, not alias)
	
	BOOL shouldInsert = NO;
	if (graphIdx)
	{
		if (graphIdx.unsignedIntegerValue < pipeline.graphCount)
		{
			shouldInsert = YES;
		}
	}
	
	if (shouldInsert)
	{
		// Insert operation into existing graph
		
		NSMutableDictionary *graphs = parentConnection->operations_inserted[pipelineName];
		
		if (graphs == nil)
		{
			graphs = [NSMutableDictionary dictionaryWithCapacity:1];
			parentConnection->operations_inserted[pipelineName] = graphs;
		}
		
		NSMutableArray<YapDatabaseCloudCoreOperation *> *insertedOps = graphs[graphIdx];
		
		if (insertedOps == nil)
		{
			insertedOps = [NSMutableArray arrayWithCapacity:1];
			graphs[graphIdx] = insertedOps;
		}
		
		[insertedOps addObject:operation];
	}
	else
	{
		// Add operation to new graph
		
		NSMutableArray<YapDatabaseCloudCoreOperation *> *addedOps = parentConnection->operations_added[pipelineName];
		
		if (addedOps == nil)
		{
			addedOps = [NSMutableArray arrayWithCapacity:1];
			parentConnection->operations_added[pipelineName] = addedOps;
		}
		
		[addedOps addObject:operation];
	}
	
	if (options.enableAttachDetachSupport)
	{
		// Attach: rowid <-> cloudURI (if needed)
		
		if (databaseRowid)
		{
			NSString *attachCloudURI = operation.attachCloudURI;
			if (attachCloudURI)
			{
				[self attachCloudURI:attachCloudURI forRowid:[databaseRowid unsignedLongLongValue]];
			}
		}
	}
	
	// Now that the operation is fully imported, mark it as immutable.
	// This will prevent the user from changing the public properties of the operation instance.
	
	[operation makeImmutable];
	return YES;
}

/**
 * This method peforms the common task of inspecting parentConnection->operations_block,
 * and importing each one.
**/
- (void)importAddedOperations:(int64_t)rowid
{
	if ([parentConnection->operations_block count] > 0)
	{
		__unsafe_unretained NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
		
		for (YapDatabaseCloudCoreOperation *operation in parentConnection->operations_block)
		{
			// Make sure the operation type is allowed (generally enforeced by subclasses)
			if (allowedOperationClasses)
			{
				BOOL allowed = NO;
				for (Class class in allowedOperationClasses)
				{
					if ([operation isKindOfClass:class])
					{
						allowed = YES;
						break;
					}
				}
				
				if (!allowed)
				{
					@throw [self disallowedOperationClass:operation];
				}
			}
			
			// Invoke import hook (performs all required pre-processing of operation)
			[self importOperation:operation withDatabaseRowid:@(rowid) graphIdx:nil];
		}
		
		[parentConnection->operations_block removeAllObjects];
	}
}

/**
 * Subclasses may override this class to properly handle their specific flavor of operations.
 * 
 * The implementation in the base class ONLY handles YapDatabaseCloudCoreFileOperation's and subclasses
 * (such as YapDatabaseCloudCoreRecordOperation).
 * 
 * Thus, if your subclass also supports these operation types, you may wish to invoke the base class implementation.
 * Otherwise, you should completely override it.
**/
- (NSArray *)processOperations:(NSArray *)inOperations
                    inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
                  withGraphIdx:(NSUInteger)operationsGraphIdx
{
	// Filter all operations, except those supported by this method (file ops).
	// Also setup a system to find an operation given a dependency uuid/string/url.
	
	NSUInteger capacity = inOperations.count;
	
	NSMutableArray<YapDatabaseCloudCoreFileOperation *> *operations =
	  [NSMutableArray arrayWithCapacity:capacity];
	
	NSMutableDictionary<NSUUID *, YapDatabaseCloudCoreFileOperation *> *uuidMap =
	  [NSMutableDictionary dictionaryWithCapacity:capacity];
	
	for (YapDatabaseCloudCoreOperation *op in inOperations)
	{
		if (!op.pendingStatusIsCompletedOrSkipped)
		{
			if ([op isKindOfClass:[YapDatabaseCloudCoreFileOperation class]])
			{
				__unsafe_unretained YapDatabaseCloudCoreFileOperation *fileOp = (YapDatabaseCloudCoreFileOperation *)op;
				
				[fileOp clearDependencyUUIDs];
				[operations addObject:fileOp];
				
				uuidMap[fileOp.uuid] = fileOp;
			}
		}
	}
	
	YapDatabaseCloudCoreFileOperation* (^FindOperationForDependency)(id dependency, NSUInteger srcIndex);
	FindOperationForDependency = ^YapDatabaseCloudCoreFileOperation* (id dependency, NSUInteger srcIndex){
		
		if ([dependency isKindOfClass:[NSUUID class]])
		{
			__unsafe_unretained NSUUID *uuid = (NSUUID *)dependency;
			
			YapDatabaseCloudCoreFileOperation *srcOp = operations[srcIndex];
			YapDatabaseCloudCoreFileOperation *dstOp = uuidMap[uuid];
			
			if (srcOp == dstOp) // Op cannot depend on itself.
				return nil;
			else
				return dstOp;
		}
		else
		{
			BOOL (^OperationMatchesDependency)(YapDatabaseCloudCoreFileOperation *op);
			if ([dependency isKindOfClass:[NSString class]])
			{
				OperationMatchesDependency = ^BOOL (YapDatabaseCloudCoreFileOperation *op){
					
					return [op.name isEqualToString:(NSString *)dependency];
				};
			}
			else
			{
				OperationMatchesDependency = ^BOOL (YapDatabaseCloudCoreFileOperation *op){
					
					return NO;
				};
			}
			
			// Search methodology:
			//
			// A 'name' can be ambiguous.
			// That is, it's technically possible to queue multiple operations with the same name (type + cloudPath)
			// within a single transaction.
			//
			// Doing so is obviously discouraged.
			// It adds ambiguity to the upload system, and likely results in excessive bandwidth usage.
			//
			// Further, it's not possible to properly consolidate every possible combination of ambiguity.
			// At least not within the context of a generic cloud framework.
			//
			// Consider the following list of operations:
			// 1. upload X
			// 2. move X -> Y
			// 3. upload X
			// 4. move X -> Y
			//
			// Is this 2 duplicate multi-step ops? (2 upload + move ops)
			// Maybe. But probably not if Y is "/printer/queue".
			// In which case this sequence likely represents the printing of 2 different documents.
			//
			// And herein lies the difficulty of providing a generic framework.
			// There will always be certain trade-offs involved.
			// The principles chosen to navigate these trade-offs are:
			//
			// 1. Strive to achieve flexibility where possible.
			//    This will allow other developers to utilize the framework in ways you'd never considered.
			// 2. Strive to reduce the barrier-to-entry for the average user.
			//    This is done by understanding where/how most developers will use the framework,
			//    and making these common cases easy to use and understand.
			//
			// Now let's re-visit the list of operations from above.
			// What if both move operations have a dependency of "upload X".
			// Obviously this ambiguous name can be matched to 2 different operations.
			// But if we just look at the list it's rather obvious what we should do:
			//
			// - Op#2 depends on Op#1
			// - Op#4 depends on Op#3
			//
			// Recall we also tell users that operation order matters.
			// And that generally (excluding dependencies & priority), operations will be dispatched in the order they
			// were originally given.
			//
			// So our algorithm is:
			// 1. Look for a matching target operation that comes BEFORE source operation.
			//    If multiple, pick the nearest match.
			// 2. Look for a matching target operation that comes AFTER source operation.
			//    If multiple, pick the nearest match.
			
			YapDatabaseCloudCoreFileOperation *match = nil;
			
			for (NSUInteger i = srcIndex; i > 0; i--)
			{
				YapDatabaseCloudCoreFileOperation *op = [operations objectAtIndex:(i - 1)];
				
				if (OperationMatchesDependency(op))
				{
					if (match == nil) {
						match = op;
					}
					else {
						YDBLogWarn(@"Ambiguous dependency! Mutliple matches found for: %@", dependency);
					}
				}
			}
			
			for (NSUInteger i = srcIndex + 1; i < operations.count; i++)
			{
				YapDatabaseCloudCoreFileOperation *op = [operations objectAtIndex:i];
				
				if (OperationMatchesDependency(op))
				{
					if (match == nil) {
						match = op;
					}
					else {
						YDBLogWarn(@"Ambiguous dependency! Mutliple matches found for: %@", dependency);
					}
				}
			}
			
			return match;
		}
	};
	
	// Scan user submitted dependencies
	
	NSUInteger index = 0;
	for (YapDatabaseCloudCoreFileOperation *op in operations)
	{
		for (id dependency in op.dependencies)
		{
			YapDatabaseCloudCoreFileOperation *depOp = FindOperationForDependency(dependency, index);
			if (depOp)
			{
				[op addDependencyUUID:depOp.uuid];
			}
		}
		
		index++;
	}
	
	// Automatically add implicit dependencies & merge operations (if possible)
	
	NSMutableIndexSet *replacedIndex = [NSMutableIndexSet indexSet];
	
	NSMutableArray<NSUUID *> *replacedOpUUID    = [NSMutableArray arrayWithCapacity:1];
	NSMutableArray<NSUUID *> *replacementOpUUID = [NSMutableArray arrayWithCapacity:1];
	
	for (NSUInteger laterIdx = 1; laterIdx < operations.count; laterIdx++)
	{
		YapDatabaseCloudCoreFileOperation *laterOp = operations[laterIdx];
		
		for (NSUInteger earlierIdx = laterIdx; earlierIdx > 0; earlierIdx--)
		{
			YapDatabaseCloudCoreFileOperation *earlierOp = operations[(earlierIdx - 1)];
			
			YDBCloudFileOpProcessResult result = [laterOp processEarlierOperationFromSameTransaction:earlierOp];
			
			if (result == YDBCloudFileOpProcessResult_MergedIntoLater)
			{
				// The 2 operations were merged into 1.
				// They were merged into the laterOp.
				// The laterOp will replace the earlierOp in the finalOpsList.
				
				[replacedIndex addIndex:earlierIdx];
				
				[replacedOpUUID addObject:earlierOp.uuid];
				[replacementOpUUID addObject:laterOp.uuid];
			}
			else if (result == YDBCloudFileOpProcessResult_DependentOnEarlier)
			{
				// The laterOp has an implicit dependency on the earlierOp.
				//
				// First we check to make sure that adding the implicit dependency won't interfere
				// with any other dependency. We do this by checking to see if adding the implicit dependency
				// will create a circular dependency within the graph.
				
				if ([self canAddImplicitDependency:earlierOp forOp:laterOp withOperations:operations])
				{
					[laterOp addDependencyUUID:earlierOp.uuid];
				}
			}
			else if (result == YDBCloudFileOpProcessResult_DependentOnLater)
			{
				// The earlierOp has an implicit dependency on the laterOp.
				//
				// First we check to make sure that adding the implicit dependency won't interfere
				// with any other dependency. We do this by checking to see if adding the implicit dependency
				// will create a circular dependency within the graph.
				
				if ([self canAddImplicitDependency:laterOp forOp:earlierOp withOperations:operations])
				{
					[earlierOp addDependencyUUID:laterOp.uuid];
				}
			}
		}
	}
	
	NSMutableArray *finalOpsList = [NSMutableArray arrayWithCapacity:operations.count];
	
	index = 0;
	for (YapDatabaseCloudCoreFileOperation *op in operations)
	{
		if (![replacedIndex containsIndex:index])
		{
			[finalOpsList addObject:op];
		}
		
		index++;
	}
	
	// Update dependencies.
	// For example:
	//
	// op9.dependencyUUIDs = @[ op1.uuid ] gets changed to
	// op9.dependencyUUIDs = @[ op2.uuid ] (since op2 replaced op1).
	
	for (NSUInteger i = 0; i < replacedOpUUID.count; i++)
	{
		NSUUID *oldUUID = replacedOpUUID[i];
		NSUUID *newUUID = replacementOpUUID[i];
		
		for (YapDatabaseCloudCoreFileOperation *op in finalOpsList)
		{
			[op replaceDependencyUUID:oldUUID with:newUUID];
		}
	}
	
	// Modify previous record operations, as needed.
	
	YDBCloudCore_EnumOps flags = YDBCloudCore_EnumOps_Existing | YDBCloudCore_EnumOps_Inserted;
	
	[self _enumerateOperations:flags
	                inPipeline:pipeline
	                usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if (graphIdx >= operationsGraphIdx)
		{
			*stop = YES;
			return nil;
		}
		
		YapDatabaseCloudCoreOperation *result = nil;
		
		if ([operation isKindOfClass:[YapDatabaseCloudCoreRecordOperation class]])
		{
			YapDatabaseCloudCoreRecordOperation *recordOperation = (YapDatabaseCloudCoreRecordOperation *)operation;
			BOOL wasModified = NO;
			
			for (YapDatabaseCloudCoreFileOperation *newOperation in finalOpsList)
			{
				YapDatabaseCloudCoreRecordOperation *modifiedRecordOperation =
				  [recordOperation updateWithOperationFromLaterTransaction:newOperation];
				
				if (modifiedRecordOperation)
				{
					recordOperation = modifiedRecordOperation;
					wasModified = YES;
				}
			}
			
			if (wasModified)
			{
				recordOperation.needsModifyDatabaseRow = YES;
				result = recordOperation;
			}
		}
		
		return result;
	}];
	
	return finalOpsList;
}

/**
 * Before we add an implicit dependency, we first ensure that doing so won't invalidate any explicit dependencies.
 * We do this by ensuring that the addition of the implicit dependency won't create a circular dependency in the graph.
**/
- (BOOL)canAddImplicitDependency:(YapDatabaseCloudCoreFileOperation *)opA
                           forOp:(YapDatabaseCloudCoreFileOperation *)opB
                   withOperations:(NSArray *)operations
{
	// We want to add an implicit dependency such that opB will depend upon opA. (opA must go first).
	// But we obviously can't do this if opA already depends upon opB.
	// Or else we'd end up with a circular dependency.
	//
	// So we verify that opA does NOT already depend upon opB.
	
	NSMutableSet *visitedOps = [NSMutableSet setWithCapacity:operations.count];
	[visitedOps addObject:opB.uuid];
	
	if ([self hasCircularDependency:opA withOperations:operations visitedOps:visitedOps])
		return NO;
	else
		return YES;
}

- (BOOL)hasCircularDependency:(YapDatabaseCloudCoreOperation *)op
               withOperations:(NSArray *)operations
                   visitedOps:(NSMutableSet<NSUUID *> *)visitedOps
{
	YapDatabaseCloudCoreOperation* (^OperationWithUUID)(NSUUID *opUUID);
	OperationWithUUID = ^YapDatabaseCloudCoreOperation *(NSUUID *opUUID)
	{
		for (YapDatabaseCloudCoreOperation *op in operations)
		{
			if ([op.uuid isEqual:opUUID])
			{
				return op;
			}
		}
		
		return nil;
	};
	
	if ([visitedOps containsObject:op.uuid])
	{
		return YES;
	}
	else
	{
		BOOL result = NO;
		
		[visitedOps addObject:op.uuid];
		
		for (NSUUID *depUUID in op.dependencyUUIDs)
		{
			YapDatabaseCloudCoreOperation *depOp = OperationWithUUID(depUUID);
			if (depOp)
			{
				if ([self hasCircularDependency:depOp withOperations:operations visitedOps:visitedOps])
				{
					result = YES;
					break;
				}
			}
		}
		
		[visitedOps removeObject:op.uuid];
		
		return result;
	}
}

/**
 * Subclasses may override this class to properly handle their specific flavor of operation.
 * 
 * Subclasses should invoke [super didCompleteOperation:operation].
**/
- (void)didCompleteOperation:(YapDatabaseCloudCoreOperation *)operation
{
	if (parentConnection->parent->options.enableTagSupport)
	{
		if ([operation isKindOfClass:[YapDatabaseCloudCoreFileOperation class]])
		{
			__unsafe_unretained YapDatabaseCloudCoreFileOperation *fileOperation =
			                   (YapDatabaseCloudCoreFileOperation *)operation;
			
			if (fileOperation.isDeleteOperation)
			{
				[self removeAllTagsForCloudURI:fileOperation.cloudPath.path];
			}
		}
	}
}

/**
 * Subclasses may override this class to properly handle their specific flavor of operation.
 * 
 * Subclasses should invoke [super didSkipOperation:operation].
**/
- (void)didSkipOperation:(YapDatabaseCloudCoreOperation *)operation
{
	// Nothing to do here.
}

/**
 * Helper method to add a modified operation to the list.
**/
- (void)addModifiedOperation:(YapDatabaseCloudCoreOperation *)modifiedOp
{
	NSParameterAssert(modifiedOp != nil);
	
	// First, we make the modifiedOp immutable.
	// It's either this, or we'd need to make our own copy.
	
	[modifiedOp makeImmutable];
	
	// Then find the originalOp & replace it.
	
	NSUUID *uuid = modifiedOp.uuid;
	
	__block BOOL found = NO;
	__block NSUInteger foundIdx = 0;
	
	[parentConnection->operations_added enumerateKeysAndObjectsUsingBlock:
	  ^(NSString *pipelineName, NSMutableArray<YapDatabaseCloudCoreOperation *> *operations, BOOL *stop)
	{
		NSUInteger idx = 0;
		for (YapDatabaseCloudCoreOperation *op in operations)
		{
			if ([op.uuid isEqual:uuid])
			{
				found = YES;
				foundIdx = idx;
				
				*stop = YES;
				break;
			}
		}
		
		if (found)
		{
			[operations replaceObjectAtIndex:foundIdx withObject:modifiedOp];
		}
	}];
	
	if (found) return;
	
	[parentConnection->operations_inserted enumerateKeysAndObjectsUsingBlock:
	  ^(NSString *pipelineName, NSMutableDictionary *graphs, BOOL *outerStop)
	{
		[graphs enumerateKeysAndObjectsUsingBlock:
		  ^(NSNumber *graphIdx, NSMutableArray<YapDatabaseCloudCoreOperation *> *operations, BOOL *innerStop)
		{
			NSUInteger idx = 0;
			for (YapDatabaseCloudCoreOperation *op in operations)
			{
				if ([op.uuid isEqual:uuid])
				{
					found = YES;
					foundIdx = idx;
					
					*innerStop = YES;
					*outerStop = YES;
					break;
				}
			}
			
			if (found)
			{
				[operations replaceObjectAtIndex:foundIdx withObject:modifiedOp];
			}
		}];
	}];
	
	if (found) return;
	
	parentConnection->operations_modified[modifiedOp.uuid] = modifiedOp;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - queue
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)queueTable_insertOperations:(NSArray *)operations
                      withGraphUUID:(NSUUID *)graphUUID
                      prevGraphUUID:(NSUUID *)prevGraphUUID
                           pipeline:(YapDatabaseCloudCorePipeline *)pipeline
{
	YDBLogAutoTrace();
	
	if (operations.count == 0) return;
	
	sqlite3_stmt *statement = [parentConnection queueTable_insertStatement];
	if (statement == NULL) {
		return;
	}
	
	// INSERT INTO "queueTableName"
	//   ("pipelineID",
	//    "graphID",
	//    "prevGraphID",
	//    "operation")
	//   VALUES (?, ?, ?, ?);
	
	int const bind_idx_pipelineID     = SQLITE_BIND_START + 0; // INTEGER
	int const bind_idx_graphID        = SQLITE_BIND_START + 1; // BLOB NOT NULL
	int const bind_idx_prevGraphID    = SQLITE_BIND_START + 2; // BLOB
	int const bind_idx_operation      = SQLITE_BIND_START + 3; // BLOB
	
	
	BOOL needsBindPipelineRowid = ![pipeline.name isEqualToString:YapDatabaseCloudCoreDefaultPipelineName];
	
	NSAssert(sizeof(uuid_t) == 16, @"C is hard ???");
	
	uuid_t graphID;
	[graphUUID getUUIDBytes:graphID];
	
	uuid_t prevGraphID;
	[prevGraphUUID getUUIDBytes:prevGraphID];
	
	for (YapDatabaseCloudCoreOperation *operation in operations)
	{
		// pipelineID
		
		if (needsBindPipelineRowid)
		{
			sqlite3_bind_int64(statement, bind_idx_pipelineID, pipeline.rowid);
		}
		
		// graphID
		
		sqlite3_bind_blob(statement, bind_idx_graphID, graphID, sizeof(uuid_t), SQLITE_STATIC);
		
		// prevGraphID
		
		if (prevGraphUUID) {
			sqlite3_bind_blob(statement, bind_idx_prevGraphID, prevGraphID, sizeof(uuid_t), SQLITE_STATIC);
		}
		
		// operation
		
		__attribute__((objc_precise_lifetime)) NSData *operationBlob = [self serializeOperation:operation];
		
		sqlite3_bind_blob(statement, bind_idx_operation, operationBlob.bytes, (int)operationBlob.length, SQLITE_STATIC);
		
	
		int status = sqlite3_step(statement);
		if (status == SQLITE_DONE)
		{
			int64_t opRowid = sqlite3_last_insert_rowid(databaseTransaction->connection->db);
			operation.operationRowid = opRowid;
		}
		else
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
	
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
}

- (void)queueTable_modifyOperation:(YapDatabaseCloudCoreOperation *)operation
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection queueTable_modifyStatement];
	if (statement == NULL) {
		return;
	}
	
	// UPDATE "queueTableName" SET "operation" = ? WHERE "rowid" = ?;

	int const bind_idx_operation = SQLITE_BIND_START + 0;
	int const bind_idx_rowid     = SQLITE_BIND_START + 1;
	
	__attribute__((objc_precise_lifetime)) NSData *operationBlob = [self serializeOperation:operation];
	sqlite3_bind_blob(statement, bind_idx_operation, operationBlob.bytes, (int)operationBlob.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, bind_idx_rowid, operation.operationRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

- (void)queueTable_removeRowWithRowid:(int64_t)operationRowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection queueTable_removeStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "queueTableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, SQLITE_BIND_START, operationRowid);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

- (void)queueTable_removeAllRows
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection queueTable_removeAllStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "queueTableName";
	
	YDBLogVerbose(@"Deleting all rows from queue table...");
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - mappings
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSSet *)allAttachedCloudURIsForRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection mappingTable_fetchForRowidStatement];
	if (statement == NULL) {
		return nil;
	}
	
	NSMutableSet *attachedCloudURIs = [NSMutableSet setWithCapacity:1];
	
	// SELECT "cloudURI" FROM "mappingTableName" WHERE "database_rowid" = ?;
	
	const int column_idx_clouduri = SQLITE_COLUMN_START;
	const int bind_idx_rowid = SQLITE_BIND_START;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, column_idx_clouduri);
		int textSize = sqlite3_column_bytes(statement, column_idx_clouduri);
		
		NSString *cloudURI = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		if (cloudURI)
		{
			[attachedCloudURIs addObject:cloudURI];
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	[parentConnection->dirtyMappingInfo enumerateValuesForKey:@(rowid) withBlock:
	    ^(NSString *cloudURI, id metadata, BOOL *stop)
	{
		if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsInsert)
		{
			[attachedCloudURIs addObject:cloudURI];
		}
		else if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsRemove)
		{
			[attachedCloudURIs removeObject:cloudURI];
		}
	}];
	
	return attachedCloudURIs;
}

- (NSSet *)allAttachedRowidsForCloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection mappingTable_fetchForCloudURIStatement];
	if (statement == NULL) {
		return nil;
	}
	
	NSMutableSet *attachedRowids = [NSMutableSet setWithCapacity:1];
	
	// SELECT "database_rowid" FROM "mappingTableName" WHERE "cloudURI" = ?;
	
	int const column_idx_rowid = SQLITE_COLUMN_START;
	int const bind_idx_identifier = SQLITE_BIND_START;
	
	YapDatabaseString _cloudURI; MakeYapDatabaseString(&_cloudURI, cloudURI);
	sqlite3_bind_text(statement, bind_idx_identifier, _cloudURI.str, _cloudURI.length, SQLITE_STATIC);
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t databaseRowid = sqlite3_column_int64(statement, column_idx_rowid);
		
		[attachedRowids addObject:@(databaseRowid)];
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_cloudURI);
	
	[parentConnection->dirtyMappingInfo enumerateKeysForValue:cloudURI withBlock:
	    ^(NSNumber *rowid, id metadata, BOOL *stop)
	{
		if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsInsert)
		{
			[attachedRowids addObject:rowid];
		}
		else if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsRemove)
		{
			[attachedRowids removeObject:rowid];
		}
	}];
	
	return attachedRowids;
}

- (BOOL)containsMappingWithRowid:(int64_t)rowid cloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	// Check dirtyMappingInfo
	
	NSString *metadata = [parentConnection->dirtyMappingInfo metadataForKey:@(rowid) value:cloudURI];
	if (metadata)
	{
		if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsInsert)
			return YES;
		
		if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsRemove)
			return NO;
	}
	
	// Check cleanMappingCache
	
	if ([parentConnection->cleanMappingCache containsKey:@(rowid) value:cloudURI])
	{
		return YES;
	}
	
	// Query database
	
	sqlite3_stmt *statement = [parentConnection mappingTable_fetchStatement];
	if (statement == NULL) {
		return NO;
	}
	
	// SELECT COUNT(*) AS NumberOfRows FROM "mappingTableName" WHERE "database_rowid" = ? AND "cloudURI" = ?;
	
	const int column_idx_count = SQLITE_COLUMN_START;
	
	const int bind_idx_rowid    = SQLITE_BIND_START + 0;
	const int bind_idx_clouduri = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	YapDatabaseString _cloudURI; MakeYapDatabaseString(&_cloudURI, cloudURI);
	sqlite3_bind_text(statement, bind_idx_clouduri, _cloudURI.str, _cloudURI.length, SQLITE_STATIC);
	
	int64_t count = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		count = sqlite3_column_int64(statement, column_idx_count);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_cloudURI);
	
	if (count > 0)
	{
		// Add to cache
		[parentConnection->cleanMappingCache insertKey:@(rowid) value:cloudURI];
		
		return YES;
	}
	else
	{
		return NO;
	}
}

- (void)attachCloudURI:(NSString *)cloudURI forRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	if (![self containsMappingWithRowid:rowid cloudURI:cloudURI])
	{
		[parentConnection->dirtyMappingInfo insertKey:@(rowid)
		                                        value:cloudURI
		                                     metadata:YDBCloudCore_DiryMappingMetadata_NeedsInsert];
	}
}

- (void)detachCloudURI:(NSString *)cloudURI forRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	if ([self containsMappingWithRowid:rowid cloudURI:cloudURI])
	{
		[parentConnection->cleanMappingCache removeItemWithKey:@(rowid) value:cloudURI];
		
		[parentConnection->dirtyMappingInfo insertKey:@(rowid)
		                                        value:cloudURI
		                                     metadata:YDBCloudCore_DiryMappingMetadata_NeedsRemove];
	}
}

- (void)mappingTable_insertRowWithRowid:(int64_t)rowid cloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection mappingTable_insertStatement];
	if (statement == NULL) {
		return; // from_block
	}
	
	// INSERT OR REPLACE INTO "mappingTableName" ("database_rowid", "cloudURI") VALUES (?, ?);
	
	const int bind_idx_rowid    = SQLITE_BIND_START + 0;
	const int bind_idx_clouduri = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	YapDatabaseString _cloudURI; MakeYapDatabaseString(&_cloudURI, cloudURI);
	sqlite3_bind_text(statement, bind_idx_clouduri, _cloudURI.str, _cloudURI.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_cloudURI);
}

- (void)mappingTable_removeRowWithRowid:(int64_t)rowid cloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection mappingTable_removeStatement];
	if (statement == NULL) {
		return; // from_block
	}
	
	// DELETE FROM "mappingTableName" WHERE "database_rowid" = ? AND "cloudURI" = ?;
	
	const int bind_idx_rowid    = SQLITE_BIND_START + 0;
	const int bind_idx_clouduri = SQLITE_BIND_START + 1;
	
	sqlite3_bind_int64(statement, bind_idx_rowid, rowid);
	
	YapDatabaseString _cloudURI; MakeYapDatabaseString(&_cloudURI, cloudURI);
	sqlite3_bind_text(statement, bind_idx_clouduri, _cloudURI.str, _cloudURI.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_cloudURI);
}

- (void)mappingTable_removeAllRows
{
	YDBLogAutoTrace();
	
	NSAssert(parentConnection->parent->options.enableAttachDetachSupport,
	         @"YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection mappingTable_removeAllStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "mappingTableName";
	
	YDBLogVerbose(@"Deleting all rows from mapping table...");
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - tag
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tagTable_insertOrUpdateRowWithCloudURI:(NSString *)cloudURI
                                    identifier:(NSString *)identifier
                                           tag:(id)tag
{
	NSParameterAssert(cloudURI != nil);
	NSParameterAssert(identifier != nil);
	NSParameterAssert(tag != nil);
	
	NSAssert(parentConnection->parent->options.enableTagSupport, @"YapDatabaseCloudCoreOptions.enableTagSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection tagTable_setStatement];
	if (statement == NULL) {
		return;
	}
	
	// INSERT OR REPLACE INTO "changeTagTableName" ("cloudURI", "identifier", "changeTag") VALUES (?, ?, ?);
	
	int const bind_idx_cloudURI   = SQLITE_BIND_START + 0;
	int const bind_idx_identifier = SQLITE_BIND_START + 1;
	int const bind_idx_changeTag  = SQLITE_BIND_START + 2;
	
	YapDatabaseString _uri; MakeYapDatabaseString(&_uri, cloudURI);
	sqlite3_bind_text(statement, bind_idx_cloudURI, _uri.str, _uri.length, SQLITE_STATIC);
	
	YapDatabaseString _identifier; MakeYapDatabaseString(&_identifier, identifier);
	sqlite3_bind_text(statement, bind_idx_identifier, _identifier.str, _identifier.length, SQLITE_STATIC);
	
	if ([tag isKindOfClass:[NSNumber class]])
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)tag;
		
		CFNumberType numberType = CFNumberGetType((CFNumberRef)number);
		
		if (numberType == kCFNumberFloat32Type ||
			numberType == kCFNumberFloat64Type ||
			numberType == kCFNumberFloatType   ||
			numberType == kCFNumberDoubleType  ||
			numberType == kCFNumberCGFloatType  )
		{
			double value = [number doubleValue];
			sqlite3_bind_double(statement, bind_idx_changeTag, value);
		}
		else
		{
			int64_t value = [number longLongValue];
			sqlite3_bind_int64(statement, bind_idx_changeTag, value);
		}
	}
	else if ([tag isKindOfClass:[NSString class]])
	{
		__unsafe_unretained NSString *string = (NSString *)tag;
		
		sqlite3_bind_text(statement, bind_idx_changeTag, [string UTF8String], -1, SQLITE_TRANSIENT);
	}
	else if ([tag isKindOfClass:[NSData class]])
	{
		__unsafe_unretained NSData *data = (NSData *)tag;
		
		sqlite3_bind_blob(statement, bind_idx_changeTag, [data bytes], (int)data.length, SQLITE_STATIC);
	}
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uri);
	FreeYapDatabaseString(&_identifier);
}

- (void)tagTable_removeRowWithCloudURI:(NSString *)cloudURI identifier:(NSString *)identifier
{
	NSParameterAssert(cloudURI != nil);
	NSParameterAssert(identifier != nil);
	
	NSAssert(parentConnection->parent->options.enableTagSupport, @"YapDatabaseCloudCoreOptions.enableTagSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection tagTable_removeForBothStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "tagTableName" WHERE "cloudURI" = ? AND "identifier" = ?;
	
	int const bind_idx_cloudURI   = SQLITE_BIND_START + 0;
	int const bind_idx_identifier = SQLITE_BIND_START + 1;
	
	YapDatabaseString _uri; MakeYapDatabaseString(&_uri, cloudURI);
	sqlite3_bind_text(statement, bind_idx_cloudURI, _uri.str, _uri.length, SQLITE_STATIC);
	
	YapDatabaseString _identifier; MakeYapDatabaseString(&_identifier, identifier);
	sqlite3_bind_text(statement, bind_idx_identifier, _identifier.str, _identifier.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uri);
	FreeYapDatabaseString(&_identifier);
}

- (void)tagTable_removeRowsWithCloudURI:(NSString *)cloudURI
{
	NSParameterAssert(cloudURI != nil);
	
	NSAssert(parentConnection->parent->options.enableTagSupport, @"YapDatabaseCloudCoreOptions.enableTagSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection tagTable_removeForCloudURIStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "tagTableName" WHERE "cloudURI" = ?;
	
	int const bind_idx_cloudURI   = SQLITE_BIND_START;

	YapDatabaseString _uri; MakeYapDatabaseString(&_uri, cloudURI);
	sqlite3_bind_text(statement, bind_idx_cloudURI, _uri.str, _uri.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uri);
}

- (void)tagTable_removeAllRows
{
	YDBLogAutoTrace();
	
	NSAssert(parentConnection->parent->options.enableTagSupport, @"YapDatabaseCloudCoreOptions.enableTagSupport == NO");
	
	sqlite3_stmt *statement = [parentConnection tagTable_removeAllStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "tagTableName";
	
	YDBLogVerbose(@"Deleting all rows from tag table...");
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal helper method for other handleX methods.
**/
- (void)_handleChangeWithRowid:(int64_t)rowid
                 collectionKey:(YapCollectionKey *)ck
                        object:(id)object
                      metadata:(id)metadata
{
	YDBLogAutoTrace();
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	if (handler->blockType == YapDatabaseBlockTypeWithKey)
	{
		YapDatabaseCloudCoreHandlerWithKeyBlock block =
		  (YapDatabaseCloudCoreHandlerWithKeyBlock)handler->block;
		
		block(databaseTransaction, parentConnection->operations_block, ck.collection, ck.key);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithObject)
	{
		YapDatabaseCloudCoreHandlerWithObjectBlock block =
		  (YapDatabaseCloudCoreHandlerWithObjectBlock)handler->block;
		
		block(databaseTransaction, parentConnection->operations_block, ck.collection, ck.key, object);
	}
	else if (handler->blockType == YapDatabaseBlockTypeWithMetadata)
	{
		YapDatabaseCloudCoreHandlerWithMetadataBlock block =
		  (YapDatabaseCloudCoreHandlerWithMetadataBlock)handler->block;
		
		block(databaseTransaction, parentConnection->operations_block, ck.collection, ck.key, metadata);
	}
	else
	{
		YapDatabaseCloudCoreHandlerWithRowBlock block =
		  (YapDatabaseCloudCoreHandlerWithRowBlock)handler->block;
		
		block(databaseTransaction, parentConnection->operations_block, ck.collection, ck.key, object, metadata);
	}
	
	if ([parentConnection->operations_block count] > 0)
	{
		NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
		
		for (YapDatabaseCloudCoreOperation *operation in parentConnection->operations_block)
		{
			// Make sure the operation type is allowed (generally enforeced by subclasses)
			if (allowedOperationClasses)
			{
				BOOL allowed = NO;
				for (Class class in allowedOperationClasses)
				{
					if ([operation isKindOfClass:class])
					{
						allowed = YES;
						break;
					}
				}
				
				if (!allowed)
				{
					@throw [self disallowedOperationClass:operation];
				}
			}
			
			// Invoke import hook (performs all required pre-processing of operation)
			[self importOperation:operation withDatabaseRowid:@(rowid) graphIdx:nil];
		}
		
		[parentConnection->operations_block removeAllObjects];
	}
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being inserted, meaning there is not currently an entry for the collection/key tuple.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Check for pending attach request
	
	if ([parentConnection->pendingAttachRequests containsKey:collectionKey])
	{
		[parentConnection->pendingAttachRequests enumerateValuesForKey:collectionKey withBlock:
		    ^(NSString *cloudURI, id metadata, BOOL *stop)
		{
			[self attachCloudURI:cloudURI forRowid:rowid];
		}];
		
		[parentConnection->pendingAttachRequests removeAllItemsWithKey:collectionKey];
		
		return;
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being modified, meaning there is already an entry for the collection/key tuple which is being modified.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectModified |
	                                            YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
 *
 * There is already a row for the collection/key tuple, and only the object is being modified (metadata untouched).
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
 *
 * There is already a row for the collection/key tuple, and only the metadata is being modified (object untouched).
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfMetadataModified;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)handleTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained YapDatabaseCloudCoreHandler *handler = parentConnection->parent->handler;
	
	YapDatabaseBlockInvoke blockInvokeBitmask = YapDatabaseBlockInvokeIfObjectTouched |
	                                            YapDatabaseBlockInvokeIfMetadataTouched;
	
	if (!(handler->blockInvokeOptions & blockInvokeBitmask)) return;
	
	id object = nil;
	if (handler->blockType & YapDatabaseBlockType_ObjectFlag)
	{
		object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
	}
	
	id metadata = nil;
	if (handler->blockType & YapDatabaseBlockType_MetadataFlag)
	{
		metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
	}
	
	[self _handleChangeWithRowid:rowid
	               collectionKey:collectionKey
	                      object:object
	                    metadata:metadata];
}



/**
 * Extensions may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
**/
- (void)handleWillRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	// Update mappings (attach / detach stuff).
	//
	// Note: We do this before invoking the delete handler.
	// This way, should the delete handler query the attach/detach system, it will produce the expected results
	// (with the deleted item deleted from the mappings system).
	
	NSMutableDictionary<NSString *, NSNumber *> *mappings = nil;
	
	__unsafe_unretained YapDatabaseCloudCoreOptions *options = parentConnection->parent->options;
	if (options.enableAttachDetachSupport)
	{
		// Detach all (rowid <-> cloudURI) mappings
		
		NSSet *attachedCloudURIs = [self allAttachedCloudURIsForRowid:rowid];
		
		for (NSString *cloudURI in attachedCloudURIs)
		{
			[self detachCloudURI:cloudURI forRowid:rowid];
		}
		
		// See if we need to automatically generate a deleteOperation
		
		mappings = [NSMutableDictionary dictionaryWithCapacity:[attachedCloudURIs count]];
		
		for (NSString *cloudURI in attachedCloudURIs)
		{
			NSUInteger retainCount = [[self allAttachedRowidsForCloudURI:cloudURI] count];
			
			mappings[cloudURI] = @(retainCount);
		}
	}
	
	// Invoke DeleteHandler (if installed)
	
	__unsafe_unretained YapDatabaseCloudCoreDeleteHandler *deleteHandler = parentConnection->parent->deleteHandler;
	if (deleteHandler)
	{
		if (deleteHandler->blockType == YapDatabaseBlockTypeWithKey)
		{
			YapDatabaseCloudCoreDeleteHandlerWithKeyBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)deleteHandler->block;
			
			block(databaseTransaction, parentConnection->operations_block, mappings, ck.collection, ck.key);
		}
		else if (deleteHandler->blockType == YapDatabaseBlockTypeWithObject)
		{
			YapDatabaseCloudCoreDeleteHandlerWithObjectBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)deleteHandler->block;
			
			id object = [databaseTransaction objectForCollectionKey:ck withRowid:rowid];
			
			block(databaseTransaction, parentConnection->operations_block, mappings, ck.collection, ck.key, object);
		}
		else if (deleteHandler->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)deleteHandler->block;
			
			id metadata = [databaseTransaction metadataForCollectionKey:ck withRowid:rowid];
			
			block(databaseTransaction, parentConnection->operations_block, mappings, ck.collection, ck.key, metadata);
		}
		else
		{
			YapDatabaseCloudCoreDeleteHandlerWithRowBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithRowBlock)deleteHandler->block;
			
			id object = nil;
			id metadata = nil;
			[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
			block(databaseTransaction, parentConnection->operations_block, mappings,
			      ck.collection, ck.key, object, metadata);
		}
		
		[self importAddedOperations:rowid];
	}
}

/**
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	// We do everyting in the pre-hook. (^^ the above method ^^)
	//
	// @see handleWillRemoveObjectForCollectionKey:withRowid:
}

/**
 * Extensions may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
 *
 * IMPORTANT:
 *   The number of items passed to this method has the following guarantee:
 *   count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
 *
 * The YapDatabaseReadWriteTransaction will inspect the list of keys that are to be removed,
 * and then loop over them in "chunks" which are readily processable for extensions.
**/
- (void)handleWillRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Update mappings (attach / detach stuff).
	//
	// Note: We do this before invoking the delete handler.
	// This way, should the delete handler query the attach/detach system, it will produce the expected results
	// (with the deleted item deleted from the mappings system).
	
	NSMutableDictionary<NSString *, NSNumber *> *mappings = nil;
	
	__unsafe_unretained YapDatabaseCloudCoreOptions *options = parentConnection->parent->options;
	if (options.enableAttachDetachSupport)
	{
		// Detach all (rowid <-> cloudURI) mappings
		
		for (NSNumber *rowidNum in rowids)
		{
			int64_t rowid = [rowidNum unsignedLongLongValue];
			
			NSSet *attachedCloudURIs = [self allAttachedCloudURIsForRowid:rowid];
			
			for (NSString *cloudURI in attachedCloudURIs)
			{
				[self detachCloudURI:cloudURI forRowid:rowid];
			}
			
			// See if we need to automatically generate a deleteOperation
			
			mappings = [NSMutableDictionary dictionaryWithCapacity:[attachedCloudURIs count]];
			
			for (NSString *cloudURI in attachedCloudURIs)
			{
				NSUInteger retainCount = [[self allAttachedRowidsForCloudURI:cloudURI] count];
				
				mappings[cloudURI] = @(retainCount);
			}
		}
	}
	
	// Invoke DeleteHandler (if installed)
	
	__unsafe_unretained YapDatabaseCloudCoreDeleteHandler *deleteHandler = parentConnection->parent->deleteHandler;
	if (deleteHandler)
	{
		void (^InvokeDeleteHandlerBlock)(NSString *key, int64_t rowid);
		
		if (deleteHandler->blockType == YapDatabaseBlockTypeWithKey)
		{
			__unsafe_unretained YapDatabaseCloudCoreDeleteHandlerWithKeyBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)deleteHandler->block;
			
			InvokeDeleteHandlerBlock = ^(NSString *key, int64_t rowid){
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key);
			};
		}
		else if (deleteHandler->blockType == YapDatabaseBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseCloudCoreDeleteHandlerWithObjectBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)deleteHandler->block;
			
			InvokeDeleteHandlerBlock = ^(NSString *key, int64_t rowid){
				
				id object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, object);
			};
		}
		else if (deleteHandler->blockType == YapDatabaseBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)deleteHandler->block;
			
			InvokeDeleteHandlerBlock = ^(NSString *key, int64_t rowid){
				
				id metadata = [databaseTransaction metadataForKey:key inCollection:collection withRowid:rowid];
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, metadata);
			};
		}
		else
		{
			__unsafe_unretained YapDatabaseCloudCoreDeleteHandlerWithRowBlock block =
			  (YapDatabaseCloudCoreDeleteHandlerWithRowBlock)deleteHandler->block;
			
			InvokeDeleteHandlerBlock = ^(NSString *key, int64_t rowid){
				
				YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = nil;
				id metadata = nil;
				[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
			
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, object, metadata);
			};
		}
		
		NSUInteger count = keys.count;
		for (NSUInteger i = 0; i < count; i++)
		{
			NSString *key = keys[i];
			int64_t rowid = [rowids[i] longLongValue];
			
			InvokeDeleteHandlerBlock(key, rowid);
			
			[self importAddedOperations:rowid];
		}
	
	} // end: if (deleteHandler)
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	// We do everyting in the pre-hook. (^^ the above method ^^)
	//
	// @see handleWillRemoveObjectsForKeys:inCollection:withRowids:
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self queueTable_removeAllRows];
	if (parentConnection->parent->options.enableAttachDetachSupport) {
		[self mappingTable_removeAllRows];
	}
	if (parentConnection->parent->options.enableTagSupport) {
		[self tagTable_removeAllRows];
	}
	
	[parentConnection->pendingAttachRequests removeAllItems];
	
	[parentConnection->operations_added removeAllObjects];
	[parentConnection->operations_inserted removeAllObjects];
	[parentConnection->operations_modified removeAllObjects];
	
	[parentConnection->cleanMappingCache removeAllItems];
	[parentConnection->dirtyMappingInfo removeAllItems];
	
	[parentConnection->tagCache removeAllObjects];
	[parentConnection->dirtyTags removeAllObjects];
	
	parentConnection->reset = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Handling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Allows you to queue an operation to be executed automatically by the appropriate pipeline.
 * This may be used as an alternative to creating an operation from within the YapDatabaseCloudCoreHandler.
 *
 * @param operation
 *   The operation to be added to the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be added to a new graph for the current commit.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)addOperation:(YapDatabaseCloudCoreOperation *)operation
{
	return [self addOperation:operation forKey:nil inCollection:nil];
}

/**
 * Allows you to queue an operation to be executed automatically by the appropriate pipeline.
 * This may be used as an alternative to creating an operation from within the YapDatabaseCloudCoreHandler.
 *
 * @param operation
 *   The operation to be added to the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be added to a new graph for the current commit.
 *
 * @param key
 *   Optional key of a row in YapDatabase.
 *   This is only used if attach/detach support is enabled.
 *
 * @param collection
 *   Optional collection of the row in YapDatabase.
 *   This is only used if attach/detach support is enabled.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)addOperation:(YapDatabaseCloudCoreOperation *)operation
              forKey:(NSString *)key
        inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return NO;
	}
	
	// Sanity checks
	
	if (operation == nil) return NO;
	
	NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
	if (allowedOperationClasses)
	{
		BOOL allowed = NO;
		for (Class class in allowedOperationClasses)
		{
			if ([operation isKindOfClass:class])
			{
				allowed = YES;
				break;
			}
		}
		
		if (!allowed)
		{
			@throw [self disallowedOperationClass:operation];
			return NO;
		}
	}
	
	// Lookup rowid for key/collection (if given)
	
	NSNumber *rowidNum = nil;
	if (key)
	{
		int64_t rowid = 0;
		if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
		{
			// collection/key tuple doesn't exist in database
			return NO;
		}
		
		rowidNum = @(rowid);
	}
	
	// Standard import logic
	
	return [self importOperation:operation withDatabaseRowid:rowidNum graphIdx:nil];
}

/**
 * Allows you to insert an operation into an existing graph.
 *
 * For example, say an operation in the currently executing graph (graphIdx = 0) fails due to some conflict.
 * And to resolve the conflict you need to:
 * - execute a different (new operation)
 * - and then re-try the failed operation
 *
 * What you can do is create & insert the new operation (into graphIdx zero).
 * And modify the old operation to depend on the new operation (@see 'modifyOperation').
 *
 * The dependency graph will automatically be recalculated using the inserted operation.
 *
 * @param operation
 *   The operation to be inserted into the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be inserted into the graph corresponding to the graphIdx parameter.
 *
 * @param graphIdx
 *   The graph index for the corresponding pipeline.
 *   The currently executing graph index is always zero, which is the most common value.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)insertOperation:(YapDatabaseCloudCoreOperation *)operation inGraph:(NSInteger)graphIdx
{
	return [self insertOperation:operation inGraph:graphIdx forKey:nil inCollection:nil];
}

/**
 * Allows you to insert an operation into an existing graph.
 *
 * For example, say an operation in the currently executing graph (graphIdx = 0) fails due to some conflict.
 * And to resolve the conflict you need to:
 * - execute a different (new operation)
 * - and then re-try the failed operation
 * 
 * What you can do is create & insert the new operation (into graphIdx zero).
 * And modify the old operation to depend on the new operation (@see 'modifyOperation').
 *
 * The dependency graph will automatically be recalculated using the inserted operation.
 *
 * @param operation
 *   The operation to be inserted into the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be inserted into the graph corresponding to the graphIdx parameter.
 * 
 * @param graphIdx
 *   The graph index for the corresponding pipeline.
 *   The currently executing graph index is always zero, which is the most common value.
 *
 * @param key
 *   Optional key of a row in YapDatabase.
 *   This is only used if attach/detach support is enabled.
 *
 * @param collection
 *   Optional collection of the row in YapDatabase.
 *   This is only used if attach/detach support is enabled.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)insertOperation:(YapDatabaseCloudCoreOperation *)operation
                inGraph:(NSUInteger)graphIdx
                 forKey:(NSString *)key
           inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return NO;
	}
	
	// Sanity checks
	
	if (operation == nil) return NO;
	
	NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
	if (allowedOperationClasses)
	{
		BOOL allowed = NO;
		for (Class class in allowedOperationClasses)
		{
			if ([operation isKindOfClass:class])
			{
				allowed = YES;
				break;
			}
		}
		
		if (!allowed)
		{
			@throw [self disallowedOperationClass:operation];
			return NO;
		}
	}
	
	if ([self operationWithUUID:operation.uuid inPipeline:operation.pipeline] != nil)
	{
		// The operation already exists.
		// Did you mean to use the 'modifyOperation' method?
		return NO;
	}
	
	// Lookup rowid for key/collection (if given)
	
	NSNumber *rowidNum = nil;
	if (key)
	{
		int64_t rowid = 0;
		if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
		{
			// collection/key tuple doesn't exist in database
			return NO;
		}
		
		rowidNum = @(rowid);
	}
	
	// Standard insert logic
	
	return [self importOperation:operation withDatabaseRowid:rowidNum graphIdx:@(graphIdx)];
}

/**
 * Replaces the existing operation with the new version.
 *
 * The dependency graph will automatically be recalculated using the new operation version.
**/
- (BOOL)modifyOperation:(YapDatabaseCloudCoreOperation *)operation
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return NO;
	}
	
	// Sanity checks
	
	if (operation == nil) return NO;
	
	NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
	if (allowedOperationClasses)
	{
		BOOL allowed = NO;
		for (Class class in allowedOperationClasses)
		{
			if ([operation isKindOfClass:class])
			{
				allowed = YES;
				break;
			}
		}
		
		if (!allowed)
		{
			@throw [self disallowedOperationClass:operation];
			return NO;
		}
	}
	
	if ([self operationWithUUID:operation.uuid inPipeline:operation.pipeline] == nil)
	{
		// The operation doesn't appear to exist.
		// It either never existed, or it's already been completed or skipped.
		return NO;
	}
	
	// Modify logic
	
	[self addModifiedOperation:operation];
	return YES;
}

/**
 * This method MUST be invoked in order to mark an operation as complete.
 * 
 * Until an operation is marked as completed or skipped,
 * the pipeline will act as if the operation is still in progress.
 * And the only way to mark an operation as complete or skipped,
 * is to use either the completeOperation: or one of the skipOperation methods.
 * These methods allow the system to remove the operation from its internal sqlite table.
**/
- (void)completeOperation:(YapDatabaseCloudCoreOperation *)inOp
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	YapDatabaseCloudCoreOperation *op = [self operationWithUUID:inOp.uuid inPipeline:inOp.pipeline];
	if (op && !op.pendingStatusIsCompleted)
	{
		op = [op copy];
		
		op.needsDeleteDatabaseRow = YES;
		op.pendingStatus = @(YDBCloudOperationStatus_Completed);
		
		[self addModifiedOperation:op];
		[self didCompleteOperation:op];
	}
}

/**
 * Use this method to skip/abort operations.
 *
 * Until an operation is marked as completed or skipped,
 * the pipeline will act as if the operation is still in progress.
 * And the only way to mark an operation as complete or skipped,
 * is to use either the completeOperation: or one of the skipOperation methods.
 * These methods allow the system to remove the operation from its internal sqlite table.
**/
- (void)skipOperation:(YapDatabaseCloudCoreOperation *)inOp
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	YapDatabaseCloudCoreOperation *op = [self operationWithUUID:inOp.uuid inPipeline:inOp.pipeline];
	if (op && !op.pendingStatusIsCompletedOrSkipped)
	{
		op = [op copy];
			
		op.needsDeleteDatabaseRow = YES;
		op.pendingStatus = @(YDBCloudOperationStatus_Skipped);
		
		[self addModifiedOperation:op];
		[self didSkipOperation:op];
	}
}

/**
 * Use this method to skip/abort operations (across all registered pipelines).
**/
- (void)skipOperationsPassingTest:(BOOL (^)(YapDatabaseCloudCorePipeline *pipeline,
                                            YapDatabaseCloudCoreOperation *operation,
                                            NSUInteger graphIdx, BOOL *stop))testBlock
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	__block NSMutableArray *skippedOps = nil;
	
	[self _enumerateOperations:YDBCloudCore_EnumOps_All
	                usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCorePipeline *pipeline,
	                                   YapDatabaseCloudCoreOperation *operation,
	                                   NSUInteger graphIdx, BOOL *stop)
	{
		YapDatabaseCloudCoreOperation *modifiedOp = nil;
		
		if (testBlock(pipeline, operation, graphIdx, stop))
		{
			modifiedOp = [operation copy];
			
			modifiedOp.needsDeleteDatabaseRow = YES;
			modifiedOp.pendingStatus = @(YDBCloudOperationStatus_Skipped);
			
			if (skippedOps == nil)
				skippedOps = [NSMutableArray array];
			
			[skippedOps addObject:modifiedOp];
		}
		
		return modifiedOp;
	}];
	
	for (YapDatabaseCloudCoreOperation *op in skippedOps)
	{
		[self didSkipOperation:op];
	}
}

/**
 * Use this method to skip/abort operations in a specific pipeline.
**/
- (void)skipOperationsInPipeline:(NSString *)pipelineName
                     passingTest:(BOOL (^)(YapDatabaseCloudCoreOperation *operation,
                                           NSUInteger graphIdx, BOOL *stop))testBlock;
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:pipelineName];
	
	__block NSMutableArray *skippedOps = nil;
	
	[self _enumerateOperations:YDBCloudCore_EnumOps_All
	                inPipeline:pipeline
	                usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		YapDatabaseCloudCoreOperation *modifiedOp = nil;
		
		if (testBlock(operation, graphIdx, stop))
		{
			modifiedOp = [operation copy];
			
			modifiedOp.needsDeleteDatabaseRow = YES;
			modifiedOp.pendingStatus = @(YDBCloudOperationStatus_Skipped);
			
			if (skippedOps == nil)
				skippedOps = [NSMutableArray array];
			
			[skippedOps addObject:modifiedOp];
		}
		
		return modifiedOp;
	}];
	
	for (YapDatabaseCloudCoreOperation *op in skippedOps)
	{
		[self didSkipOperation:op];
	}
}

/**
 *
**/
- (void)mergeRecord:(NSDictionary *)record withCloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	BOOL isDirectory = [cloudURI hasSuffix:@"/"];
	YapFilePath *cloudUriPath = [[YapFilePath alloc] initWithPath:cloudURI isDirectory:isDirectory];
	
	NSMutableArray<YapDatabaseCloudCoreRecordOperation *> *recordOperations = [NSMutableArray array];
	
	[self enumerateOperationsUsingBlock:
	    ^(YapDatabaseCloudCorePipeline *pipeline,
			YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
	{
		if ([operation isKindOfClass:[YapDatabaseCloudCoreRecordOperation class]])
		{
			__unsafe_unretained YapDatabaseCloudCoreRecordOperation *recordOperation =
			                    (YapDatabaseCloudCoreRecordOperation *)operation;
			
			BOOL cloudPathMatches = [recordOperation.cloudPath isEqualToFilePath:cloudUriPath];
			if (cloudPathMatches)
			{
				[recordOperations addObject:recordOperation];
			}
		}
	}];
	
//	if (recordOperations.count > 0)
//	{
//		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
//		                   (YapDatabaseReadWriteTransaction *)databaseTransaction;
//	
//		for (YapDatabaseCloudCoreRecordOperation *immutableRecordOp in recordOperations)
//		{
//			YapDatabaseCloudCoreRecordOperation *recordOp = [immutableRecordOp copy];
//			
//			YapCollectionKey *ck = nil;
//			
//			if (recordOp.databaseRowid)
//			{
//				int64_t rowid = [recordOp.databaseRowid longLongValue];
//				ck = [databaseTransaction collectionKeyForRowid:rowid];
//			}
//			
//			parentConnection->parent->mergeRecordBlock(transaction, ck.collection, ck.key, record, recordOp);
//			
//			if (recordOp.hasChanges)
//			{
//				recordOp.needsModifyDatabaseRow = YES;
//				
//				[self addModifiedOperation:recordOp];
//			}
//		}
//	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Searching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Searches for an operation with the given UUID.
 *
 * @return The corresponding operation, if found. Otherwise nil.
**/
- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid
{
	// Search operations from previous commits.
	
	NSArray *allPipelines = [parentConnection->parent registeredPipelines];
	
	for (YapDatabaseCloudCorePipeline *pipeline in allPipelines)
	{
		YapDatabaseCloudCoreOperation *originalOp = [pipeline operationWithUUID:uuid];
		if (originalOp)
		{
			YapDatabaseCloudCoreOperation *modifiedOp = parentConnection->operations_modified[uuid];
			
			if (modifiedOp)
				return modifiedOp;
			else
				return originalOp;
		}
	}
	
	// Search operations that have been added (to a new graph) during this transaction.
	
	__block YapDatabaseCloudCoreOperation *matchedOp = nil;
	
	[parentConnection->operations_added enumerateKeysAndObjectsUsingBlock:
	  ^(NSString *pipelineName, NSArray<YapDatabaseCloudCoreOperation *> *ops, BOOL *stop)
	{
		for (YapDatabaseCloudCoreOperation *op in ops)
		{
			if ([op.uuid isEqual:uuid])
			{
				matchedOp = op;
				
				*stop = YES;
				break;
			}
		}
	}];
	
	if (matchedOp) return matchedOp;
	
	// Search operations that have been inserted (into a previous graph) during this transaction.
	
	[parentConnection->operations_inserted enumerateKeysAndObjectsUsingBlock:
	  ^(NSString *pipelineName, NSMutableDictionary *graphs, BOOL *outerStop)
	{
		[graphs enumerateKeysAndObjectsUsingBlock:
		  ^(NSNumber *graphIdx, NSArray<YapDatabaseCloudCoreOperation *> *ops, BOOL *innerStop)
		{
			for (YapDatabaseCloudCoreOperation *op in ops)
			{
				if ([op.uuid isEqual:uuid])
				{
					matchedOp = op;
					
					*innerStop = YES;
					*outerStop = YES;
					break;
				}
			}
		}];
	}];
	
	return matchedOp;
}

/**
 * Searches for an operation with the given UUID and pipeline.
 * If you know the pipeline, this method is a bit more efficient than 'operationWithUUID'.
 *
 * @return The corresponding operation, if found. Otherwise nil.
**/
- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid inPipeline:(NSString *)pipelineName
{
	// Search operations from previous commits.
	
	YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:pipelineName];
	
	YapDatabaseCloudCoreOperation *originalOp = [pipeline operationWithUUID:uuid];
	if (originalOp)
	{
		YapDatabaseCloudCoreOperation *modifiedOp = parentConnection->operations_modified[uuid];
		
		if (modifiedOp)
			return modifiedOp;
		else
			return originalOp;
	}
	
	// Search operations that have been added (to a new graph) during this transaction.
	
	NSArray<YapDatabaseCloudCoreOperation *> *ops = parentConnection->operations_added[pipeline.name];
	for (YapDatabaseCloudCoreOperation *op in ops)
	{
		if ([op.uuid isEqual:uuid])
		{
			return op;
		}
	}
	
	// Search operations that have been inserted (into a previous graph) during this transaction.
	
	__block YapDatabaseCloudCoreOperation *matchedOp = nil;
	
	NSDictionary *graphs = parentConnection->operations_inserted[pipeline.name];
	
	[graphs enumerateKeysAndObjectsUsingBlock:
	  ^(NSNumber *graphIdx, NSArray<YapDatabaseCloudCoreOperation *> *ops, BOOL *stop)
	{
		for (YapDatabaseCloudCoreOperation *op in ops)
		{
			if ([op.uuid isEqual:uuid])
			{
				matchedOp = op;
				
				*stop = YES;
				break;
			}
		}
	}];
	
	return matchedOp;
}

/**
 * @param operation
 *   The operation to search for.
 *   The operation.pipeline property specifies which pipeline to use.
 *
 * @return
 *   The index of the graph that contains the given operation.
 *   Or NSNotFound if a graph isn't found.
**/
- (NSUInteger)graphForOperation:(YapDatabaseCloudCoreOperation *)operation
{
	NSUUID *uuid = operation.uuid;
	
	// Search operations from previous commits.
	
	YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:operation.pipeline];
	if (pipeline)
	{
		__block BOOL found = NO;
		__block NSUInteger foundGraphIdx = 0;
		
		[pipeline enumerateOperationsUsingBlock:
		  ^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
		{
			if ([operation.uuid isEqual:uuid])
			{
				found = YES;
				foundGraphIdx = graphIdx;
				*stop = YES;
			}
		}];
		
		if (found) {
			return foundGraphIdx;
		}
	}
	
	// Search operations that have been added (to a new graph) during this transaction.
	
	NSArray<YapDatabaseCloudCoreOperation *> *ops = parentConnection->operations_added[pipeline.name];
	for (YapDatabaseCloudCoreOperation *op in ops)
	{
		if ([op.uuid isEqual:uuid])
		{
			// This is an added operation for a new graph.
			// So the graphIdx is going to be the next available idx (i.e. currentGraphs.count)
			
			return [pipeline graphCount];
		}
	}
	
	// Search operations that have been inserted (into a previous graph) during this transaction.
	
	__block NSUInteger foundGraphIdx = NSNotFound;
	
	NSDictionary *graphs = parentConnection->operations_inserted[pipeline.name];
	
	[graphs enumerateKeysAndObjectsUsingBlock:
	  ^(NSNumber *graphIdx, NSArray<YapDatabaseCloudCoreOperation *> *ops, BOOL *stop)
	{
		for (YapDatabaseCloudCoreOperation *op in ops)
		{
			if ([op.uuid isEqual:uuid])
			{
				// This is an inserted operaration for a previous graph.
				
				foundGraphIdx = graphIdx.unsignedIntegerValue;
				*stop = YES;
			}
		}
	}];
	
	return foundGraphIdx;
}


- (void)enumerateOperationsUsingBlock:(void (^)(YapDatabaseCloudCorePipeline *pipeline,
                                               YapDatabaseCloudCoreOperation *operation,
                                               NSUInteger graphIdx, BOOL *stop))enumBlock
{
	if (enumBlock == nil) return;
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		[self _enumerateOperations:YDBCloudCore_EnumOps_All
		                usingBlock:
		  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCorePipeline *pipeline,
		                                   YapDatabaseCloudCoreOperation *operation,
		                                   NSUInteger graphIdx, BOOL *stop)
		{
			enumBlock(pipeline, operation, graphIdx, stop);
			return nil;
		}];
	}
	else
	{
		__block BOOL stop = NO;
		
		NSArray *allPipelines = [parentConnection->parent registeredPipelines];
		for (YapDatabaseCloudCorePipeline *pipeline in allPipelines)
		{
			[pipeline enumerateOperationsUsingBlock:
			  ^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *innerStop)
			{
				enumBlock(pipeline, operation, graphIdx, &stop);
				
				if (stop) *innerStop = YES;
			}];
			
			if (stop) break;
		}
	}
}

- (void)enumerateOperationsInPipeline:(NSString *)pipelineName
                           usingBlock:
    (void (^)(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop))enumBlock
{
	if (enumBlock == nil) return;
	
	YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:pipelineName];
	
	if (databaseTransaction->isReadWriteTransaction)
	{
		[self _enumerateOperations:YDBCloudCore_EnumOps_All
		                inPipeline:pipeline
		                usingBlock:
		  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
		{
			enumBlock(operation, graphIdx, stop);
			return nil;
		}];
	}
	else
	{
		[pipeline enumerateOperationsUsingBlock:enumBlock];
	}
}

/**
 * Internal enumerate method (for readWriteTransactions only).
 *
 * Allows for enumeration of all existing, inserted & added operations (filtering as needed via parameter),
 * and allows for the modification of any item during enumeration.
**/
- (void)_enumerateOperations:(YDBCloudCore_EnumOps)flags
                  usingBlock:(YapDatabaseCloudCoreOperation *
                               (^)(YapDatabaseCloudCorePipeline *pipeline,
                                   YapDatabaseCloudCoreOperation *operation,
                                   NSUInteger graphIdx, BOOL *stop))enumBlock
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Oops");
	if (enumBlock == nil) return;
	
	NSArray *allPipelines = [parentConnection->parent registeredPipelines];
	
	for (YapDatabaseCloudCorePipeline *pipeline in allPipelines)
	{
		__block BOOL stop = NO;
		__block BOOL pipelineHasOps = NO;
		__block NSUInteger lastGraphIdx = 0;
		
		[pipeline enumerateOperationsUsingBlock:
		  ^(YapDatabaseCloudCoreOperation *queuedOp, NSUInteger graphIdx, BOOL *innerStop)
		{
			pipelineHasOps = YES;
			
			if (lastGraphIdx != graphIdx)
			{
				if (flags & YDBCloudCore_EnumOps_Inserted)
				{
					NSDictionary *insertedGraphs = parentConnection->operations_inserted[pipeline.name];
					NSMutableArray<YapDatabaseCloudCoreOperation *> *insertedOps = insertedGraphs[@(lastGraphIdx)];
					
					for (NSUInteger i = 0; i < insertedOps.count; i++)
					{
						YapDatabaseCloudCoreOperation *op = insertedOps[i];
						
						if (!op.pendingStatusIsCompletedOrSkipped)
						{
							YapDatabaseCloudCoreOperation *modifiedOp = enumBlock(pipeline, op, lastGraphIdx, &stop);
							
							if (modifiedOp)
							{
								[modifiedOp makeImmutable];
								insertedOps[i] = modifiedOp;
							}
							
							if (stop) break;
						}
					}
					
					if (stop) {
						*innerStop = YES;
						return;
					}
				}
				
				lastGraphIdx = graphIdx;
			}
			
			if (flags & YDBCloudCore_EnumOps_Existing)
			{
				YapDatabaseCloudCoreOperation *modifiedOp = parentConnection->operations_modified[queuedOp.uuid];
				
				if (!modifiedOp || !modifiedOp.pendingStatusIsCompletedOrSkipped)
				{
					if (modifiedOp)
						modifiedOp = enumBlock(pipeline, modifiedOp, graphIdx, &stop);
					else
						modifiedOp = enumBlock(pipeline, queuedOp, graphIdx, &stop);
					
					if (modifiedOp)
					{
						[modifiedOp makeImmutable];
						parentConnection->operations_modified[modifiedOp.uuid] = modifiedOp;
					}
					
					if (stop) {
						*innerStop = YES;
						return;
					}
				}
			}
			
		}]; // end [pipeline enumerateOperationsUsingBlock:]
		
		if (!stop && (flags & YDBCloudCore_EnumOps_Added))
		{
			NSUInteger nextGraphIdx = pipelineHasOps ? (lastGraphIdx + 1) : 0;
			
			NSMutableArray<YapDatabaseCloudCoreOperation *> *addedOps =
			  parentConnection->operations_added[pipeline.name];
			
			for (NSUInteger i = 0; i < addedOps.count; i++)
			{
				YapDatabaseCloudCoreOperation *op = addedOps[i];
				
				if (!op.pendingStatusIsCompletedOrSkipped)
				{
					YapDatabaseCloudCoreOperation *modifiedOp = enumBlock(pipeline, op, nextGraphIdx, &stop);
					
					if (modifiedOp)
					{
						[modifiedOp makeImmutable];
						addedOps[i] = modifiedOp;
					}
					
					if (stop) break;
				}
			}
		}
		
	} // end for (YapDatabaseCloudCorePipeline *pipeline in allPipelines)
}

/**
 * Internal enumerate method (for readWriteTransactions only).
 *
 * Allows for enumeration of all existing, inserted & added operations (filtering as needed via parameter),
 * and allows for the modification of any item during enumeration.
**/
- (void)_enumerateOperations:(YDBCloudCore_EnumOps)flags
                  inPipeline:(YapDatabaseCloudCorePipeline *)pipeline
                  usingBlock:(YapDatabaseCloudCoreOperation *
                               (^)(YapDatabaseCloudCoreOperation *operation,
                                   NSUInteger graphIdx, BOOL *stop))enumBlock
{
	NSAssert(databaseTransaction->isReadWriteTransaction, @"Oops");
	if (enumBlock == nil) return;
	
	__block BOOL stop = NO;
	__block BOOL pipelineHasOps = NO;
	__block NSUInteger lastGraphIdx = 0;
	
	[pipeline enumerateOperationsUsingBlock:
	  ^(YapDatabaseCloudCoreOperation *queuedOp, NSUInteger graphIdx, BOOL *innerStop)
	{
		pipelineHasOps = YES;
		
		if (lastGraphIdx != graphIdx)
		{
			if (flags & YDBCloudCore_EnumOps_Inserted)
			{
				NSDictionary *insertedGraphs = parentConnection->operations_inserted[pipeline.name];
				NSMutableArray<YapDatabaseCloudCoreOperation *> *insertedOps = insertedGraphs[@(lastGraphIdx)];
				
				for (NSUInteger i = 0; i < insertedOps.count; i++)
				{
					YapDatabaseCloudCoreOperation *op = insertedOps[i];
					
					YapDatabaseCloudCoreOperation *modifiedOp = enumBlock(op, lastGraphIdx, &stop);
					
					if (modifiedOp)
					{
						[modifiedOp makeImmutable];
						insertedOps[i] = modifiedOp;
					}
					
					if (stop) break;
				}
				
				if (stop) *innerStop = YES;
				return;
			}
			
			lastGraphIdx = graphIdx;
		}
		
		if (flags & YDBCloudCore_EnumOps_Existing)
		{
			YapDatabaseCloudCoreOperation *modifiedOp = parentConnection->operations_modified[queuedOp.uuid];
			
			if (modifiedOp)
				modifiedOp = enumBlock(modifiedOp, graphIdx, &stop);
			else
				modifiedOp = enumBlock(queuedOp, graphIdx, &stop);
			
			if (modifiedOp)
			{
				[modifiedOp makeImmutable];
				parentConnection->operations_modified[modifiedOp.uuid] = modifiedOp;
			}
			
			if (stop) *innerStop = YES;
		}
	}];
	
	if (!stop && (flags & YDBCloudCore_EnumOps_Added))
	{
		NSUInteger nextGraphIdx = pipelineHasOps ? (lastGraphIdx + 1) : 0;
		
		NSMutableArray<YapDatabaseCloudCoreOperation *> *addedOps =
		  parentConnection->operations_added[pipeline.name];
		
		for (NSUInteger i = 0; i < addedOps.count; i++)
		{
			YapDatabaseCloudCoreOperation *op = addedOps[i];
			
			YapDatabaseCloudCoreOperation *modifiedOp = enumBlock(op, nextGraphIdx, &stop);
			
			if (modifiedOp)
			{
				[modifiedOp makeImmutable];
				addedOps[i] = modifiedOp;
			}
			
			if (stop) break;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Move Support
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 *
**/
- (void)moveCloudPath:(YapFilePath *)srcCloudPath toCloudPath:(YapFilePath *)dstCloudPath
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (srcCloudPath == nil) {
		YDBLogWarn(@"%@ - Ignoring request: srcCloudPath is nil", THIS_METHOD);
		return;
	}
	if (dstCloudPath == nil) {
		YDBLogWarn(@"%@ - Ignoring request: dstCloudPath is nil", THIS_METHOD);
		return;
	}
	
	[self _enumerateOperations:YDBCloudCore_EnumOps_All
	                usingBlock:
	  ^YapDatabaseCloudCoreOperation *(YapDatabaseCloudCorePipeline *pipeline,
	                                   YapDatabaseCloudCoreOperation *operation,
	                                   NSUInteger graphIdx, BOOL *stop)
	{
		YapDatabaseCloudCoreFileOperation *modifiedOp = nil;
		
		if ([operation isKindOfClass:[YapDatabaseCloudCoreFileOperation class]])
		{
			YapDatabaseCloudCoreFileOperation *op = (YapDatabaseCloudCoreFileOperation *)operation;
			
			if (op.cloudPath)
			{
				YapFilePath *movedSrc = [op.cloudPath filePathByMovingFrom:srcCloudPath to:dstCloudPath];
				if (movedSrc)
				{
					if (modifiedOp == nil)
						modifiedOp = [op copy];
					
					modifiedOp.cloudPath = movedSrc;
				}
			}
			
			if (op.targetCloudPath)
			{
				YapFilePath *movedDst = [op.targetCloudPath filePathByMovingFrom:srcCloudPath to:dstCloudPath];
				if (movedDst)
				{
					if (modifiedOp == nil)
						modifiedOp = [op copy];
					
					modifiedOp.targetCloudPath = movedDst;
				}
			}
		}
		
		return modifiedOp;
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Attach / Detach Support
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for method description.
**/
- (void)attachCloudURI:(NSString *)inCloudURI
                forKey:(NSString *)key
          inCollection:(NSString *)collection
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	if (!parentConnection->parent->options.enableAttachDetachSupport)
	{
		@throw [self attachDetachSupportDisabled:NSStringFromSelector(_cmd)];
		return;
	}
	
	NSString *cloudURI = [inCloudURI copy]; // mutable string protection
	
	if (cloudURI == nil) {
		YDBLogWarn(@"%@ - Ignoring: cloudURI is nil", THIS_METHOD);
		return;
	}
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		[self attachCloudURI:cloudURI forRowid:rowid];
	}
	else
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		if (parentConnection->pendingAttachRequests == nil)
			parentConnection->pendingAttachRequests = [[YapManyToManyCache alloc] initWithCountLimit:0];
		
		[parentConnection->pendingAttachRequests insertKey:collectionKey value:cloudURI];
	}
}

/**
 * See header file for method description.
**/
- (void)detachCloudURI:(NSString *)inCloudURI
                forKey:(NSString *)key
          inCollection:(NSString *)collection
     wasRemoteDeletion:(BOOL)wasRemoteDeletion
   invokeDeleteHandler:(BOOL)invokeDeleteHandler
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	if (!parentConnection->parent->options.enableAttachDetachSupport)
	{
		@throw [self attachDetachSupportDisabled:NSStringFromSelector(_cmd)];
		return;
	}
	
	NSString *cloudURI = [inCloudURI copy]; // mutable string protection
	
	if (cloudURI == nil) {
		YDBLogWarn(@"%@ - Ignoring: cloudURI is nil", THIS_METHOD);
		return;
	}
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		// Doesn't exist in the database.
		// Remove from pendingAttachRequests (if needed), and return.
		
		BOOL logWarning = YES;
		
		if ([parentConnection->pendingAttachRequests count] > 0)
		{
			YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			if ([parentConnection->pendingAttachRequests containsKey:collectionKey value:cloudURI])
			{
				[parentConnection->pendingAttachRequests removeItemWithKey:collectionKey value:cloudURI];
				logWarning = NO;
			}
		}
		
		if (logWarning) {
			YDBLogWarn(@"%@ - No row in database with given collection/key: %@, %@", THIS_METHOD, collection, key);
		}
		
		return;
	}
	
	// Perform detach
		
	[self detachCloudURI:cloudURI forRowid:rowid];
	
	// Handle options
	
	if (wasRemoteDeletion)
	{
		BOOL isDirectory = [cloudURI hasSuffix:@"/"];
		YapFilePath *cloudUriPath = [[YapFilePath alloc] initWithPath:cloudURI isDirectory:isDirectory];
		
		[self skipOperationsPassingTest:
		    ^BOOL (YapDatabaseCloudCorePipeline *pipeline,
		           YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop)
		{
			if ([operation isKindOfClass:[YapDatabaseCloudCoreFileOperation class]])
			{
				__unsafe_unretained YapDatabaseCloudCoreFileOperation *fileOperation =
				  (YapDatabaseCloudCoreFileOperation *)operation;
				
				BOOL cloudPathMatches = [fileOperation.cloudPath isEqualToFilePath:cloudUriPath];
				if (cloudPathMatches)
				{
					return YES;
				}
			}
			
			return NO;
		}];
		
		if (parentConnection->parent->options.enableTagSupport)
		{
			[self removeAllTagsForCloudURI:cloudURI];
		}
	}
	else if (invokeDeleteHandler)
	{
		// Invoke DeleteHandler (if installed)
	
		__unsafe_unretained YapDatabaseCloudCoreDeleteHandler *deleteHandler = parentConnection->parent->deleteHandler;
		if (deleteHandler)
		{
			NSUInteger retainCount = [[self allAttachedRowidsForCloudURI:cloudURI] count];
			NSDictionary *mappings = @{ cloudURI : @(retainCount) };
			
			if (deleteHandler->blockType == YapDatabaseBlockTypeWithKey)
			{
				YapDatabaseCloudCoreDeleteHandlerWithKeyBlock block =
				  (YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)deleteHandler->block;
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key);
			}
			else if (deleteHandler->blockType == YapDatabaseBlockTypeWithObject)
			{
				YapDatabaseCloudCoreDeleteHandlerWithObjectBlock block =
				  (YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)deleteHandler->block;
				
				id object = [databaseTransaction objectForKey:key inCollection:collection withRowid:rowid];
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, object);
			}
			else if (deleteHandler->blockType == YapDatabaseBlockTypeWithMetadata)
			{
				YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock block =
				  (YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)deleteHandler->block;
				
				id metadata = [databaseTransaction metadataForKey:key inCollection:collection withRowid:rowid];
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, metadata);
			}
			else
			{
				YapDatabaseCloudCoreDeleteHandlerWithRowBlock block =
				  (YapDatabaseCloudCoreDeleteHandlerWithRowBlock)deleteHandler->block;
				
				YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = nil;
				id metadata = nil;
				[databaseTransaction getObject:&object metadata:&metadata forCollectionKey:ck withRowid:rowid];
				
				block(databaseTransaction, parentConnection->operations_block, mappings, collection, key, object, metadata);
			}
			
			[self importAddedOperations:rowid];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Tag Support
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the currently set tag for the given URI.
 *
 * @param cloudURI
 *   The URI for a remote file / record.
 *   This is typically the relative path of the file on the cloud server.
 *   E.g. "/documents/foo.bar"
 *
 *   Note: The exact format of URI's is defined by the cloud domain. For example:
 *   - Dropbox may use a relative URL format. (/documents/foo.bar)
 *   - Apple's CloudKit may use URIs based upon CKRecordID.
 *
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 *
 * @return
 *   The most recently assigned tag.
**/
- (id)tagForCloudURI:(NSString *)cloudURI withIdentifier:(NSString *)identifier
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!parentConnection->parent->options.enableTagSupport)
	{
		@throw [self tagSupportDisabled:NSStringFromSelector(_cmd)];
		return nil;
	}
	
	if (cloudURI == nil) return nil;
	if (identifier == nil) identifier = @"";
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(cloudURI, identifier);
	
	id tag = nil;
	
	// Check dirtyTags (modified values from current transaction)
	
	tag = [parentConnection->dirtyTags objectForKey:tuple];
	if (tag)
	{
		if (tag == [NSNull null])
			return nil;
		else
			return tag;
	}
	
	// Check tagCache (cached clean values)
	
	tag = [parentConnection->tagCache objectForKey:tuple];
	if (tag)
	{
		if (tag == [NSNull null])
			return nil;
		else
			return tag;
	}
	
	// Fetch from disk
	
	sqlite3_stmt *statement = [parentConnection tagTable_fetchStatement];
	if (statement == NULL) {
		return nil;
	}
	
	// SELECT "tag" FROM "tagTableName" WHERE "cloudURI" = ? AND "identifier" = ?;
	
	int const column_idx_changeTag = SQLITE_COLUMN_START;
	
	int const bind_idx_cloudURI   = SQLITE_BIND_START + 0;
	int const bind_idx_identifier = SQLITE_BIND_START + 1;
	
	YapDatabaseString _uri; MakeYapDatabaseString(&_uri, cloudURI);
	sqlite3_bind_text(statement, bind_idx_cloudURI, _uri.str, _uri.length, SQLITE_STATIC);
	
	YapDatabaseString _identifier; MakeYapDatabaseString(&_identifier, identifier);
	sqlite3_bind_text(statement, bind_idx_identifier, _identifier.str, _identifier.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int column_type = sqlite3_column_type(statement, column_idx_changeTag);
		
		if (column_type == SQLITE_INTEGER)
		{
			int64_t value = sqlite3_column_int64(statement, column_idx_changeTag);
			
			tag = @(value);
		}
		else if (column_type == SQLITE_FLOAT)
		{
			double value = sqlite3_column_double(statement, column_idx_changeTag);
			
			tag = @(value);
		}
		else if (column_type == SQLITE_TEXT)
		{
			const unsigned char *text = sqlite3_column_text(statement, column_idx_changeTag);
			int textLen = sqlite3_column_bytes(statement, column_idx_changeTag);
			
			tag = [[NSString alloc] initWithBytes:text length:textLen encoding:NSUTF8StringEncoding];
		}
		else if (column_type == SQLITE_BLOB)
		{
			const void *blob = sqlite3_column_blob(statement, column_idx_changeTag);
			int blobSize = sqlite3_column_bytes(statement, column_idx_changeTag);
			
			tag = [NSData dataWithBytes:(void *)blob length:blobSize];
		}
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'recordTable_getInfoForHashStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uri);
	FreeYapDatabaseString(&_identifier);
	
	if (tag)
		[parentConnection->tagCache setObject:tag forKey:tuple];
	else
		[parentConnection->tagCache setObject:[NSNull null] forKey:tuple];
	
	return tag;
}

/**
 * Allows you to update the current tag value for the given path.
 * 
 * @param tag
 *   The tag received from the cloud server.
 *
 *   The following classes are supported:
 *   - NSString
 *   - NSNumber
 *   - NSData
 * 
 * @param cloudURI
 *   The URI for a remote file / record.
 *   This is typically the relative path of the file on the cloud server.
 *   E.g. "/documents/foo.bar"
 *
 *   Note: The exact format of URI's is defined by the cloud domain. For example:
 *   - Dropbox may use a relative URL format. (/documents/foo.bar)
 *   - Apple's CloudKit may use URIs based upon CKRecordID
 * 
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 * 
 * If the given tag is nil, the effect is the same as invoking removeTagForCloudURI:withIdentifier:.
 * If the given changeTag is an unsupported class, throws an exception.
**/
- (void)setTag:(id)tag forCloudURI:(NSString *)cloudURI withIdentifier:(NSString *)identifier
{
	YDBLogAutoTrace();
	
	if (tag == nil)
	{
		[self removeTagForCloudURI:cloudURI withIdentifier:identifier];
		return;
	}
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	if (!parentConnection->parent->options.enableTagSupport)
	{
		@throw [self tagSupportDisabled:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (cloudURI == nil)
	{
		YDBLogWarn(@"%@ - Ignoring: cloudURI is nil", THIS_METHOD);
		return;
	}
	if (identifier == nil)
		identifier = @"";
	
	if (![tag isKindOfClass:[NSNumber class]] &&
	    ![tag isKindOfClass:[NSString class]] &&
	    ![tag isKindOfClass:[NSData class]])
	{
		YDBLogWarn(@"%@ - Ignoring: unsupported changeTag class: %@", THIS_METHOD, [tag class]);
		return;
	}
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(cloudURI, identifier);
	
	[parentConnection->dirtyTags setObject:tag forKey:tuple];
	[parentConnection->tagCache removeObjectForKey:tuple];
}

/**
 * Removes the tag for the given cloudURI/identifier tuple.
 * 
 * Note that this method only removes the specific cloudURI+identifier value.
 * If there are other tags with the same cloudURI, but different identifier, then those values will remain.
 * To remove all such values, use removeAllTagsForCloudURI.
 *
 * @param cloudURI
 *   The URI for a remote file / record.
 *   This is typically the relative path of the file on the cloud server.
 *   E.g. "/documents/foo.bar"
 *
 *   Note: The exact format of URI's is defined by the cloud domain. For example:
 *   - Dropbox may use a relative URL format. (/documents/foo.bar)
 *   - Apple's CloudKit may use URIs based upon CKRecordID
 * 
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 * 
 * @see removeAllTagsForCloudURI
**/
- (void)removeTagForCloudURI:(NSString *)cloudURI withIdentifier:(NSString *)identifier
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	if (!parentConnection->parent->options.enableTagSupport)
	{
		@throw [self tagSupportDisabled:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (cloudURI == nil)
	{
		YDBLogWarn(@"%@ - Ignoring: cloudURI is nil", THIS_METHOD);
		return;
	}
	if (identifier == nil)
		identifier = @"";
	
	YapCollectionKey *tuple = YapCollectionKeyCreate(cloudURI, identifier);
	
	[parentConnection->dirtyTags setObject:[NSNull null] forKey:tuple];
	[parentConnection->tagCache removeObjectForKey:tuple];
}

/**
 * Removes all tags with the given cloudURI.
 *
 * IMPORTANT:
 * It is generally not necessary to directly invoke this method.
 * It is invoked automatically when one of the following occurs:
 *
 * - a delete operation for the cloudURI is marked as completed
 * - the cloudURI is detached with the 'wasRemoteDeletion' flag set
**/
- (void)removeAllTagsForCloudURI:(NSString *)cloudURI
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	if (!parentConnection->parent->options.enableTagSupport)
	{
		@throw [self tagSupportDisabled:NSStringFromSelector(_cmd)];
		return;
	}
	
	if (cloudURI == nil)
	{
		YDBLogWarn(@"%@ - Ignoring: cloudURI is nil", THIS_METHOD);
		return;
	}
	
	// Remove matching items from dirtyTags (modified values from current transaction)
	
	NSMutableArray<YapCollectionKey*> *keysToRemove = [NSMutableArray array];
	
	for (YapCollectionKey *tuple in parentConnection->dirtyTags)
	{
		__unsafe_unretained NSString *tuple_cloudURI = tuple.collection;
	//	__unsafe_unretained NSString *tuple_identifier = tuple.key;
		
		if ([tuple_cloudURI isEqualToString:cloudURI])
		{
			[keysToRemove addObject:tuple];
		}
	}
	
	if (keysToRemove.count > 0)
	{
		[parentConnection->dirtyTags removeObjectsForKeys:keysToRemove];
		[keysToRemove removeAllObjects];
	}
	
	// Remove matching items from tagCache (cached clean values)
	
	[parentConnection->tagCache enumerateKeysWithBlock:^(YapCollectionKey *tuple, BOOL *stop) {
		
		__unsafe_unretained NSString *tuple_cloudURI = tuple.collection;
	//	__unsafe_unretained NSString *tuple_identifier = tuple.key;
		
		if ([tuple_cloudURI isEqualToString:cloudURI])
		{
			[keysToRemove addObject:tuple];
		}
	}];
	
	if (keysToRemove.count > 0)
	{
		[parentConnection->tagCache removeObjectsForKeys:keysToRemove];
	}
	
	// Hit the disk
	
	[self tagTable_removeRowsWithCloudURI:cloudURI];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should write any last changes to their database table(s) if needed,
 * and should perform any needed cleanup before the changeset is requested.
 *
 * Remember, the changeset is requested immediately after this method is invoked.
**/
- (void)flushPendingChangesToExtensionTables
{
	YDBLogAutoTrace();
	
	// Step 1 of 5:
	//
	// Post-Process all modified & inserted operations.
	//
	// - modified ops :
	//     pre-existing operations (that were added in previous commits) that have been modified
	// - inserted ops :
	//     new operations that have been inserted into previous graphs (graphs that were added in previous commits)
	//
	// This is a trick step, as a modified/inserted operation may end up modifying
	// other operations within the same graph. This is due to dependencies.
	//
	// For example, say a graph consists of a single operation: <upload /foo/bar.pdf>
	// Then an operation is inserted into the same graph: <createDir /foo>
	//
	// The end result is that the upload operation is modified,
	// because it now implicitly depends on the new createDir operation.
	//
	// Here's how we deal with this:
	//
	// - enumerate each graph in each pipeline
	// - check to see if there were modified or inserted operations
	// - if so then:
	//   - re-run the processOperations algorithm
	//   - check for any operations that may have been modified or removed
	
	NSArray<YapDatabaseCloudCorePipeline *> *pipelines = [parentConnection->parent registeredPipelines];
	
	for (YapDatabaseCloudCorePipeline *pipeline in pipelines)
	{
		NSDictionary *graphs_inserted = parentConnection->operations_inserted[pipeline.name];
		
		NSArray<NSArray<YapDatabaseCloudCoreOperation *> *> *graphOperations = [pipeline graphOperations];
		
		NSUInteger graphIdx = 0;
		for (NSArray<YapDatabaseCloudCoreOperation *> *oldOps in graphOperations)
		{
			NSMutableArray<YapDatabaseCloudCoreOperation *> *insertedOps = graphs_inserted[@(graphIdx)];
			
			BOOL graphHasChanges = (insertedOps.count > 0);
			if (!graphHasChanges)
			{
				for (YapDatabaseCloudCoreOperation *oldOp in oldOps)
				{
					if (parentConnection->operations_modified[oldOp.uuid])
					{
						graphHasChanges = YES;
						break;
					}
				}
			}
			
			if (graphHasChanges)
			{
				// Create copy of oldOps list (that includes the modified & inserted ops)
				
				NSMutableArray<YapDatabaseCloudCoreOperation *> *newOps =
				  [NSMutableArray arrayWithCapacity:(oldOps.count + insertedOps.count)];
				
				for (YapDatabaseCloudCoreOperation *oldOp in oldOps)
				{
					YapDatabaseCloudCoreOperation *modifiedOp = parentConnection->operations_modified[oldOp.uuid];
					
					if (modifiedOp)
						[newOps addObject:modifiedOp];
					else
						[newOps addObject:[oldOp copy]];
				}
				
				[newOps addObjectsFromArray:insertedOps];
				
				// Invoke processOperations algorithm
				
				NSArray<YapDatabaseCloudCoreOperation *> *newProcessedOps =
				  [self processOperations:newOps inPipeline:pipeline withGraphIdx:graphIdx];
				
				// Compare the new list with the old list
				
				for (YapDatabaseCloudCoreOperation *oldOp in oldOps)
				{
					NSUUID *uuid = oldOp.uuid;
					YapDatabaseCloudCoreOperation *newOp = nil;
					
					for (YapDatabaseCloudCoreOperation *op in newProcessedOps)
					{
						if ([op.uuid isEqual:uuid])
						{
							newOp = op;
							break;
						}
					}
					
					if (newOp)
					{
						if (![newOp isEqualToOperation:oldOp])
						{
							newOp.needsModifyDatabaseRow = YES;
							
							[newOp makeImmutable];
							parentConnection->operations_modified[uuid] = newOp;
						}
					}
					else
					{
						newOp = [oldOp copy];
						
						newOp.needsDeleteDatabaseRow = YES;
						newOp.pendingStatus = @(YDBCloudOperationStatus_Skipped);
						
						[newOp makeImmutable];
						parentConnection->operations_modified[uuid] = newOp;
					}
				}
				
				// Not every single inserted operation may have survived the processOperations algorithm.
				// So we need to check the list here.
				
				NSUInteger i = 0;
				while (i < insertedOps.count)
				{
					YapDatabaseCloudCoreOperation *insertedOp = insertedOps[i];
					
					NSUUID *uuid = insertedOp.uuid;
					BOOL insertedOpSurvived = NO;
					
					for (YapDatabaseCloudCoreOperation *op in newProcessedOps)
					{
						if ([op.uuid isEqual:uuid])
						{
							insertedOpSurvived = YES;
							break;
						}
					}
					
					if (insertedOpSurvived)
						i++;
					else
						[insertedOps removeObjectAtIndex:i];
				}
				
			} // end if (graphHasChanges)
			
			graphIdx++;
			
		}
	
	} // end for (YapDatabaseCloudCorePipeline *pipeline in pipelines)
	
	
	// Step 2 of 5:
	//
	// Post-Process all added operations.
	//
	// - added ops:
	//     new operations that are to be added to a new graph
	//
	// - consolidates duplicate operations into one (if possible)
	// - sets dependencyUUIDs property per operation
	// - updates older operations in the same pipeline
	
	NSMutableDictionary *processedAddedOps = nil;
	
	if ([parentConnection->operations_added count] > 0)
	{
		processedAddedOps = [NSMutableDictionary dictionaryWithCapacity:[parentConnection->operations_added count]];
		
		[parentConnection->operations_added enumerateKeysAndObjectsUsingBlock:
		    ^(NSString *pipelineName, NSArray *allAddedOperationsForPipeline, BOOL *stop)
		 {
			 YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:pipelineName];
			 NSUInteger graphIdx = pipeline.graphCount;
			 
			 NSArray *processedOperationsForPipeline =
			   [self processOperations:allAddedOperationsForPipeline inPipeline:pipeline withGraphIdx:graphIdx];
			 
			 if (processedOperationsForPipeline.count > 0)
			 {
				 processedAddedOps[pipelineName] = processedOperationsForPipeline;
			 }
		 }];
	}
	
	// Step 3 of 5:
	//
	// Flush changes to queue table
	
	[processedAddedOps enumerateKeysAndObjectsUsingBlock:
	    ^(NSString *pipelineName, NSArray *operations, BOOL *stop)
	{
		NSUUID *graphUUID = [NSUUID UUID];
		
		YapDatabaseCloudCorePipeline *pipeline = [parentConnection->parent pipelineWithName:pipelineName];
		NSUUID *prevGraphUUID = [[pipeline lastGraph] uuid];
		
		[self queueTable_insertOperations:operations
		                    withGraphUUID:graphUUID
		                    prevGraphUUID:prevGraphUUID
		                         pipeline:pipeline];
		
		YapDatabaseCloudCoreGraph *graph =
		  [[YapDatabaseCloudCoreGraph alloc] initWithUUID:graphUUID operations:operations];
		
		[parentConnection->graphs_added setObject:graph forKey:pipelineName];
	}];
	
	for (YapDatabaseCloudCorePipeline *pipeline in pipelines)
	{
		NSDictionary *graphs = parentConnection->operations_inserted[pipeline.name];
		
		[graphs enumerateKeysAndObjectsUsingBlock:
		  ^(NSNumber *graphIdx, NSArray<YapDatabaseCloudCoreOperation *> *insertedOps, BOOL *stop)
		{
			NSUUID *graphUUID = nil;
			NSUUID *prevGraphUUID = nil;
			
			[pipeline getGraphUUID:&graphUUID prevGraphUUID:&prevGraphUUID forGraphIdx:graphIdx.unsignedIntegerValue];
			
			[self queueTable_insertOperations:insertedOps
			                    withGraphUUID:graphUUID
			                    prevGraphUUID:prevGraphUUID
			                         pipeline:pipeline];
		}];
	}
	
	for (YapDatabaseCloudCoreOperation *operation in [parentConnection->operations_modified objectEnumerator])
	{
		if (operation.needsDeleteDatabaseRow)
		{
			[self queueTable_removeRowWithRowid:operation.operationRowid];
		}
		else if (operation.needsModifyDatabaseRow)
		{
			[self queueTable_modifyOperation:operation];
		}
	}
	
	// Step 4 of 5:
	//
	// Flush changes to mapping table
	
	if (parentConnection->dirtyMappingInfo.count > 0)
	{
		[parentConnection->dirtyMappingInfo enumerateWithBlock:
		    ^(NSNumber *rowid, NSString *cloudURI, id metadata, BOOL *stop)
		{
			if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsInsert)
			{
				[self mappingTable_insertRowWithRowid:[rowid unsignedLongLongValue] cloudURI:cloudURI];
				
				[parentConnection->cleanMappingCache insertKey:rowid value:cloudURI];
			}
			else if (metadata == YDBCloudCore_DiryMappingMetadata_NeedsRemove)
			{
				[self mappingTable_removeRowWithRowid:[rowid unsignedLongLongValue] cloudURI:cloudURI];
			}
		}];
	}
	
	// Step 5 of 5:
	//
	// Flush changes to tag table
	
	if (parentConnection->dirtyTags.count > 0)
	{
		NSNull *nsnull = [NSNull null];
		
		[parentConnection->dirtyTags enumerateKeysAndObjectsUsingBlock:
		    ^(YapCollectionKey *tuple, id tag, BOOL *stop)
		{
			NSString *cloudURI = tuple.collection;
			NSString *identifier = tuple.key;
			
			if (tag == nsnull)
			{
				[self tagTable_removeRowWithCloudURI:cloudURI identifier:identifier];
			}
			else
			{
				[self tagTable_insertOrUpdateRowWithCloudURI:cloudURI identifier:identifier tag:tag];
				
				[parentConnection->tagCache setObject:tag forKey:tuple];
			}
		}];
	}
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
	[parentConnection->parent commitAddedGraphs:parentConnection->graphs_added
	                         insertedOperations:parentConnection->operations_inserted
	                         modifiedOperations:parentConnection->operations_modified];
	
	// Forward to connection for further cleanup.
	
	[parentConnection postCommitCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (void)didRollbackTransaction
{
	YDBLogAutoTrace();
	
	// Forward to connection for further cleanup.
	
	[parentConnection postRollbackCleanup];
	
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.

	parentConnection = nil;    // Do not remove !
	databaseTransaction = nil; // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)requiresReadWriteTransactionException:(NSString *)methodName
{
	NSString *extName = NSStringFromClass([[[self extensionConnection] extension] class]);
	NSString *className = NSStringFromClass([self class]);
	
	NSString *reason = [NSString stringWithFormat:
	  @"The method [%@ %@] can only be used within a readWriteTransaction.", className, methodName];
	
	return [NSException exceptionWithName:extName reason:reason userInfo:nil];
}

- (NSException *)disallowedOperationClass:(YapDatabaseCloudCoreOperation *)operation
{
	NSString *extName = NSStringFromClass([[[self extensionConnection] extension] class]);
	NSSet *allowedOperationClasses = parentConnection->parent->options.allowedOperationClasses;
	
	NSString *reason = [NSString stringWithFormat:
	  @"An operation is disallowed by configuration settings.\n"
	  @" - operation: %@\n"
	  @" - YapDatabaseCloudCoreOptions.allowedOperationClasses: %@", operation, allowedOperationClasses];
	
	return [NSException exceptionWithName:extName reason:reason userInfo:nil];
}

- (NSException *)attachDetachSupportDisabled:(NSString *)methodName
{
	NSString *extName = NSStringFromClass([[[self extensionConnection] extension] class]);
	NSString *className = NSStringFromClass([self class]);
	
	NSString *reason = [NSString stringWithFormat:
	  @"Attempting to use attach/detach method ([%@ %@]), but attach/detach support has been disabled"
	  @" (YapDatabaseCloudCoreOptions.enableAttachDetachSupport == NO).", className, methodName];
	
	return [NSException exceptionWithName:extName reason:reason userInfo:nil];
}

- (NSException *)tagSupportDisabled:(NSString *)methodName
{
	NSString *extName = NSStringFromClass([[[self extensionConnection] extension] class]);
	NSString *className = NSStringFromClass([self class]);
	
	NSString *reason = [NSString stringWithFormat:
	  @"Attempting to use tag method ([%@ %@]), but tag support has been disabled"
	  @" (YapDatabaseCloudCoreOptions.enableTagSupport == NO).", className, methodName];
	
	return [NSException exceptionWithName:extName reason:reason userInfo:nil];
}

@end
