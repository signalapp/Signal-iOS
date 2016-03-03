#import "YDBCKChangeSet.h"
#import "YDBCKChangeRecord.h"
#import "YDBCKRecord.h"
#import "YapDatabaseCloudKitPrivate.h"


@implementation YDBCKChangeSet

@synthesize uuid = uuid;
@synthesize prev = prev;

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize isInFlight = isInFlight;

@dynamic recordIDsToDelete;
@dynamic recordsToSave;
@dynamic recordsToSave_noCopy;

@dynamic recordIDsToDeleteCount;
@dynamic recordsToSaveCount;

@synthesize hasChangesToDeletedRecordIDs;
@synthesize hasChangesToModifiedRecords;

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
		isInFlight = NO;
		
		[self deserializeDeletedRecordIDs:serializedDeletedRecordIDs];
		[self deserializeModifiedRecords:serializedModifiedRecords];
	}
	return self;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
{
	if ((self = [super init]))
	{
		databaseIdentifier = inDatabaseIdentifier;
		isInFlight = NO;
		
		uuid = nil; // Will be set later when the changeSets are ordered
		prev = nil; // Will be set later when the changeSets are ordered
	}
	return self;
}

- (instancetype)emptyCopy
{
	YDBCKChangeSet *emptyCopy = [[YDBCKChangeSet alloc] init];
	emptyCopy->uuid = uuid;
	emptyCopy->prev = prev;
	emptyCopy->databaseIdentifier = databaseIdentifier;
	emptyCopy->isInFlight = isInFlight;
	
	return emptyCopy;
}

- (instancetype)fullCopy
{
	YDBCKChangeSet *fullCopy = [self emptyCopy];
	
	if (deletedRecordIDs)
	{
		fullCopy->deletedRecordIDs = [deletedRecordIDs mutableCopy];
	}
	
	if (modifiedRecords)
	{
		fullCopy->modifiedRecords = [[NSMutableDictionary alloc] initWithDictionary:modifiedRecords copyItems:YES];
	}
	
	return fullCopy;
}

/**
 * Array of CKRecordID's for CKModifyRecordsOperation
**/
- (NSArray *)recordIDsToDelete
{
	return [deletedRecordIDs copy];
}

/**
 * Array of CKRecord's for CKModifyRecordsOperation.
**/
- (NSArray *)recordsToSave
{
	NSUInteger modifiedRecordsCount = modifiedRecords.count;
	if (modifiedRecordsCount == 0) return nil;
	
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:modifiedRecordsCount];
	
	for (YDBCKChangeRecord *changeRecord in [modifiedRecords objectEnumerator])
	{
		[array addObject:[changeRecord.record safeCopy]];
	}
	
	return array;
}

/**
 * Private API for YapDatabaseCloudKit extension internals only.
 * NOT for external use under any circumstances !!!
**/
- (NSArray *)recordsToSave_noCopy
{
	if (modifiedRecords.count == 0) return nil;
	
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[modifiedRecords count]];
	
	for (YDBCKChangeRecord *changeRecord in [modifiedRecords objectEnumerator])
	{
		[array addObject:changeRecord.record];
	}
	
	return array;
}

/**
 * Array of CKRecordID's (from recordsToSave).
**/
- (NSArray *)recordIDsToSave
{
	NSUInteger modifiedRecordsCount = modifiedRecords.count;
	if (modifiedRecordsCount == 0) return 0;
	
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:modifiedRecordsCount];
	
	for (YDBCKChangeRecord *changeRecord in [modifiedRecords objectEnumerator])
	{
		[array addObject:changeRecord.recordID];
	}
	
	return array;
}

/**
 * Shortcut if you just want the count (for CKModifyRecordsOperation.recordIDsToDelete).
**/
- (NSUInteger)recordIDsToDeleteCount
{
	return deletedRecordIDs.count;
}

/**
 * Shortcut if you just want the count (for CKModifyRecordsOperation.recordsToSave).
**/
- (NSUInteger)recordsToSaveCount
{
	return modifiedRecords.count;
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
	if (modifiedRecords.count == 0)
		return nil;
	else
		return [NSKeyedArchiver archivedDataWithRootObject:[modifiedRecords allValues]];
}

- (void)deserializeModifiedRecords:(NSData *)serializedModifiedRecords
{
	NSArray *modifiedRecordsArray = nil;
	
	if (serializedModifiedRecords) {
		modifiedRecordsArray = [NSKeyedUnarchiver unarchiveObjectWithData:serializedModifiedRecords];
	}
	
	if (modifiedRecordsArray) {
		NSAssert([modifiedRecordsArray isKindOfClass:[NSArray class]], @"Deserialized object is wrong class");
	}
	
	modifiedRecords = [[NSMutableDictionary alloc] initWithCapacity:[modifiedRecordsArray count]];
	
	for (YDBCKChangeRecord *changeRecord in modifiedRecordsArray)
	{
		CKRecordID *recordID = changeRecord.recordID;
		if (recordID) {
			[modifiedRecords setObject:changeRecord forKey:recordID];
		}
	}
}

- (void)enumerateMissingRecordsWithBlock:(CKRecord* (^)(CKRecordID *recordID, NSArray *changedKeys))block
{
	for (YDBCKChangeRecord *changeRecord in [modifiedRecords objectEnumerator])
	{
		if (changeRecord.record == nil)
		{
			CKRecord *record = block(changeRecord.recordID, changeRecord.changedKeys);
			
			changeRecord.record = record;
		}
	}
}

@end
