#import "YapDebugDictionary.h"


/**
 * This is a simple class to ensure that keys & objects we're putting into a dictionary are all of the desired class.
 * It's intended only for debugging purposes, especially in refactoring cases.
**/
@implementation YapDebugDictionary
{
	NSMutableDictionary *dict;
	
	Class keyClass;
	Class objectClass;
}

- (instancetype)initWithKeyClass:(Class)inKeyClass objectClass:(Class)inObjectClass
{
	return [self initWithKeyClass:inKeyClass objectClass:inObjectClass capacity:0];
}

- (instancetype)initWithKeyClass:(Class)inKeyClass objectClass:(Class)inObjectClass capacity:(NSUInteger)capacity
{
	if ((self = [super init]))
	{
		if (capacity > 0)
			dict = [[NSMutableDictionary alloc] initWithCapacity:capacity];
		else
			dict = [[NSMutableDictionary alloc] init];
		
		keyClass = inKeyClass;
		objectClass = inObjectClass;
	}
	return self;
}

- (instancetype)initWithDictionary:(YapDebugDictionary *)ydd copyItems:(BOOL)copyItems
{
	if ((self = [super init]))
	{
		dict = [[NSMutableDictionary alloc] initWithDictionary:ydd->dict copyItems:copyItems];
		
		keyClass = ydd->keyClass;
		objectClass = ydd->objectClass;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	return [[YapDebugDictionary alloc] initWithDictionary:self copyItems:NO];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Inspection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)objectForKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Invalid key class");
	
	return [dict objectForKey:key];
}

- (void)setObject:(id)object forKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Invalid key class");
	NSAssert([object isKindOfClass:objectClass], @"Invalid key class");
	
	[dict setObject:object forKey:key];
}

- (void)removeObjectForKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Invalid key class");
	
	[dict removeObjectForKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pass Through
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)count
{
	return dict.count;
}

- (NSArray *)allKeys
{
	return [dict allKeys];
}

- (NSArray *)allValues
{
	return [dict allValues];
}

- (NSEnumerator *)objectEnumerator
{
	return [dict objectEnumerator];
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	[dict enumerateKeysAndObjectsUsingBlock:block];
}

@end
