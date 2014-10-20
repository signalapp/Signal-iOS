#import "YDBCKChangeQueue.h"


@interface YDBCKChangeSet () {
@public
	
	NSMutableArray *deletedRecordIDs;
	NSMutableDictionary *modifiedRecords;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)databaseIdentifier;
- (instancetype)emptyCopy;

@property (nonatomic, readwrite) NSString *prev;
@property (nonatomic, readwrite) BOOL hasChanges;

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
	
	NSMutableArray *oldChangeSets;
	
	NSArray *newChangeSets;
	NSMutableDictionary *newChangeSetsDict;
}

@dynamic isMasterQueue;
@dynamic isPendingQueue;

@dynamic oldChangeSets;
@dynamic newChangeSets;

- (instancetype)initMasterQueue
{
	if ((self = [super init]))
	{
		isMasterQueue = YES;
		
		oldChangeSets = [[NSMutableArray alloc] init];
	}
	return self;
}

/**
 * Invoke this method from 'prepareForReadWriteTransaction' in order to fetch a 'pendingQueue' object.
 *
 * This pendingQueue object will then be used to keep track of all the changes
 * that need to be written to the changesTable.
**/
- (YDBCKChangeQueue *)newPendingQueue
{
	NSUInteger capacity = [oldChangeSets count] + 1;
	
	YDBCKChangeQueue *pendingQueue = [[YDBCKChangeQueue alloc] init];
	pendingQueue->isMasterQueue = NO;
	pendingQueue->oldChangeSets = [[NSMutableArray alloc] initWithCapacity:capacity];
	
	for (YDBCKChangeSet *changeSet in oldChangeSets)
	{
		[pendingQueue->oldChangeSets addObject:[changeSet emptyCopy]];
	}
	
	pendingQueue->newChangeSetsDict = [[NSMutableDictionary alloc] initWithCapacity:1];
	
	return pendingQueue;
}

/**
 * Sanity checks
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
 *
 * The oldChangeSets array is the list of changeSets from previous commits.
 * The newChangeSets array is the list of changeSets from the current commit (only available for the pendingQueue).
 *
 * The changeSet at index 0 of the oldChangeSets is the next (or in-progress) changeSet.
**/
- (NSArray *)oldChangeSets
{
	return oldChangeSets;
}
- (NSArray *)newChangeSets
{
	if ((newChangeSets == nil) && ([newChangeSetsDict count] > 0))
	{
		NSMutableArray *orderedChangeSets = [NSMutableArray arrayWithCapacity:[newChangeSetsDict count]];
		
		NSString *prevChangeSetUUID = [[oldChangeSets lastObject] uuid];
		for (YDBCKChangeSet *newChangeSet in [newChangeSetsDict objectEnumerator])
		{
			newChangeSet.prev = prevChangeSetUUID;
			prevChangeSetUUID = newChangeSet.uuid;
			
			[orderedChangeSets addObject:newChangeSet];
		}
		
		newChangeSets = [orderedChangeSets copy];
	}
	
	return newChangeSets;
}

- (id)keyForDatabaseIdentifier:(NSString *)databaseIdentifier
{
	if (databaseIdentifier)
		return databaseIdentifier;
	else
		return [NSNull null];
}

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
					
					pendingPrevChangeSet.hasChanges = YES;
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
					
					pendingPrevChangeSet.hasChanges = YES;
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
					
					pendingPrevChangeSet.hasChanges = YES;
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
 * This should be done AFTER the pendingQueue has been written to disk,
 * at the end of the commitTransaction method.
**/
- (void)mergePendingQueue:(YDBCKChangeQueue *)pendingQueue
{
	NSAssert(self.isMasterQueue, @"Method can only be invoked on masterQueue");
	NSAssert(pendingQueue.isPendingQueue, @"Bad parameter: 'pendingQueue' is not a pendingQueue");
	
	NSUInteger count = [oldChangeSets count];
	
	for (NSUInteger index = 0; index < count; index++)
	{
		YDBCKChangeSet *pendingChangeSet = [pendingQueue->oldChangeSets objectAtIndex:index];
		if (pendingChangeSet.hasChanges)
		{
			YDBCKChangeSet *masterChangeSet = [oldChangeSets objectAtIndex:index];
			
			masterChangeSet->modifiedRecords = pendingChangeSet->modifiedRecords;
		}
	}
	
	NSArray *pendingNewChangeSets = pendingQueue.newChangeSets;
	for (YDBCKChangeSet *pendingChangeSet in pendingNewChangeSets)
	{
		pendingChangeSet.hasChanges = NO;
		
		[oldChangeSets addObject:pendingChangeSet];
	}
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

@synthesize hasChanges;

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
		
		uuid = [[NSUUID UUID] UUIDString];
		prev = nil; // Will be set later when the changeSets are ordered
	}
	return self;
}

- (instancetype)emptyCopy
{
	YDBCKChangeSet *emptyCopy = [[YDBCKChangeSet alloc] init];
	emptyCopy->databaseIdentifier = databaseIdentifier;
	emptyCopy->uuid = uuid;
	emptyCopy->prev = prev;
	
	return emptyCopy;
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

- (NSArray *)changedKeys
{
	if (changedKeys)
		return changedKeys;
	else
		return record.changedKeys;
}

- (void)setChangedKeys:(NSArray *)inChangedKeys
{
	if (changedKeysSet && !inChangedKeys) {
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
