#import "YDBCKMappingTableInfo.h"


@implementation YDBCKCleanMappingTableInfo

@synthesize recordTable_hash = recordTable_hash;

- (instancetype)initWithRecordTableHash:(NSString *)hash
{
	if ((self = [super init]))
	{
		recordTable_hash = hash;
	}
	return self;
}

- (NSString *)current_recordTable_hash {
	return recordTable_hash;
}

- (YDBCKDirtyMappingTableInfo *)dirtyCopy
{
	YDBCKDirtyMappingTableInfo *dirtyCopy =
	  [[YDBCKDirtyMappingTableInfo alloc] initWithRecordTableHash:recordTable_hash];
	
	return dirtyCopy;
}

@end

#pragma mark -

@implementation YDBCKDirtyMappingTableInfo

@synthesize clean_recordTable_hash = clean_recordTable_hash;
@synthesize dirty_recordTable_hash = dirty_recordTable_hash;

- (instancetype)initWithRecordTableHash:(NSString *)hash
{
	if ((self = [super init]))
	{
		clean_recordTable_hash = hash;
		dirty_recordTable_hash = hash;
	}
	return self;
}

- (NSString *)current_recordTable_hash {
	return dirty_recordTable_hash;
}

- (YDBCKCleanMappingTableInfo *)cleanCopy
{
	YDBCKCleanMappingTableInfo *cleanCopy =
 	  [[YDBCKCleanMappingTableInfo alloc] initWithRecordTableHash:dirty_recordTable_hash];
	
	return cleanCopy;
}

@end
