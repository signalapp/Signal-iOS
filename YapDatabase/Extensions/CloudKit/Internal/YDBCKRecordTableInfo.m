#import "YDBCKRecordTableInfo.h"


@implementation YDBCKCleanRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize ownerCount = ownerCount;
@synthesize recordKeys_hash = recordKeys_hash;
@synthesize record = record;

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                ownerCount:(int64_t)inOwnerCount
                           recordKeys_hash:(NSString *)inRecordKeys_hash
                                    record:(CKRecord *)inRecord
{
	if ((self = [super init]))
	{
		databaseIdentifier = inDatabaseIdentifier;
		ownerCount = inOwnerCount;
		recordKeys_hash = inRecordKeys_hash;
		record = inRecord;
	}
	return self;
}

- (YDBCKDirtyRecordTableInfo *)dirtyCopyWithBaseRecord:(CKRecord *)baseRecord
{
	YDBCKDirtyRecordTableInfo *dirtyCopy =
	  [[YDBCKDirtyRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                       recordID:record.recordID
	                                                     ownerCount:ownerCount
	                                                recordKeys_hash:recordKeys_hash];
	
	dirtyCopy.dirty_ownerCount = ownerCount;
	dirtyCopy.dirty_record = baseRecord;
	
	return dirtyCopy;
}

- (YDBCKCleanRecordTableInfo *)cleanCopyWithRecordKeys_hash:(NSString *)newRecordKeys_hash
                                            sanitizedRecord:(CKRecord *)newRecord
{
	YDBCKCleanRecordTableInfo *copy = [[YDBCKCleanRecordTableInfo alloc] init];
	copy->databaseIdentifier = databaseIdentifier;
	copy->ownerCount = ownerCount;
	copy->recordKeys_hash = newRecordKeys_hash;
	copy->record = newRecord;
	
	return copy;
}

- (CKRecord *)current_record {
	return record;
}

- (int64_t)current_ownerCount {
	return ownerCount;
}

@end

#pragma mark -

@implementation YDBCKDirtyRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize recordID = recordID;

@synthesize clean_ownerCount = clean_ownerCount;
@synthesize clean_recordKeys_hash = clean_recordKeys_hash;

@synthesize dirty_record = dirty_record;
@synthesize dirty_ownerCount = dirty_ownerCount;

@synthesize skipUploadRecord;
@synthesize skipUploadDeletion;
@synthesize remoteDeletion;
@synthesize remoteMerge;

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                  recordID:(CKRecordID *)inRecordID
                                ownerCount:(int64_t)in_clean_ownerCount
                           recordKeys_hash:(NSString *)in_clean_recordKeys_hash
{
	if ((self = [super init]))
	{
		databaseIdentifier = [inDatabaseIdentifier copy];
		recordID = inRecordID;
		
		clean_ownerCount = in_clean_ownerCount;
		clean_recordKeys_hash = in_clean_recordKeys_hash;
	}
	return self;
}

- (CKRecord *)current_record {
	return dirty_record;
}

- (int64_t)current_ownerCount {
	return dirty_ownerCount;
}

- (void)incrementOwnerCount
{
	if (dirty_ownerCount < INT64_MAX) {
		dirty_ownerCount++;
	}
}

- (void)decrementOwnerCount
{
	if (dirty_ownerCount > 0) {
		dirty_ownerCount--;
	}
}

- (BOOL)ownerCountChanged
{
	return (clean_ownerCount != dirty_ownerCount);
}

- (BOOL)hasNilRecordOrZeroOwnerCount
{
	if (dirty_record == 0) return YES;
	if (dirty_ownerCount <= 0) return YES;
	
	return NO;
}

- (YDBCKCleanRecordTableInfo *)cleanCopyWithRecordKeys_hash:(NSString *)newRecordKeys_hash
                                            sanitizedRecord:(CKRecord *)newRecord
{
	YDBCKCleanRecordTableInfo *cleanCopy =
	  [[YDBCKCleanRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                     ownerCount:dirty_ownerCount
	                                                recordKeys_hash:newRecordKeys_hash
	                                                         record:newRecord];
	return cleanCopy;
}

@end
