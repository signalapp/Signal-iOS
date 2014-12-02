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

+ (NSString *)mappingTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"cloudKit_mapping_%@", registeredName];
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
@synthesize operationErrorBlock = opErrorBlock;

@synthesize versionTag = versionTag;

@dynamic options;
@dynamic isSuspended;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:nil
	                       versionInfo:nil
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:inVersionTag
	                       versionInfo:inVersionInfo
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	return [self initWithRecordHandler:recordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:inVersionTag
	                       versionInfo:inVersionInfo
	                           options:inOptions];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
              databaseIdentifierBlock:(YapDatabaseCloudKitDatabaseIdentifierBlock)inDatabaseIdentifierBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	if ((self = [super init]))
	{
		recordBlock = recordHandler.recordBlock;
		recordBlockType = recordHandler.recordBlockType;
		
		mergeBlock = inMergeBlock;
		opErrorBlock = inOpErrorBlock;
		databaseIdentifierBlock = inDatabaseIdentifierBlock;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		versionInfo = inVersionInfo;
		
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
		YDBLogInfo(@"=> SUSPENDED : incremented suspendCount == %lu", (unsigned long)newSuspendCount);
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
			YDBLogInfo(@"=> SUSPENDED : decremented suspendCount == %lu", (unsigned long)newSuspendCount);
	}
	
	if (newSuspendCount == 0 && !underflow) {
		[self asyncMaybeDispatchNextOperation];
	}
	
	return newSuspendCount;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Change-Sets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an array of YDBCKChangeSet objects, which represent the pending (and in-flight) change-sets.
 * The array is ordered, such that:
 * - the first item in the array is either in-flight or the next to be uploaded
 * - the last item in the array represents the most recent change-set
 *
 * From this array you'll be able to see exactly what YapDatabaseCloudKit is uploading (or intends to upload).
 *
 * This is also useful if you want to perform a "dry run" test.
 * You can simply run a few tests with a debug database,
 * and keep the YapDatabaseCloudKit extension suspended the whole time.
 * Then just inspect the change-sets to ensure that everything is working as you expect.
**/
- (NSArray *)pendingChangeSets
{
	// Implementation Note:
	// The changeSetsFromPreviousCommits method is thread-safe,
	// and also creates fullCopies of all the change-sets so the user receives immutable copies.
	return [masterQueue changeSetsFromPreviousCommits];
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

- (NSString *)mappingTableName
{
	return [[self class] mappingTableNameForRegisteredName:self.registeredName];
}

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
			if (databaseIdentifierBlock == nil) {
				@throw [self missingDatabaseIdentifierBlockException:databaseIdentifier];
			}
			
			database = databaseIdentifierBlock(databaseIdentifier);
			if (database == nil) {
				@throw [self missingCKDatabaseException:databaseIdentifier];
			}
			
			if (databaseCache == nil) {
				databaseCache = [[YapCache alloc] initWithCountLimit:4];
				databaseCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
				databaseCache.allowedObjectClasses = [NSSet setWithObject:[CKDatabase class]];
			}
			
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
		
		NSArray *recordsToSave = changeSet.recordsToSave_noCopy;
		NSArray *recordIDsToDelete = changeSet.recordIDsToDelete;
		
		CKModifyRecordsOperation *modifyRecordsOperation =
		  [[CKModifyRecordsOperation alloc] initWithRecordsToSave:recordsToSave recordIDsToDelete:recordIDsToDelete];
		modifyRecordsOperation.database = database;
		
		modifyRecordsOperation.modifyRecordsCompletionBlock =
		    ^(NSArray *savedRecords, NSArray *deletedRecordIDs, NSError *operationError)
		{
			__strong YapDatabaseCloudKit *strongSelf = weakSelf;
			if (strongSelf == nil) return;
			
			if (operationError)
			{
				if (operationError.code == CKErrorPartialFailure)
				{
					YDBLogInfo(@"CKModifyRecordsOperation partial error: databaseIdentifier = %@\n"
					           @"  error = %@", changeSet.databaseIdentifier, operationError);
					
					[strongSelf handlePartiallyFailedOperationWithChangeSet:changeSet
					                                           savedRecords:savedRecords
					                                       deletedRecordIDs:deletedRecordIDs
					                                                  error:operationError];
				}
				else
				{
					YDBLogInfo(@"CKModifyRecordsOperation error: databaseIdentifier = %@\n"
					           @"  error = %@", changeSet.databaseIdentifier, operationError);
					
					[strongSelf handleFailedOperationWithChangeSet:changeSet
					                                         error:operationError];
				}
			}
			else
			{
				YDBLogVerbose(@"CKModifyRecordsOperation complete: databaseIdentifier = %@:\n"
				              @"  savedRecords: %@\n"
				              @"  deletedRecordIDs: %@",
				              changeSet.databaseIdentifier, savedRecords, deletedRecordIDs);
				
				[strongSelf handleCompletedOperationWithChangeSet:changeSet
				                                     savedRecords:savedRecords
				                                 deletedRecordIDs:deletedRecordIDs];
			}
		};
		
		[masterOperationQueue addOperation:modifyRecordsOperation];
	}
}

