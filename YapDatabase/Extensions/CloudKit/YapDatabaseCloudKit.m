#import "YapDatabaseCloudKitPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseLogging.h"

#import <libkern/OSAtomic.h>

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


@implementation YapDatabaseCloudKit
{
	NSUInteger suspendCount;
	OSSpinLock suspendCountLock;
	
	NSOperationQueue *masterOperationQueue;
	
	dispatch_queue_t dispatchOperationQueue;
	
	YapDatabaseConnection *completionDatabaseConnection;
	YapCache *databaseCache;
}

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
@dynamic isSuspended;

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
		
		suspendCountLock = OS_SPINLOCK_INIT;
		
		dispatchOperationQueue = dispatch_queue_create("YapDatabaseCloudKit_dispatchOperation", DISPATCH_QUEUE_SERIAL);
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

- (BOOL)isSuspended
{
	BOOL isSuspended = NO;
	
	OSSpinLockLock(&suspendCountLock);
	{
		isSuspended = (suspendCount > 0);
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	return isSuspended;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Suspend & Resume
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Before the CloudKit stack can begin pushing changes to the cloud, there are generally several steps that
 * must be taken first. These include general configuration steps, as well as querying the server to
 * pull down changes from other devices that occurred while the app was offline.
 *
 * Some example steps that may need to be performed prior to taking the extension "online":
 * - registering for push notifications
 * - creating the needed CKRecordZone's (if needed)
 * - creating the zone subscriptions (if needed)
 * - pulling changes via CKFetchRecordChangesOperation
 * 
 * It's important that all these tasks get completed before the YapDatabaseCloudKit extension begins attempting
 * to push data to the cloud. For example, if the proper CKRecordZone's haven't been created yet, then attempting
 * to insert objects into those missing zones will fail. And if, after after being offline, we begin pushing our
 * changes to the server before we pull others' changes, then we'll likely just get a bunch of failures & conflicts.
 * Not to mention waste a lot of bandwidth in the process.
 * 
 * For this reason, there is a flexible mechanism to "suspend" the upload process.
 *
 * That is, if YapDatabaseCloudKit is "suspended", it still remains fully functional.
 * That is, it's still "listening" for changes in the database, and invoking the recordHandler block to track
 * changes to CKRecord's, etc. However, while suspended, it operates in a slightly different mode, wherein it
 * it only QUEUES its CKModifyRecords operations. (It suspends its internal master operationQueue.) And where it
 * may dynamically modify its pending queue in response to merges and continued changes to the database.
 * 
 * You MUST match every call to suspend with a matching call to resume.
 * For example, if you invoke suspend 3 times, then the extension won't resume until you've invoked resume 3 times.
 *
 * Use this to your advantage if you have multiple tasks to complete before you want to resume the extension.
 * From the example above, one would create and register the extension as usual when setting up YapDatabase
 * and all the normal extensions needed by the app. However, they would invoke the suspend method 3 times before
 * registering the extension with the database. And then, as each of the 3 required steps complete, they would
 * invoke the resume method. Therefore, the extension will be available immediately to start monitoring for changes
 * in the database. However, it won't start pushing any changes to the cloud until the 3 required step
 * have all completed.
 * 
 * @return
 *   The current suspend count.
 *   This will be 1 if the extension was previously active, and is now suspended due to this call.
 *   Otherwise it will be greater than one, meaning it was previously suspended,
 *   and you just incremented the suspend count.
**/
- (NSUInteger)suspend
{
	return [self suspendWithCount:1];
}

/**
 * This method operates the same as invoking the suspend method the given number of times.
 * That is, it increments the suspend count by the given number.
 *
 * You can invoke this method with a zero parameter in order to obtain the current suspend count, without modifying it.
 *
 * @see suspend
**/
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement
{
	BOOL overflow = NO;
	NSUInteger oldSuspendCount = 0;
	NSUInteger newSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		oldSuspendCount = suspendCount;
		
		if (suspendCount <= (NSUIntegerMax - suspendCountIncrement))
			suspendCount += suspendCountIncrement;
		else {
			suspendCount = NSUIntegerMax;
			overflow = YES;
		}
		
		newSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	if (overflow) {
		YDBLogWarn(@"%@ - The suspendCount has reached NSUIntegerMax!", THIS_METHOD);
	}
	
	if (YDB_LOG_INFO && (suspendCountIncrement > 0)) {
		if (newSuspendCount == 1)
			YDBLogInfo(@"=> SUSPENDED");
		else
			YDBLogInfo(@"=> SUSPENDED : suspendCount++ => %lu", (unsigned long)newSuspendCount);
	}
	
	return newSuspendCount;
}

- (NSUInteger)resume
{
	BOOL underflow = 0;
	NSUInteger newSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		if (suspendCount > 0)
			suspendCount--;
		else
			underflow = YES;
		
		newSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	if (underflow) {
		YDBLogWarn(@"%@ - Attempting to resume with suspendCount already at zero.", THIS_METHOD);
	}
	
	if (YDB_LOG_INFO) {
		if (newSuspendCount == 0)
			YDBLogInfo(@"=> RESUMED");
		else
			YDBLogInfo(@"=> SUSPENDED : suspendCount-- => %lu", (unsigned long)newSuspendCount);
	}
	
	if (newSuspendCount == 0 && !underflow) {
		[self asyncMaybeDispatchNextOperation];
	}
	
	return newSuspendCount;
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

- (void)asyncMaybeDispatchNextOperation
{
	YDBLogAutoTrace();
	
	dispatch_async(dispatchOperationQueue, ^{ @autoreleasepool {
		
		if (self.isSuspended)
		{
			YDBLogVerbose(@"Skipping dispatch operation - suspended");
			return;
		}
		
		YDBCKChangeSet *nextChangeSet = [masterQueue makeInFlightChangeSet];
		if (nextChangeSet == nil)
		{
			YDBLogVerbose(@"Skipping dispatch operation - upload in progress || nothing to upload");
			return;
		}
		
		YDBLogVerbose(@"Queueing operation: %@", nextChangeSet);
		[self queueOperationsForChangeSets:@[ nextChangeSet ]];
	}});
}


- (YapDatabaseConnection *)completionDatabaseConnection
{
	// Todo: Maybe figure out better solution for this ?
	
	if (completionDatabaseConnection == nil)
	{
		completionDatabaseConnection = [self.registeredDatabase newConnection];
		completionDatabaseConnection.objectCacheEnabled = NO;
		completionDatabaseConnection.metadataCacheEnabled = NO;
	}
	
	return completionDatabaseConnection;
}

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
			if (databaseBlock == nil) {
				@throw [self missingDatabaseBlockException:databaseIdentifier];
			}
			
			database = databaseBlock(databaseIdentifier);
			if (database == nil) {
				@throw [self missingDatabaseBlockException:databaseIdentifier];
			}
			
			if (databaseCache == nil)
				databaseCache = [[YapCache alloc] initWithKeyClass:[NSString class] countLimit:4];
			
			[databaseCache setObject:database forKey:databaseIdentifier];
		}
		
		return database;
	}
}

