#import "YDBCKChangeSet.h"
#import "YDBCKChangeRecord.h"
#import "YapDatabaseCloudKitPrivate.h"


@implementation YDBCKChangeSet

@synthesize uuid = uuid;
@synthesize prev = prev;

@synthesize databaseIdentifier = databaseIdentifier;

@dynamic recordIDsToDelete;
@dynamic recordsToSave_noCopy;

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
	
	return emptyCopy;
}

- (instancetype)fullCopy
{
	YDBCKChangeSet *fullCopy = [self emptyCopy];
	fullCopy->deletedRecordIDs = [deletedRecordIDs mutableCopy];
	
#if DEBUG
	fullCopy->moodifiedRecords = [[YapDebugDictionary alloc] initWithDictionary:moodifiedRecords copyItems:YES];
#else
	fullCopy->moodifiedRecords = [[NSMutableDictionary alloc] initWithDictionary:moodifiedRecords copyItems:YES];
#endif
	
	return fullCopy;
}

- (NSArray *)recordIDsToDelete
{
	return [deletedRecordIDs copy];
}

- (NSArray *)recordsToSave_noCopy
{
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[moodifiedRecords count]];
	
	for (YDBCKChangeRecord *changeRecord in [moodifiedRecords objectEnumerator])
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
	if ([moodifiedRecords count] > 0)
		return [NSKeyedArchiver archivedDataWithRootObject:[moodifiedRecords allValues]];
	else
		return nil;
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
	
#if DEBUG
	moodifiedRecords = [[YapDebugDictionary alloc] initWithKeyClass:[CKRecordID class]
	                                                    objectClass:[YDBCKChangeRecord class]
	                                                       capacity:[modifiedRecordsArray count]];
#else
	moodifiedRecords = [[NSMutableDictionary alloc] initWithCapacity:[modifiedRecordsArray count]];
#endif
	
	for (YDBCKChangeRecord *changeRecord in modifiedRecordsArray)
	{
		CKRecordID *recordID = changeRecord.recordID;
		if (recordID) {
			[moodifiedRecords setObject:changeRecord forKey:recordID];
		}
	}
}

- (void)enumerateMissingRecordsWithBlock:(CKRecord* (^)(CKRecordID *recordID, NSArray *changedKeys))block
{
	for (YDBCKChangeRecord *changeRecord in [moodifiedRecords objectEnumerator])
	{
		if (changeRecord.record == nil)
		{
			CKRecord *record = block(changeRecord.recordID, changeRecord.changedKeys);
			
			changeRecord.record = record;
		}
	}
}

@end
