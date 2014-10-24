#import "YDBCKDirtyRecordInfo.h"


@implementation YDBCKDirtyRecordInfo

@synthesize clean_recordID = clean_recordID;
@synthesize clean_databaseIdentifier = clean_databaseIdentifier;

@synthesize dirty_record = dirty_record;
@synthesize dirty_databaseIdentifier = dirty_databaseIdentifier;

- (BOOL)wasInserted
{
	return (clean_recordID == nil);
}

- (BOOL)databaseIdentifierOrRecordIDChanged
{
	if (clean_databaseIdentifier)
	{
		if (![clean_databaseIdentifier isEqualToString:dirty_databaseIdentifier]) {
			return YES;
		}
	}
	else
	{
		if (dirty_databaseIdentifier) {
			return YES;
		}
	}
	
	if (![clean_recordID isEqual:dirty_record.recordID]) {
		return YES;
	}
	
	return NO;
}

@end
