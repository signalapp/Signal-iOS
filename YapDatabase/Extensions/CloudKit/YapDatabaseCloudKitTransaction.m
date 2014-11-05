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
	
	// Capture NEW values
	//
	// classVersion - the internal version number of YapDatabaseView implementation
	// versionTag - user specified versionTag, used to force upgrade mechanisms
	
	int classVersion = YAP_DATABASE_CLOUD_KIT_CLASS_VERSION;
	
	NSString *versionTag = parentConnection->parent->versionTag;
	
	// Fetch OLD values
	//
	// - hasOldClassVersion - will be YES if the extension exists from a previous run of the app
	
	int oldClassVersion = 0;
	BOOL hasOldClassVersion = [self getIntValue:&oldClassVersion forExtensionKey:ExtKey_classVersion persistent:YES];
	
	NSString *oldVersionTag = [self stringValueForExtensionKey:ExtKey_versionTag persistent:YES];
	
	if (!hasOldClassVersion)
	{
		// First time registration
		
		if (![self createTables]) return NO;
		if (![self createNewMasterChangeQueue]) return NO;
		if (![self populateTables]) return NO;
		
		[self setIntValue:classVersion forExtensionKey:ExtKey_classVersion persistent:YES];
		[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
	}
	else if (oldClassVersion != classVersion)
	{
		// Upgrading from older codebase
		//
		// Reserved for potential future use.
		// Code would likely need to do something similar to the following:
		//
		// - restoreMasterChangeQueue
		// - migrate table(s)
		// - repopulateTables
		
		NSAssert(NO, @"Attempting invalid upgrade path !");
	}
	else if (![versionTag isEqualToString:oldVersionTag])
	{
		// Todo: Figure out how exactly to handle versionTag changes...
		
		if (![self restoreMasterChangeQueue]) return NO;
		if (![self repopulateTables]) return NO;
		
		[self setStringValue:versionTag forExtensionKey:ExtKey_versionTag persistent:YES];
	}
	else
	{
		// Restoring an up-to-date extension from a previous run.
		
		if (![self restoreMasterChangeQueue]) return NO;
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
	// | uuid | prev | deletedRecordIDs | modifiedRecords |
	
	YDBLogVerbose(@"Creating cloudKit table for registeredName(%@): %@", [self registeredName], queueTableName);
	
	NSString *createQueueTable = [NSString stringWithFormat:
	    @"CREATE TABLE IF NOT EXISTS \"%@\""
	    @" (\"uuid\" TEXT PRIMARY KEY NOT NULL,"
	    @"  \"prev\" TEXT,"
		@"  \"databaseIdentifier\" TEXT,"
	    @"  \"deletedRecordIDs\" BLOB,"
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

/**
 * Shortcut when creating an extension for the first time.
 * (No need to restore the masterChangeQueue when we know it doesn't exist.)
**/
- (BOOL)createNewMasterChangeQueue
{
	parentConnection->parent->masterQueue = [[YDBCKChangeQueue alloc] initMasterQueue];
	
	return YES;
}

/**
 * This method restores the masterChangeQueue from a previous app run.
 * This allows us to pick up where we left off, and ensure all requested changes make it up to the cloud.
**/
- (BOOL)restoreMasterChangeQueue
{
	YDBLogAutoTrace();
	
	// Enumerate the rows in the queue table,
	// and extract the row information into YDBCKChangeSet objects.
	
	sqlite3 *db = databaseTransaction->connection->db;
	sqlite3_stmt *statement;
	int status;
	
	NSMutableDictionary *changeSetsDict = [NSMutableDictionary dictionaryWithCapacity:1];
	YDBCKChangeSet *lastChangeSetFromEnumeration = nil;
	
	NSString *enumerate = [NSString stringWithFormat:
	  @"SELECT \"uuid\", \"prev\", \"databaseIdentifier\", \"deletedRecordIDs\", \"modifiedRecords\" FROM \"%@\";",
	  [self queueTableName]];
	
	status = sqlite3_prepare_v2(db, [enumerate UTF8String], -1, &statement, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@: Error creating prepared statement: %d %s", THIS_METHOD, status, sqlite3_errmsg(db));
		
		return NO;
	}
	
	while ((status = sqlite3_step(statement)) == SQLITE_ROW)
	{
		const unsigned char *_uuid = sqlite3_column_text(statement, 0);
		int _uuidLen = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *_prev = sqlite3_column_text(statement, 1);
		int _prevLen = sqlite3_column_bytes(statement, 1);
		
		const unsigned char *_dbid = sqlite3_column_text(statement, 2);
		int _dbidLen = sqlite3_column_bytes(statement, 2);
		
		const void *_blob1 = sqlite3_column_blob(statement, 3);
		int _blob1Len = sqlite3_column_bytes(statement, 3);
		
		const void *_blob2 = sqlite3_column_blob(statement, 4);
		int _blob2Len = sqlite3_column_bytes(statement, 4);
		
		NSString *uuid = [[NSString alloc] initWithBytes:_uuid length:_uuidLen encoding:NSUTF8StringEncoding];
		NSString *prev = [[NSString alloc] initWithBytes:_prev length:_prevLen encoding:NSUTF8StringEncoding];
		NSString *dbid = [[NSString alloc] initWithBytes:_dbid length:_dbidLen encoding:NSUTF8StringEncoding];
		
		NSData *blob1 = [NSData dataWithBytesNoCopy:(void *)_blob1 length:_blob1Len freeWhenDone:NO];
		NSData *blob2 = [NSData dataWithBytesNoCopy:(void *)_blob2 length:_blob2Len freeWhenDone:NO];
		
		YDBCKChangeSet *changeSet = [[YDBCKChangeSet alloc] initWithUUID:uuid
		                                                            prev:prev
		                                              databaseIdentifier:dbid
		                                                deletedRecordIDs:blob1
		                                                 modifiedRecords:blob2];
		
		[changeSetsDict setObject:changeSet forKey:uuid];
		lastChangeSetFromEnumeration = changeSet;
	}
	
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_finalize(statement);
	statement = NULL;
	
	// Put the changeSets into the correct order.
	//
	// We have a reverse linked-list, where every element points to the previous one.
	// The first item in the linked-list will point to an item that no longer exists.
	// That is, when an item is removed from the front of the linked list,
	// we don't attempt to set next.prev = nil. (That would be unnecessary disk IO.)
	//
	// Also note that it's highly likely that the changeSets were enumerated in-order by sqlite.
	// This is because sqlite likely enumerated the rows by rowid,
	// and its very very likely the the highest rowid is the most recently inserted changeSet.
	//
	// So here's our algorithm:
	//
	// - Start with the lastChangeSetFromEnumeration.
	// - Add it to the array.
	// - Work backwards, looping, and adding prevChangeSet to the front of the array.
	// - At this point we have an array that contains the range [firstChangeSet, lastChangeSetFromEnumeration].
	// - If lastChangeSetFromEnumeration was indeed the lastChangeSet, then we're done.
	// - Otherwise we grab another changeSet from the dictionary,
	// - add it to the end of the array, and then begin working backwards again.
	
	NSMutableArray *orderedChangeSets = [NSMutableArray arrayWithCapacity:[changeSetsDict count]];
	
	YDBCKChangeSet *changeSet = lastChangeSetFromEnumeration;
	NSUInteger offset = 0;
	
	while (changeSet != nil)
	{
		// Add the changeSet to the end of the ordered array (and remove from dictionary)
		[orderedChangeSets addObject:changeSet];
		[changeSetsDict removeObjectForKey:changeSet.uuid];
		
		// Work backwards, filling in all previous changeSets
		do
		{
			changeSet = [changeSetsDict objectForKey:changeSet.prev];
			if (changeSet)
			{
				[orderedChangeSets insertObject:changeSet atIndex:offset];
				[changeSetsDict removeObjectForKey:changeSet.uuid];
			}
			
		} while (changeSet != nil);
		
		// Check to see if there are more in the dictionary,
		// and keep going if needed.
		
		__block YDBCKChangeSet *remainingChangeSet = nil;
		[changeSetsDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			remainingChangeSet = (YDBCKChangeSet *)obj;
			*stop = YES;
		}];
		
		changeSet = remainingChangeSet;
		offset = [orderedChangeSets count];
	}
	
	// Sanity check 1: Did we drain the changeSetsDict?
	
	if ([changeSetsDict count] != 0)
	{
		YDBLogError(@"Error restoring masterChangeQueue: Reverse-linked list corruption ! (A)");
		return NO;
	}
	
	// Sanity check 2: The changeSets are all in order
	
	NSString *prevUuid = [[orderedChangeSets firstObject] uuid];
	
	for (NSUInteger i = 1; i < [orderedChangeSets count]; i++)
	{
		YDBCKChangeSet *changeSet = [orderedChangeSets objectAtIndex:i];
		if (![changeSet.prev isEqualToString:prevUuid])
		{
			YDBLogError(@"Error restoring masterChangeQueue: Reverse-linked-list corruption ! (B)");
			return NO;
		}
		
		prevUuid = changeSet.uuid;
	}
	
	// Restore CKRecords as needed
	
	void (^RestoreRecordBlock)(int64_t rowid, CKRecord **inOutRecord, YDBCKRecordInfo *recordInfo);
	
	YapDatabaseCloudKitBlockType recordBlockType = parentConnection->parent->recordBlockType;
	if (recordBlockType == YapDatabaseCloudKitBlockTypeWithKey)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithKeyBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithKeyBlock)parentConnection->parent->recordBlock;
		
		RestoreRecordBlock = ^(int64_t rowid, CKRecord **inOutRecord, YDBCKRecordInfo *recordInfo) {
			
			YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
			if (ck)
			{
				recordBlock(inOutRecord, recordInfo, ck.collection, ck.key);
			}
		};
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithObject)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithObjectBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithObjectBlock)parentConnection->parent->recordBlock;
		
		RestoreRecordBlock = ^(int64_t rowid, CKRecord **inOutRecord, YDBCKRecordInfo *recordInfo) {
			
			YapCollectionKey *ck = nil;
			id object = nil;
			
			if ([databaseTransaction getCollectionKey:&ck object:&object forRowid:rowid])
			{
				recordBlock(inOutRecord, recordInfo, ck.collection, ck.key, object);
			}
		};
	}
	else if (recordBlockType == YapDatabaseCloudKitBlockTypeWithMetadata)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithMetadataBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithMetadataBlock)parentConnection->parent->recordBlock;
		
		RestoreRecordBlock = ^(int64_t rowid, CKRecord **inOutRecord, YDBCKRecordInfo *recordInfo) {
			
			YapCollectionKey *ck = nil;
			id metadata = nil;
			
			if ([databaseTransaction getCollectionKey:&ck metadata:&metadata forRowid:rowid])
			{
				recordBlock(inOutRecord, recordInfo, ck.collection, ck.key, metadata);
			}
		};
	}
	else // if (recordBlockType == YapDatabaseCloudKitBlockTypeWithRow)
	{
		__unsafe_unretained YapDatabaseCloudKitRecordWithRowBlock recordBlock =
		  (YapDatabaseCloudKitRecordWithRowBlock)parentConnection->parent->recordBlock;
		
		RestoreRecordBlock = ^(int64_t rowid, CKRecord **inOutRecord, YDBCKRecordInfo *recordInfo) {
			
			YapCollectionKey *ck = nil;
			id object = nil;
			id metadata = nil;
			
			if ([databaseTransaction getCollectionKey:&ck object:&object metadata:&metadata forRowid:rowid])
			{
				recordBlock(inOutRecord, recordInfo, ck.collection, ck.key, object, metadata);
			}
		};
	}
	
	YDBCKRecordInfo *recordInfo = [[YDBCKRecordInfo alloc] init];
	
	[orderedChangeSets enumerateObjectsUsingBlock:^(YDBCKChangeSet *changeSet, NSUInteger idx, BOOL *stop) {
		
		recordInfo.databaseIdentifier = changeSet.databaseIdentifier;
		[changeSet enumerateMissingRecordsWithBlock:^CKRecord *(int64_t rowid, NSArray *changedKeys) {
			
			recordInfo.changedKeysToRestore = changedKeys;
			
			YDBCKCleanRecordInfo *cleanRecordInfo = [self recordInfoForRowid:rowid cacheResult:NO];
			CKRecord *record = cleanRecordInfo.record;
			
			RestoreRecordBlock(rowid, &record, recordInfo);
			
			return record;
		}];
	}];
	
	// Restart the uploads
	
	[self queueOperationsForChangeSets:orderedChangeSets];
	
	// Done!
	
	[parentConnection->parent->masterQueue restoreOldChangeSets:orderedChangeSets];
	return YES;
}

