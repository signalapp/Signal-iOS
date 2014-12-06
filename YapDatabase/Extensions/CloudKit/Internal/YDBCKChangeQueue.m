#import "YDBCKChangeQueue.h"
#import "YDBCKChangeSet.h"
#import "YDBCKChangeRecord.h"
#import "YapDatabaseCKRecord.h"
#import "YapDatabaseCloudKitPrivate.h"
//#import "YapDebugDictionary.h"


@interface YDBCKChangeQueue ()
@property (atomic, readwrite, strong) NSString *lockUUID;
@end

@implementation YDBCKChangeQueue
{
	BOOL isMasterQueue;
	NSLock *masterQueueLock;
	
	NSMutableArray *oldChangeSets;
	
	NSArray *newChangeSets;
	NSMutableDictionary *newChangeSetsDict;
}

@dynamic isMasterQueue;
@dynamic isPendingQueue;

@synthesize lockUUID;

- (instancetype)initMasterQueue
{
	if ((self = [super init]))
	{
		isMasterQueue = YES;
		masterQueueLock = [[NSLock alloc] init];
		
		oldChangeSets = [[NSMutableArray alloc] init];
	}
	return self;
}

#pragma mark Lifecycle

/**
 * This method is used during extension registration
 * after the old changeSets, from previous app run(s), have been restored.
**/
- (void)restoreOldChangeSets:(NSArray *)inOldChangeSets
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		[oldChangeSets addObjectsFromArray:inOldChangeSets];
	}
	[masterQueueLock unlock];
}

/**
 * If there is NOT already an in-flight changeSet, then this method sets the appropriate flag(s),
 * and returns the next changeSet ready for upload.
**/
- (YDBCKChangeSet *)makeInFlightChangeSet
{
	YDBCKChangeSet *inFlightChangeSet = nil;
	
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		YDBCKChangeSet *nextChangeSet = [oldChangeSets firstObject];
		
		if (nextChangeSet && !nextChangeSet.isInFlight)
		{
			nextChangeSet.isInFlight = YES;
			inFlightChangeSet = [nextChangeSet fullCopy];
		}
	}
	[masterQueueLock unlock];
	
	return inFlightChangeSet;
}

/**
 * If there is an in-flight changeSet,
 * then this method removes it to make room for new in-flight changeSets.
**/
- (void)removeCompletedInFlightChangeSet
{
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		YDBCKChangeSet *firstChangeSet = [oldChangeSets firstObject];
		if (firstChangeSet.isInFlight)
		{
			firstChangeSet.isInFlight = NO;
			[oldChangeSets removeObjectAtIndex:0];
		}
	}
	[masterQueueLock unlock];
}

/**
 * If there is an in-flight changeSet,
 * then this method "resets" it so it can be restarted again (when ready).
**/
- (void)resetFailedInFlightChangeSet
{
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		YDBCKChangeSet *firstChangeSet = [oldChangeSets firstObject];
		if (firstChangeSet.isInFlight)
		{
			firstChangeSet.isInFlight = NO;
		}
	}
	[masterQueueLock unlock];
}

/**
 * Invoke this method from 'prepareForReadWriteTransaction' in order to fetch a 'pendingQueue' object.
 *
 * This pendingQueue object will then be used to keep track of all the changes
 * that need to be written to the changesTable.
**/
- (YDBCKChangeQueue *)newPendingQueue
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	NSUInteger capacity = [oldChangeSets count] + 1;
	
	YDBCKChangeQueue *pendingQueue = [[YDBCKChangeQueue alloc] init];
	pendingQueue->isMasterQueue = NO;
	pendingQueue->oldChangeSets = [[NSMutableArray alloc] initWithCapacity:capacity];
	
	for (YDBCKChangeSet *changeSet in oldChangeSets)
	{
		[pendingQueue->oldChangeSets addObject:[changeSet emptyCopy]];
	}
	
	pendingQueue->newChangeSetsDict = [[NSMutableDictionary alloc] initWithCapacity:1];
	
	[masterQueueLock lock];
	self.lockUUID = pendingQueue.lockUUID = [[NSUUID UUID] UUIDString];
	
	return pendingQueue;
}

