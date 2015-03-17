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
	handler->recordBlockType = YapDatabaseCloudKitBlockTypeWithKey;
	
	return handler;
}

+ (instancetype)withObjectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseCloudKitBlockTypeWithObject;
	
	return handler;
}

+ (instancetype)withMetadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseCloudKitBlockTypeWithMetadata;
	
	return handler;
}

+ (instancetype)withRowBlock:(YapDatabaseCloudKitRecordWithRowBlock)recordBlock
{
	if (recordBlock == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->recordBlock = recordBlock;
	handler->recordBlockType = YapDatabaseCloudKitBlockTypeWithRow;
	
	return handler;
}

@end
