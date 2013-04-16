#import "YapDatabaseViewInternal.h"


@implementation YapDatabaseViewPageMetadata

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: 'pageKey' is transient
		
		nextPageKey = [decoder decodeObjectForKey:@"nextPageKey"];
		section = [decoder decodeIntegerForKey:@"section"];
		count = [decoder decodeIntegerForKey:@"count"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	// Note: 'pageKey' is transient
	
	[coder encodeObject:nextPageKey forKey:@"nextPageKey"];
	[coder encodeInteger:section forKey:@"section"];
	[coder encodeInteger:count forKey:@"count"];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewPageMetadata *copy = [[YapDatabaseViewPageMetadata alloc] init];
	
	copy->pageKey = pageKey;
	copy->nextPageKey = nextPageKey;
	copy->section = section;
	copy->count = count;
	
	return copy;
}

@end
