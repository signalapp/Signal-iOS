#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitPrivate.h"


@implementation YapDatabaseCloudKitRecordHandler

@synthesize recordBlock = recordBlock;
@synthesize recordBlockType = recordBlockType;

+ (instancetype)withKeyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseBlockTypeWithKey;
	
	return handler;
}

+ (instancetype)withObjectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseBlockTypeWithObject;
	
	return handler;
}

+ (instancetype)withMetadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseBlockTypeWithMetadata;
	
	return handler;
}

+ (instancetype)withRowBlock:(YapDatabaseCloudKitRecordWithRowBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseBlockTypeWithRow;
	
	return handler;
}

@end
