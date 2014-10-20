#import "YapDatabaseCloudKitPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseCKRecord.h"

#import "NSDictionary+YapDatabase.h"

#import "YapMurmurHash.h"
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

static NSString *const ExtKey_classVersion = @"classVersion";
static NSString *const ExtKey_versionTag   = @"versionTag";


@implementation YapDatabaseCloudKitTransaction

- (id)initWithParentConnection:(YapDatabaseCloudKitConnection *)inParentConnection
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
	
	int classVersion = YAP_DATABASE_CLOUD_KIT_CLASS_VERSION;
	
//	NSString *versionTag = parentConnection->parent->versionTag;
	
	// Figure out what steps we need to take in order to register the view
	
	BOOL needsCreateTables = NO;
	BOOL needsPopulateTables = NO;
	
	// Check classVersion (the internal version number of YapDatabaseView implementation)
	
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion
	                            forExtensionKey:ExtKey_classVersion persistent:YES];
	
	if (!hasOldClassVersion)
	{
		// First time registration
		
		needsCreateTables = YES;
		needsPopulateTables = YES;
	}
	else if (oldClassVersion != classVersion)
	{
		// Upgrading from older codebase
		
		[self dropTablesForOldClassVersion:oldClassVersion];
		
		needsCreateTables = YES;
		needsPopulateTables = YES;
	}
	
	// Create the database tables (if needed)
	
	if (needsCreateTables)
	{
		if (![self createTables]) return NO;
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
	
	// Todo...
	
	return YES;
}

- (void)dropTablesForOldClassVersion:(int)oldClassVersion
{
	// Reserved for future use (when upgrading this class)
}