/**
 * This should be done AFTER the pendingQueue has been written to disk,
 * at the end of the flushPendingChangesToExtensionTables method.
**/
- (void)mergePendingQueue:(YDBCKChangeQueue *)pendingQueue
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	NSUInteger count = [oldChangeSets count];
	
	for (NSUInteger index = 0; index < count; index++)
	{
		YDBCKChangeSet *pending_oldChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
		if (pending_oldChangeSet.hasChangesToDeletedRecordIDs || pending_oldChangeSet.hasChangesToModifiedRecords)
		{
			YDBCKChangeSet *master_oldChangeSet = [self->oldChangeSets objectAtIndex:index];
			
			if (pending_oldChangeSet.hasChangesToDeletedRecordIDs)
				master_oldChangeSet->deletedRecordIDs = pending_oldChangeSet->deletedRecordIDs;
			
			if (pending_oldChangeSet.hasChangesToModifiedRecords)
				master_oldChangeSet->modifiedRecords = pending_oldChangeSet->modifiedRecords;
		}
	}
	
	NSArray *pending_newChangeSets = pendingQueue.changeSetsFromCurrentCommit;
	for (YDBCKChangeSet *pending_newChangeSet in pending_newChangeSets)
	{
		pending_newChangeSet.hasChangesToDeletedRecordIDs = NO;
		pending_newChangeSet.hasChangesToModifiedRecords = NO;
		
		[oldChangeSets addObject:pending_newChangeSet];
	}
	
	self.lockUUID = nil;
	[masterQueueLock unlock];
}

#pragma mark Properties

/**
 * Determining queue type.
 * Primarily used for sanity checks.
**/
- (BOOL)isMasterQueue {
	return isMasterQueue;
}
- (BOOL)isPendingQueue {
	return !isMasterQueue;
}

/**
 * Each commit that makes one or more changes to a CKRecord (insert/modify/delete)
 * will result in one or more YDBCKChangeSet(s).
 * There is one YDBCKChangeSet per databaseIdentifier.
 * So a single commit may possibly generate multiple changeSets.
 *
 * Thus a changeSet encompasses all the relavent CloudKit related changes per database, per commit.
**/
- (NSArray *)changeSetsFromPreviousCommits
{
	if (self.isMasterQueue)
	{
		NSMutableArray *oldChangeSetsCopy = nil;
		[masterQueueLock lock];
		
		if (oldChangeSets.count)
		{
			oldChangeSetsCopy = [NSMutableArray arrayWithCapacity:oldChangeSets.count];
			
			for (YDBCKChangeSet *changeSet in oldChangeSets)
			{
				[oldChangeSetsCopy addObject:[changeSet fullCopy]];
			}
		}
		
		[masterQueueLock unlock];
		return oldChangeSetsCopy;
	}
	else // if (self.isPendingQueue)
	{
		return [oldChangeSets copy];
	}
}
- (NSArray *)changeSetsFromCurrentCommit
{
	NSAssert(self.isPendingQueue, @"Method can only be invoked on pendingQueue");
	
	if ((newChangeSets == nil) && ([newChangeSetsDict count] > 0))
	{
		NSMutableArray *orderedChangeSets = [NSMutableArray arrayWithCapacity:[newChangeSetsDict count]];
		
		NSString *baseUUID = [[NSUUID UUID] UUIDString];
		NSString *prevChangeSetUUID = [[oldChangeSets lastObject] uuid];
		
		for (YDBCKChangeSet *newChangeSet in [newChangeSetsDict objectEnumerator])
		{
			NSString *uuid = [NSString stringWithFormat:@"%@@%lu", baseUUID, (unsigned long)[orderedChangeSets count]];
			
			newChangeSet.uuid = uuid;
			newChangeSet.prev = prevChangeSetUUID;
			prevChangeSetUUID = newChangeSet.uuid;
			
			[orderedChangeSets addObject:newChangeSet];
		}
		
		newChangeSets = [orderedChangeSets copy];
	}
	
	return newChangeSets;
}

/**
 * See header file for documentation.
**/
- (NSUInteger)numberOfInFlightChangeSets
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	NSUInteger count = 0;
	[masterQueueLock lock];
	
	YDBCKChangeSet *firstChangeSet = [oldChangeSets firstObject];
	if (firstChangeSet.isInFlight) {
		count = 1;
	}
	
	[masterQueueLock unlock];
	return count;
}

