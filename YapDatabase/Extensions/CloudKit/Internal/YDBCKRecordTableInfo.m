#import "YDBCKRecordTableInfo.h"


@implementation YDBCKCleanRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize ownerCount = ownerCount;
@synthesize record = record;

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                ownerCount:(NSNumber *)inOwnerCount
                                    record:(CKRecord *)inRecord
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
	copy->ownerCount = ownerCount;
	copy->record = newRecord;
	
	return copy;
}

- (NSNumber *)current_ownerCount {
	return ownerCount;
}

- (CKRecord *)current_record {
	return record;
}

@end

#pragma mark -

@implementation YDBCKDirtyRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize recordID = recordID;

@synthesize clean_ownerCount = clean_ownerCount;

@synthesize dirty_ownerCount;
@synthesize dirty_record;

@synthesize skipUploadRecord;
@synthesize skipUploadDeletion;
@synthesize remoteDeletion;
@synthesize remoteMerge;

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                  recordID:(CKRecordID *)inRecordID
                                ownerCount:(NSNumber *)in_clean_ownerCount
{
	if ((self = [super init]))
	{
		databaseIdentifier = [inDatabaseIdentifier copy];
		recordID = inRecordID;
		
		clean_ownerCount = in_clean_ownerCount;
	}
	return self;
}

- (NSNumber *)current_ownerCount {
	return dirty_ownerCount;
}

- (CKRecord *)current_record {
	return dirty_record;
}

- (void)incrementOwnerCount
{
	int64_t ownerCount = [dirty_ownerCount longLongValue];
	if (ownerCount >= 0)
	{
		dirty_ownerCount = @(ownerCount + 1);
	}
}

- (void)decrementOwnerCount
{
	int64_t ownerCount = [dirty_ownerCount longLongValue];
	if (ownerCount > 0)
	{
		dirty_ownerCount = @(ownerCount - 1);
	}
}

- (BOOL)ownerCountChanged
{
	return [clean_ownerCount longLongValue] != [dirty_ownerCount longLongValue];
}

- (BOOL)hasNilRecordOrZeroOwnerCount
{
	if (dirty_record == 0) return YES;
	if ([dirty_ownerCount longLongValue] == 0) return YES;
	
	return NO;
}

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)newRecord
{
	YDBCKCleanRecordTableInfo *cleanCopy =
	  [[YDBCKCleanRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                     ownerCount:dirty_ownerCount
	                                                         record:newRecord];
	return cleanCopy;
}

@end
