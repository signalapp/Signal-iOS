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

NSString *const YapDatabaseCloudKitSuspendCountChangedNotification = @"YDBCK_SuspendCountChanged";
NSString *const YapDatabaseCloudKitInFlightChangeSetChangedNotification = @"YDBCK_InFlightChangeSetChanged";

@implementation YapDatabaseCloudKit
{
	NSUInteger suspendCount;
	OSSpinLock suspendCountLock;
	
	NSOperationQueue *masterOperationQueue;
	
	YapDatabaseConnection *completionDatabaseConnection;
	YapCache<NSString *, CKDatabase *> *databaseCache;
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
	
	NSArray *tableNames = @[
	  [self mappingTableNameForRegisteredName:registeredName],
	  [self recordTableNameForRegisteredName:registeredName],
	  [self queueTableNameForRegisteredName:registeredName]
	];
	
	for (NSString *tableName in tableNames)
	{
		NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", tableName];
		
		int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping table (%@): %d %s",
			            THIS_METHOD, tableName, status, sqlite3_errmsg(db));
		}
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

@synthesize recordHandler = handler;
@synthesize mergeBlock = mergeBlock;
@synthesize operationErrorBlock = opErrorBlock;

@synthesize versionTag = versionTag;

@dynamic options;
@dynamic isSuspended;
@dynamic suspendCount;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)inRecordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
{
	return [self initWithRecordHandler:inRecordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:nil
	                       versionInfo:nil
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)inRecordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
{
	return [self initWithRecordHandler:inRecordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:inVersionTag
	                       versionInfo:inVersionInfo
	                           options:nil];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)inRecordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	return [self initWithRecordHandler:inRecordHandler
	                        mergeBlock:inMergeBlock
	               operationErrorBlock:inOpErrorBlock
	           databaseIdentifierBlock:NULL
	                        versionTag:inVersionTag
	                       versionInfo:inVersionInfo
	                           options:inOptions];
}

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)inRecordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)inMergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)inOpErrorBlock
              databaseIdentifierBlock:(YapDatabaseCloudKitDatabaseIdentifierBlock)inDatabaseIdentifierBlock
                           versionTag:(NSString *)inVersionTag
                          versionInfo:(id)inVersionInfo
                              options:(YapDatabaseCloudKitOptions *)inOptions
{
	if ((self = [super init]))
	{
		recordHandler = inRecordHandler;
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
	return ([self suspendCount] > 0);
}

- (NSUInteger)suspendCount
{
	NSUInteger currentSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		currentSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	return currentSuspendCount;
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
	NSUInteger newSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		if (suspendCount <= (NSUIntegerMax - suspendCountIncrement))
			suspendCount += suspendCountIncrement;
		else {
			suspendCount = NSUIntegerMax;
			overflow = YES;
		}
		
		newSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	if (overflow)
	{
		YDBLogWarn(@"%@ - The suspendCount has reached NSUIntegerMax!", THIS_METHOD);
	}
	else if (suspendCountIncrement > 0)
	{
		YDBLogInfo(@"=> SUSPENDED : incremented suspendCount == %lu", (unsigned long)newSuspendCount);
		
		[self postSuspendCountChangedNotification];
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
	
	if (underflow)
	{
		YDBLogWarn(@"%@ - Attempting to resume with suspendCount already at zero.", THIS_METHOD);
	}
	else
	{
		if (newSuspendCount == 0) { // <- { brackets } required when YapDatabaseLoggingTechnique_Disabled
			YDBLogInfo(@"=> RESUMED");
		}
		else {
			YDBLogInfo(@"=> SUSPENDED : decremented suspendCount == %lu", (unsigned long)newSuspendCount);
		}
		
		[self postSuspendCountChangedNotification];
	}
	
	if (newSuspendCount == 0 && !underflow)
	{
		BOOL forceNotification = NO;
		[self asyncMaybeDispatchNextOperation:forceNotification];
	}
	
	return newSuspendCount;
}

- (void)postSuspendCountChangedNotification
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[[NSNotificationCenter defaultCenter] postNotificationName:YapDatabaseCloudKitSuspendCountChangedNotification
		                                                    object:self];
	}};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Change-Sets
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the "current" changeSet,
 * which is either the inFlightChangeSet, or the next changeSet to go inFlight once resumed.
 *
 * In other words, the first YDBCKChangeSet in the queue.