/**
 * See header file for documentation.
**/
- (NSUInteger)numberOfQueuedChangeSets
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	NSUInteger count = 0;
	[masterQueueLock lock];
	
	count = [oldChangeSets count];
	
	YDBCKChangeSet *firstChangeSet = [oldChangeSets firstObject];
	if (firstChangeSet.isInFlight) {
		count--;
	}
	
	[masterQueueLock unlock];
	return count;
}

/**
 * See header file for documentation.
**/
- (NSUInteger)numberOfPendingChangeSets
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	NSUInteger count = 0;
	[masterQueueLock lock];
	
	count = [oldChangeSets count];
	
	[masterQueueLock unlock];
	return count;
}

/**
 * Atomic access to all counts at once.
**/
- (void)getNumberOfInFlightChangeSets:(NSUInteger *)numInFlightChangeSetsPtr
                     queuedChangeSets:(NSUInteger *)numQueuedChangeSetsPtr
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	
	NSUInteger inFlightCount = 0;
	NSUInteger queuedCount = 0;
	
	[masterQueueLock lock];
	
	queuedCount = [oldChangeSets count];
	
	YDBCKChangeSet *firstChangeSet = [oldChangeSets firstObject];
	if (firstChangeSet.isInFlight) {
		inFlightCount++;
		queuedCount--;
	}
	
	[masterQueueLock unlock];
	
	if (numInFlightChangeSetsPtr) *numInFlightChangeSetsPtr = inFlightCount;
	if (numQueuedChangeSetsPtr) *numQueuedChangeSetsPtr = queuedCount;
}

#pragma mark Utilities

- (id)keyForDatabaseIdentifier:(NSString *)databaseIdentifier
{
	if (databaseIdentifier)
		return databaseIdentifier;
	else
		return [NSNull null];
}

static BOOL CompareDatabaseIdentifiers(NSString *dbid1, NSString *dbid2)
{
	if (dbid1 == nil) {
		return (dbid2 == nil);
	}
	else {
		return [dbid1 isEqualToString:dbid2];
	}
}

#pragma mark Merge Handling

/**
 * This method enumerates pendingChangeSetsFromPreviousCommits, from oldest commit to newest commit,
 * and merges the changedKeys & values into the given record.
 * Thus, if the value for a particular key has been changed multiple times,
 * then the given record will end up with the most recent value for that key.
 *
 * The given record is expected to be a sanitized record.
 * 
 * Returns YES if there were any pending records in the pendingChangeSetsFromPreviousCommits.
**/
- (BOOL)mergeChangesForRecordID:(CKRecordID *)recordID
             databaseIdentifier:(NSString *)databaseIdentifier
                     intoRecord:(CKRecord *)record
{
	BOOL hasPendingChanges = NO;
	
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
		{
			if (CompareDatabaseIdentifiers(databaseIdentifier, prevChangeSet.databaseIdentifier))
			{
				YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:recordID];
				if (prevRecord)
				{
					for (NSString *changedKey in prevRecord.record.changedKeys)
					{
						id value = [prevRecord.record valueForKey:changedKey];
						if (value) {
							[record setValue:value forKey:changedKey];
						}
					}
					
					hasPendingChanges = YES;
				}
			}
		}
	}
	[masterQueueLock unlock];
	
	return hasPendingChanges;
}

