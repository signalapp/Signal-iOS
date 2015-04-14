#import "YapDatabaseViewPageMetadata.h"


@implementation YapDatabaseViewPageMetadata

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseViewPageMetadata *copy = [[YapDatabaseViewPageMetadata alloc] init];
	
	copy->pageKey = pageKey;
	copy->prevPageKey = prevPageKey;
	copy->group = group;
	copy->count = count;
	
	// Do NOT copy the isNew property.
	// This value is relavent only to a single connection.
	
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:
	    @"<YapDatabaseViewPageMetadata[%p]: group(%@) count(%lu) pageKey(%@) prevPageKey(%@)>",
	    self, group, (unsigned long)count, pageKey, prevPageKey];
}

@end
