#import "YapDatabaseViewPageMetadata.h"


@implementation YapDatabaseViewPageMetadata

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: 'pageKey' is transient
		
		nextPageKey = [decoder decodeObjectForKey:@"nextPageKey"];
		group = [decoder decodeObjectForKey:@"group"];
		count = [decoder decodeIntegerForKey:@"count"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	// Note: 'pageKey' is transient
	
	[coder encodeObject:nextPageKey forKey:@"nextPageKey"];
	[coder encodeObject:group forKey:@"group"];
	[coder encodeInteger:count forKey:@"count"];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewPageMetadata *copy = [[YapDatabaseViewPageMetadata alloc] init];
	
	copy->pageKey = pageKey;
	copy->nextPageKey = nextPageKey;
	copy->group = group;
	copy->count = count;
	
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:
	    @"<YapDatabaseViewPageMetadata[%p]: group(%@) count(%lu) pageKey(%@) nextPageKey(%@)>",
	    self, group, (unsigned long)count, pageKey, nextPageKey];
}

@end
