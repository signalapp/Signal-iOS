#import "YDBCKChangeQueue.h"
#import "YapDatabaseCKRecord.h"


@interface YDBCKChangeQueue ()

@property (atomic, readwrite, strong) NSString *lockUUID;

@end

@interface YDBCKChangeSet () {
@public
	
	NSMutableArray *deletedRecordIDs;
	NSMutableDictionary *modifiedRecords;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)databaseIdentifier;
- (instancetype)emptyCopy;
- (instancetype)fullCopy;

@property (nonatomic, readwrite) NSString *uuid;
@property (nonatomic, readwrite) NSString *prev;

@property (nonatomic, readwrite) BOOL hasChangesToDeletedRecordIDs;
@property (nonatomic, readwrite) BOOL hasChangesToModifiedRecords;

@property (nonatomic, readonly) NSString *lockUUID;

@end


@interface YDBCKChangeRecord : NSObject <NSCoding, NSCopying>

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readwrite) CKRecord *record;
@property (nonatomic, strong, readwrite) NSArray *changedKeys;

@property (nonatomic, assign, readwrite) BOOL canStoreOnlyChangedKeys;

@property (nonatomic, readonly) NSSet *changedKeysSet;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YDBCKChangeQueue
{
	BOOL isMasterQueue;
	NSLock *masterQueueLock;
	
	BOOL hasInFlightChangeSet;
	NSMutableArray *oldChangeSets;
	
	NSArray *newChangeSets;
	NSMutableDictionary *newChangeSetsDict;
}

@dynamic isMasterQueue;
@dynamic isPendingQueue;

@dynamic changeSetsFromPreviousCommits;
@dynamic changeSetsFromCurrentCommit;

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
		if (!hasInFlightChangeSet && (oldChangeSets.count > 0))
		{
			inFlightChangeSet = [[oldChangeSets objectAtIndex:0] fullCopy];
			hasInFlightChangeSet = YES;
		}
	}
	[masterQueueLock unlock];
	
	return inFlightChangeSet;
}