#pragma mark Transaction Handling

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
        withInsertedRecord:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	CKRecordID *recordID = record.recordID;
	
	// Create change record
	
	YDBCKChangeRecord *currentRecord = [[YDBCKChangeRecord alloc] initWithRecord:record];
	currentRecord.canStoreOnlyChangedKeys = YES;
	
	// Update current changeSet
	
	id key = [self keyForDatabaseIdentifier:databaseIdentifier];
	
	YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
	if (currentChangeSet == nil)
	{
		currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
		[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
	}
	
#if DEBUG
	if (currentChangeSet->modifiedRecords == nil)
		currentChangeSet->modifiedRecords = [[YapDebugDictionary alloc] initWithKeyClass:[CKRecordID class]
		                                                                     objectClass:[YDBCKChangeRecord class]];
#else
	if (currentChangeSet->modifiedRecords == nil)
		currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
#endif
	
	[currentChangeSet->modifiedRecords setObject:currentRecord forKey:recordID];
}

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
        withModifiedRecord:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	CKRecordID *recordID = record.recordID;
	
	// Create change record
	
	YDBCKChangeRecord *currentRecord = [[YDBCKChangeRecord alloc] initWithRecord:record];
	currentRecord.canStoreOnlyChangedKeys = YES;
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			YDBCKChangeRecord *mqPrevRecord = [mqPrevChangeSet->modifiedRecords objectForKey:recordID];
			if (mqPrevRecord)
			{
				if (mqPrevRecord.canStoreOnlyChangedKeys &&
				    [mqPrevRecord.changedKeysSet intersectsSet:currentRecord.changedKeysSet])
				{
					// The prevRecord is configured to only store the changedKeys array to disk.
					//
					// However, we're now seeing conflicting changes to the same CKRecord.
					// For example:
					// - a previous commit (not yet pushed to the cloud) changed CKRecord.firstName.
					// - and this commit is also changing CKRecord.firstName.
					//
					// We can only use the changedKeys shortcut when it's possible for use to retrieve
					// the corresponding values from the object. However, when this type of 'conflict' occurs,
					// we can no longer use that shortcut. So we must modify the persisted information for
					// the previous commit so that it stores the previous CKRecord in full,
					// as opposed to just the changedKeys.
					
					YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
					if (pqPrevChangeSet->modifiedRecords == nil)
					{
					#if DEBUG
						pqPrevChangeSet->modifiedRecords =
						  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                       copyItems:YES];
					#else
						pqPrevChangeSet->modifiedRecords =
						  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                        copyItems:YES];
					#endif
						
						pqPrevChangeSet.hasChangesToModifiedRecords = YES;
					}
					
					YDBCKChangeRecord *pqPrevRecord = [pqPrevChangeSet->modifiedRecords objectForKey:recordID];
					pqPrevRecord.canStoreOnlyChangedKeys = NO;
				}
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in changeSets)
	
	// Update current changeSet
	
	id key = [self keyForDatabaseIdentifier:databaseIdentifier];
	
	YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
	if (currentChangeSet == nil)
	{
		currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
		[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
	}
	
#if DEBUG
	if (currentChangeSet->modifiedRecords == nil)
		currentChangeSet->modifiedRecords = [[YapDebugDictionary alloc] initWithKeyClass:[CKRecordID class]
		                                                                     objectClass:[YDBCKChangeRecord class]];
#else
	if (currentChangeSet->modifiedRecords == nil)
		currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
#endif
	
	[currentChangeSet->modifiedRecords setObject:currentRecord forKey:recordID];
}

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
      withDetachedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			YDBCKChangeRecord *mqPrevRecord = [mqPrevChangeSet->modifiedRecords objectForKey:recordID];
			if (mqPrevRecord)
			{
				if (mqPrevRecord.canStoreOnlyChangedKeys)
				{
					// The masterPrevRecord is configured to only store the changedKeys array to disk.
					//
					// However, we're now detaching the rowid from the CKRecord.
					//
					// We can only use the changedKeys shortcut when it's possible for use to retrieve
					// the corresponding values from the object. However, when the rowid is detached,
					// we can no longer use that shortcut. So we must modify the persisted information for
					// the previous commit so that it stores the previous CKRecord in full,
					// as opposed to just the changedKeys.
					
					YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
					if (pqPrevChangeSet->modifiedRecords == nil)
					{
					#if DEBUG
						pqPrevChangeSet->modifiedRecords =
						  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                       copyItems:YES];
					#else
						pqPrevChangeSet->modifiedRecords =
						  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                        copyItems:YES];
					#endif
						
						pqPrevChangeSet.hasChangesToModifiedRecords = YES;
					}
					
					YDBCKChangeRecord *pqPrevRecord = [pqPrevChangeSet->modifiedRecords objectForKey:recordID];
					pqPrevRecord.canStoreOnlyChangedKeys = NO;
				}
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in changeSets)
}

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the deleted recordID to the changeSet
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
       withDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			YDBCKChangeRecord *mqPrevRecord = [mqPrevChangeSet->modifiedRecords objectForKey:recordID];
			if (mqPrevRecord)
			{
				if (mqPrevRecord.canStoreOnlyChangedKeys)
				{
					// The mqPrevRecord is configured to only store the changedKeys array to disk.
					//
					// However, we're now seeing conflicting changes to the same CKRecord.
					// For example:
					// - a previous commit (not yet pushed to the cloud) changed CKRecord.firstName.
					// - and this commit is deleting the same CKRecord.
					//
					// We can only use the changedKeys shortcut when it's possible for use to retrieve
					// the corresponding values from the object. However, when this type of 'conflict' occurs,
					// we can no longer use that shortcut. So we must modify the persisted information for
					// the previous commit so that it stores the previous CKRecord in full,
					// as opposed to just the changedKeys.
					
					YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
					if (pqPrevChangeSet->modifiedRecords == nil)
					{
					#if DEBUG
						pqPrevChangeSet->modifiedRecords =
						  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                       copyItems:YES];
					#else
						pqPrevChangeSet->modifiedRecords =
						  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                        copyItems:YES];
					#endif
						
						pqPrevChangeSet.hasChangesToModifiedRecords = YES;
					}
					
					YDBCKChangeRecord *pqPrevRecord = [pqPrevChangeSet->modifiedRecords objectForKey:recordID];
					pqPrevRecord.canStoreOnlyChangedKeys = NO;
				}
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	
	// Update current changeSet
	
	id key = [self keyForDatabaseIdentifier:databaseIdentifier];
	
	YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
	if (currentChangeSet == nil)
	{
		currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
		[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
	}
	
	[currentChangeSet->modifiedRecords removeObjectForKey:recordID];
	
	if (currentChangeSet->deletedRecordIDs == nil) {
		currentChangeSet->deletedRecordIDs = [[NSMutableArray alloc] init];
	}
	
	[currentChangeSet->deletedRecordIDs addObject:recordID];
}

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed),
 *   if the mergedRecord disagrees with the pending record.
 * - If the mergedRecord contains values that aren're represending in previous commits,
 *   then it creates a changeSet for the given databaseIdentifier for the current commit,
 *   and adds a record with the missing values.
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
          withMergedRecord:(CKRecord *)mergedRecord
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	
	// Update previous changeSets (if needed)
	
	NSSet *mergedRecordChangedKeysSet = [NSSet setWithArray:mergedRecord.changedKeys];
	NSMutableSet *mergedRecordHandledKeys = [NSMutableSet setWithCapacity:mergedRecord.changedKeys.count];
	
	NSMutableSet *keysToRemove = nil;
	NSMutableSet *keysToCompare = nil;
	
	CKRecordID *recordID = mergedRecord.recordID;
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			YDBCKChangeRecord *mqPrevRecord = [mqPrevChangeSet->modifiedRecords objectForKey:recordID];
			if (mqPrevRecord)
			{
				CKRecord *localRecord = mqPrevRecord.record;
				NSSet *localRecordChangedKeysSet = mqPrevRecord.changedKeysSet;
				
				if (keysToRemove == nil)
					keysToRemove = [NSMutableSet setWithCapacity:localRecordChangedKeysSet.count];
				else
					[keysToRemove removeAllObjects];
				
				if (keysToCompare == nil)
					keysToCompare = [NSMutableSet setWithCapacity:localRecordChangedKeysSet.count];
				else
					[keysToCompare removeAllObjects];
				
				for (NSString *key in localRecordChangedKeysSet)
				{
					if ([mergedRecordChangedKeysSet containsObject:key])
						[keysToCompare addObject:key];
					else
						[keysToRemove addObject:key];
				}
				
				if (keysToCompare.count > 0)
				{
					for (NSString *key in keysToCompare)
					{
						id localValue = [localRecord valueForKey:key];
						id mergedValue = [mergedRecord valueForKey:key];
						
						if ([localValue isEqual:mergedValue])
						{
							[mergedRecordHandledKeys addObject:key];
						}
						else
						{
							[keysToRemove addObject:key];
						}
					}
				}
				
				if (keysToRemove.count > 0)
				{
					CKRecord *newLocalRecord = [YapDatabaseCKRecord sanitizedRecord:localRecord];
					
					for (NSString *key in localRecord.changedKeys)
					{
						if (![keysToRemove containsObject:key])
						{
							id value = [localRecord valueForKey:key];
							if (value) {
								[newLocalRecord setValue:value forKey:key];
							}
						}
					}
					
					YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
					if (pqPrevChangeSet->modifiedRecords == nil)
					{
					#if DEBUG
						pqPrevChangeSet->modifiedRecords =
						  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                       copyItems:YES];
					#else
						pqPrevChangeSet->modifiedRecords =
						  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords
						                                        copyItems:YES];
					#endif
						
						pqPrevChangeSet.hasChangesToModifiedRecords = YES;
					}
					
					YDBCKChangeRecord *pqPrevRecord = [pqPrevChangeSet->modifiedRecords objectForKey:recordID];
					pqPrevRecord.record = newLocalRecord;
				}
			
			} // end if (mqPrevRecord)
		} // end if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		
		index++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	
	if (mergedRecordChangedKeysSet.count != mergedRecordHandledKeys.count)
	{
		// There are key/value pairs in the mergedRecord that aren't represented in any of the pendingLocalRecord's.
		// So we need to add these to a new CKRecord, and queue that record for upload to the server.
		
		NSMutableSet *mergedRecordUnhandledKeys = [mergedRecordChangedKeysSet mutableCopy];
		[mergedRecordUnhandledKeys minusSet:mergedRecordHandledKeys];
		
		CKRecord *newMergedRecord = [YapDatabaseCKRecord sanitizedRecord:mergedRecord];
		
		for (NSString *key in mergedRecordUnhandledKeys)
		{
			id value = [mergedRecord valueForKey:key];
			if (value) {
				[newMergedRecord setValue:value forKey:key];
			}
		}
		
		// Add newMergedRecord to a new YDBCKChangeRecord,
		// and add to newChangeSets for this transaction.
		
		YDBCKChangeRecord *currentRecord = [[YDBCKChangeRecord alloc] initWithRecord:newMergedRecord];
		currentRecord.canStoreOnlyChangedKeys = YES;
		
		id key = [self keyForDatabaseIdentifier:databaseIdentifier];
		
		YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
		if (currentChangeSet == nil)
		{
			currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
			[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
		}
		
	#if DEBUG
		if (currentChangeSet->modifiedRecords == nil)
			currentChangeSet->modifiedRecords =
			  [[YapDebugDictionary alloc] initWithKeyClass:[CKRecordID class]
			                                   objectClass:[YDBCKChangeRecord class]];
	#else
		if (currentChangeSet->modifiedRecords == nil)
			currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
	#endif
		
		[currentChangeSet->modifiedRecords setObject:currentRecord forKey:recordID];
	}
}

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
 withRemoteDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			// Check to see if we have queued modifications to push for this item
			
			YDBCKChangeRecord *mqPrevRecord = [mqPrevChangeSet->modifiedRecords objectForKey:recordID];
			if (mqPrevRecord)
			{
				YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pqPrevChangeSet->modifiedRecords == nil)
				{
				#if DEBUG
					pqPrevChangeSet->modifiedRecords =
					  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords copyItems:YES];
				#else
					pqPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords copyItems:YES];
				#endif
					
					pqPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				[pqPrevChangeSet->modifiedRecords removeObjectForKey:recordID];
			}
			
			// Check to see if we have queued deletion for this item
			
			if ([mqPrevChangeSet->deletedRecordIDs containsObject:recordID])
			{
				YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pqPrevChangeSet->deletedRecordIDs == nil)
				{
					pqPrevChangeSet->deletedRecordIDs = [mqPrevChangeSet->deletedRecordIDs copy];
					pqPrevChangeSet.hasChangesToDeletedRecordIDs = YES;
				}
				
				[pqPrevChangeSet->deletedRecordIDs removeObject:recordID];
			
			}
			
		} // end if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		
		index++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
}

- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
           withSavedRecord:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
     isOpPartialCompletion:(BOOL)isOpPartialCompletion
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	CKRecordID *recordID = record.recordID;
	
	// Update inFlight changeSet of pendingQueue (if needed)
	
	if (isOpPartialCompletion)
	{
		YDBCKChangeSet *pqInFlightChangeSet = [pendingQueue->oldChangeSets firstObject];
		
		if (pqInFlightChangeSet->modifiedRecords == nil)
		{
			YDBCKChangeSet *mqInFlightChangeSet = [masterQueue->oldChangeSets firstObject];
			
			if (mqInFlightChangeSet->modifiedRecords)
			{
			#if DEBUG
				pqInFlightChangeSet->modifiedRecords =
				  [[YapDebugDictionary alloc] initWithDictionary:mqInFlightChangeSet->modifiedRecords copyItems:YES];
			#else
				pqInFlightChangeSet->modifiedRecords =
				  [[NSMutableDictionary alloc] initWithDictionary:mqInFlightChangeSet->modifiedRecords copyItems:YES];
			#endif
			}
			else
			{
			#if DEBUG
				pqInFlightChangeSet->modifiedRecords =
				  [[YapDebugDictionary alloc] initWithKeyClass:[CKRecordID class]
				                                   objectClass:[YDBCKChangeRecord class]];
			#else
				pqInFlightChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
			#endif
			}
			
			pqInFlightChangeSet.hasChangesToModifiedRecords = YES;
		}
		
		[pqInFlightChangeSet->modifiedRecords removeObjectForKey:recordID];
	}
	
	// Update previous changeSets (if needed)
	
	CKRecord *sanitizedRecord = nil;
	
	NSUInteger i = 0;
	for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
	{
		// Skip inFlight changeSet
		if (i == 0) {
			i++;
			continue;
		}
		
		// Process other previous changeSets

		if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		{
			if ([mqPrevChangeSet->modifiedRecords objectForKey:recordID])
			{
				YDBCKChangeSet *pqPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:i];
				
				if (pqPrevChangeSet->modifiedRecords == nil)
				{
				#if DEBUG
					pqPrevChangeSet->modifiedRecords =
					  [[YapDebugDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords copyItems:YES];
				#else
					pqPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:mqPrevChangeSet->modifiedRecords copyItems:YES];
				#endif
					
					pqPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				if (sanitizedRecord == nil)
				{
					sanitizedRecord = [YapDatabaseCKRecord sanitizedRecord:record];
				}
				
				YDBCKChangeRecord *pqChangeRecord = [pqPrevChangeSet->modifiedRecords objectForKey:recordID];
				
				CKRecord *originalRecord = pqChangeRecord.record;
				CKRecord *mergedRecord = [sanitizedRecord copy];
				
				// The 'originalRecord' contains all the values we need to sync to the cloud.
				// But the 'sanitizedRecord' contains the proper system fields within the CKRecord internals
				// that reflect the proper sync state we have with the server.
				//
				// Because the internal sync-state stuff is private, we cannot access it.
				// So we copy the needed values from the originalRecord into a new CKRecord container
				// that already has the updated sync-state fields.
				
				for (NSString *changedKey in [originalRecord changedKeys])
				{
					id value = [originalRecord objectForKey:changedKey];
					if (value) {
						[mergedRecord setObject:value forKey:changedKey];
					}
				}
				
				pqChangeRecord.record = mergedRecord;
				
			} // end if ([mqPrevChangeSet->modifiedRecords objectForKey:recordID])
		} // end if (CompareDatabaseIdentifiers(databaseIdentifier, mqPrevChangeSet.databaseIdentifier))
		
		i++;
	} // end for (YDBCKChangeSet *mqPrevChangeSet in masterQueue->oldChangeSets)
}

/**
 * This method:
 * - modifies the inFlightChangeSet by removing the given recordID from the deletedRecordIDs
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
  withSavedDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	__unsafe_unretained typeof(self) masterQueue = self;
	
	// Update inFlight changeSet of pendingQueue
	
	YDBCKChangeSet *pqInFlightChangeSet = [pendingQueue->oldChangeSets firstObject];
	
	if (pqInFlightChangeSet->deletedRecordIDs == nil)
	{
		YDBCKChangeSet *mqInFlightChangeSet = [masterQueue->oldChangeSets firstObject];
		
		pqInFlightChangeSet->deletedRecordIDs = [mqInFlightChangeSet->deletedRecordIDs copy];
	}
	
	NSUInteger index = [pqInFlightChangeSet->deletedRecordIDs indexOfObject:recordID];
	if (index != NSNotFound)
	{
		[pqInFlightChangeSet->deletedRecordIDs removeObjectAtIndex:index];
		pqInFlightChangeSet.hasChangesToDeletedRecordIDs = YES;
	}
}

@end
