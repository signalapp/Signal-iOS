#import "YapDatabaseViewState.h"

#define AssertIsMutable() NSAssert(!isImmutable, @"Attempting to mutate immutable state")

@implementation YapDatabaseViewState
{
	NSMutableDictionary<NSString *, NSMutableArray<YapDatabaseViewPageMetadata *> *> *group_pagesMetadata_dict;
	NSMutableDictionary<NSString *, NSString *> *pageKey_group_dict;
	
	// - group_pagesMetadata_dict : group -> @[ YapDatabaseViewPageMetadata, ... ]
	// - pageKey_group_dict       : pageKey -> group
}

@synthesize isImmutable = isImmutable;

- (id)init
{
	if ((self = [super init]))
	{
		isImmutable = NO;
		
		group_pagesMetadata_dict = [[NSMutableDictionary alloc] init];
		pageKey_group_dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (id)initForCopy
{
	if ((self = [super init])) { }
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Copying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableDictionary *)group_pagesMetadata_dict_deepCopy
{
	NSMutableDictionary *deepCopy = [NSMutableDictionary dictionaryWithCapacity:[group_pagesMetadata_dict count]];
	
	[group_pagesMetadata_dict enumerateKeysAndObjectsUsingBlock:
	    ^(NSString *group, NSMutableArray *pagesMetadata, BOOL __unused *stop)
	{
		// We need a mutable copy of the pagesMetadata array,
		// and we need a copy of each YapDatabaseViewPageMetadata object within the pages array.
		
		NSMutableArray *pagesMetadataDeepCopy = [[NSMutableArray alloc] initWithArray:pagesMetadata copyItems:YES];
		
		[deepCopy setObject:pagesMetadataDeepCopy forKey:group];
	}];
	
	return deepCopy;
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	if (isImmutable)
	{
		return self;
	}
	else
	{
		YapDatabaseViewState *copy = [[YapDatabaseViewState alloc] initForCopy];
		copy->isImmutable = YES;
		copy->group_pagesMetadata_dict = [self group_pagesMetadata_dict_deepCopy];
		copy->pageKey_group_dict = [pageKey_group_dict mutableCopy];
		
		return copy;
	}
}

- (id)mutableCopyWithZone:(NSZone __unused *)zone
{
	YapDatabaseViewState *copy = [[YapDatabaseViewState alloc] initForCopy];
	copy->isImmutable = NO;
	copy->group_pagesMetadata_dict = [self group_pagesMetadata_dict_deepCopy];
	copy->pageKey_group_dict = [pageKey_group_dict mutableCopy];
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Access
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)pagesMetadataForGroup:(NSString *)group
{
	return [group_pagesMetadata_dict objectForKey:group];
}

- (NSString *)groupForPageKey:(NSString *)pageKey
{
	return [pageKey_group_dict objectForKey:pageKey];
}

- (NSUInteger)numberOfGroups
{
	return [group_pagesMetadata_dict count];
}

- (void)enumerateGroupsWithBlock:(void (^)(NSString *group, BOOL *stop))block
{
	BOOL stop = NO;
	for (NSString *group in group_pagesMetadata_dict)
	{
		block(group, &stop);
		
		if (stop) break;
	}
}

- (void)enumerateWithBlock:(void (^)(NSString *group, NSArray *pagesMetadataForGroup, BOOL *stop))block
{
	[group_pagesMetadata_dict enumerateKeysAndObjectsUsingBlock:block];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mutation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)createGroup:(NSString *)group
{
	return [self createGroup:group withCapacity:0];
}

- (NSArray *)createGroup:(NSString *)group withCapacity:(NSUInteger)capacity
{
	AssertIsMutable();
	
	NSMutableArray *pagesMetadataForGroup = [group_pagesMetadata_dict objectForKey:group];
	if (pagesMetadataForGroup == nil)
	{
		if (capacity > 0)
			pagesMetadataForGroup = [[NSMutableArray alloc] initWithCapacity:capacity];
		else
			pagesMetadataForGroup = [[NSMutableArray alloc] init];
		
		[group_pagesMetadata_dict setObject:pagesMetadataForGroup forKey:group];
	}
	
	return pagesMetadataForGroup;
}

- (NSArray *)addPageMetadata:(YapDatabaseViewPageMetadata *)pageMetadata
                     toGroup:(NSString *)group
{
	AssertIsMutable();
	NSParameterAssert(pageMetadata != nil);
	
	[pageKey_group_dict setObject:group forKey:pageMetadata->pageKey];
	
	NSMutableArray *pagesMetadataForGroup = [group_pagesMetadata_dict objectForKey:group];
	[pagesMetadataForGroup addObject:pageMetadata];
	
	return pagesMetadataForGroup;
}

- (NSArray *)insertPageMetadata:(YapDatabaseViewPageMetadata *)pageMetadata
                        atIndex:(NSUInteger)index
                        inGroup:(NSString *)group
{
	AssertIsMutable();
	NSParameterAssert(pageMetadata != nil);
	
	[pageKey_group_dict setObject:group forKey:pageMetadata->pageKey];
	
	NSMutableArray *pagesMetadataForGroup = [group_pagesMetadata_dict objectForKey:group];
	[pagesMetadataForGroup insertObject:pageMetadata atIndex:index];
	
	return pagesMetadataForGroup;
}

- (NSArray *)removePageMetadataAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	AssertIsMutable();
	
	NSMutableArray *pagesMetadataForGroup = [group_pagesMetadata_dict objectForKey:group];
	YapDatabaseViewPageMetadata *pageMetadata = [pagesMetadataForGroup objectAtIndex:index];
	
	[pageKey_group_dict removeObjectForKey:pageMetadata->pageKey];
	[pagesMetadataForGroup removeObjectAtIndex:index];
	
	return pagesMetadataForGroup;
}

- (void)removeGroup:(NSString *)group
{
	AssertIsMutable();
	
	NSUInteger count = [[group_pagesMetadata_dict objectForKey:group] count];
	NSAssert(count == 0, @"Attempting to remove non-empty group");
	
	if (count == 0)
	{
		[group_pagesMetadata_dict removeObjectForKey:group];
	}
}

- (void)removeAllGroups
{
	AssertIsMutable();
	
	[group_pagesMetadata_dict removeAllObjects];
	[pageKey_group_dict removeAllObjects];
}

@end