- (BOOL)createTables
{
	YDBLogAutoTrace();
	
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSString *recordTableName = [self recordTableName];
	NSString *queueTableName  = [self queueTableName];
	
	int status;
	
	// Record Table
	//
	// | rowid | recordIDHash | record |
	
	YDBLogVerbose(@"Creating cloudKit table for registeredName(%@): %@", [self registeredName], recordTableName);
		
	NSString *createRecordTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"rowid\" INTEGER PRIMARY KEY,"         // rowid in 'database' table
	    @"  \"recordIDHash\" INTEGER NOT NULL,"     // custom hash of CKRecordID (for lookups)
		@"  \"databaseIdentifier\" TEXT,"           // user specified databaseIdentifier (null for default)
	    @"  \"record\" BLOB"                        // serialized CKRecord (system fields only)
	    @" );", recordTableName];
	
	NSString *createRecordTableIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"recordIDHash\" ON \"%@\" (\"recordIDHash\");", recordTableName];
	
	YDBLogVerbose(@"Create table: %@", createRecordTable);
	status = sqlite3_exec(db, [createRecordTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, recordTableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	YDBLogVerbose(@"Create index: %@", createRecordTableIndex);
	status = sqlite3_exec(db, [createRecordTableIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating index on table (%@): %d %s",
		            THIS_METHOD, recordTableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	// Queue Table
	//
	// | uuid | prev | deletedRecordIDs | modifiedRecordKeys | modifiedRecords |
	
	YDBLogVerbose(@"Creating cloudKit table for registeredName(%@): %@", [self registeredName], queueTableName);
	
	NSString *createQueueTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"uuid\" TEXT PRIMARY KEY NOT NULL,"
	    @"  \"prev\" TEXT,"
	    @"  \"deletedRecordIDs\" BLOB,"
	    @"  \"modifiedRecordKeys\" BLOB,"
		@"  \"modifiedRecords\" BLOB"
	    @" );", queueTableName];
	
	NSString *createQueueTableIndex = [NSString stringWithFormat:
	  @"CREATE INDEX IF NOT EXISTS \"prev\" ON \"%@\" (\"prev\");", queueTableName];
	
	YDBLogVerbose(@"Create table: %@", createQueueTable);
	status = sqlite3_exec(db, [createQueueTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating table (%@): %d %s",
		            THIS_METHOD, queueTableName, status, sqlite3_errmsg(db));
		return NO;
	}
	
	YDBLogVerbose(@"Create index: %@", createQueueTableIndex);
	status = sqlite3_exec(db, [createQueueTableIndex UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed creating index on table (%@): %d %s",
		            THIS_METHOD, queueTableName, status, sqlite3_errmsg(db));
		return NO;
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

- (NSString *)recordTableName
{
	return [parentConnection->parent recordTableName];
}

- (NSString *)queueTableName
{
	return [parentConnection->parent queueTableName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Serialization & Deserialization
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int64_t)hashRecordID:(CKRecordID *)recordID
{
	// It would be nice to simply use [recordID hash].
	// But we don't have any control over this method,
	// meaning that Apple may choose to change it in a later release.
	//
	// We need to use a hashing technique that will remain constant.
	// So we use our own technique.
	
	NSString *str1 = recordID.recordName;
	NSString *str2 = recordID.zoneID.zoneName;
	NSString *str3 = recordID.zoneID.ownerName;
	
	if (str1 == nil) str1 = @"";
	if (str2 == nil) str2 = @"";
	if (str3 == nil) str3 = @"";
	
	NSUInteger len = 0;
	
	len += [str1 lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	len += [str2 lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	len += [str3 lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	
	void *buffer = malloc((size_t)len);
	
	NSUInteger available = len;
	NSUInteger totalUsed = 0;
	NSUInteger used = 0;
	
	[str1 getBytes:buffer
	     maxLength:available
	    usedLength:&used
	      encoding:NSUTF8StringEncoding
	       options:0
	         range:NSMakeRange(0, [str1 length]) remainingRange:NULL];
	
	available -= used;
	totalUsed += used;
	
	[str2 getBytes:buffer
	     maxLength:available
	    usedLength:&used
	      encoding:NSUTF8StringEncoding
	       options:0
	         range:NSMakeRange(0, [str2 length]) remainingRange:NULL];
	
	available -= used;
	totalUsed += used;
	
	[str3 getBytes:buffer
	     maxLength:available
	    usedLength:&used
	      encoding:NSUTF8StringEncoding
	       options:0
	         range:NSMakeRange(0, [str3 length]) remainingRange:NULL];
	
	totalUsed += used;
	
	NSData *data = [NSData dataWithBytesNoCopy:buffer length:totalUsed freeWhenDone:NO];
	int64_t hash = YapMurmurHashData_64(data);
	
	free(buffer);
	return hash;
}

- (NSData *)serializeRecord:(CKRecord *)record
{
	if (record == nil) return nil;
	
	// The YapDatabaseCKRecord class handles serializing just the "system fields" of the given record.
	// That is, it won't store any of the user-created key/value pairs.
	// It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
	
	YapDatabaseCKRecord *recordWrapper = [[YapDatabaseCKRecord alloc] initWithRecord:record];
	
	return [NSKeyedArchiver archivedDataWithRootObject:recordWrapper];
}

- (CKRecord *)deserializeRecord:(NSData *)data
{
	if (data)
		return [NSKeyedUnarchiver unarchiveObjectWithData:data];
	else
		return nil;
}

- (CKRecord *)sanitizedRecord:(CKRecord *)record
{
	// This is the ONLY way in which I know how to accomplish this task.
	//
	// Other techniques, such as making a copy and removing all the values,
	// ends up giving us a record with a bunch of changedKeys. Not what we want.
	
	return [self deserializeRecord:[self serializeRecord:record]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - RecordTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method returns one of the following instance types:
 *
 * - YDBCKDirtyRecordInfo
 * - YDBCKCleanRecordInfo
 * - nil  (if rowid doesn't have any CK info)
 * 
 * The caller must inspect the class type of the returned object.
**/
- (id)recordInfoForRowid:(int64_t)rowid cacheResult:(BOOL)cacheResult
{
	YDBLogAutoTrace();
	
	NSNumber *rowidNumber = @(rowid);
	
	// Check dirtyRecordInfo (modified records)
	
	YDBCKDirtyRecordInfo *dirtyRecordInfo = [parentConnection->dirtyRecordInfo objectForKey:rowidNumber];
	if (dirtyRecordInfo) {
		return dirtyRecordInfo;
	}
	
	// Check cleanRecordInfo (cache)
	
	YDBCKCleanRecordInfo *cleanRecordInfo = [parentConnection->cleanRecordInfo objectForKey:rowidNumber];
	if (cleanRecordInfo)
	{
		if (cleanRecordInfo == (id)[NSNull null])
			return nil;
		else
			return cleanRecordInfo;
	}
	
	// Fetch from disk
	
	sqlite3_stmt *statement = [parentConnection recordTable_getInfoForRowidStatement];
	if (statement == NULL) {
		return nil;
	}
	
	// SELECT "databaseIdentifier", "record" FROM "recordTableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	NSString *databaseIdentifier = nil;
	CKRecord *record = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		int textSize = sqlite3_column_bytes(statement, 0);
		if (textSize > 0)
		{
			const unsigned char *text = sqlite3_column_text(statement, 0);
			
			databaseIdentifier = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		const void *blob = sqlite3_column_blob(statement, 1);
		int blobSize = sqlite3_column_bytes(statement, 1);
		
		// Performance tuning:
		// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
		
		NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		record = [self deserializeRecord:data];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyCountForCollectionStatement': %d %s",
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (record)
	{
		cleanRecordInfo = [[YDBCKCleanRecordInfo alloc] init];
		cleanRecordInfo.databaseIdentifier = databaseIdentifier;
		cleanRecordInfo.record = record;
		
		if (cacheResult){
			[parentConnection->cleanRecordInfo setObject:cleanRecordInfo forKey:rowidNumber];
		}
		return cleanRecordInfo;
	}
	else
	{
		if (cacheResult) {
			[parentConnection->cleanRecordInfo setObject:[NSNull null] forKey:rowidNumber];
		}
		return nil;
	}
}

/**
 * This method is called from handleRemoveObjectsForKeys:inCollection:withRowids:.
 * 
 * It's used to fetch all the recordInfo items for all the given rowids.
 * This information is used in order to determine which rowids have associated CKRecords,
 * and should be deleted (locally and possibly from the cloud too).
**/
- (NSDictionary *)recordInfoForRowids:(NSArray *)rowids
{
	NSMutableDictionary *foundRowids = [NSMutableDictionary dictionaryWithCapacity:[rowids count]];
	NSMutableArray *remainingRowids = [NSMutableArray arrayWithCapacity:[rowids count]];
	
	for (NSNumber *rowidNumber in rowids)
	{
		// Check dirtyRecordInfo (modified records)
		
		YDBCKDirtyRecordInfo *dirtyRecordInfo = [parentConnection->dirtyRecordInfo objectForKey:rowidNumber];
		if (dirtyRecordInfo)
		{
			[foundRowids setObject:dirtyRecordInfo forKey:rowidNumber];
			continue;
		}
		
		// Check cleanRecordInfo (cache)
		
		YDBCKCleanRecordInfo *cleanRecordInfo = [parentConnection->cleanRecordInfo objectForKey:rowidNumber];
		if (cleanRecordInfo)
		{
			if (cleanRecordInfo != (id)[NSNull null])
			{
				[foundRowids setObject:cleanRecordInfo forKey:rowidNumber];
			}
			
			continue;
		}
		
		// Need to fetch from disk
		
		[remainingRowids addObject:rowidNumber];
	}
	
	NSUInteger count = [remainingRowids count];
	if (count > 0)
	{
		sqlite3 *db = databaseTransaction->connection->db;
		
		// Note:
		// The handleRemoveObjectsForKeys:inCollection:withRowids: has the following guarantee:
		//     count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
		//
		// So we don't have to worry about sqlite's upper bound on host parameters.
		
		// SELECT "rowid", "databaseIdentifier", "record" FROM "recordTableName" WHERE "rowid" IN (?, ?, ...);
		
		NSUInteger capacity = 75 + (count * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"rowid\", \"databaseIdentifier\", \"record\""];
		[query appendFormat:@" FROM \"%@\" WHERE \"rowid\" IN (", [self recordTableName]];
		
		for (NSUInteger i = 0; i < count; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		int status;
		
		status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ (%@): Error creating statement\n"
			            @" - status(%d), errmsg: %s\n"
			            @" - query: %@",
			            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db), query);
			
			return foundRowids;
		}
		
		for (NSUInteger i = 0; i < count; i++)
		{
			int64_t rowid = [[remainingRowids objectAtIndex:i] longLongValue];
			
			sqlite3_bind_int64(statement, (int)(i + 1), rowid);
		}
		
		while ((status = sqlite3_step(statement)) == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			NSString *databaseIdentifier = nil;
			
			int textSize = sqlite3_column_bytes(statement, 1);
			if (textSize > 1)
			{
				const unsigned char *text = sqlite3_column_text(statement, 1);
				
				databaseIdentifier = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			}
			
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			CKRecord *record = [self deserializeRecord:data];
			
			if (record)
			{
				YDBCKCleanRecordInfo *cleanRecordInfo = [[YDBCKCleanRecordInfo alloc] init];
				cleanRecordInfo.databaseIdentifier = databaseIdentifier;
				cleanRecordInfo.record = record;
				
				[foundRowids setObject:cleanRecordInfo forKey:@(rowid)];
			}
		}
		
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error executing statement: %d %s",
						THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
	}
	
	return foundRowids;
}

- (NSDictionary *)recordInfoForAllRowids
{
	NSMutableDictionary *foundRowids = [NSMutableDictionary dictionary];
	
	[parentConnection->dirtyRecordInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)obj;
		
		[foundRowids setObject:dirtyRecordInfo forKey:rowidNumber];
	}];
	
	[parentConnection->cleanRecordInfo enumerateKeysAndObjectsWithBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)obj;
		
		if (![foundRowids ydb_containsKey:rowidNumber])
		{
			[foundRowids setObject:cleanRecordInfo forKey:rowidNumber];
		}
	}];
	
	sqlite3_stmt *statement = [parentConnection recordTable_getInfoForAllStatement];
	if (statement == NULL) {
		return foundRowids;
	}
	
	// SELECT "rowid", "databaseIdentifier", "record" FROM "recordTableName";
	
	int status;
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		int64_t rowid = sqlite3_column_int64(statement, 0);
		
		if ([foundRowids ydb_containsKey:@(rowid)])
		{
			continue;
		}
		
		NSString *databaseIdentifier = nil;
		
		int textSize = sqlite3_column_bytes(statement, 1);
		if (textSize > 1)
		{
			const unsigned char *text = sqlite3_column_text(statement, 1);
			
			databaseIdentifier = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
		}
		
		const void *blob = sqlite3_column_blob(statement, 2);
		int blobSize = sqlite3_column_bytes(statement, 2);
		
		// Performance tuning:
		// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
		
		NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		
		CKRecord *record = [self deserializeRecord:data];
		
		if (record)
		{
			YDBCKCleanRecordInfo *cleanRecordInfo = [[YDBCKCleanRecordInfo alloc] init];
			cleanRecordInfo.databaseIdentifier = databaseIdentifier;
			cleanRecordInfo.record = record;
			
			[foundRowids setObject:cleanRecordInfo forKey:@(rowid)];
		}
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ (%@): Error executing statement: %d %s",
		            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
	
	return foundRowids;
}

/**
 * Inserts or Updates the row with the given rowid.
 * 
 * This method returns a sanitized version of the record.
 * That is, a bare CKRecord with only the system fields in tact.
**/
- (CKRecord *)setRecord:(CKRecord *)record databaseIdentfier:(NSString *)databaseIdentifier forRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection recordTable_insertStatement];
	if (statement == NULL) {
		return nil;
	}
	
	// INSERT OR REPLACE INTO "recordTableName"
	//   ("rowid", "ckRecordIDHash", "databaseIdentifier", "record") VALUES (?, ?, ?, ?);
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	int64_t recordHash = [self hashRecordID:record.recordID];
	sqlite3_bind_int64(statement, 2, recordHash);
	
	YapDatabaseString dbID; MakeYapDatabaseString(&dbID, databaseIdentifier);
	if (databaseIdentifier)
		sqlite3_bind_text(statement, 3, dbID.str, dbID.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 3);
	
	__attribute__((objc_precise_lifetime)) NSData *recordBlob = [self serializeRecord:record];
	sqlite3_bind_blob(statement, 4, recordBlob.bytes, (int)recordBlob.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&dbID);
	
	return [self deserializeRecord:recordBlob];
}

- (void)removeRecordForRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection recordTable_removeForRowidStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "recordTableName" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	YDBLogVerbose(@"Deleting 1 row from records table...");
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ERROR)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
}

/**
 * This method is invoked from flushPendingChangesToExtensionTables.
 * The given rowids are an summation of all the rowids that have been deleted throughout this tranaction.
**/
- (void)removeRecordsForRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	NSUInteger rowidsCount = [rowids count];
	
	if (rowidsCount == 0) return;
	if (rowidsCount == 1)
	{
		int64_t rowid = [[rowids firstObject] longLongValue];
		[self removeRecordForRowid:rowid];
		
		return;
	}
	
	sqlite3 *db = databaseTransaction->connection->db;
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	NSUInteger offset = 0;
	do
	{
		NSUInteger left = rowidsCount - offset;
		NSUInteger numParams = MIN(left, maxHostParams);
		
		// DELETE FROM "recordTableName" WHERE "rowid" IN (?, ?, ...);
		
		NSUInteger capacity = 60 + (numParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendFormat:@"DELETE FROM \"%@\" WHERE \"rowid\" IN (", [self recordTableName]];
		
		for (NSUInteger i = 0; i < numParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		int status;
		
		status = sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ (%@): Error creating statement\n"
			            @" - status(%d), errmsg: %s\n"
			            @" - query: %@",
			            THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db), query);
			
			return;
		}
		
		for (NSUInteger i = 0; i < numParams; i++)
		{
			int64_t rowid = [[rowids objectAtIndex:i] longLongValue];
			
			sqlite3_bind_int64(statement, (int)(i + 1), rowid);
		}
		
		YDBLogVerbose(@"Deleting %lu rows from records table...", (unsigned long)numParams);
		
		status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ (%@): Error executing statement: %d %s",
						THIS_METHOD, [self registeredName], status, sqlite3_errmsg(db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		offset += numParams;
		
	} while (offset < rowidsCount);
	
}

