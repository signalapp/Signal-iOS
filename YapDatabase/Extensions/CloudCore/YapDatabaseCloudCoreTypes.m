/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreTypes.h"
#import "YapDatabaseCloudCorePrivate.h"


@implementation YapDatabaseCloudCoreHandler

@synthesize block = block;
@synthesize blockType = blockType;
@synthesize blockInvokeOptions = blockInvokeOptions;

+ (instancetype)withKeyBlock:(YapDatabaseCloudCoreHandlerWithKeyBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithKey;
	return [self withOptions:iops keyBlock:block];
}

+ (instancetype)withObjectBlock:(YapDatabaseCloudCoreHandlerWithObjectBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithObject;
	return [self withOptions:iops objectBlock:block];
}

+ (instancetype)withMetadataBlock:(YapDatabaseCloudCoreHandlerWithMetadataBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata;
	return [self withOptions:iops metadataBlock:block];
}

+ (instancetype)withRowBlock:(YapDatabaseCloudCoreHandlerWithRowBlock)block
{
	YapDatabaseBlockInvoke iops = YapDatabaseBlockInvokeDefaultForBlockTypeWithRow;
	return [self withOptions:iops rowBlock:block];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseCloudCoreHandlerWithKeyBlock)block
{
	return [[YapDatabaseCloudCoreHandler alloc] initWithBlock:block
	                                                blockType:YapDatabaseBlockTypeWithKey
	                                       blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseCloudCoreHandlerWithObjectBlock)block
{
	return [[YapDatabaseCloudCoreHandler alloc] initWithBlock:block
	                                                blockType:YapDatabaseBlockTypeWithObject
	                                       blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseCloudCoreHandlerWithMetadataBlock)block
{
	return [[YapDatabaseCloudCoreHandler alloc] initWithBlock:block
	                                                blockType:YapDatabaseBlockTypeWithMetadata
	                                       blockInvokeOptions:ops];
}

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseCloudCoreHandlerWithRowBlock)block
{
	return [[YapDatabaseCloudCoreHandler alloc] initWithBlock:block
	                                                blockType:YapDatabaseBlockTypeWithRow
	                                       blockInvokeOptions:ops];
}

- (instancetype)init
{
	return nil;
}

- (instancetype)initWithBlock:(YapDatabaseCloudCoreHandlerBlock)inBlock
                    blockType:(YapDatabaseBlockType)inBlockType
           blockInvokeOptions:(YapDatabaseBlockInvoke)inBlockInvokeOptions
{
	if (inBlock == nil) return nil;
	
	if ((self = [super init]))
	{
		block = inBlock;
		blockType = inBlockType;
		blockInvokeOptions = inBlockInvokeOptions;
	}
	return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseCloudCoreDeleteHandler

@synthesize block = block;
@synthesize blockType = blockType;

+ (instancetype)withKeyBlock:(YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)block
{
	return [[YapDatabaseCloudCoreDeleteHandler alloc] initWithBlock:block blockType:YapDatabaseBlockTypeWithKey];
}

+ (instancetype)withObjectBlock:(YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)block
{
	return [[YapDatabaseCloudCoreDeleteHandler alloc] initWithBlock:block blockType:YapDatabaseBlockTypeWithObject];
}

+ (instancetype)withMetadataBlock:(YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)block
{
	return [[YapDatabaseCloudCoreDeleteHandler alloc] initWithBlock:block blockType:YapDatabaseBlockTypeWithMetadata];
}

+ (instancetype)withRowBlock:(YapDatabaseCloudCoreDeleteHandlerWithRowBlock)block
{
	return [[YapDatabaseCloudCoreDeleteHandler alloc] initWithBlock:block blockType:YapDatabaseBlockTypeWithRow];
}

- (instancetype)init
{
	return nil;
}

- (instancetype)initWithBlock:(YapDatabaseCloudCoreDeleteHandlerBlock)inBlock
                    blockType:(YapDatabaseBlockType)inBlockType
{
	if (inBlock == nil) return nil;
	
	if ((self = [super init]))
	{
		block = inBlock;
		blockType = inBlockType;
	}
	return self;
}

@end
