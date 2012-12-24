#import "YapCopyOnWriteMutableDictionary.h"


@implementation YapCopyOnWriteMutableDictionary
{
	NSDictionary *originalDict;
	NSMutableDictionary *modifiedDict;
	
	BOOL modifiedCheck;
}

- (id)initWithOriginalDictionary:(NSDictionary *)inOriginalDict
{
	if ((self = [super init]))
	{
		originalDict = inOriginalDict;
		modifiedDict = nil;
	}
	return self;
}

- (NSUInteger)count
{
	if (modifiedDict)
		return [modifiedDict count];
	else
		return [originalDict count];
}

- (NSArray *)allKeys
{
	if (modifiedDict)
		return [modifiedDict allKeys];
	else
		return [originalDict allKeys];
}

- (id)objectForKey:(id)key
{
	if (modifiedDict)
		return [modifiedDict objectForKey:key];
	else
		return [originalDict objectForKey:key];
}

- (void)setObject:(id)object forKey:(id)key
{
	if (modifiedDict == nil)
		modifiedDict = [originalDict mutableCopy];
	
	[modifiedDict setObject:object forKey:key];
	modifiedCheck = YES;
}

- (void)removeAllObjects
{
	if (modifiedDict == nil)
		modifiedDict = [originalDict mutableCopy];
	
	[modifiedDict removeAllObjects];
	modifiedCheck = YES;
}

- (void)removeObjectForKey:(id)key
{
	if (modifiedDict == nil)
		modifiedDict = [originalDict mutableCopy];
	
	[modifiedDict removeObjectForKey:key];
	modifiedCheck = YES;
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	if (modifiedDict == nil)
		modifiedDict = [originalDict mutableCopy];
	
	[modifiedDict removeObjectsForKeys:keys];
	modifiedCheck = YES;
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	if (modifiedDict)
	{
		[modifiedDict enumerateKeysAndObjectsUsingBlock:block];
	}
	else
	{
		modifiedCheck = NO;
		[originalDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
			
			block(key, obj, stop);
			if (modifiedCheck)
			{
				NSString *format =
				    @"Collection <YapCopyOnWriteMutableDictionary: %p> was mutated while being enumerated. "
				    @" Maybe you modified the database within enumerateKeysAndMetadataUsingBlock: ?";
				
				[NSException raise:NSGenericException format:format, self];
			}
		}];
	}
}

/**
 * Returns whether or not the dictionary was modified.
**/
- (BOOL)isModified
{
	return (modifiedDict != nil);
}

/**
 * If the dictionary was modified, returns the newly created and modified dictionary.
 * Otherwise returns nil.
**/
- (NSMutableDictionary *)modifiedDictionary
{
	return modifiedDict;
}

@end
