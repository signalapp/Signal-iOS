#import "YapDatabaseCKRecord.h"


@implementation YapDatabaseCKRecord

/**
 * This method serializes just the "system fields" of the given record.
 * That is, it won't store any of the user-created key/value pairs.
 * It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
**/
+ (NSData *)serializeRecord:(CKRecord *)record
{
	if (record == nil) return nil;
	
	YapDatabaseCKRecord *recordWrapper = [[YapDatabaseCKRecord alloc] initWithRecord:record];
	return [NSKeyedArchiver archivedDataWithRootObject:recordWrapper];
}

/**
 * Deserialized the given record data.
 *
 * If the record data came from [YapDatabaseCKRecord serializeRecord:],
 * then the returned record will only contain the "system fields".
**/
+ (CKRecord *)deserializeRecord:(NSData *)data
{
	if (data)
		return [NSKeyedUnarchiver unarchiveObjectWithData:data];
	else
		return nil;
}

/**
 * Returns a "sanitized" copy of the given record.
 * That is, a copy that ONLY includes the "system fields" of the record.
 * It will NOT contain any key/value pairs from the original record.
**/
+ (CKRecord *)sanitizedRecord:(CKRecord *)record
{
	// This is the ONLY way in which I know how to accomplish this task.
	//
	// Other techniques, such as making a copy and removing all the values,
	// ends up giving us a record with a bunch of changedKeys. Not what we want.
	
	return [self deserializeRecord:[self serializeRecord:record]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize record = record;

- (instancetype)initWithRecord:(CKRecord *)inRecord
{
	if ((self = [super init]))
	{
		record = inRecord;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	return nil;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[record encodeSystemFieldsWithCoder:coder];
}

/**
 * When this object is decoded, it should decode it as a straight CKRecord object.
**/
- (Class)classForKeyedArchiver
{
	return [CKRecord class];
}

/**
 * I think this method is largely replaced by classForKeyedArchiver.
 * But it may be used by other 'coders', so it's included just in case.
**/
- (Class)classForCoder
{
	return [CKRecord class];
}

@end
