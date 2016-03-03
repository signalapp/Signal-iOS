#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitPrivate.h" // Required for public/package ivars


@implementation YapDatabaseCloudKitRecordHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:ops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:ops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:ops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseCloudKitRecordWithRowBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:ops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)block
{
	if (block == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)block
{
	if (block == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)block
{
	if (block == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseCloudKitRecordWithRowBlock)block
{
	if (block == nil) return nil;
	
	YapDatabaseCloudKitRecordHandler *handler = [[YapDatabaseCloudKitRecordHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

@end
