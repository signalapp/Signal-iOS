#import "YDBCKChangeRecord.h"
#import "YDBCKRecord.h"

static NSString *const k_record         = @"record";
static NSString *const k_originalValues = @"originalValues";
static NSString *const k_recordID       = @"recordID";
static NSString *const k_changedKeys    = @"changedKeys";

@implementation YDBCKChangeRecord
{
	CKRecordID *recordID;
	
	NSArray *changedKeys;
	NSSet *changedKeysSet;
}

@synthesize record = record;
@synthesize needsStoreFullRecord = needsStoreFullRecord;
@synthesize originalValues = originalValues;

@dynamic recordID;
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
	
	// Important: We MUST make a copy of the record so each changeSet.record is unique !
	// This is to ensure that modifying changeRecords in the pendingQueue doesn't interfere with the masterQueue.
	copy->record = [record safeCopy];
	
	copy->needsStoreFullRecord = needsStoreFullRecord;
	copy->originalValues = originalValues;
	
	copy->recordID = recordID;
	copy->changedKeys = changedKeys;
	
	return copy;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		record = [decoder decodeObjectForKey:k_record];
		
		originalValues = [decoder decodeObjectForKey:k_originalValues];
		
		recordID = [decoder decodeObjectForKey:k_recordID];
		changedKeys = [decoder decodeObjectForKey:k_changedKeys];
		
		if (record)
			needsStoreFullRecord = YES;
		else
			needsStoreFullRecord = NO;
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (needsStoreFullRecord)
	{
		[coder encodeObject:record forKey:k_record];
	}
	else
	{
		[coder encodeObject:self.recordID forKey:k_recordID];
		[coder encodeObject:self.changedKeys forKey:k_changedKeys];
	}
	
	[coder encodeObject:originalValues forKey:k_originalValues];
}

- (void)setRecord:(CKRecord *)inRecord
{
	recordID = nil;
	changedKeys = nil;
	changedKeysSet = nil;
	
	record = inRecord;
}

- (CKRecordID *)recordID
{
	if (recordID)
		return recordID;
	else
		return record.recordID;
}

- (NSArray *)changedKeys
{
	if (changedKeys)
		return changedKeys;
	else
		return record.changedKeys;
}

- (NSSet *)changedKeysSet
{
	if (changedKeysSet == nil) // Generated on-demand (if needed)
	{
		changedKeysSet = [[NSSet alloc] initWithArray:self.changedKeys];
	}
	
	return changedKeysSet;
}

@end
