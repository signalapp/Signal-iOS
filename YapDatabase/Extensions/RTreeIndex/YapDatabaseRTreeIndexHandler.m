#import "YapDatabaseRTreeIndexHandler.h"
#import "YapDatabaseRTreeIndexPrivate.h" // Required for public/package ivars


@implementation YapDatabaseRTreeIndexHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:ops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:ops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:ops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseRTreeIndexWithRowBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:ops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseRTreeIndexWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

@end
