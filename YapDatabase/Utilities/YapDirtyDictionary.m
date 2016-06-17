#import "YapDirtyDictionary.h"


@interface YapDirtyDictionaryItem : NSObject {
@public
	
	id currentValue;
	id originalValue;
}

@end

@implementation YapDirtyDictionaryItem
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDirtyDictionary {
	
	NSMutableDictionary *dict;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity
{
	if ((self = [super init]))
	{
		dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (NSUInteger)count
{
	return dict.count;
}

/**
 * Returns the current value, regardless of whether it's "dirty" or "clean".
**/
- (id)objectForKey:(id)key
{
	YapDirtyDictionaryItem *item = [dict objectForKey:key];
	if (item)
		return item->currentValue;
	else
		return nil;
}

/**
 * Returns the current value, but only if it's "dirty" (doesn't match the original value).
**/
- (id)dirtyValueForKey:(id)key
{
	YapDirtyDictionaryItem *item = [dict objectForKey:key];
	
	if (item && ![item->originalValue isEqual:item->currentValue])
		return item->currentValue;
	else
		return nil;
}

/**
 * Returns the original value (the oldest previousValue for the key).
**/
- (id)originalValueForKey:(id)key
{
	YapDirtyDictionaryItem *item = [dict objectForKey:key];
	
	if (item)
		return item->originalValue;
	else
		return nil;
}

/**
 * Sets the current value for the key.
 *
 * When making the change, you should attempt to set the previous value.
 * The first time a value is set for a particular key, the previous value will be stored alongside it.
 * Subsequent changes to a value won't modify the original 'previous value'.
**/
- (void)setObject:(id)object forKey:(id)key withPreviousValue:(id)prevObj
{
	NSParameterAssert(key != nil);
	NSParameterAssert(object != nil);
	
	YapDirtyDictionaryItem *item = [dict objectForKey:key];
	if (item)
	{
		item->currentValue = object;
	}
	else if (object)
	{
		item = [[YapDirtyDictionaryItem alloc] init];
		
		item->currentValue = object;
		item->originalValue = prevObj;
		
		[dict setObject:item forKey:key];
	}
}

/**
 * Removes all objects from the dictionary, and all stored original values too.
 *
 * Use this method when you no longer need to track anything using the dictionary,
 * and you simply want a clean slate.
**/
- (void)removeAllObjects
{
	[dict removeAllObjects];
}

/**
 * Removes only those objects from the dictionary for which the current value matches the original value.
 *
 * Use this method when you're done tracking changes,
 * and you want to pass the dictionary to other connections (e.g. in a changeset).
**/
- (void)removeCleanObjects
{
	__block NSMutableArray *keysToRemove = nil;
	
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, YapDirtyDictionaryItem *item, BOOL *stop) {
		
		BOOL shouldRemove = NO;
		
		if (item->originalValue) {
			shouldRemove = [item->originalValue isEqual:item->currentValue];
		}
		else {
			shouldRemove = (item->currentValue == nil);
		}
		
		if (shouldRemove)
		{
			if (keysToRemove == nil)
				keysToRemove = [[NSMutableArray alloc] init];
			
			[keysToRemove addObject:key];
		}
	}];
	
	if (keysToRemove.count > 0)
	{
		[dict removeObjectsForKeys:keysToRemove];
	}
}

/**
 * Enumerates all key/value pairs, including both "dirty" & "clean" values.
**/
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, YapDirtyDictionaryItem *item, BOOL *stop) {
		
		block(key, item->currentValue, stop);
	}];
}

/**
 * Enumerates only the key/value pairs that are dirty (current value differs from original value).
**/
- (void)enumerateDirtyKeysAndObjectsUsingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, YapDirtyDictionaryItem *item, BOOL *stop) {
		
		BOOL shouldInvoke = NO;
		
		if (item->originalValue) {
			shouldInvoke = ![item->originalValue isEqual:item->currentValue];
		}
		else {
			shouldInvoke = (item->currentValue != nil);
		}
		
		if (shouldInvoke)
		{
			block(key, item->currentValue, stop);
		}
	}];
}

@end