**/
- (YDBCKChangeSet *)currentChangeSet
{
	return [masterQueue currentChangeSet];
}

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

/**
 * Faster access if you just want to get the counts.
 *
 * - numberOfInFlightChangeSets:
 *     YDBCKChangeSets that have been dispatched to CloudKit Framework.
 *     These may or may not succeed, depending upon network conditions & other factors.
 *
 * - numberOfQueuedChangeSets:
 *     YDBCKChangeSets that have not been dispatched to CloudKit Framework.
 *     They are waiting for the current inFlight change-sets to succeed, or for YDBCK to be resumed.
 *
 * - numberOfPendingChangeSets:
 *     Includes all YDBCKChangeSets, both inFlight & queued.
 *
 * In mathematical notion, the relationships are:
 *
 * numberOfInFlightChangeSets == numberOfPendingChangeSets - numberOfQueuedChangeSets
 * numberOfQueuedChangeSets   == numberOfPendingChangeSets - numberOfInFlightChangeSets
 * numberOfPendingChangeSets  == numberOfPendingChangeSets + numberOfQueuedChangeSets
**/
- (NSUInteger)numberOfInFlightChangeSets
{
	return [masterQueue numberOfInFlightChangeSets];
}
- (NSUInteger)numberOfQueuedChangeSets {
	return [masterQueue numberOfQueuedChangeSets];
}
- (NSUInteger)numberOfPendingChangeSets {
	return [masterQueue numberOfPendingChangeSets];
}
- (void)getNumberOfInFlightChangeSets:(NSUInteger *)numInFlightChangeSetsPtr
                     queuedChangeSets:(NSUInteger *)numQueuedChangeSetsPtr
{
	return [masterQueue getNumberOfInFlightChangeSets:numInFlightChangeSetsPtr
	                                 queuedChangeSets:numQueuedChangeSetsPtr];
}

- (void)postInFlightChangeSetChangedNotification:(NSString *)newChangeSetUUID
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSDictionary *details = nil;
		if (newChangeSetUUID) {
			details = @{ @"uuid" : newChangeSetUUID };
		}
		
		[[NSNotificationCenter defaultCenter]
		  postNotificationName:YapDatabaseCloudKitInFlightChangeSetChangedNotification
		                object:self
		              userInfo:details];
	}};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
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

