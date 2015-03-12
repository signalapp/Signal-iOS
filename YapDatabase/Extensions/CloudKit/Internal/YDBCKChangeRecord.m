#import "YDBCKChangeRecord.h"


static NSString *const k_record          = @"record";
static NSString *const k_recordID        = @"recordID";
static NSString *const k_changedKeys     = @"changedKeys";
static NSString *const k_recordKeys_hash = @"recordKeys_hash";

@implementation YDBCKChangeRecord
{
	CKRecordID *recordID;
	
	NSArray *changedKeys;
	NSSet *changedKeysSet;
}

@synthesize record = record;
@synthesize recordKeys_hash = recordKeys_hash;
@synthesize needsStoreFullRecord = needsStoreFullRecord;

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
	
	copy->record = record;
	copy->recordKeys_hash = recordKeys_hash;
	copy->needsStoreFullRecord = needsStoreFullRecord;
	
	copy->recordID = recordID;
	copy->changedKeys = changedKeys;
	
	return copy;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		record = [decoder decodeObjectForKey:k_record];
		
		recordID = [decoder decodeObjectForKey:k_recordID];
		changedKeys = [decoder decodeObjectForKey:k_changedKeys];
		recordKeys_hash = [decoder decodeObjectForKey:k_recordKeys_hash];
		
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
		[coder encodeObject:self.recordKeys_hash forKey:k_recordKeys_hash];
	}
}

- (void)setRecord:(CKRecord *)inRecord
{
	recordID = nil;
	recordKeys_hash = nil;
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
