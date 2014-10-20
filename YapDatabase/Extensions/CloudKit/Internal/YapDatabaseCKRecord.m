#import "YapDatabaseCKRecord.h"


@implementation YapDatabaseCKRecord

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
