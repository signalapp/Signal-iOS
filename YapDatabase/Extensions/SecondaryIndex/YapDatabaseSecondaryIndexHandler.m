#import "YapDatabaseSecondaryIndexHandler.h"


@implementation YapDatabaseSecondaryIndexHandler

@synthesize block = block;
@synthesize blockType = blockType;

+ (instancetype)withKeyBlock:(YapDatabaseSecondaryIndexWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;
	
	return handler;
}

+ (instancetype)withObjectBlock:(YapDatabaseSecondaryIndexWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;
	
	return handler;
}

+ (instancetype)withMetadataBlock:(YapDatabaseSecondaryIndexWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;
	
	return handler;
}

+ (instancetype)withRowBlock:(YapDatabaseSecondaryIndexWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseSecondaryIndexHandler *handler = [[YapDatabaseSecondaryIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;
	
	return handler;
}

@end