- (void)queueOperationsForChangeSets:(NSArray *)changeSets
{
	YDBLogAutoTrace();
	
	__weak YapDatabaseCloudKit *weakSelf = self;
	
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
			__strong YapDatabaseCloudKit *strongSelf = weakSelf;
			if (strongSelf)
			{
				if (operationError)
				{
					YDBLogError(@"Failed upload for (%@): %@", changeSet.databaseIdentifier, operationError);
					
					// I've seen:
					//
					// - CKErrorPartialFailure
					//   And operationError.userInfo returns a dictionary with a key of CKPartialErrorsByItemIDKey.
					//   key = CKRecordID
					//   value = CKError (with error code 14 = CKErrorServerRecordChanged)
					
					[strongSelf handleFailedOperation:changeSet withError:operationError];
				}
				else
				{
					YDBLogVerbose(@"Finished upload for (%@):\n  savedRecords: %@\n  deletedRecordIDs: %@",
					              changeSet.databaseIdentifier, savedRecords, deletedRecordIDs);
					
					[strongSelf handleCompletedOperation:changeSet withSavedRecords:savedRecords];
				}
			}
		};
		
		[masterOperationQueue addOperation:modifyRecordsOperation];
	}
}

- (void)handleFailedOperation:(YDBCKChangeSet *)changeSet withError:(NSError *)error
{
	YDBLogAutoTrace();
	
	// Todo: How to handle failed operations...
	
	masterOperationQueue.suspended = YES;
}

- (void)handleCompletedOperation:(YDBCKChangeSet *)changeSet withSavedRecords:(NSArray *)savedRecords
{
	YDBLogAutoTrace();
	
	NSString *extName = self.registeredName;
	
	[[self completionDatabaseConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)missingDatabaseBlockException:(NSString *)databaseIdentifier
{
	NSString *reason = [NSString stringWithFormat:
	  @"The YapDatabaseCloudKit instance was not configured with a databaseBlock (YapDatabaseCloudKitDatabaseBlock)."
	  @" However, we encountered an object with a databaseIdentifier (%@)."
	  @" The databaseBlock is required in order to discover the proper CKDatabase for the databaseIdentifier."
	  @" Without the CKDatabase, we don't know where to send the corresponding CKRecord/CKRecordID.",
	  databaseIdentifier];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

@end