- (BOOL)populateTables
{
	// Todo...
	
	return YES;
}

- (BOOL)repopulateTables
{
	// Todo...
	
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
#pragma mark Utilities - General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int64_t)hashRecordID:(CKRecordID *)recordID
{
	// It would be nice to simply use [recordID hash].
	// But we don't have any control over this method,
	// meaning that Apple may choose to change it in a later release.
	//
	// We need to use a hashing technique that will remain constant
	// because we are storing this hash value in the database (for quick lookup purposes).
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
	
	void *buffer = malloc((size_t)len); // Todo: Use the stack if not too big (like YapDatabaseString)
	
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
		
		record = [YapDatabaseCKRecord deserializeRecord:data];
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
			
			CKRecord *record = [YapDatabaseCKRecord deserializeRecord:data];
			
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
		
		CKRecord *record = [YapDatabaseCKRecord deserializeRecord:data];
		
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
	
	__attribute__((objc_precise_lifetime)) NSData *recordBlob = [YapDatabaseCKRecord serializeRecord:record];
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
	
	return [YapDatabaseCKRecord deserializeRecord:recordBlob];
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

/**
 *
**/
- (BOOL)getRowid:(int64_t *)rowidPtr forRecordID:(CKRecordID *)recordID
                              databaseIdentifier:(NSString *)databaseIdentifier
{
	if (recordID == nil) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	
	sqlite3_stmt *statement = [parentConnection recordTable_getRowidForRecordStatement];
	if (statement == NULL) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	
	BOOL result = NO;
	int64_t rowid = 0;
	
	// SELECT "rowid" FROM "recordTableName" WHERE "recordIDHash" = ? AND "databaseIdentifier" = ?;
	
	int64_t recordHash = [self hashRecordID:recordID];
	sqlite3_bind_int64(statement, 1, recordHash);
	
	YapDatabaseString _dbid; MakeYapDatabaseString(&_dbid, databaseIdentifier);
	if (databaseIdentifier)
		sqlite3_bind_text(statement, 2, _dbid.str, _dbid.length, SQLITE_STATIC);
	else
		sqlite3_bind_null(statement, 2);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		rowid = sqlite3_column_int64(statement, 0);
		result = YES;
	}
	else if (status != SQLITE_DONE)
	{
		YDBLogError(@"%@ - Error executing statement: %d %s", THIS_METHOD,
					status, sqlite3_errmsg(databaseTransaction->connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_dbid);
	
	if (rowidPtr) *rowidPtr = rowid;
	return result;
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
	
	NSAssert(changeSet.hasChangesToDeletedRecordIDs || changeSet.hasChangesToModifiedRecords,
	         @"Method expected modified changeSet !");
	
	if (changeSet.hasChangesToDeletedRecordIDs && !changeSet.hasChangesToModifiedRecords)
	{
		// Update "deletedRecordIDs" value
		
		sqlite3_stmt *statement = [parentConnection queueTable_updateDeletedRecordIDsStatement];
		if (statement == NULL) {
			return;
		}
		
		// UPDATE "queueTqbleName" SET "deletedRecordIDs" = ? WHERE "uuid" = ?;
		
		__attribute__((objc_precise_lifetime)) NSData *blob = [changeSet serializeDeletedRecordIDs];
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
	else if (!changeSet.hasChangesToDeletedRecordIDs && changeSet.hasChangesToModifiedRecords)
	{
		// Update "modifiedRecords" value
		
		sqlite3_stmt *statement = [parentConnection queueTable_updateModifiedRecordsStatement];
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
	else if (changeSet.hasChangesToDeletedRecordIDs && changeSet.hasChangesToModifiedRecords)
	{
		// Update "deletedRecordIDs" && "modifiedRecords" value
		
		sqlite3_stmt *statement = [parentConnection queueTable_updateBothStatement];
		if (statement == NULL) {
			return;
		}
		
		// UPDATE "queueTableName" SET "deletedRecordIDs" = ?, "modifiedRecords" = ? WHERE "uuid" = ?;
		
		__attribute__((objc_precise_lifetime)) NSData *drBlob = [changeSet serializeDeletedRecordIDs];
		if (drBlob)
			sqlite3_bind_blob(statement, 1, drBlob.bytes, (int)drBlob.length, SQLITE_STATIC);
		else
			sqlite3_bind_null(statement, 1);
		
		__attribute__((objc_precise_lifetime)) NSData *mrBlob = [changeSet serializeModifiedRecords];
		if (mrBlob)
			sqlite3_bind_blob(statement, 2, mrBlob.bytes, (int)mrBlob.length, SQLITE_STATIC);
		else
			sqlite3_bind_null(statement, 2);
		
		YapDatabaseString _uuid; MakeYapDatabaseString(&_uuid, changeSet.uuid);
		sqlite3_bind_text(statement, 3, _uuid.str, _uuid.length, SQLITE_STATIC);
		
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
		int64_t rowid = 0;
		if ([self getRowid:&rowid forRecordID:record.recordID databaseIdentifier:databaseIdentifier])
		{
			rowidNumber = @(rowid);
		}
	}
	
	if (rowidNumber)
	{
		sqlite3_stmt *statement = [parentConnection recordTable_updateForRowidStatement];
		if (statement == NULL) {
			return;
		}
		
		// UPDATE "recordTableName" SET "record" = ? WHERE "rowid" = ?;
		
		__attribute__((objc_precise_lifetime)) NSData *recordBlob = [YapDatabaseCKRecord serializeRecord:record];
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
		
		CKRecord *sanitizedRecord = [YapDatabaseCKRecord deserializeRecord:recordBlob];
		
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
	
	// Step 1 of 5:
	//
	// Create a pendingQueue,
	// and lock the masterQueue so we can make changes to it.
	
	YDBCKChangeQueue *masterQueue = parentConnection->parent->masterQueue;
	YDBCKChangeQueue *pendingQueue = [masterQueue newPendingQueue];
	
	parentConnection->pendingQueue = pendingQueue;
	
	// Step 1 of 4:
	//
	// Use YDBCKChangeQueue tools to generate a list of updates for the queue table.
	// Also, make a list of the deletedRowids.
	
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
			
			if (dirtyRecordInfo.remoteDeletion)
			{
				[masterQueue updatePendingQueue:pendingQueue
				         withRemoteDeletedRowid:rowidNumber
				                       recordID:dirtyRecordInfo.dirty_record.recordID // I don't think we'll have this?
				             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
			}
			else if (dirtyRecordInfo.skipUploadDeletion)
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
			// The CKRecord has been modified via one or more of the following:
			//
			// - [transaction setObject:forKey:inCollection:]
			// - [[transaction ext:ck] detachKey:inCollection:]
			// - [[transaction ext:ck] attachRecord:forKey:inCollection:]
			
			if ([dirtyRecordInfo wasInserted])
			{
				// [dirtyRecordInfo wasInserted] => there wasn't a previously set record for this item.
				
				if (dirtyRecordInfo.remoteMerge)
				{
					[masterQueue updatePendingQueue:pendingQueue
						                withMergedRowid:rowidNumber
						                         record:dirtyRecordInfo.dirty_record
						             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
				}
				else if (dirtyRecordInfo.skipUploadRecord == NO)
				{
					[masterQueue updatePendingQueue:pendingQueue
					              withInsertedRowid:rowidNumber
					                         record:dirtyRecordInfo.dirty_record
					             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
				}
			}
			else
			{
				if ([dirtyRecordInfo databaseIdentifierOrRecordIDChanged])
				{
					if (dirtyRecordInfo.skipUploadDeletion)
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
					
					if (dirtyRecordInfo.remoteMerge)
					{
						[masterQueue updatePendingQueue:pendingQueue
						                withMergedRowid:rowidNumber
						                         record:dirtyRecordInfo.dirty_record
						             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
					}
					else
					{
						[masterQueue updatePendingQueue:pendingQueue
						              withInsertedRowid:rowidNumber
						                         record:dirtyRecordInfo.dirty_record
						             databaseIdentifier:dirtyRecordInfo.dirty_databaseIdentifier];
					}
				}
				else
				{
					if (dirtyRecordInfo.remoteMerge)
					{
						[masterQueue updatePendingQueue:pendingQueue
						                withMergedRowid:rowidNumber
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
		}
	}];
	
	// Step 2 of 4:
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
				sanitizedRecord = [YapDatabaseCKRecord sanitizedRecord:dirtyRecordInfo.dirty_record];
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
	
	// Step 3 of 4:
	//
	// Update queue table.
	// This includes any changes the pendingQueue table gives us.
	
	for (YDBCKChangeSet *oldChangeSet in pendingQueue.changeSetsFromPreviousCommits)
	{
		if (oldChangeSet.hasChangesToDeletedRecordIDs || oldChangeSet.hasChangesToModifiedRecords)
		{
			[self updateRowWithChangeSet:oldChangeSet];
		}
	}
	
	for (YDBCKChangeSet *newChangeSet in pendingQueue.changeSetsFromCurrentCommit)
	{
		[self insertRowWithChangeSet:newChangeSet];
	}
	
	// Step 4 of 4:
	//
	// Update the masterQueue,
	// and unlock it so the next operation can be dispatched.
	
	[masterQueue mergePendingQueue:pendingQueue];
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (void)didCommitTransaction
{
	YDBLogAutoTrace();
	
	// Now that the commit has hit the disk,
	// we can create all the NSOperation(s) with all the changes, and hand them to CloudKit.
	
	[self queueOperationsForChangeSets:parentConnection->pendingQueue.newChangeSets];
	
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
	
	// Check for pre-attached record
	
	YDBCKDirtyRecordInfo *dirtyRecordInfo = nil;
	
	dirtyRecordInfo = [parentConnection->pendingAttachRequests objectForKey:collectionKey];
	if (dirtyRecordInfo)
	{
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		
		[parentConnection->pendingAttachRequests removeObjectForKey:collectionKey];
		
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
		
		if (dirtyRecordInfo.skipUploadRecord && ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo.skipUploadRecord = NO;
		}
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
		
		if (dirtyRecordInfo.skipUploadRecord && ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo.skipUploadRecord = NO;
		}
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
		
		if (dirtyRecordInfo.skipUploadRecord && ([record.changedKeys count] > 0))
		{
			dirtyRecordInfo.skipUploadRecord = NO;
		}
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
	else if ([cleanDirtyRecordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
	{
		__unsafe_unretained YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)cleanDirtyRecordInfo;
		
		dirtyRecordInfo.dirty_record = nil;
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
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is use to associate an existing CKRecord with a row in the database.
 * There are two primary use cases for this method.
 * 
 * 1. To associate a discovered/pulled CKRecord with a row in the database before we insert it.
 *    In particular, for the following situation:
 *    
 *    - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 *    - You discover a record that was inserted by another device.
 *    - You need to add a corresponding row to the database,
 *      but you somehow need to inform the YapDatabaseCloud extension about the existing record,
 *      and tell it not to bother invoking the recordHandler, or attempting to upload the existing record.
 *    - So you invoke this method FIRST.
 *    - And THEN you insert the corresponding object into the database via the
 *      normal setObject:forKey:inCollection method (or similar methods).
 *
 * 2. To assist in the migration process when switching to YapDatabaseCloudKit.
 *    In particular, for the following situation:
 * 
 *    - You have an existing object in the database that is associated with a CKRecord.
 *    - You've been handling CloudKit manually (not via YapDatabaseCloudKit).
 *    - You have an existing CKRecord that is up-to-date.
 *    - And you now want YapDatabaseCloudKit to manage the CKRecord for you.
 * 
 * Thus, this methods works as a simple "hand-off" of the CKRecord to the YapDatabaseCloudKit extension.
 *
 * In other words, YapDatbaseCloudKit will write the system fields of the given CKRecord to its internal table,
 * and associate it with the given collection/key tuple.
 * 
 * @param record
 *   The CKRecord to associate with the collection/key tuple.
 * 
 * @param databaseIdentifer
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseBlock.
 *
 * @param key
 *   The key of the row to associaed the record with.
 * 
 * @param collection
 *   The collection of the row to associate the record with.
 * 
 * @param shouldUpload
 *   If NO, then the record is simply associated with the collection/key,
 *     and YapDatabaseCloudKit doesn't attempt to push the record to the cloud.
 *   If YES, then the record is associated with the collection/key ,
 *     and YapDatabaseCloutKit assumes the given record is dirty and attempts to push the record to the cloud.
 * 
 * @return
 *   YES if the record was associated with the given collection/key.
 *   NO if one of the following errors occurred.
 * 
 * The following errors will prevent this method from succeeding:
 * - The given record is nil.
 * - The given collection/key is already associated with another record.
 * - The recordID/databaseIdentifier is already associated with another collection/key.
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (BOOL)attachRecord:(CKRecord *)record
  databaseIdentifier:(NSString *)databaseIdentifier
              forKey:(NSString *)key
        inCollection:(NSString *)collection
  shouldUploadRecord:(BOOL)shouldUpload
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return NO;
	}
	
	// Sanity checks
	
	if (record == nil) {
		return NO;
	}
	if (key == nil) {
		return NO;
	}
	
	// Check for attachedRecord that hasn't been inserted into the database yet.
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		CKRecord *dirtyRecord = shouldUpload ? record : [YapDatabaseCKRecord sanitizedRecord:record];
		
		YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.dirty_record = dirtyRecord;
		dirtyRecordInfo.dirty_databaseIdentifier = databaseIdentifier;
		dirtyRecordInfo.skipUploadRecord = !shouldUpload;
		
		if (parentConnection->pendingAttachRequests == nil)
			parentConnection->pendingAttachRequests = [[NSMutableDictionary alloc] initWithCapacity:1];
		
		[parentConnection->pendingAttachRequests setObject:dirtyRecordInfo forKey:collectionKey];
		
		return YES;
	}
	
	// Handle other attach scenarios.
	
	YDBCKDirtyRecordInfo *dirtyRecordInfo = nil;
	
	id existingRecordInfo = [self recordInfoForRowid:rowid cacheResult:YES];
	BOOL isAssociatedWithAnotherRecord = NO;
	
	if (existingRecordInfo)
	{
		if ([existingRecordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			isAssociatedWithAnotherRecord = YES;
		}
		else
		{
			dirtyRecordInfo = (YDBCKDirtyRecordInfo *)existingRecordInfo;
			if (dirtyRecordInfo.dirty_record)
			{
				isAssociatedWithAnotherRecord = YES;
			}
		}
	}
	
	if (isAssociatedWithAnotherRecord)
	{
		// The collection/key is already associated with an existing record.
		// You must detach it first.
		return NO;
	}
	
	// Make the association
	//
	// shouldUpload == YES : Store record as-is for upload.
	// shouldUpload ==  NO : Store sanitized version of the record.
	//                       This allows for future modifications within this transaction.
	
	CKRecord *dirtyRecord = shouldUpload ? record : [YapDatabaseCKRecord sanitizedRecord:record];
	
	if (dirtyRecordInfo == nil)
	{
		dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
	}
	
	dirtyRecordInfo.dirty_record = dirtyRecord;
	dirtyRecordInfo.dirty_databaseIdentifier = databaseIdentifier;
	dirtyRecordInfo.skipUploadRecord = !shouldUpload;
	
	[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	
	return YES;
}

/**
 * This method is use to unassociate an existing CKRecord with a row in the database.
 * There are three primary use cases for this method.
 * 
 * 1. To properly handle CKRecordID's that are reported as deleted from the server.
 *    In particular, for the following situation:
 *    
 *    - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 *    - You discover a recordID that was deleted by another device.
 *    - You need to remove the associated record from the database,
 *      but you also need to inform the YapDatabaseCloud extension that it was remotely deleted,
 *      so it won't bother attempting to upload the already deleted recordID.
 *    - So you invoke this method FIRST.
 *    - And THEN you remove the corresponding object from the database via the
 *      normal remoteObjectForKey:inCollection: method (or similar methods).
 * 
 * 2. To assist in various migrations, such as version migrations.
 *    For example:
 * 
 *    - In version 2 of your app, you need to move a few CKRecords into a new zone.
 *    - But you don't want to delete the items from the old zone,
 *      because you need to continue supporting v1.X for awhile.
 *    - So you invoke this method first in order to drop the previously associated record.
 *    - And then you can attach the new CKRecords,
 *      and have YapDatabaseCloudKit upload the new records (to their new zone).
 * 
 * 3. To "move" an object from the cloud to "local-only".
 *    For example:
 * 
 *    - You're making a Notes app that allows user to stores notes locally, or in the cloud.
 *    - The user moves an existing note from the cloud, to local-storage only.
 *    - This method can be used to delete the item from the cloud without deleting it locally.
 * 
 * @param key
 *   The key of the row associated with the record to detach.
 *   
 * @param collection
 *   The collection of the row associated with the record to detach.
 * 
 * @param wasRemoteDeletion
 *   If you're invoking this method because the server notified you of a deleted CKRecordID,
 *   then be sure to pass YES for this parameter. Doing so allows the extension to properly modify the
 *   changeSets that are still queued for upload so that it can remove potential modifications for this recordID.
 * 
 * @param shouldUpload
 *   Whether or not the extension should push a deleted CKRecordID to the cloud.
 *   In use case #2 (from the discussion of this method, concerning migration), you'd pass NO.
 *   In use case #3 (from the discussion of this method, concerning moving), you'd pass YES.
 *   This parameter is ignored if wasRemoteDeletion is YES.
 * 
 * Note: If you're notified of a deleted CKRecordID from the server,
 *       and you're unsure of the associated local collection/key,
 *       then you can use the getKey:collection:forRecordID:databaseIdentifier: method.
 * 
 * @see getKey:collection:forRecordID:databaseIdentifier:
**/
- (void)detachRecordForKey:(NSString *)key
              inCollection:(NSString *)collection
         wasRemoteDeletion:(BOOL)wasRemoteDeletion
      shouldUploadDeletion:(BOOL)shouldUpload
{
	YDBLogAutoTrace();
	
	// Proper API usage check
	if (!databaseTransaction->isReadWriteTransaction)
	{
		@throw [self requiresReadWriteTransactionException:NSStringFromSelector(_cmd)];
		return;
	}
	
	int64_t rowid;
	if (![databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		YDBLogWarn(@"%@ - No row in database with given collection/key: %@, %@", THIS_METHOD, collection, key);
		return;
	}
	
	id recordInfo = [self recordInfoForRowid:rowid cacheResult:NO];
	
	if ([recordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
	{
		YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)recordInfo;
		
		YDBCKDirtyRecordInfo *dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_recordID = cleanRecordInfo.record.recordID;
		dirtyRecordInfo.clean_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
		dirtyRecordInfo.dirty_record = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = cleanRecordInfo.databaseIdentifier;
		dirtyRecordInfo.remoteDeletion = wasRemoteDeletion;
		dirtyRecordInfo.skipUploadDeletion = !shouldUpload;
		
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
	}
	else if ([recordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
	{
		YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)recordInfo;
		
		dirtyRecordInfo.dirty_record = nil;
		dirtyRecordInfo.dirty_databaseIdentifier = nil;
		dirtyRecordInfo.remoteDeletion = wasRemoteDeletion;
		dirtyRecordInfo.skipUploadDeletion = !shouldUpload;
	}
}

/**
 * This method is used to merge a pulled record from the server with what's in the database.
 * In particular, for the following situation:
 *
 * - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 * - You discover a record that was modified by another device.
 * - You need to properly merge the changes with your own version of the object in the database,
 *   and you also need to inform YapDatabaseCloud extension about the merger
 *   so it can properly handle any changes that were pending a push to the cloud.
 * 
 * Thus, you should use this method, which will invoke your mergeBlock with the appropriate parameters.
 * 
 * @param record
 *   A record that was modified remotely, and discovered via CKFetchRecordChangesOperation (or similar).
 * 
 * @param databaseIdentifier
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseBlock.
 * 
 * @param key (optional)
 *   If the key & collection of the corresponding object are known, then you should pass them.
 *   This allows the method to skip the overhead of doing the lookup itself.
 *   If unknown, then you can simply pass nil, and it will do the appropriate lookup.
 * 
 * @param collection (optional)
 *   If the key & collection of the corresponding object are known, then you should pass them.
 *   This allows the method to skip the overhead of doing the lookup itself.
 *   If unknown, then you can simply pass nil, and it will do the appropriate lookup.
**/
- (void)mergeRecord:(CKRecord *)remoteRecord
 databaseIdentifier:(NSString *)databaseIdentifer
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
	
	if (remoteRecord == nil)
	{
		YDBLogWarn(@"%@ - Unable to merge a nil record! Did you mean to detach the recordID?", THIS_METHOD);
		return;
	}
	
	BOOL found = NO;
	int64_t rowid = 0;
	
	if (key == nil)
	{
		found = [self getKey:&key
		          collection:&collection
		         forRecordID:remoteRecord.recordID
		  databaseIdentifier:databaseIdentifer];
	}
	else
	{
		found = [databaseTransaction getRowid:&rowid forKey:key inCollection:collection];
	}
	
	if (!found)
	{
		YDBLogWarn(@"%@ - Unable to merge record: No associated collection/key! Did you mean to attach the record?",
		           THIS_METHOD);
		return;
	}
	if (collection == nil) collection = @"";
	
	// Make sanitized copies of the remoteRecord.
	// Sanitized == copy of the system fields only, without any values.
	
	CKRecord *pendingLocalRecord = [YapDatabaseCKRecord sanitizedRecord:remoteRecord];
	CKRecord *newLocalRecord = [pendingLocalRecord copy];
	
	// And then infuse the localRecord with any key/value pairs that are pending upload.
	//
	// First we start with any previous commits.
	
	BOOL hasPendingChanges =
	  [parentConnection->parent->masterQueue mergeChangesForRowid:@(rowid) intoRecord:pendingLocalRecord];
	
	// And then we check changes from this readWriteTransaction, just in case.
	
	YDBCKDirtyRecordInfo *dirtyRecordInfo = [parentConnection->dirtyRecordInfo objectForKey:@(rowid)];
	if (dirtyRecordInfo)
	{
		for (NSString *changedKey in dirtyRecordInfo.dirty_record.changedKeys)
		{
			id value = [dirtyRecordInfo.dirty_record valueForKey:changedKey];
			if (value) {
				[pendingLocalRecord setValue:value forKey:changedKey];
			}
		}
		
		hasPendingChanges = YES;
	}
	
	CKRecordID *recordID = remoteRecord.recordID;
	
	// Invoke the mergeBlock
	
	__unsafe_unretained YapDatabaseCloudKitMergeBlock mergeBlock = parentConnection->parent->mergeBlock;
	__unsafe_unretained YapDatabaseReadWriteTransaction *rwTransaction =
	  (YapDatabaseReadWriteTransaction *)databaseTransaction;
	
	if (hasPendingChanges)
		mergeBlock(rwTransaction, collection, key, remoteRecord, pendingLocalRecord, newLocalRecord);
	else
		mergeBlock(rwTransaction, collection, key, remoteRecord, nil, nil);
	
	// And store the results
	
	if (dirtyRecordInfo == nil)
	{
		dirtyRecordInfo = [[YDBCKDirtyRecordInfo alloc] init];
		dirtyRecordInfo.clean_recordID = recordID;
		dirtyRecordInfo.clean_databaseIdentifier = databaseIdentifer;
		
		[parentConnection->dirtyRecordInfo setObject:dirtyRecordInfo forKey:@(rowid)];
		[parentConnection->cleanRecordInfo removeObjectForKey:@(rowid)];
	}
	
	dirtyRecordInfo.dirty_record = hasPendingChanges ? newLocalRecord : newLocalRecord;
	dirtyRecordInfo.dirty_databaseIdentifier = databaseIdentifer;
	dirtyRecordInfo.remoteMerge = YES;
}

/**
 * If the given recordID & databaseIdentifier are associated with row in the database,
 * then this method will return YES, and set the collectionPtr/keyPtr with the collection/key of the associated row.
 * 
 * @param keyPtr (optional)
 *   If non-null, and this method returns YES, then the keyPtr will be set to the associated row's key.
 * 
 * @param collectionPtr (optional)
 *   If non-null, and this method returns YES, then the collectionPtr will be set to the associated row's collection.
 * 
 * @param recordID
 *   The CKRecordID to look for.
 * 
 * @param databaseIdentifier
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseBlock.
 * 
 * @return
 *   YES if the given recordID & databaseIdentifier are associated with a row in the database.
 *   NO otherwise.
**/
- (BOOL)getKey:(NSString **)keyPtr collection:(NSString **)collectionPtr
                                  forRecordID:(CKRecordID *)recordID
                           databaseIdentifier:(NSString *)databaseIdentifier
{
	NSString *key = nil;
	NSString *collection = nil;
	
	int64_t rowid = 0;
	if ([self getRowid:&rowid forRecordID:recordID databaseIdentifier:databaseIdentifier])
	{
		YapCollectionKey *ck = [databaseTransaction collectionKeyForRowid:rowid];
		key = ck.key;
		collection = ck.collection;
	}
	
	if (keyPtr) *keyPtr = key;
	if (collectionPtr) *collectionPtr = collection;
	
	return (key != nil);
}

/**
 * If the given key/collection tuple is associated with a record,
 * then this method returns YES, and sets the recordIDPtr & databaseIdentifierPtr accordingly.
 * 
 * @param recordIDPtr (optional)
 *   If non-null, and this method returns YES, then the recordIDPtr will be set to the associated recordID.
 * 
 * @param databaseIdentifierPtr (optional)
 *   If non-null, and this method returns YES, then the databaseIdentifierPtr will be set to the associated value.
 *   Keep in mind that nil is a valid databaseIdentifier,
 *   and is generally used to signify the defaultContainer/privateCloudDatabase.
 *
 * @param key
 *   The key of the row in the database.
 * 
 * @param collection
 *   The collection of the row in the database.
 * 
 * @return
 *   YES if the given collection/key is associated with a CKRecord.
 *   NO otherwise.
**/
- (BOOL)getRecordID:(CKRecordID **)recordIDPtr
 databaseIdentifier:(NSString **)databaseIdentifierPtr
             forKey:(NSString *)key
       inCollection:(NSString *)collection
{
	CKRecordID *recordID = nil;
	NSString *databaseIdentifier = nil;
	
	int64_t rowid = 0;
	if ([databaseTransaction getRowid:&rowid forKey:key inCollection:collection])
	{
		id recordInfo = [self recordInfoForRowid:rowid cacheResult:YES];
		
		if ([recordInfo isKindOfClass:[YDBCKCleanRecordInfo class]])
		{
			YDBCKCleanRecordInfo *cleanRecordInfo = (YDBCKCleanRecordInfo *)recordInfo;
			
			recordID = cleanRecordInfo.record.recordID;
			databaseIdentifier = cleanRecordInfo.databaseIdentifier;
		}
		else if ([recordInfo isKindOfClass:[YDBCKDirtyRecordInfo class]])
		{
			YDBCKDirtyRecordInfo *dirtyRecordInfo = (YDBCKDirtyRecordInfo *)recordInfo;
			
			recordID = dirtyRecordInfo.dirty_record.recordID;
			databaseIdentifier = dirtyRecordInfo.dirty_databaseIdentifier;
		}
	}
	
	if (recordIDPtr) *recordIDPtr = recordID;
	if (databaseIdentifierPtr) *databaseIdentifierPtr = databaseIdentifier;
	
	return (recordID != nil);
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

- (NSException *)requiresReadWriteTransactionException:(NSString *)methodName
{
	NSString *reason = [NSString stringWithFormat:
	  @"The method [YapDatabaseCloudKitTransaction %@] can only be used within a readWriteTransaction.", methodName];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

@end
