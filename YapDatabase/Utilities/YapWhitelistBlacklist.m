#import "YapWhitelistBlacklist.h"


@implementation YapWhitelistBlacklist
{
	NSSet *whitelist;
	NSSet *blacklist;
	
	YapWhitelistBlacklistFilterBlock filterBlock;
}

// See header file for documentation
- (instancetype)initWithWhitelist:(NSSet *)inWhitelist
{
	if ((self = [super init]))
	{
		whitelist = inWhitelist ? [inWhitelist copy] : [[NSSet alloc] init];
	}
	return self;
}

// See header file for documentation
- (instancetype)initWithBlacklist:(NSSet *)inBlacklist
{
	if ((self = [super init]))
	{
		blacklist = inBlacklist ? [inBlacklist copy] : [[NSSet alloc] init];
	}
	return self;
}

// See header file for documentation
- (instancetype)initWithFilterBlock:(YapWhitelistBlacklistFilterBlock)block
{
	if (block == NULL) return nil;
	
	if ((self = [super init]))
	{
		filterBlock = block;
	}
	return self;
}

// See header file for documentation
- (BOOL)isAllowed:(id)item
{
	if (whitelist)
	{
		return [whitelist containsObject:item];
	}
	else if (blacklist)
	{
		return ![blacklist containsObject:item];
	}
	else
	{
		return filterBlock(item);
	}
}

@end
