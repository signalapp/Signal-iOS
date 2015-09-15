#import "YapDatabaseFilteredViewTypes.h"


@implementation YapDatabaseViewFiltering

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

+ (instancetype)withKeyBlock:(YapDatabaseViewFilteringWithKeyBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseBlockTypeWithKey;
	
	return filtering;
}

+ (instancetype)withObjectBlock:(YapDatabaseViewFilteringWithObjectBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseBlockTypeWithObject;
	
	return filtering;
}

+ (instancetype)withMetadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseBlockTypeWithMetadata;
	
	return filtering;
}

+ (instancetype)withRowBlock:(YapDatabaseViewFilteringWithRowBlock)filteringBlock
{
	if (filteringBlock == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->filteringBlock = filteringBlock;
	filtering->filteringBlockType = YapDatabaseBlockTypeWithRow;
	
	return filtering;
}

@end
