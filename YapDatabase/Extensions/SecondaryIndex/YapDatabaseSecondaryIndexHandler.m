#import "YapDatabaseSecondaryIndexHandler.h"


@implementation YapDatabaseSecondaryIndexHandler

@synthesize block = block;
@synthesize blockType = blockType;

+ (instancetype)withKeyBlock:(YapDatabaseSecondaryIndexWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseSecondaryIndexBlockTypeWithKey;
	
	return handler;
}

+ (instancetype)withObjectBlock:(YapDatabaseSecondaryIndexWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseSecondaryIndexBlockTypeWithObject;
	
	return handler;
}

+ (instancetype)withMetadataBlock:(YapDatabaseSecondaryIndexWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseSecondaryIndexBlockTypeWithMetadata;
	
	return handler;
}

+ (instancetype)withRowBlock:(YapDatabaseSecondaryIndexWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseSecondaryIndexBlockTypeWithRow;
	
	return handler;
}

/**
 * Helper method for supporting deprecated methods.
 * This method will disappear in the future.
**/
+ (instancetype)withBlock:(YapDatabaseSecondaryIndexBlock)block blockType:(YapDatabaseSecondaryIndexBlockType)blockType
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = blockType;
	
	return handler;
}

@end
