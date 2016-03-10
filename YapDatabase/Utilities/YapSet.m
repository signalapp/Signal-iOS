#import "YapSet.h"


@implementation YapSet
{
	NSDictionary *dictionary;
	NSSet *set;
}

@dynamic count;

- (id)initWithSet:(NSMutableSet *)inSet
{
	if ((self = [super init]))
	{
		set = inSet; // retain, do NOT copy (which would defeat the entire purpose of this class)
	}
	return self;
}

- (id)initWithDictionary:(NSMutableDictionary *)inDictionary
{
	if ((self = [super init]))
	{
		dictionary = inDictionary; // retain, do NOT copy (which would defeat the entire purpose of this class)
	}
	return self;
}

// NSSet methods

- (NSUInteger)count
{
	if (set)
		return set.count;
	else
		return dictionary.count;
}

- (BOOL)containsObject:(id)object
{
	if (set)
		return [set containsObject:object];
	else
		return CFDictionaryContainsKey((__bridge CFDictionaryRef)dictionary, (const void *)object);
}

- (BOOL)intersectsSet:(NSSet *)otherSet
{
	if (set)
	{
		return [set intersectsSet:otherSet];
	}
	else
	{
		for (id object in otherSet)
		{
			if (CFDictionaryContainsKey((__bridge CFDictionaryRef)dictionary, (const void *)object))
				return YES;
		}
		
		return NO;
	}
}

- (void)enumerateObjectsUsingBlock:(void (^)(id obj, BOOL *stop))block
{
	if (set)
	{
		[set enumerateObjectsUsingBlock:block];
	}
	else
	{
		if (block == NULL) return;
		[dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id __unused obj, BOOL *stop) {
			
			block(key, stop);
		}];
	}
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(__unsafe_unretained id *)stackbuf
                                    count:(NSUInteger)len
{
	if (set)
		return [set countByEnumeratingWithState:state objects:stackbuf count:len];
	else
		return [dictionary countByEnumeratingWithState:state objects:stackbuf count:len];
}

@end
