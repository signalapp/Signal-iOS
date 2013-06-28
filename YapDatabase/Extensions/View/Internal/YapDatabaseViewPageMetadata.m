#import "YapDatabaseViewPageMetadata.h"


@implementation YapDatabaseViewPageMetadata

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: 'pageKey' and 'nextPageKey' are transient
		
		prevPageKey = [decoder decodeObjectForKey:@"prevPageKey"];
		group = [decoder decodeObjectForKey:@"group"];
		count = [decoder decodeIntegerForKey:@"count"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	// Note: 'pageKey' and 'nextPageKey' are transient
	
	[coder encodeObject:prevPageKey forKey:@"prevPageKey"];
	[coder encodeObject:group forKey:@"group"];
	[coder encodeInteger:count forKey:@"count"];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewPageMetadata *copy = [[YapDatabaseViewPageMetadata alloc] init];
	
	copy->pageKey = pageKey;
	copy->prevPageKey = prevPageKey;
	copy->nextPageKey = nextPageKey;
	copy->group = group;
	copy->count = count;
	
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:
	    @"<YapDatabaseViewPageMetadata[%p]: group(%@) count(%lu) pageKey(%@) prev(%@) next(%@)>",
	    self, group, (unsigned long)count, pageKey, prevPageKey, nextPageKey];
}

@end
