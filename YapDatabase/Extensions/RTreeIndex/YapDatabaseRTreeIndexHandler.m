#import "YapDatabaseRTreeIndexHandler.h"


@implementation YapDatabaseRTreeIndexHandler

@synthesize block = block;
@synthesize blockType = blockType;

+ (instancetype)withKeyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block
{
	if (block == NULL) return nil;

	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;

	return handler;
}

+ (instancetype)withObjectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block
{
	if (block == NULL) return nil;

	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;

	return handler;
}

+ (instancetype)withMetadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block
{
	if (block == NULL) return nil;

	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;

	return handler;
}

+ (instancetype)withRowBlock:(YapDatabaseRTreeIndexWithRowBlock)block
{
	if (block == NULL) return nil;

	YapDatabaseRTreeIndexHandler *handler = [[YapDatabaseRTreeIndexHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;

	return handler;
}

@end