/**
 * ???
**/
- (void)dropInFlightChangeSet
{
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		if (hasInFlightChangeSet)
		{
			NSAssert(oldChangeSets.count > 0, @"Logic error");
			
			[oldChangeSets removeObjectAtIndex:0];
			hasInFlightChangeSet = NO;
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
	self.lockUUID = pendingQueue.lockUUID;
	
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
	NSAssert(self.isPendingQueue, @"Method can only be invoked on pendingQueue");
	
	return [oldChangeSets copy];
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

#pragma mark Utilities

- (id)keyForDatabaseIdentifier:(NSString *)databaseIdentifier
{
	if (databaseIdentifier)
		return databaseIdentifier;
	else
		return [NSNull null];
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
- (BOOL)mergeChangesForRowid:(NSNumber *)rowidNumber intoRecord:(CKRecord *)record
{
	BOOL hasPendingChanges = NO;
	
	// Get lock for access to 'oldChangeSets'
	[masterQueueLock lock];
	{
		for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
		{
			YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
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
	[masterQueueLock unlock];
	
	return hasPendingChanges;
}

#pragma mark Transaction Handling

/**
 * This method updates the current changeSet of the pendingQueue
 * so that the required CloudKit related information can be restored from disk in the event the app is quit.
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
         withInsertedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
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
	
	if (currentChangeSet->modifiedRecords == nil) {
		currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
	}
	[currentChangeSet->modifiedRecords setObject:currentRecord forKey:rowidNumber];
}

/**
 * This method properly updates the pendingQueue,
 * including the current changeSet and any previous changeSets (for previous commits) if needed,
 * so that the required CloudKit related information can be restored from disk in the event the app is quit.
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
		 withModifiedRowid:(NSNumber *)rowidNumber
				    record:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	YDBCKChangeRecord *currentRecord = [[YDBCKChangeRecord alloc] initWithRecord:record];
	currentRecord.canStoreOnlyChangedKeys = YES;
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
	{
		YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
		if (prevRecord)
		{
			if (prevRecord.canStoreOnlyChangedKeys &&
			    [prevRecord.changedKeysSet intersectsSet:currentRecord.changedKeysSet])
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
				
				YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pendingPrevChangeSet->modifiedRecords == nil)
				{
					pendingPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:prevChangeSet->modifiedRecords copyItems:YES];
					
					pendingPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				YDBCKChangeRecord *pendingPrevRecord =
				  [pendingPrevChangeSet->modifiedRecords objectForKey:rowidNumber];
				
				pendingPrevRecord.canStoreOnlyChangedKeys = NO;
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *prevChangeSet in changeSets)
	
	// Update current changeSet
	
	id key = [self keyForDatabaseIdentifier:databaseIdentifier];
	
	YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
	if (currentChangeSet == nil)
	{
		currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
		[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
	}
	
	if (currentChangeSet->modifiedRecords == nil) {
		currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
	}
	[currentChangeSet->modifiedRecords setObject:currentRecord forKey:rowidNumber];
}

/**
 * This method properly updates the pendingQueue,
 * including any previous changeSets (for previous commits) if needed,
 * so that the required CloudKit related information can be restored from disk in the event the app is quit.
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
         withDetachedRowid:(NSNumber *)rowidNumber
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
	{
		YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
		if (prevRecord)
		{
			if (prevRecord.canStoreOnlyChangedKeys)
			{
				// The prevRecord is configured to only store the changedKeys array to disk.
				//
				// However, we're now detaching the rowid from the CKRecord.
				//
				// We can only use the changedKeys shortcut when it's possible for use to retrieve
				// the corresponding values from the object. However, when the rowid is detached,
				// we can no longer use that shortcut. So we must modify the persisted information for
				// the previous commit so that it stores the previous CKRecord in full,
				// as opposed to just the changedKeys.
				
				YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pendingPrevChangeSet->modifiedRecords == nil)
				{
					pendingPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:prevChangeSet->modifiedRecords copyItems:YES];
					
					pendingPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				YDBCKChangeRecord *pendingPrevRecord =
				  [pendingPrevChangeSet->modifiedRecords objectForKey:rowidNumber];
				
				pendingPrevRecord.canStoreOnlyChangedKeys = NO;
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *prevChangeSet in changeSets)
}

/**
 * This method properly updates the pendingQueue,
 * including the current changeSet and any previous changeSets (for previous commits) if needed,
 * so that the required CloudKit related information can be restored from disk in the event the app is quit.
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
          withDeletedRowid:(NSNumber *)rowidNumber
                  recordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
	{
		YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
		if (prevRecord)
		{
			if (prevRecord.canStoreOnlyChangedKeys)
			{
				// The prevRecord is configured to only store the changedKeys array to disk.
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
				
				YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pendingPrevChangeSet->modifiedRecords == nil)
				{
					pendingPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:prevChangeSet->modifiedRecords copyItems:YES];
					
					pendingPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				YDBCKChangeRecord *pendingPrevRecord =
				  [pendingPrevChangeSet->modifiedRecords objectForKey:rowidNumber];
				
				pendingPrevRecord.canStoreOnlyChangedKeys = NO;
			}
		}
		
		index++;
	} // end for (YDBCKChangeSet *prevChangeSet in changeSets)
	
	// Update current changeSet
	
	id key = [self keyForDatabaseIdentifier:databaseIdentifier];
	
	YDBCKChangeSet *currentChangeSet = [pendingQueue->newChangeSetsDict objectForKey:key];
	if (currentChangeSet == nil)
	{
		currentChangeSet = [[YDBCKChangeSet alloc] initWithDatabaseIdentifier:databaseIdentifier];
		[pendingQueue->newChangeSetsDict setObject:currentChangeSet forKey:key];
	}
	
	[currentChangeSet->modifiedRecords removeObjectForKey:rowidNumber];
	
	if (currentChangeSet->deletedRecordIDs == nil) {
		currentChangeSet->deletedRecordIDs = [[NSMutableArray alloc] init];
	}
	
	[currentChangeSet->deletedRecordIDs addObject:recordID];
}

/**
 * This method properly updates the pendingQueue,
 * and updates any previous queued changeSets that include
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
           withMergedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)mergedRecord
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	// Update previous changeSets (if needed)
	
	NSSet *mergedRecordChangedKeysSet = [NSSet setWithArray:mergedRecord.changedKeys];
	NSMutableSet *mergedRecordHandledKeys = [NSMutableSet setWithCapacity:mergedRecord.changedKeys.count];
	
	NSMutableSet *keysToRemove = nil;
	NSMutableSet *keysToCompare = nil;
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
	{
		YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
		if (prevRecord)
		{
			CKRecord *pendingLocalRecord = prevRecord.record;
			NSSet *pendingLocalRecordChangedKeysSet = prevRecord.changedKeysSet;
			
			if (keysToRemove == nil)
				keysToRemove = [NSMutableSet setWithCapacity:pendingLocalRecordChangedKeysSet.count];
			else
				[keysToRemove removeAllObjects];
			
			if (keysToCompare == nil)
				keysToCompare = [NSMutableSet setWithCapacity:pendingLocalRecordChangedKeysSet.count];
			else
				[keysToCompare removeAllObjects];
			
			for (NSString *key in pendingLocalRecordChangedKeysSet)
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
					id pendingValue = [pendingLocalRecord valueForKey:key];
					id mergedValue = [mergedRecord valueForKey:key];
					
					if ([pendingValue isEqual:mergedValue])
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
				CKRecord *newPendingLocalRecord = [YapDatabaseCKRecord sanitizedRecord:pendingLocalRecord];
				
				for (NSString *key in pendingLocalRecord.changedKeys)
				{
					if (![keysToRemove containsObject:key])
					{
						id value = [pendingLocalRecord valueForKey:key];
						if (value) {
							[newPendingLocalRecord setValue:value forKey:key];
						}
					}
				}
				
				YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
				if (pendingPrevChangeSet->modifiedRecords == nil)
				{
					pendingPrevChangeSet->modifiedRecords =
					  [[NSMutableDictionary alloc] initWithDictionary:prevChangeSet->modifiedRecords copyItems:YES];
					
					pendingPrevChangeSet.hasChangesToModifiedRecords = YES;
				}
				
				YDBCKChangeRecord *pendingPrevRecord =
				  [pendingPrevChangeSet->modifiedRecords objectForKey:rowidNumber];
				
				pendingPrevRecord.record = newPendingLocalRecord;
			}
		
		} // end if (prevRecord)
		
		index++;
	} // end for (YDBCKChangeSet *prevChangeSet in changeSets)
	
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
		
		if (currentChangeSet->modifiedRecords == nil) {
			currentChangeSet->modifiedRecords = [[NSMutableDictionary alloc] init];
		}
		[currentChangeSet->modifiedRecords setObject:currentRecord forKey:rowidNumber];
	}
}

/**
 * This method properly updates the pendingQueue,
 * and updates any previously queued changeSets that include modifications for this item.
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
    withRemoteDeletedRowid:(NSNumber *)rowidNumber
                  recordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	NSAssert(pendingQueue->newChangeSets == nil, @"Cannot modify pendingQueue after newChangeSets has been fetched");
	NSAssert([self.lockUUID isEqualToString:pendingQueue.lockUUID], @"Bad state: Not locked for pendingQueue");
	
	// Update previous changeSets (if needed)
	
	NSUInteger index = 0;
	for (YDBCKChangeSet *prevChangeSet in oldChangeSets)
	{
		// Check to see if we have queued modifications to push for this item
		
		YDBCKChangeRecord *prevRecord = [prevChangeSet->modifiedRecords objectForKey:rowidNumber];
		if (prevRecord)
		{
			YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
			if (pendingPrevChangeSet->modifiedRecords == nil)
			{
				pendingPrevChangeSet->modifiedRecords =
				  [[NSMutableDictionary alloc] initWithDictionary:prevChangeSet->modifiedRecords copyItems:YES];
				
				pendingPrevChangeSet.hasChangesToModifiedRecords = YES;
			}
			
			[pendingPrevChangeSet->modifiedRecords removeObjectForKey:rowidNumber];
		}
		
		// Check to see if we have queued deletion for this item
		
		if ([prevChangeSet->deletedRecordIDs containsObject:recordID])
		{
			YDBCKChangeSet *pendingPrevChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
			if (pendingPrevChangeSet->deletedRecordIDs == nil)
			{
				pendingPrevChangeSet->deletedRecordIDs = [prevChangeSet->deletedRecordIDs copy];
				pendingPrevChangeSet.hasChangesToDeletedRecordIDs = YES;
			}
			
			[pendingPrevChangeSet->deletedRecordIDs removeObject:recordID];
		}
		
		index++;
	} // end for (YDBCKChangeSet *prevChangeSet in changeSets)
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YDBCKChangeSet

@synthesize uuid = uuid;
@synthesize prev = prev;

@synthesize databaseIdentifier = databaseIdentifier;

@dynamic recordIDsToDelete;
@dynamic recordsToSave;

@synthesize hasChangesToDeletedRecordIDs;
@synthesize hasChangesToModifiedRecords;

@synthesize lockUUID = lockUUID;

- (id)initWithUUID:(NSString *)inUuid
              prev:(NSString *)inPrev
databaseIdentifier:(NSString *)inDatabaseIdentifier
  deletedRecordIDs:(NSData *)serializedDeletedRecordIDs
   modifiedRecords:(NSData *)serializedModifiedRecords
{
	if ((self = [super init]))
	{
		uuid = inUuid;
		prev = inPrev;
		
		databaseIdentifier = inDatabaseIdentifier;
		
		[self deserializeDeletedRecordIDs:serializedDeletedRecordIDs];
		[self deserializeModifiedRecords:serializedModifiedRecords];
	}
	return nil;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
{
	if ((self = [super init]))
	{
		databaseIdentifier = inDatabaseIdentifier;
		
		uuid = nil; // Will be set later when the changeSets are ordered
		prev = nil; // Will be set later when the changeSets are ordered
		
		lockUUID = [[NSUUID UUID] UUIDString];
	}
	return self;
}

- (instancetype)emptyCopy
{
	YDBCKChangeSet *emptyCopy = [[YDBCKChangeSet alloc] init];
	emptyCopy->uuid = uuid;
	emptyCopy->prev = prev;
	emptyCopy->databaseIdentifier = databaseIdentifier;
	emptyCopy->lockUUID = lockUUID;
	
	return emptyCopy;
}

- (instancetype)fullCopy
{
	YDBCKChangeSet *fullCopy = [self emptyCopy];
	fullCopy->deletedRecordIDs = [deletedRecordIDs mutableCopy];
	fullCopy->modifiedRecords = [modifiedRecords mutableCopy];
	
	return fullCopy;
}

- (NSArray *)recordIDsToDelete
{
	return [deletedRecordIDs copy];
}

- (NSArray *)recordsToSave
{
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[modifiedRecords count]];
	
	for (YDBCKChangeRecord *changeRecord in [modifiedRecords objectEnumerator])
	{
		[array addObject:changeRecord.record];
	}
	
	return array;
}

- (NSData *)serializeDeletedRecordIDs
{
	if ([deletedRecordIDs count] > 0)
		return [NSKeyedArchiver archivedDataWithRootObject:deletedRecordIDs];
	else
		return nil;
}

- (void)deserializeDeletedRecordIDs:(NSData *)serializedDeletedRecordIDs
{
	if (serializedDeletedRecordIDs)
		deletedRecordIDs = [NSKeyedUnarchiver unarchiveObjectWithData:serializedDeletedRecordIDs];
	else
		deletedRecordIDs = nil;
	
	if (deletedRecordIDs) {
		NSAssert([deletedRecordIDs isKindOfClass:[NSMutableArray class]], @"Deserialized object is wrong class");
	}
}

- (NSData *)serializeModifiedRecords
{
	if ([modifiedRecords count] > 0)
		return [NSKeyedArchiver archivedDataWithRootObject:modifiedRecords];
	else
		return nil;
}

- (void)deserializeModifiedRecords:(NSData *)serializedModifiedRecords
{
	if (serializedModifiedRecords)
		modifiedRecords = [NSKeyedUnarchiver unarchiveObjectWithData:serializedModifiedRecords];
	else
		modifiedRecords = nil;
	
	if (modifiedRecords) {
		NSAssert([modifiedRecords isKindOfClass:[NSMutableDictionary class]], @"Deserialized object is wrong class");
	}
}

- (void)enumerateMissingRecordsWithBlock:(CKRecord* (^)(int64_t rowid, NSArray *changedKeys))block
{
	[modifiedRecords enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKChangeRecord *changeRecord = (YDBCKChangeRecord *)obj;
		
		if (changeRecord.record == nil)
		{
			int64_t rowid = [rowidNumber longLongValue];
			
			CKRecord *record = block(rowid, changeRecord.changedKeys);
			
			changeRecord.record = record;
			changeRecord.changedKeys = nil;
		}
	}];
}

- (NSDictionary *)recordIDToRowidMapping
{
	NSMutableDictionary *mapping = [NSMutableDictionary dictionaryWithCapacity:[modifiedRecords count]];
	
	[modifiedRecords enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSNumber *rowidNumber = (NSNumber *)key;
		__unsafe_unretained YDBCKChangeRecord *changeRecord = (YDBCKChangeRecord *)obj;
		
		CKRecordID *recordID = changeRecord.record.recordID;
		if (recordID)
		{
			[mapping setObject:rowidNumber forKey:recordID];
		}
	}];
	
	return mapping;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static NSString *const k_record      = @"record";
static NSString *const k_changedKeys = @"changedKeys";


@implementation YDBCKChangeRecord
{
	NSArray *changedKeys;
	NSSet *changedKeysSet;
}

@synthesize record = record;
@synthesize canStoreOnlyChangedKeys = canStoreOnlyChangedKeys;

@dynamic changedKeys;
@dynamic changedKeysSet;

- (instancetype)initWithRecord:(CKRecord *)inRecord
{
	if ((self = [super init]))
	{
		record = inRecord;
	}
	return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
	YDBCKChangeRecord *copy = [[YDBCKChangeRecord alloc] init];
	copy->record = record;
	copy->changedKeys = changedKeys;
	copy->canStoreOnlyChangedKeys = canStoreOnlyChangedKeys;
	
	return copy;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		record = [decoder decodeObjectForKey:k_record];
		changedKeys = [decoder decodeObjectForKey:k_changedKeys];
		
		if (changedKeys)
			canStoreOnlyChangedKeys = YES;
		else
			canStoreOnlyChangedKeys = NO;
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (canStoreOnlyChangedKeys)
	{
		if (changedKeys)
			[coder encodeObject:changedKeys forKey:k_changedKeys];
		else
			[coder encodeObject:[record changedKeys] forKey:k_changedKeys];
	}
	else
	{
		[coder encodeObject:record forKey:k_record];
	}
}

- (void)setRecord:(CKRecord *)inRecord
{
	if (changedKeysSet) {
		changedKeysSet = nil;
	}
	
	record = inRecord;
}

- (NSArray *)changedKeys
{
	if (changedKeys)
		return changedKeys;
	else
		return record.changedKeys;
}

- (void)setChangedKeys:(NSArray *)inChangedKeys
{
	if (changedKeysSet) {
		changedKeysSet = nil;
	}
	
	changedKeys = inChangedKeys;
}

- (NSSet *)changedKeysSet
{
	if (changedKeysSet == nil) // Generated on-demand (if needed)
	{
		if (changedKeys)
			changedKeysSet = [[NSSet alloc] initWithArray:changedKeys];
		else
			changedKeysSet = [[NSSet alloc] initWithArray:record.changedKeys];
	}
	
	return changedKeysSet;
}

@end
