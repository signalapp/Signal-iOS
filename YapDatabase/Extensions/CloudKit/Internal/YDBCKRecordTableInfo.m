#import "YDBCKRecordTableInfo.h"
#import "YDBCKRecord.h"


@implementation YDBCKCleanRecordTableInfo

@synthesize databaseIdentifier = databaseIdentifier;
@synthesize ownerCount = ownerCount;
@synthesize record = record;

- (instancetype)init
{
	NSAssert(NO, @"Invalid init method used");
	return nil;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                ownerCount:(int64_t)inOwnerCount
                                    record:(CKRecord *)inRecord
{
	NSAssert(inRecord != nil, @"Invalid record");
	NSAssert(inRecord.recordID != nil, @"Invalid recordID");
	
	if ((self = [super init]))
	{
		databaseIdentifier = inDatabaseIdentifier;
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
	
	dirtyCopy.dirty_record = [record safeCopy];
	
	return dirtyCopy;
}

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)newRecord
{
	return [[YDBCKCleanRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                          ownerCount:ownerCount
	                                                              record:newRecord];
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

@synthesize originalValues = originalValues;

- (instancetype)init
{
	NSAssert(NO, @"Invalid init method used");
	return nil;
}

- (instancetype)initWithDatabaseIdentifier:(NSString *)inDatabaseIdentifier
                                  recordID:(CKRecordID *)inRecordID
                                ownerCount:(int64_t)in_ownerCount
{
	NSAssert(inRecordID != nil, @"Invalid recordID - nil");
	
	if ((self = [super init]))
	{
		databaseIdentifier = [inDatabaseIdentifier copy];
		recordID = inRecordID;
		
		clean_ownerCount = in_ownerCount;
		dirty_ownerCount = in_ownerCount;
	}
	return self;
}

- (void)setDirty_record:(CKRecord *)new_dirty_record
{
	if (new_dirty_record) {
		NSAssert([new_dirty_record.recordID isEqual:recordID], @"Invalid recordID - mismatch");
	}
	
	dirty_record = new_dirty_record;
}

- (CKRecord *)current_record {
	return dirty_record;
}

- (int64_t)current_ownerCount {
	return dirty_ownerCount;
}

- (void)mergeOriginalValues:(NSDictionary *)inOriginalValues
{
	if (inOriginalValues == nil) return;
	
	if (originalValues == nil)
	{
		originalValues = [inOriginalValues copy];
	}
	else
	{
		__block NSMutableDictionary *newOriginalValues = nil;
		
		[inOriginalValues enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			if ([originalValues objectForKey:key] == nil)
			{
				if (newOriginalValues == nil)
					newOriginalValues = [originalValues mutableCopy];
				
				[newOriginalValues setObject:obj forKey:key];
			}
		}];
		
		if (newOriginalValues) {
			originalValues = [newOriginalValues copy];
		}
	}
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
	NSAssert([newRecord.recordID isEqual:recordID], @"Invalid sanitizedRecord - recordID mismatch");
	
	return [[YDBCKCleanRecordTableInfo alloc] initWithDatabaseIdentifier:databaseIdentifier
	                                                          ownerCount:dirty_ownerCount
	                                                              record:newRecord];
}

@end
