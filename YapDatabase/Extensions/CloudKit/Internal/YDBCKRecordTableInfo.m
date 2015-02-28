#import "YDBCKRecordTableInfo.h"


@implementation YDBCKCleanRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize record = record;
@synthesize ownerCount = ownerCount;


- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                    record:(CKRecord *)inRecord
                                ownerCount:(int64_t)inOwnerCount
{
	if ((self = [super init]))
	{
		databaseIdentifier = [inDatabaseIdentifier copy];
		ownerCount = inOwnerCount;
		record = inRecord;
	}
	return self;
}


- (YDBCKDirtyRecordTableInfo *)dirtyCopy
{
	YDBCKDirtyRecordTableInfo *dirtyCopy =
	  [[YDBCKDirtyRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                       recordID:record.recordID
	                                                     ownerCount:ownerCount];
	
	dirtyCopy.dirty_ownerCount = ownerCount;
	dirtyCopy.dirty_record = [record copy];
	
	return dirtyCopy;
}

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)newRecord
{
	YDBCKCleanRecordTableInfo *copy = [[YDBCKCleanRecordTableInfo alloc] init];
	copy->databaseIdentifier = databaseIdentifier;
	copy->record = newRecord;
	copy->ownerCount = ownerCount;
	
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

@synthesize dirty_record = dirty_record;
@synthesize dirty_ownerCount = dirty_ownerCount;

@synthesize skipUploadRecord;
@synthesize skipUploadDeletion;
@synthesize remoteDeletion;
@synthesize remoteMerge;

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                  recordID:(CKRecordID *)inRecordID
                                ownerCount:(int64_t)in_clean_ownerCount
{
	if ((self = [super init]))
	{
		databaseIdentifier = [inDatabaseIdentifier copy];
		recordID = inRecordID;
		
		clean_ownerCount = in_clean_ownerCount;
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

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)newRecord
{
	YDBCKCleanRecordTableInfo *cleanCopy =
	  [[YDBCKCleanRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                         record:newRecord
	                                                     ownerCount:dirty_ownerCount];
	return cleanCopy;
}

@end
