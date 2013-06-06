#import "YapCollectionsDatabaseViewPage.h"


@implementation YapCollectionsDatabaseViewPage
{
	NSMutableArray *collections;
	NSMutableArray *keys;
}

- (id)init
{
	return [self initWithCapacity:50];
}

- (id)initWithCapacity:(NSUInteger)capacity
{
	if ((self = [super init]))
	{
		collections = [[NSMutableArray alloc] initWithCapacity:50];
		keys        = [[NSMutableArray alloc] initWithCapacity:50];
	}
	return self;
}

- (id)initForCopy
{
	if ((self = [super init]))
	{
	//	collections = nil;
	//	keys        = nil;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		collections = [decoder decodeObjectForKey:@"collections"];
		keys        = [decoder decodeObjectForKey:@"keys"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:collections forKey:@"collections"];
	[coder encodeObject:keys        forKey:@"keys"];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapCollectionsDatabaseViewPage *copy = [[YapCollectionsDatabaseViewPage alloc] initForCopy];
	
	// We need a mutable copy of the collections and keys array,
	// but we don't have to copy all the immutable strings within each.
	
	copy->collections = [[NSMutableArray alloc] initWithArray:collections copyItems:NO];
	copy->keys        = [[NSMutableArray alloc] initWithArray:keys        copyItems:NO];
	
	return copy;
}

- (NSUInteger)count
{
	return [keys count];
}

- (NSString *)collectionAtIndex:(NSUInteger)index
{
	return [collections objectAtIndex:index];
}

- (NSString *)keyAtIndex:(NSUInteger)index
{
	return [keys objectAtIndex:index];
}

- (void)getCollection:(NSString **)collectionPtr key:(NSString **)keyPtr atIndex:(NSUInteger)index
{
	if (collectionPtr) *collectionPtr = [collections objectAtIndex:index];
	if (keyPtr)        *keyPtr        = [keys objectAtIndex:index];
}

- (NSUInteger)indexOfCollection:(NSString *)inCollection key:(NSString *)inKey
{
	if (inCollection == nil)
		inCollection = @"";
	
	__block NSUInteger index = NSNotFound;
	
	[keys enumerateObjectsUsingBlock:^(id key, NSUInteger idx, BOOL *stop) {
		
		if ([inKey isEqualToString:(NSString *)key])
		{
			NSString *collection = (NSString *)[collections objectAtIndex:idx];
			
			if ([inCollection isEqualToString:collection])
			{
				index = idx;
				*stop = YES;
			}
		}
	}];
	
	return index;
}

- (void)removeObjectsAtIndex:(NSUInteger)index
{
	[collections removeObjectAtIndex:index];
	[keys        removeObjectAtIndex:index];
}

- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes
{
	[collections removeObjectsAtIndexes:indexes];
	[keys        removeObjectsAtIndexes:indexes];
}

- (void)insertCollection:(NSString *)collection key:(NSString *)key atIndex:(NSUInteger)index
{
	if (collection == nil)
		collection = @"";
	
	[collections insertObject:collection atIndex:index];
	[keys        insertObject:key        atIndex:index];
}

- (void)enumerateWithBlock:(void (^)(NSString *collection, NSString *key, NSUInteger idx, BOOL *stop))block
{
	[collections enumerateObjectsUsingBlock:^(id collectionObj, NSUInteger idx, BOOL *stop) {
		
		block((NSString *)collectionObj, [keys objectAtIndex:idx], idx, stop);
	}];
}

@end
