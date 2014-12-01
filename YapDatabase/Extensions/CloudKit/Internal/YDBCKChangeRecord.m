#import "YDBCKChangeRecord.h"


static NSString *const k_record      = @"record";
static NSString *const k_recordID    = @"recordID";
static NSString *const k_changedKeys = @"changedKeys";

@implementation YDBCKChangeRecord
{
	CKRecordID *recordID;
	NSArray *changedKeys;
	NSSet *changedKeysSet;
}

@synthesize record = record;
@synthesize canStoreOnlyChangedKeys = canStoreOnlyChangedKeys;

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
	copy->canStoreOnlyChangedKeys = canStoreOnlyChangedKeys;
	
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
		
		if (recordID || changedKeys)
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
		[coder encodeObject:self.recordID forKey:k_recordID];
		[coder encodeObject:self.changedKeys forKey:k_changedKeys];
	}
	else
	{
		[coder encodeObject:record forKey:k_record];
	}
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
