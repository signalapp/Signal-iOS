#import "YapDatabaseFilteredViewTypes.h"

@implementation YapDatabaseViewFiltering

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

+ (instancetype)withKeyBlock:(YapDatabaseViewFilteringWithKeyBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseViewBlockTypeWithKey;
	
	return filtering;
}

+ (instancetype)withObjectBlock:(YapDatabaseViewFilteringWithObjectBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	
	return filtering;
}

+ (instancetype)withMetadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseViewBlockTypeWithMetadata;
	
	return filtering;
}

+ (instancetype)withRowBlock:(YapDatabaseViewFilteringWithRowBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseViewBlockTypeWithRow;
	
	return filtering;
}

/**
 * Helper method for supporting deprecated methods.
 * This method will disappear in the future.
**/
+ (instancetype)withBlock:(YapDatabaseViewFilteringBlock)block blockType:(YapDatabaseViewBlockType)blockType
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = block;
	filtering->filteringBlockType = blockType;
	
	return filtering;
}

@end
