#import "YapDatabaseFilteredViewTypes.h"
#import "YapDatabaseFilteredViewPrivate.h"


@implementation YapDatabaseViewFiltering

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseViewFilteringWithKeyBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:ops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseViewFilteringWithObjectBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:ops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:ops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseViewFilteringWithRowBlock)block
{
	YapDatabaseBlockInvoke ops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:ops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseViewFilteringWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithKey;
	filtering->blockInvokeOptions = ops;
	
	return filtering;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseViewFilteringWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithObject;
	filtering->blockInvokeOptions = ops;
	
	return filtering;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithMetadata;
	filtering->blockInvokeOptions = ops;
	
	return filtering;
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseViewFilteringWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithRow;
	filtering->blockInvokeOptions = ops;
	
	return filtering;
}

@end