/**
 * This method is invoked from flushPendingChangesToExtensionTables.
 * It is only invoked if the user cleared the entire database at some point during this tranaction.
 * (And thus our handleRemoveAllObjectsInAllCollections method was invoked).
**/
- (void)removeRecordsForAllRowids
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection recordTable_removeAllStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "recordTableName";
	
	YDBLogVerbose(@"Deleting all rows from records table...");
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_reset(statement);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities - QueueTable
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoke this method with the NEW changeSets from the pendingQueue (pendingQueue.newChangeSets).
**/
- (void)insertRowWithChangeSet:(YDBCKChangeSet *)changeSet
{
	YDBLogAutoTrace();
	
	sqlite3_stmt *statement = [parentConnection queueTable_insertStatement];
	if (statement == NULL) {
		return;
	}
	
	// INSERT INTO "queueTableName"
	//   ("uuid", "prev", "databaseIdentifier", "deletedRecordIDs", "modifiedRecords") VALUES (?, ?, ?, ?, ?);
	
	YapDatabaseString _uuid; MakeYapDatabaseString(&_uuid, changeSet.uuid);
	sqlite3_bind_text(statement, 1, _uuid.str, _uuid.length, SQLITE_STATIC);
	
	YapDatabaseString _prev; MakeYapDatabaseString(&_prev, changeSet.prev);
	sqlite3_bind_text(statement, 2, _prev.str, _prev.length, SQLITE_STATIC);
	
	YapDatabaseString _dbid; MakeYapDatabaseString(&_dbid, changeSet.databaseIdentifier);
	if (changeSet.databaseIdentifier)
		sqlite3_bind_text(statement, 3, _dbid.str, _dbid.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 3);
	
	__attribute__((objc_precise_lifetime)) NSData *blob1 = [changeSet serializeDeletedRecordIDs];
	if (blob1)
		sqlite3_bind_blob(statement, 4, blob1.bytes, (int)blob1.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 4);
	
	__attribute__((objc_precise_lifetime)) NSData *blob2 = [changeSet serializeModifiedRecords];
	if (blob2)
		sqlite3_bind_blob(statement, 5, blob2.bytes, (int)blob2.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 5);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uuid);
	FreeYapDatabaseString(&_prev);
	FreeYapDatabaseString(&_dbid);
}

