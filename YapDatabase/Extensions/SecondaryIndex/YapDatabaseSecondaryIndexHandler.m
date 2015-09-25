#import "YapDatabaseSecondaryIndexHandler.h"
#import "YapDatabaseSecondaryIndexPrivate.h" // Required for public/package ivars


@implementation YapDatabaseSecondaryIndexHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseSecondaryIndexWithKeyBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:ops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseSecondaryIndexWithObjectBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:ops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseSecondaryIndexWithMetadataBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:ops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseSecondaryIndexWithRowBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:ops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseSecondaryIndexWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseSecondaryIndexWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseSecondaryIndexWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseSecondaryIndexWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

@end