- (void)asyncMaybeDispatchNextOperation:(BOOL)forceNotification
{
	YDBLogAutoTrace();
	
	// The 'forceNotification' parameter will be YES when this method
	// is being called after successfully completing a previous operation.
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(bgQueue, ^{ @autoreleasepool {
		
		if (self.isSuspended) // this method is thread-safe
		{
			YDBLogVerbose(@"Skipping dispatch operation - suspended");
			
			if (forceNotification) {
				[self postInFlightChangeSetChangedNotification:[masterQueue currentChangeSetUUID]];
			}
			return;
		}
		
		BOOL isAlreadyInFlight = NO;
		YDBCKChangeSet *nextChangeSet = nil;
		
		nextChangeSet = [masterQueue makeInFlightChangeSet:&isAlreadyInFlight]; // this method is thread-safe
		if (nextChangeSet == nil)
		{
			if (isAlreadyInFlight) { // <- { brackets } required when YapDatabaseLoggingTechnique_Disabled
				YDBLogVerbose(@"Skipping dispatch operation - upload in progress");
			}
			else {
				YDBLogVerbose(@"Skipping dispatch operation - nothing to upload");
			}
			
			if (forceNotification) {
				[self postInFlightChangeSetChangedNotification:[masterQueue currentChangeSetUUID]];
			}
			return;
		}
		
		if ([nextChangeSet->deletedRecordIDs count] == 0 &&
		    [nextChangeSet->modifiedRecords count] == 0)
		{
			YDBLogVerbose(@"Dropping empty queued operation: %@", nextChangeSet);
			
			NSString *changeSetUUID = nextChangeSet.uuid;
			
			[self handleCompletedOperationWithChangeSet:nextChangeSet savedRecords:nil deletedRecordIDs:nil];
			[self postInFlightChangeSetChangedNotification:changeSetUUID];
		}
		else
		{
			YDBLogVerbose(@"Queueing operation: %@", nextChangeSet);
			
			NSString *changeSetUUID = nextChangeSet.uuid;
			
			[self queueOperationForChangeSet:nextChangeSet];
			[self postInFlightChangeSetChangedNotification:changeSetUUID];
		}
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

- (void)queueOperationForChangeSet:(YDBCKChangeSet *)changeSet
{
	YDBLogAutoTrace();
	
	CKDatabase *database = [self databaseForIdentifier:changeSet.databaseIdentifier];
	
	NSArray *recordsToSave = changeSet.recordsToSave_noCopy;
	NSArray *recordIDsToDelete = changeSet.recordIDsToDelete;
	
	YDBLogVerbose(@"CKModifyRecordsOperation UPLOADING: databaseIdentifier = %@:\n"
				  @"  recordsToSave: %@\n"
				  @"  recordIDsToDelete: %@",
				  changeSet.databaseIdentifier, recordsToSave, recordIDsToDelete);
	
	CKModifyRecordsOperation *modifyRecordsOperation =
	  [[CKModifyRecordsOperation alloc] initWithRecordsToSave:recordsToSave recordIDsToDelete:recordIDsToDelete];
	modifyRecordsOperation.database = database;
	modifyRecordsOperation.savePolicy = CKRecordSaveIfServerRecordUnchanged;
	
	__weak YapDatabaseCloudKit *weakSelf = self;
	
	modifyRecordsOperation.modifyRecordsCompletionBlock =
	    ^(NSArray *savedRecords, NSArray *deletedRecordIDs, NSError *operationError)
	{
	#pragma clang diagnostic push
	#pragma clang diagnostic warning "-Wimplicit-retain-self"
		
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
			YDBLogVerbose(@"CKModifyRecordsOperation COMPLETE: databaseIdentifier = %@:\n"
			              @"  savedRecords: %@\n"
			              @"  deletedRecordIDs: %@",
			              changeSet.databaseIdentifier, savedRecords, deletedRecordIDs);
			
			[strongSelf handleCompletedOperationWithChangeSet:changeSet
			                                     savedRecords:savedRecords
			                                 deletedRecordIDs:deletedRecordIDs];
		}
		
	#pragma clang diagnostic pop
	};
		
	[masterOperationQueue addOperation:modifyRecordsOperation];
}

- (void)handleFailedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                     error:(NSError *)operationError
{
	YDBLogAutoTrace();
	
	// First, we suspend ourself.
	// It is the responsibility of the delegate to resume us at the appropriate time.
	
	[self suspend];
	
	// Then we reset changeSet.isInFlight to NO (since it failed).
	//
	// Note: For partially failed operations this step is done elsewhere.
	// Specifically, it's performed at the end of the databaseTransaction that removes the items that did complete.
	
	[masterQueue resetFailedInFlightChangeSet];
	[self postInFlightChangeSetChangedNotification:changeSet.uuid];
	
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
	
	NSDictionary *partialErrorsByItemID = [operationError.userInfo objectForKey:CKPartialErrorsByItemIDKey];
	NSMutableSet *failedRecordIDs = [NSMutableSet setWithCapacity:[partialErrorsByItemID count]];
	
	[partialErrorsByItemID enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
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
	NSString *databaseIdentifier = changeSet.databaseIdentifier;
	
	[[self completionDatabaseConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:extName] handlePartiallyCompletedOperationWithChangeSet:changeSet
		                                                             savedRecords:success_savedRecords
		                                                         deletedRecordIDs:success_deletedRecordIDs];
		
	} completionBlock:^{
		
		// Inform the user about the problem via the operationErrorBlock.
		
		opErrorBlock(databaseIdentifier, operationError);
	}];
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