- (void)handleFailedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                     error:(NSError *)operationError
{
	YDBLogAutoTrace();
	
	// First, we suspend ourself.
	// It is the responsibility of the delegate to resume us at the appropriate time.
	
	[self suspend];
	
	// Inform the user about the problem via the operationErrorBlock.
	
	NSString *databaseIdentifier = changeSet.databaseIdentifier;
	dispatch_async(dispatch_get_main_queue(), ^{
		
		opErrorBlock(databaseIdentifier, operationError);
	});
}

- (void)handlePartiallyFailedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                       savedRecords:(NSArray *)attempted_savedRecords
                                   deletedRecordIDs:(NSArray *)attempted_deletedRecordIDs
                                              error:(NSError *)operationError
{
	// First, we suspend ourself.
	// It is the responsibility of the delegate to resume us at the appropriate time.
	
	[self suspend];
	
	// We need to figure out what succeeded.
	// So first we get a set of the recordIDs that failed.
	
	NSDictionary *partialErrorsByItemIDKey = [operationError.userInfo objectForKey:CKPartialErrorsByItemIDKey];
	NSMutableSet *failedRecordIDs = [NSMutableSet setWithCapacity:[partialErrorsByItemIDKey count]];
	
	[partialErrorsByItemIDKey enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained CKRecordID *recordID = (CKRecordID *)key;
	//	__unsafe_unretained NSError *recordError = (NSError *)obj;
		
		[failedRecordIDs addObject:recordID];
	}];
	
	// Then we remove the failed items from the attempted items.
	
	NSUInteger sCapacity = attempted_savedRecords.count;
	NSUInteger dCapacity = attempted_deletedRecordIDs.count;
	
	NSMutableArray *success_savedRecords     = [NSMutableArray arrayWithCapacity:sCapacity];
	NSMutableArray *success_deletedRecordIDs = [NSMutableArray arrayWithCapacity:dCapacity];
	
	for (CKRecord *record in attempted_savedRecords)
	{
		if (![failedRecordIDs containsObject:record.recordID])
		{
			[success_savedRecords addObject:record];
		}
	}
	for (CKRecordID *recordID in attempted_deletedRecordIDs)
	{
		if (![failedRecordIDs containsObject:recordID])
		{
			[success_deletedRecordIDs addObject:recordID];
		}
	}
	
	// Start the database transaction to update the queue(s) by removing those items that have succeeded.
	
	NSString *extName = self.registeredName;
	
	[[self completionDatabaseConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:extName] handlePartiallyCompletedOperationWithChangeSet:changeSet
		                                                             savedRecords:success_savedRecords
		                                                         deletedRecordIDs:success_deletedRecordIDs];
	}];
	
	// Inform the user about the problem via the operationErrorBlock.
	
	NSString *databaseIdentifier = changeSet.databaseIdentifier;
	dispatch_async(dispatch_get_main_queue(), ^{
		
		opErrorBlock(databaseIdentifier, operationError);
	});
}

- (void)handleCompletedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                 savedRecords:(NSArray *)savedRecords
                             deletedRecordIDs:(NSArray *)deletedRecordIDs
{
	YDBLogAutoTrace();
	
	NSString *extName = self.registeredName;
	
	[[self completionDatabaseConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:extName] handleCompletedOperationWithChangeSet:changeSet
		                                                    savedRecords:savedRecords
		                                                deletedRecordIDs:deletedRecordIDs];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)missingDatabaseIdentifierBlockException:(NSString *)databaseIdentifier
{
	NSString *reason = [NSString stringWithFormat:
	  @"The YapDatabaseCloudKit instance was not configured with a databaseIdentifierBlock."
	  @" However, we encountered an object with a non-nil databaseIdentifier (%@)."
	  @" The databaseIdentifierBlock is required in order to discover the proper CKDatabase for the databaseIdentifier."
	  @" Without the CKDatabase, we don't know where to send the corresponding CKRecord/CKRecordID.",
	  databaseIdentifier];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

- (NSException *)missingCKDatabaseException:(NSString *)databaseIdentifier
{
	NSString *reason = [NSString stringWithFormat:
	  @"The databaseIdentifierBlock returned nil for databaseIdentifier (%@)."
	  @" The databaseIdentifierBlock is required to return the proper CKDatabase for the databaseIdentifier."
	  @" Without the CKDatabase, we don't know where to send the corresponding CKRecord/CKRecordID.",
	  databaseIdentifier];
	
	return [NSException exceptionWithName:@"YapDatabaseCloudKit" reason:reason userInfo:nil];
}

@end
