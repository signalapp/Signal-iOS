#import "YapReadOnlyMutableDictionary.h"


@implementation YapReadOnlyMutableDictionary
{
	NSDictionary *originalDict;
}

- (id)initWithOriginalDictionary:(NSDictionary *)inOriginalDict
{
	if ((self = [super init]))
	{
		originalDict = inOriginalDict;
	}
	return self;
}

- (NSUInteger)count
{
	return [originalDict count];
}

- (NSArray *)allKeys
{
	return [originalDict allKeys];
}

- (id)objectForKey:(id)key
{
	return [originalDict objectForKey:key];
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	[originalDict enumerateKeysAndObjectsUsingBlock:block];
}

@end
