#import "YapDatabaseCloudKitPrivate.h"
#import "YapDatabasePrivate.h"
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


@implementation YapDatabaseCloudKit

/**
 * Subclasses MUST implement this method.
 *
 * This method is used when unregistering an extension in order to drop the related tables.
 * 
 * @param registeredName
 *   The name the extension was registered using.
 *   The extension should be able to generated the proper table name(s) using the given registered name.
 * 
 * @param transaction
 *   A readWrite transaction for proper database access.
 * 
 * @param wasPersistent
 *   If YES, then the extension should drop tables from sqlite.
 *   If NO, then the extension should unregister the proper YapMemoryTable(s).
**/
+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent
{
	sqlite3 *db = transaction->connection->db;
	
	NSString *recordTableName = [self recordTableNameForRegisteredName:registeredName];
	NSString *queueTableName  = [self recordTableNameForRegisteredName:registeredName];
	
	NSString *dropRecordTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", recordTableName];
	NSString *dropQueueTable  = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", queueTableName];
	
	int status;
	
	status = sqlite3_exec(db, [dropRecordTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping table (%@): %d %s",
		            THIS_METHOD, recordTableName, status, sqlite3_errmsg(db));
	}
	
	status = sqlite3_exec(db, [dropQueueTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping table (%@): %d %s",
		            THIS_METHOD, queueTableName, status, sqlite3_errmsg(db));
	}
}

+ (NSString *)recordTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"cloudKit_record_%@", registeredName];
}

+ (NSString *)queueTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"cloudKit_queue_%@", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize recordBlock = recordBlock;
@synthesize recordBlockType = recordBlockType;

@synthesize mergeBlock = mergeBlock;
@synthesize conflictBlock = conflictBlock;

@synthesize versionTag = versionTag;

@dynamic options;
@dynamic paused;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)inConflictBlock
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	                     conflictBlock:inConflictBlock
	                     databaseBlock:NULL
	                        versionTag:nil
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)inConflictBlock
                           versionTag:(NSString *)inVersionTag
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	                     conflictBlock:inConflictBlock
	                     databaseBlock:NULL
	                        versionTag:inVersionTag
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)inConflictBlock
                           versionTag:(NSString *)inVersionTag
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	                     conflictBlock:inConflictBlock
	                     databaseBlock:NULL
	                        versionTag:inVersionTag
	                           options:inOptions];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)inConflictBlock
                        databaseBlock:(YapDatabaseCloudKitDatabaseBlock)inDatabaseBlock
                           versionTag:(NSString *)inVersionTag
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	if ((self = [super init]))
	{
		recordBlock = recordHandler.recordBlock;
		recordBlockType = recordHandler.recordBlockType;
		
		mergeBlock = inMergeBlock;
		conflictBlock = inConflictBlock;
		databaseBlock = inDatabaseBlock;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseCloudKitOptions alloc] init];
		
		masterQueue = [[YDBCKChangeQueue alloc] initMasterQueue];
		
		masterOperationQueue = [[NSOperationQueue alloc] init];
		masterOperationQueue.maxConcurrentOperationCount = 1;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseCloudKitOptions *)options
{
	return [options copy]; // Our copy must remain immutable
}

- (BOOL)isPaused
{
	return masterOperationQueue.suspended;
}

- (void)setPaused:(BOOL)flag
{
	masterOperationQueue.suspended = flag;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtension Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseCloudKitConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Table Name
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)recordTableName
{
	return [[self class] recordTableNameForRegisteredName:self.registeredName];
}

- (NSString *)queueTableName
{
	return [[self class] queueTableNameForRegisteredName:self.registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseConnection *)completionDatabaseConnection
{
	// Todo: Figure out better solution for this...
	
	if (completionDatabaseConnection == nil)
	{
		completionDatabaseConnection = [self.registeredDatabase newConnection];
		completionDatabaseConnection.objectCacheEnabled = NO;
		completionDatabaseConnection.metadataCacheEnabled = NO;
	}
	
	return completionDatabaseConnection;
}

- (void)handleFailedOperation:(YDBCKChangeSet *)changeSet withError:(NSError *)error
{
	// Todo...
	
	masterOperationQueue.suspended = YES;
}

- (void)handleCompletedOperation:(YDBCKChangeSet *)changeSet withSavedRecords:(NSArray *)savedRecords
{
	NSString *extName = self.registeredName;
	
	[[self completionDatabaseConnection] asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		YapDatabaseCloudKitTransaction *ckTransaction = [transaction ext:extName];
		
		// Drop the row in the queue table that was storing all the information for this changeSet.
		
		[ckTransaction removeQueueRowWithUUID:changeSet.uuid];
		
		// Update any records that were saved.
		// We need to store the new system fields of the CKRecord.
		
		NSDictionary *mapping = [changeSet recordIDToRowidMapping];
		for (CKRecord *record in savedRecords)
		{
			NSNumber *rowidNumber = [mapping objectForKey:record.recordID];
			
			[ckTransaction updateRecord:record withDatabaseIdentifier:changeSet.databaseIdentifier
			                                           potentialRowid:rowidNumber];
		}
	}];
}

@end
