#import "YapDatabaseFilteredViewTypes.h"
#import "YapDatabaseFilteredViewPrivate.h"


@implementation YapDatabaseViewFiltering

@synthesize block = block;
@synthesize blockType = blockType;

+ (instancetype)withKeyBlock:(YapDatabaseViewFilteringWithKeyBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithKey;
	
	return filtering;
}

+ (instancetype)withObjectBlock:(YapDatabaseViewFilteringWithObjectBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithObject;
	
	return filtering;
}

+ (instancetype)withMetadataBlock:(YapDatabaseViewFilteringWithMetadataBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithMetadata;
	
	return filtering;
}

+ (instancetype)withRowBlock:(YapDatabaseViewFilteringWithRowBlock)block
{
	if (block == NULL) return nil;
	
	YapDatabaseViewFiltering *filtering = [[YapDatabaseViewFiltering alloc] init];
	filtering->block = block;
	filtering->blockType = YapDatabaseBlockTypeWithRow;
	
	return filtering;
}

@end