/**
 * Invoke this method with OLDER changeSets from the pendingQueue that have changes we need to write to the DB.
**/
- (void)updateRowWithChangeSet:(YDBCKChangeSet *)changeSet
{
	YDBLogAutoTrace();
	
	NSAssert(changeSet.hasChanges, @"Method expected modified changeSet !");
	
	sqlite3_stmt *statement = [parentConnection queueTable_updateStatement];
	if (statement == NULL) {
		return;
	}
	
	// UPDATE "queueTableName" SET "modifiedRecords" = ? WHERE "uuid" = ?;
	
	__attribute__((objc_precise_lifetime)) NSData *blob = [changeSet serializeModifiedRecords];
	if (blob)
		sqlite3_bind_blob(statement, 1, blob.bytes, (int)blob.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 1);
	
	YapDatabaseString _uuid; MakeYapDatabaseString(&_uuid, changeSet.uuid);
	sqlite3_bind_text(statement, 2, _uuid.str, _uuid.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uuid);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Completion
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is invoked by [YapDatabaseCloudKit handleCompletedOperation:withSavedRecords:].
**/
- (void)removeQueueRowWithUUID:(NSString *)uuid
{
	YDBLogAutoTrace();
	
	// Mark this transaction as an uploadCompletionTransaction.
	// This is handled a little differently from a regular (user-initiated) transaction.
	
	parentConnection->isUploadCompletionTransaction = YES;
	
	// Execute that sqlite statement.
	
	sqlite3_stmt *statement = [parentConnection queueTable_removeForUuidStatement];
	if (statement == NULL) {
		return;
	}
	
	// DELETE FROM "queueTableName" WHERE "uuid" = ?;
	
	YapDatabaseString _uuid; MakeYapDatabaseString(&_uuid, uuid);
	sqlite3_bind_text(statement, 1, _uuid.str, _uuid.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
		            status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_uuid);
}

- (void)updateRecord:(CKRecord *)record withDatabaseIdentifier:(NSString *)databaseIdentifier
                                                potentialRowid:(NSNumber *)rowidNumber
{
	YDBLogAutoTrace();
	
	// Plan of action:
	// - For each record, check to see what the original rowid is
	// - Verify the rowid is still associated with the recordID & database
	// - If so, write the updated CKRecord to the row (just the system fields)
	// - If not, try to find the CKRecord elsewhere in the database
	
	YDBCKCleanRecordInfo *cleanRecordInfo = nil;
	if (rowidNumber)
	{
		cleanRecordInfo = [parentConnection->cleanRecordInfo objectForKey:rowidNumber];
		
		if (cleanRecordInfo && (cleanRecordInfo != (id)[NSNull null]))
		{
			if (![databaseIdentifier isEqualToString:cleanRecordInfo.databaseIdentifier] ||
				![record.recordID isEqual:cleanRecordInfo.record.recordID])
			{
				// The rowid is now associated with a different CKRecord.
				// So we'll have to check the database to see if we can write it somewhere else.
				
				rowidNumber = nil;
			}
		}
	}
	
	if (rowidNumber == nil)
	{
		sqlite3_stmt *statement = [parentConnection recordTable_getRowidForRecordStatement];
		if (statement == NULL) {
			return;
		}
		
		// SELECT "rowid" FROM "recordTableName" WHERE "recordIDHash" = ? AND "databaseIdentifier" = ?;
		
		int64_t recordHash = [self hashRecordID:record.recordID];
		sqlite3_bind_int64(statement, 1, recordHash);
		
		YapDatabaseString _dbid; MakeYapDatabaseString(&_dbid, databaseIdentifier);
		sqlite3_bind_text(statement, 2, _dbid.str, _dbid.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			rowidNumber = @(rowid);
		}
		else if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
			            status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_dbid);
	}
	
	if (rowidNumber)
	{
		sqlite3_stmt *statement = [parentConnection recordTable_updateForRowidStatement];
		if (statement == NULL) {
			return;
		}
		
		// UPDATE "recordTableName" SET "record" = ? WHERE "rowid" = ?;
		
		__attribute__((objc_precise_lifetime)) NSData *recordBlob = [self serializeRecord:record];
		sqlite3_bind_blob(statement, 1, recordBlob.bytes, (int)recordBlob.length, SQLITE_STATIC);
		
		int64_t rowid = [rowidNumber longLongValue];
		sqlite3_bind_int64(statement, 2, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
						status, sqlite3_errmsg(databaseTransaction->connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		
		// Update information for the changeset architecture
		
		if (parentConnection->modifiedRecords == nil)
			parentConnection->modifiedRecords = [[NSMutableDictionary alloc] init];
		
		CKRecord *sanitizedRecord = [self deserializeRecord:recordBlob];
		
		[parentConnection->modifiedRecords setObject:sanitizedRecord forKey:rowidNumber];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark CKOperations
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (CKDatabase *)databaseForIdentifier:(id)dbID
{
	if (dbID == nil || dbID == [NSNull null])
	{
		return [[CKContainer defaultContainer] privateCloudDatabase];
	}
	else
	{
		NSAssert([dbID isKindOfClass:[NSString class]], @"Invalid databaseIdentifier");
		
		NSString *databaseIdentifier = (NSString *)dbID;
		
		CKDatabase *database = [databaseCache objectForKey:databaseIdentifier];
		if (database == nil)
		{
			YapDatabaseCloudKitDatabaseBlock databaseBlock = parentConnection->parent->databaseBlock;
			if (databaseBlock == nil) {
				@throw [self misingDatabaseBlockException:databaseIdentifier];
			}
			
			database = databaseBlock(databaseIdentifier);
			if (database == nil) {
				@throw [self missingDatabaseException:databaseIdentifier];
			}
			
			if (databaseCache == nil)
				databaseCache = [[NSMutableDictionary alloc] initWithCapacity:1];
			
			[databaseCache setObject:database forKey:databaseIdentifier];
		}
		
		return database;
	}
}

- (void)queueOperationsForChangeSets:(NSArray *)changeSets
{
	YDBLogAutoTrace();
	
	__weak YapDatabaseCloudKit *weakParent = parentConnection->parent;
	NSOperationQueue *masterOperationQueue = parentConnection->parent->masterOperationQueue;
	
	for (YDBCKChangeSet *changeSet in changeSets)
	{
		CKDatabase *database = [self databaseForIdentifier:changeSet.databaseIdentifier];
		
		NSArray *recordsToSave = changeSet.recordsToSave;
		NSArray *recordIDsToDelete = changeSet.recordIDsToDelete;
		
		CKModifyRecordsOperation *modifyRecordsOperation =
		  [[CKModifyRecordsOperation alloc] initWithRecordsToSave:recordsToSave recordIDsToDelete:recordIDsToDelete];
		modifyRecordsOperation.database = database;
		
		modifyRecordsOperation.modifyRecordsCompletionBlock =
		    ^(NSArray *savedRecords, NSArray *deletedRecordIDs, NSError *operationError)
		{
			__strong YapDatabaseCloudKit *strongParent = weakParent;
			if (strongParent)
			{
				if (operationError)
				{
					YDBLogError(@"Failed upload for (%@): %@", changeSet.databaseIdentifier, operationError);
					
					[strongParent handleFailedOperation:changeSet withError:operationError];
				}
				else
				{
					YDBLogVerbose(@"Finished upload for (%@):\n  savedRecords: %@\n  deletedRecordIDs: %@",
					              changeSet.databaseIdentifier, savedRecords, deletedRecordIDs);
					
					[strongParent handleCompletedOperation:changeSet withSavedRecords:savedRecords];
				}
			}
		};
		
		[masterOperationQueue addOperation:modifyRecordsOperation];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement this method.
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
	
	if (parentConnection->isUploadCompletionTransaction)
	{
		// Nothing to do here.
		// We already handled everything in 'updateRecord:withRowid:'.
		return;
	}
	
	if ([parentConnection->dirtyRecordInfo count] == 0)
	{
		// No CKRecords were changed in this transaction.
		return;
	}
	
	// Step 1 of 3:
	//
	// Use YDBCKChangeQueue tools to generate a list of updates for the queue table.
	// Also, make a list of the deletedRowids.
	
	YDBCKChangeQueue *masterQueue = parentConnection->parent->masterQueue;
	YDBCKChangeQueue *pendingQueue = [masterQueue newPendingQueue];
	
	[parentConnection->dirtyRecordInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)obj;
		
		if (dirtyRecordInfo.dirty_record == nil)
		{
			// The CKRecord has been deleted via one of the following:
			//
			// - [transaction removeObjectForKey:inCollection:]
			// - [[transaction ext:ck] deleteRecordForKey:inCollection]
			// - [[transaction ext:ck] detachKey:inCollection]
			//
			// Note: In the detached scenario, the user wants us to "detach" the local row
			// from its associated CKRecord, but not to actually delete the CKRecord from the cloud.
			
			if (dirtyRecordInfo.detached)
			{
				[masterQueue updatePendingQueue:pendingQueue
				              withDetachedRowid:rowidNumber];
			}
			else
			{
				[masterQueue updatePendingQueue:pendingQueue
				               withDeletedRowid:rowidNumber
				                       recordID:dirtyRecordInfo.clean_recordID
				             databaseIdentifier:dirtyRecordInfo.clean_databaseIdentifier];
			}
			
			if (parentConnection->deletedRowids == nil)
				parentConnection->deletedRowids = [[NSMutableSet alloc] init];
			
			[parentConnection->deletedRowids addObject:rowidNumber];
		}
		else
		{
			// The CKRecord has been modified via one of the following:
			//
			// - [transaction setObject:forKey:inCollection:]
			// - [[transaction ext:ck] detachKey:inCollection:]
			
			if ([dirtyRecordInfo wasInserted])
			{
				[masterQueue updatePendingQueue:pendingQueue
				              withInsertedRowid:rowidNumber
				                         record:dirtyRecordInfo.dirty_record
				             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
			}
			else
			{
				if ([dirtyRecordInfo databaseIdentifierOrRecordIDChanged])
				{
					if (dirtyRecordInfo.detached)
					{
						[masterQueue updatePendingQueue:pendingQueue
						              withDetachedRowid:rowidNumber];
					}
					else
					{
						[masterQueue updatePendingQueue:pendingQueue
						               withDeletedRowid:rowidNumber
						                       recordID:dirtyRecordInfo.clean_recordID
						             databaseIdentifier:dirtyRecordInfo.clean_databaseIdentifier];
					}
					
					[masterQueue updatePendingQueue:pendingQueue
					              withInsertedRowid:rowidNumber
					                         record:dirtyRecordInfo.dirty_record
					             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
				}
				else
				{
					[masterQueue updatePendingQueue:pendingQueue
					              withModifiedRowid:rowidNumber
					                         record:dirtyRecordInfo.dirty_record
					             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
				}
			}
		}
	}];
	
	// Step 2 of 3:
	//
	// Update record table.
	// This includes deleting removed rowids, as well as inserting new records & updating modified records.
	
	if (parentConnection->reset)
	{
		[self removeRecordsForAllRowids];
	}
	else if ([parentConnection->deletedRowids count] > 0)
	{
		[self removeRecordsForRowids:[parentConnection->deletedRowids allObjects]];
	}
	
	[parentConnection->dirtyRecordInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)obj;
		
		if (dirtyRecordInfo.dirty_record)
		{
			CKRecord *sanitizedRecord = nil;
			
			if ([dirtyRecordInfo wasInserted] || [dirtyRecordInfo databaseIdentifierOrRecordIDChanged])
			{
				sanitizedRecord = [self setRecord:dirtyRecordInfo.dirty_record
				                databaseIdentfier:dirtyRecordInfo.dirty_databaseIdentifier
				                         forRowid:[rowidNumber longLongValue]];
			}
			else
			{
				sanitizedRecord = [self sanitizedRecord:dirtyRecordInfo.dirty_record];
			}
			
			if (sanitizedRecord)
			{
				if (parentConnection->modifiedRecords == nil)
					parentConnection->modifiedRecords = [[NSMutableDictionary alloc] init];
				
				[parentConnection->modifiedRecords setObject:sanitizedRecord forKey:rowidNumber];
				
				// The dirtyRecordInfo dictionary is going to disappear after this transaction completes.
				// So we move the sanitized records back into the cleanRecordInfo cache.
				
				[parentConnection->cleanRecordInfo setObject:sanitizedRecord forKey:rowidNumber];
			}
			else
			{
				if (parentConnection->deletedRowids == nil)
					parentConnection->deletedRowids = [[NSMutableSet alloc] init];
				
				[parentConnection->deletedRowids  addObject:rowidNumber];
			}
		}
	}];
	
	// Step 3 of 3:
	//
	// Update queue table.
	// This includes any changes the pendingQueue table gives us.
	
	for (YDBCKChangeSet *oldChangeSet in pendingQueue.oldChangeSets)
	{
		if (oldChangeSet.hasChanges)
		{
			[self updateRowWithChangeSet:oldChangeSet];
		}
	}
	
	for (YDBCKChangeSet *newChangeSet in pendingQueue.newChangeSets)
	{
		[self insertRowWithChangeSet:newChangeSet];
	}
	
	// Step 4 of 4:
	//
	// Create the NSOperation with all the changes, and add it to the operationQueue.
	
	[self queueOperationsForChangeSets:pendingQueue.newChangeSets];
	
	// Todo: We really want to queue the operations AFTER the commit has succeeded.
	// Otherwise we have an edge case...
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
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
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the recordBlock to find out if the row is associated with a CKRecord.
	
	CKRecord *record = nil;
	YDBCKRecordInfo *recordInfo = nil;
	
	recordInfo = [[YDBCKRecordInfo alloc] init];
	
	YapDatabaseCloudKitBlockType recordBlockType = parentConnection->parent->recordBlockType;
	
	if (recordBlockType == YapDatabaseCloudKitBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithKeyBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithKeyBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key);
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithObjectBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithObjectBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, object);
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithMetadataBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithMetadataBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, metadata);
	}
	else // if (recordBlockType == YapDatabaseCloudKitBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithRowBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithRowBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, object, metadata);
	}
	
	if (record)
	{
		YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_databaseIdentifier = nil;
		dirtyRecordInfo.clean_recordID = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
		dirtyRecordInfo.dirty_record = record;
		
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the recordBlock to find out if the row is associated with a CKRecord,
	// and if that record has modifications that need to be sync'd to the cloud.
	
	YDBCKCleanRecordInfo *cleanRecordInfo = nil;
	YDBCKDirtyRecordInfo *dirtyRecordInfo = nil;
	CKRecordID *cleanRecordID = nil;
	
	id cleanDirtyRecordInfo = [self recordInfoForRowid:rowid cacheResult:YES];
	
	CKRecord *record = nil;
	YDBCKRecordInfo *recordInfo = [[YDBCKRecordInfo alloc] init];
	
	if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
	{
		cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
		cleanRecordID = cleanRecordInfo.record.recordID;
		
		record = cleanRecordInfo.record;
		recordInfo.databaseIdentifier = cleanRecordInfo.databaseIdentifier;
	}
	else if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
	{
		dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
		
		record = dirtyRecordInfo.dirty_record;
		recordInfo.databaseIdentifier = dirtyRecordInfo.dirty_databaseIdentifier;
	}
	
	YapDatabaseCloudKitBlockType recordBlockType = parentConnection->parent->recordBlockType;
	
	if (recordBlockType == YapDatabaseCloudKitBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithKeyBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithKeyBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key);
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithObjectBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithObjectBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, object);
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithMetadataBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithMetadataBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, metadata);
	}
	else // if (recordBlockType == YapDatabaseCloudKitBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithRowBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithRowBlock)parentConnection->parent->recordBlock;
		
		recordBlock(&record, recordInfo, collection, key, object, metadata);
	}
	
	if (cleanRecordInfo)
	{
		// record == nil;                   => User deleted CKRecord (even though local object stays)
		// [record.changedKeys count] > 0;  => Changes were made to CKRecord
		// [record.changedKeys count] == 0; => No changes were made
		
		if ((record == nil) || ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordID;
			dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = record;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		}
	}
	else if (dirtyRecordInfo)
	{
		dirtyRecordInfo.dirty_record = record;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
	}
	else if (record)
	{
		dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_databaseIdentifier = nil;
		dirtyRecordInfo.clean_recordID = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
		dirtyRecordInfo.dirty_record = record;
		
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the recordBlock to find out if the row is associated with a CKRecord,
	// and if that record has modifications that need to be sync'd to the cloud.
	
	YDBCKCleanRecordInfo *cleanRecordInfo = nil;
	YDBCKDirtyRecordInfo *dirtyRecordInfo = nil;
	CKRecordID *cleanRecordID = nil;
	
	CKRecord *record = nil;
	YDBCKRecordInfo *recordInfo = nil;
	
	YapDatabaseCloudKitBlockType recordBlockType = parentConnection->parent->recordBlockType;
	
	if (recordBlockType == YapDatabaseCloudKitBlockTypeWithKey     ||
		recordBlockType == YapDatabaseCloudKitBlockTypeWithMetadata )
	{
		// Nothing to do.
		// The collection/key/metadata hasn't changed, so the CKRecord hasn't changed.
	}
	else
	{
		recordInfo = [[YDBCKRecordInfo alloc] init];
		
		id cleanDirtyRecordInfo = [self recordInfoForRowid:rowid cacheResult:YES];
		
		if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
			cleanRecordID = cleanRecordInfo.record.recordID;
			
			record = cleanRecordInfo.record;
			recordInfo.databaseIdentifier = cleanRecordInfo.databaseIdentifier;
		}
		else if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
			
			record = dirtyRecordInfo.dirty_record;
			recordInfo.databaseIdentifier = dirtyRecordInfo.dirty_databaseIdentifier;
		}
		
		if (recordBlockType == YapDatabaseCloudKitBlockTypeWithObject)
		{
			__unsafe_unretained YapDatabaseCloudKitRecordWithObjectBlock recordBlock =
			  (YapDatabaseCloudKitRecordWithObjectBlock)parentConnection->parent->recordBlock;
			
			recordBlock(&record, recordInfo, collection, key, object);
		}
		else // if (recordBlockType == YapDatabaseCloudKitBlockTypeWithRow)
		{
			__unsafe_unretained YapDatabaseCloudKitRecordWithRowBlock recordBlock =
			  (YapDatabaseCloudKitRecordWithRowBlock)parentConnection->parent->recordBlock;
			
			id metadata = [databaseTransaction metadataForCollectionKey:collectionKey withRowid:rowid];
			
			recordBlock(&record, recordInfo, collection, key, object, metadata);
		}
	}
	
	if (cleanRecordInfo)
	{
		// record == nil;                   => User deleted CKRecord (even though local object stays)
		// [record.changedKeys count] > 0;  => Changes were made to CKRecord
		// [record.changedKeys count] == 0; => No changes were made
		
		if ((record == nil) || ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordID;
			dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = record;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		}
	}
	else if (dirtyRecordInfo)
	{
		dirtyRecordInfo.dirty_record = record;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
	}
	else if (record)
	{
		dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_databaseIdentifier = nil;
		dirtyRecordInfo.clean_recordID = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
		dirtyRecordInfo.dirty_record = record;
		
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	__unsafe_unretained NSString *collection = collectionKey.collection;
	__unsafe_unretained NSString *key = collectionKey.key;
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Invoke the recordBlock to find out if the row is associated with a CKRecord,
	// and if that record has modifications that need to be sync'd to the cloud.
	
	YDBCKCleanRecordInfo *cleanRecordInfo = nil;
	YDBCKDirtyRecordInfo *dirtyRecordInfo = nil;
	CKRecordID *cleanRecordID = nil;
	
	CKRecord *record = nil;
	YDBCKRecordInfo *recordInfo = nil;
	
	YapDatabaseCloudKitBlockType recordBlockType = parentConnection->parent->recordBlockType;
	
	if (recordBlockType == YapDatabaseCloudKitBlockTypeWithKey   ||
	    recordBlockType == YapDatabaseCloudKitBlockTypeWithObject )
	{
		// Nothing to do.
		// The collection/key/object hasn't changed, so the CKRecord hasn't changed.
	}
	else
	{
		recordInfo = [[YDBCKRecordInfo alloc] init];
		
		id cleanDirtyRecordInfo = [self recordInfoForRowid:rowid cacheResult:YES];
		
		if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
			cleanRecordID = cleanRecordInfo.record.recordID;
			
			record = cleanRecordInfo.record;
			recordInfo.databaseIdentifier = cleanRecordInfo.databaseIdentifier;
		}
		else if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
			
			record = dirtyRecordInfo.dirty_record;
			recordInfo.databaseIdentifier = dirtyRecordInfo.dirty_databaseIdentifier;
		}
		
		if (recordBlockType == YapDatabaseCloudKitBlockTypeWithMetadata)
		{
			__unsafe_unretained YapDatabaseCloudKitRecordWithMetadataBlock recordBlock =
			  (YapDatabaseCloudKitRecordWithMetadataBlock)parentConnection->parent->recordBlock;
			
			recordBlock(&record, recordInfo, collection, key, metadata);
		}
		else // if (recordBlockType == YapDatabaseCloudKitBlockTypeWithRow)
		{
			__unsafe_unretained YapDatabaseCloudKitRecordWithRowBlock recordBlock =
			  (YapDatabaseCloudKitRecordWithRowBlock)parentConnection->parent->recordBlock;
			
			id object = [databaseTransaction objectForCollectionKey:collectionKey withRowid:rowid];
			
			recordBlock(&record, recordInfo, collection, key, object, metadata);
		}
	}
	
	if (cleanRecordInfo)
	{
		// record == nil;                   => User deleted CKRecord (even though local object stays)
		// [record.changedKeys count] > 0;  => Changes were made to CKRecord
		// [record.changedKeys count] == 0; => No changes were made
		
		if ((record == nil) || ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordID;
			dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = record;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		}
	}
	else if (dirtyRecordInfo)
	{
		dirtyRecordInfo.dirty_record = record;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
	}
	else if (record)
	{
		dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_databaseIdentifier = nil;
		dirtyRecordInfo.clean_recordID = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = recordInfo.databaseIdentifier;
		dirtyRecordInfo.dirty_record = record;
		
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	// Nothing to do here.
	// "Touch" is generally meant for local operations.
	//
	// We may add an explicit "remote" touch (declared in YapDatabaseCloudKitTransaction.h)
	// in the future if there seems to be a need for it.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	// Nothing to do here.
	// "Touch" is generally meant for local operations.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	id cleanDirtyRecordInfo = [self recordInfoForRowid:rowid cacheResult:NO];
	if (cleanDirtyRecordInfo)
	{
		if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			__unsafe_unretained YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
			
			YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordInfo.record.recordID;
			dirtyRecordInfo.dirty_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = nil;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		}
		else // if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
			
			dirtyRecordInfo.dirty_record = nil;
		}
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	// Fetch a dictionary of valid rowids with the format:
	//
	// key = rowid (NSNumber)
	// value = YDBCKCleanRecordInfo || YDBCKDirtyRecordInfo
	
	NSDictionary *recordInfoMap = [self recordInfoForRowids:rowids];
	
	[recordInfoMap enumerateKeysAndObjectsUsingBlock:^(NSNumber *rowidNumber, id cleanDirtyRecordInfo, BOOL *stop) {
		
		if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			__unsafe_unretained YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
			
			YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordInfo.record.recordID;
			dirtyRecordInfo.dirty_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = nil;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:rowidNumber];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:rowidNumber];
		}
		else // if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
			
			dirtyRecordInfo.dirty_record = nil;
		}
	}];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	// Fetch a dictionary of valid rowids with the format:
	//
	// key = rowid (NSNumber)
	// value = YDBCKCleanRecordInfo || YDBCKDirtyRecordInfo
	
	NSDictionary *recordInfoMap = [self recordInfoForAllRowids];
	
	[recordInfoMap enumerateKeysAndObjectsUsingBlock:^(NSNumber *rowidNumber, id cleanDirtyRecordInfo, BOOL *stop) {
		
		if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			__unsafe_unretained YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)cleanDirtyRecordInfo;
			
			YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
			dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.clean_recordID = cleanRecordInfo.record.recordID;
			dirtyRecordInfo.dirty_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
			dirtyRecordInfo.dirty_record = nil;
			
			[parentConnection->cleanRecordInfo removeObjectForKey:rowidNumber];
			[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:rowidNumber];
		}
		else // if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
			
			dirtyRecordInfo.dirty_record = nil;
		}
	}];
	
	parentConnection->reset = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)misingDatabaseBlockException:(NSString *)databaseIdentifier
{
	NSString *reason = [NSString stringWithFormat:
	  @"The YapDatabaseCloudKit instance was not configured with a databaseBlock (YapDatabaseCloudKitDatabaseBlock)."
	  @" However, we encountered an object with a databaseIdentifier (%@)."
	  @" The databaseBlock is required in order to discover the proper CKDatabase for the databaseIdentifier."
	  @" Without the CKDatabase, we don't know where to send the corresponding CKRecord/CKRecordID.",
	  databaseIdentifier];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

- (NSException *)missingDatabaseException:(NSString *)databaseIdentifier
{
	NSString *reason = [NSString stringWithFormat:
	  @"The databaseBlock (YapDatabaseCloudKitDatabaseBlock) returned a nil database"
	  @" for the databaseIdentifier: \"%@\"", databaseIdentifier];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

@end
