#import "YapDatabaseFullTextSearchHandler.h"
#import "YapDatabaseFullTextSearchPrivate.h" // Required for public/package ivars


@implementation YapDatabaseFullTextSearchHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseFullTextSearchWithKeyBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:ops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseFullTextSearchWithObjectBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:ops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseFullTextSearchWithMetadataBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:ops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseFullTextSearchWithRowBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:ops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseFullTextSearchWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseFullTextSearchHandler *handler = [[YapDatabaseFullTextSearchHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithKey;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseFullTextSearchWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseFullTextSearchHandler *handler = [[YapDatabaseFullTextSearchHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithObject;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseFullTextSearchWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseFullTextSearchHandler *handler = [[YapDatabaseFullTextSearchHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithMetadata;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseFullTextSearchWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseFullTextSearchHandler *handler = [[YapDatabaseFullTextSearchHandler alloc] init];
	handler->block = block;
	handler->blockType = YapDatabaseBlockTypeWithRow;
	handler->blockInvokeOptions = ops;
	
	return handler;
}

@end
