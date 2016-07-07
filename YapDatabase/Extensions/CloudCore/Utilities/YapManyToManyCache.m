/**
 * Copyright Deusty LLC.
**/

#import "YapManyToManyCache.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_OFF;
#endif

static const NSUInteger YapManyToManyCacheDefaultCountLimit = 40;

#undef NSNotFound
#define NSNotFound !"NSNotFound is not used by our version of NSRange!"


@interface YapManyToManyCacheItem : NSObject {
@public
	__unsafe_unretained YapManyToManyCacheItem *prev;
	__strong            YapManyToManyCacheItem *next;
	
	__strong id key;
	__strong id value;
	__strong id metadata;
}

- (id)initWithKey:(id)key value:(id)value metadata:(id)metadata;

@end

@implementation YapManyToManyCacheItem

- (id)initWithKey:(id)inKey value:(id)inValue metadata:(id)inMetadata
{
	if ((self = [super init]))
	{
		key = inKey;
		value = inValue;
		metadata = inMetadata;
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:
	  @"<YapManyToManyCacheItem: key(%@) value(%@)>", key, value];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapManyToManyCache {
	
	NSUInteger countLimit;
	
	__strong YapManyToManyCacheItem *evictedCacheItem;
	
	__strong            YapManyToManyCacheItem *mostRecentCacheItem;
	__unsafe_unretained YapManyToManyCacheItem *leastRecentCacheItem;
	
	NSPointerArray *sortedByKey;
	NSPointerArray *sortedByValue;
}

@dynamic countLimit;
@dynamic count;

- (instancetype)init
{
	return [self initWithCountLimit:YapManyToManyCacheDefaultCountLimit];
}

- (instancetype)initWithCountLimit:(NSUInteger)inCountLimit
{
	if ((self = [super init]))
	{
		countLimit = inCountLimit;
		
		NSPointerFunctionsOptions options = NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPersonality;
		
		sortedByKey   = [[NSPointerArray alloc] initWithOptions:options];
		sortedByValue = [[NSPointerArray alloc] initWithOptions:options];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)count
{
	return [sortedByKey count];
}

- (NSUInteger)countLimit
{
	return countLimit;
}

- (void)setCountLimit:(NSUInteger)newCountLimit
{
	if (countLimit != newCountLimit)
	{
		countLimit = newCountLimit;
		
		if (countLimit != 0)
		{
			while ([sortedByKey count] > countLimit)
			{
				evictedCacheItem = leastRecentCacheItem;
				
				leastRecentCacheItem->prev->next = nil;
				leastRecentCacheItem = leastRecentCacheItem->prev;
				
				evictedCacheItem->prev     = nil;
				evictedCacheItem->next     = nil;
				evictedCacheItem->key      = nil;
				evictedCacheItem->value    = nil;
				evictedCacheItem->metadata = nil;
				
				NSUInteger index;
				if ([self getIndex:&index ofCacheItem:evictedCacheItem inPointerArray:sortedByKey])
				{
					[sortedByKey removePointerAtIndex:index];
				}
				if ([self getIndex:&index ofCacheItem:evictedCacheItem inPointerArray:sortedByValue])
				{
					[sortedByValue removePointerAtIndex:index];
				}
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Uses binary search algorithm to quickly find the range for a given input.
**/
- (NSRange)findRangeForObject:(id)object isKey:(BOOL)isKey quitAfterOne:(BOOL)quitAfterOne
{
	__unsafe_unretained NSPointerArray *sorted = isKey ? sortedByKey : sortedByValue;
	
	NSUInteger count = [sorted count];
	if (count == 0)
	{
		return NSMakeRange(0, 0); // range.location MUST be insert index, NOT NSNotFound !!!!!!!!!!!!
	}
	
	NSComparisonResult (^compare)(NSUInteger);
	
	if (isKey)
	{
		compare = ^NSComparisonResult (NSUInteger index){
			
			__unsafe_unretained YapManyToManyCacheItem *item =
			          (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:index];
			
			return [item->key compare:object];
		};
	}
	else
	{
		compare = ^NSComparisonResult (NSUInteger index){
			
			__unsafe_unretained YapManyToManyCacheItem *item =
			          (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:index];
			
			return [item->value compare:object];
		};
	}
	
	// Find first match (first to return NSOrderedSame)
	
	NSUInteger mMin = 0;
	NSUInteger mMax = count;
	NSUInteger mMid = 0;
	
	BOOL found = NO;
	
	while (mMin < mMax && !found)
	{
		mMid = (mMin + mMax) / 2;
		
		NSComparisonResult cmp = compare(mMid);
		
		if (cmp == NSOrderedDescending)      // Descending => value is greater than desired range
			mMax = mMid;
		else if (cmp == NSOrderedAscending)  // Ascending => value is less than desired range
			mMin = mMid + 1;
		else
			found = YES;
	}
	
	if (!found)
	{
		return NSMakeRange(mMin, 0); // range.location MUST be insert index, NOT NSNotFound !!!!!!!!!!!!
	}
	
	if (quitAfterOne)
	{
		return NSMakeRange(mMid, 1);
	}
	
	// Find start of range
	
	NSUInteger sMin = mMin;
	NSUInteger sMax = mMid;
	NSUInteger sMid;
	
	while (sMin < sMax)
	{
		sMid = (sMin + sMax) / 2;
		
		NSComparisonResult cmp = compare(sMid);
		
		if (cmp == NSOrderedAscending) // Ascending => value is less than desired range
			sMin = sMid + 1;
		else
			sMax = sMid;
	}
	
	// Find end of range
	
	NSUInteger eMin = mMid;
	NSUInteger eMax = mMax;
	NSUInteger eMid;
	
	while (eMin < eMax)
	{
		eMid = (eMin + eMax) / 2;
		
		NSComparisonResult cmp = compare(eMid);
		
		if (cmp == NSOrderedDescending) // Descending => value is greater than desired range
			eMax = eMid;
		else
			eMin = eMid + 1;
	}
	
	return NSMakeRange(sMin, (eMax - sMin));
}

/**
 * Utility method to quickly find an item in a pointerArray.
 * Similar to [NSArray indexOfObjectIdenticalTo:]
**/
- (BOOL)getIndex:(NSUInteger *)indexPtr ofCacheItem:(YapManyToManyCacheItem *)itemToFind
                                     inPointerArray:(NSPointerArray *)sorted
{
	BOOL found = NO;
	NSUInteger foundIndex = 0;
	
	NSUInteger index = 0;
	for (YapManyToManyCacheItem *item in sorted)
	{
		if (item == itemToFind) // pointer comparison
		{
			found = YES;
			foundIndex = index;
			
			break;
		}
		
		index++;
	}
	
	if (indexPtr) *indexPtr = foundIndex;
	return found;
}

- (void)debug
{
	NSAssert([sortedByKey count] == [sortedByValue count], @"Oops");
	
	NSUInteger count = [sortedByKey count];
	
	{ // make sure MRU linked-list is the same forwards & backwards
		
		NSUInteger capacity = count * (sizeof(void*) + 2);
		
		NSMutableString *forwards  = [NSMutableString stringWithCapacity:capacity];
		NSMutableString *backwards = [NSMutableString stringWithCapacity:capacity];
		
		__unsafe_unretained YapManyToManyCacheItem *item;
		
		item = mostRecentCacheItem;
		while (item != nil)
		{
			[forwards appendFormat:@"%p, ", item];
			
			item = item->next;
		}
		
		item = leastRecentCacheItem;
		while (item != nil)
		{
			[backwards insertString:[NSString stringWithFormat:@"%p, ", item] atIndex:0];
			
			item = item->prev;
		}
	
		NSAssert([forwards isEqualToString:backwards], @"Oops");
	}
	
	NSMutableString *debugString = [NSMutableString stringWithCapacity:(count * 64)];
	
	{ // print sortedByKey
		
		[debugString appendString:@"sortedByKey: \n"];
		
		for (YapManyToManyCacheItem *item in sortedByKey)
		{
			[debugString appendFormat:@"  %@\n", item];
		}
		
		NSLog(@"%@", debugString);
		[debugString deleteCharactersInRange:NSMakeRange(0, debugString.length)];
	}
	
	{ // print sortedByValue
		
		[debugString appendString:@"sortedByValue: \n"];
		
		for (YapManyToManyCacheItem *item in sortedByValue)
		{
			[debugString appendFormat:@"  %@\n", item];
		}
		
		NSLog(@"%@", debugString);
		[debugString deleteCharactersInRange:NSMakeRange(0, debugString.length)];
	}
	
	{ // print MRU
		
		[debugString appendString:@"MRU order: \n"];
	
		__unsafe_unretained YapManyToManyCacheItem *item = mostRecentCacheItem;
		while (item != nil)
		{
			[debugString appendFormat:@"  %@\n", item];
			
			item = item->next;
		}
		
		NSLog(@"%@", debugString);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)insertKey:(id)key value:(id)value
{
	[self insertKey:key value:value metadata:nil];
}

- (void)insertKey:(id)key value:(id)value metadata:(id)metadata
{
	NSRange keyRange = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	// Remember:
	// - If the key was NOT found, then the location is the place where it should be inserted.
	// - Thus, we MUST check range.length, NOT range.location.
	
	if (keyRange.length > 0)
	{
		__strong YapManyToManyCacheItem *foundItem = nil;
		
		NSUInteger stop = keyRange.location + keyRange.length;
		for (NSUInteger index = keyRange.location; index < stop; index++)
		{
			__unsafe_unretained YapManyToManyCacheItem *item =
			          (__bridge YapManyToManyCacheItem *)[sortedByKey pointerAtIndex:index];
			
			if ([item->value isEqual:value])
			{
				foundItem = item;
				break;
			}
		}
		
		if (foundItem)
		{
			// key/value pair already exists in cache
			
			if (foundItem != mostRecentCacheItem)
			{
				// Remove item from current position in linked-list
				//
				// Things we already know (based on logic that got us here):
				//   - count >= 1
				//   - mostRecentCacheItem  != foundItem
				//   - mostRecentCacheItem  != nil
				//   - leastRecentCacheItem != nil
				
				if (leastRecentCacheItem == foundItem)       // count == 1
					leastRecentCacheItem = foundItem->prev;
				else                                         // count > 1 && foundItem isn't last (leastRecent)
					foundItem->next->prev = foundItem->prev;
				
				foundItem->prev->next = foundItem->next;     // we know foundItem isn't first (mostRecent)
				
				// Move item to beginning of linked-list
				
				mostRecentCacheItem->prev = foundItem;       // we know mostRecent isn't nil
				mostRecentCacheItem = foundItem;
			}
			
			foundItem->metadata = metadata;
			return;
		}
	}
	
	// Create (or recycle) cacheItem
	
	__strong YapManyToManyCacheItem *cacheItem = nil;
	if (evictedCacheItem)
	{
		cacheItem = evictedCacheItem;
		evictedCacheItem = nil;
		
		cacheItem->key = key;
		cacheItem->value = value;
		cacheItem->metadata = metadata;
	}
	else
	{
		cacheItem = [[YapManyToManyCacheItem alloc] initWithKey:key value:value metadata:metadata];
	}
	
	{ // Insert into sortedByKeys array
		
		NSUInteger keyIndex = keyRange.location + keyRange.length;
		
		[sortedByKey insertPointer:(__bridge void *)cacheItem atIndex:keyIndex];
	}
	
	{ // Insert into sortedByValues array
		
		NSRange valueRange = [self findRangeForObject:value isKey:NO quitAfterOne:NO];
		NSUInteger valueIndex = valueRange.location + valueRange.length;
		
		[sortedByValue insertPointer:(__bridge void *)cacheItem atIndex:valueIndex];
	}
	
	// Add item to beginning of linked-list
	
	cacheItem->next = mostRecentCacheItem;
	
	if (mostRecentCacheItem)
		mostRecentCacheItem->prev = cacheItem;
	else
		leastRecentCacheItem = cacheItem;
	
	mostRecentCacheItem = cacheItem;
	
	// Evict leastRecentCacheItem if needed
	
	if ((countLimit != 0) && ([sortedByKey count] > countLimit))
	{
		YDBLogVerbose(@"evicting: %@", leastRecentCacheItem);
		
		// Note: evictedCacheItem is nil (based on logic from above)
		
		evictedCacheItem = leastRecentCacheItem;
		
		leastRecentCacheItem->prev->next = nil;
		leastRecentCacheItem = leastRecentCacheItem->prev;
		
		evictedCacheItem->prev     = nil;
		evictedCacheItem->next     = nil;
		evictedCacheItem->key      = nil;
		evictedCacheItem->value    = nil;
		evictedCacheItem->metadata = nil;
		
		NSUInteger index;
		if ([self getIndex:&index ofCacheItem:evictedCacheItem inPointerArray:sortedByKey])
		{
			[sortedByKey removePointerAtIndex:index];
		}
		if ([self getIndex:&index ofCacheItem:evictedCacheItem inPointerArray:sortedByValue])
		{
			[sortedByValue removePointerAtIndex:index];
		}
	}
}

- (BOOL)containsKey:(id)key value:(id)value
{
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	if (range.length == 0) return NO;
	
	NSUInteger stopIndex = range.location + range.length;
	for (NSUInteger index = range.location; index < stopIndex; index++)
	{
		__unsafe_unretained YapManyToManyCacheItem *item =
		          (__bridge YapManyToManyCacheItem *)[sortedByKey pointerAtIndex:index];
		
		if ([item->value isEqual:value]) {
			return YES;
		}
	}
	
	return NO;
}

- (id)metadataForKey:(id)key value:(id)value
{
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	if (range.length == 0) return nil;
	
	__strong YapManyToManyCacheItem *foundItem = nil;
	
	NSUInteger stopIndex = range.location + range.length;
	for (NSUInteger index = range.location; index < stopIndex; index++)
	{
		__unsafe_unretained YapManyToManyCacheItem *item =
		(__bridge YapManyToManyCacheItem *)[sortedByKey pointerAtIndex:index];
		
		if ([item->value isEqual:value])
		{
			foundItem = item;
			break;
		}
	}
	
	if (foundItem && (foundItem != mostRecentCacheItem))
	{
		// Remove item from current position in linked-list
		//
		// Things we already know (based on logic that got us here):
		//   - count >= 1
		//   - mostRecentCacheItem  != foundItem
		//   - mostRecentCacheItem  != nil
		//   - leastRecentCacheItem != nil
		
		if (leastRecentCacheItem == foundItem)       // count == 1
			leastRecentCacheItem = foundItem->prev;
		else                                         // count > 1 && foundItem isn't last (isn't leastRecent)
			foundItem->next->prev = foundItem->prev;
		
		foundItem->prev->next = foundItem->next;     // we know foundItem isn't first (isn't mostRecent)
		
		// Move item to beginning of linked-list
		
		foundItem->prev = nil;
		foundItem->next = mostRecentCacheItem;
		
		mostRecentCacheItem->prev = foundItem;       // we know mostRecent isn't nil
		mostRecentCacheItem = foundItem;
	}
	
	if (foundItem)
		return foundItem->metadata;
	else
		return nil;
}

- (BOOL)containsKey:(id)key
{
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:YES];
	return (range.length > 0);
}

- (BOOL)containsValue:(id)value
{
	NSRange range = [self findRangeForObject:value isKey:NO quitAfterOne:YES];
	return (range.length > 0);
}

- (NSUInteger)countForKey:(id)key
{
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	return range.length;
}

- (NSUInteger)countForValue:(id)value
{
	NSRange range = [self findRangeForObject:value isKey:NO quitAfterOne:NO];
	return range.length;
}

- (void)enumerateValuesForKey:(id)key withBlock:(void (^)(id value, id metadata, BOOL *stop))block
{
	if (key == nil) return;
	if (block == NULL) return;
	
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	if (range.length == 0) return;
	
	__unsafe_unretained NSPointerArray *sorted = sortedByKey;
	
	NSUInteger enumIndex = range.location;
	NSUInteger stopIndex = range.location + range.length;
	
	BOOL stop = NO;
	
	while (enumIndex < stopIndex)
	{
		__unsafe_unretained YapManyToManyCacheItem *item =
		          (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:enumIndex];
		
		block(item->value, item->metadata, &stop);
		
		enumIndex++;
		if (stop) break;
	}
	
	// For every item that was touched during enumeration,
	// move it to the beginning of the (most recently used) linked-list.
	
	for (NSUInteger index = range.location; index < enumIndex; index++)
	{
		__strong YapManyToManyCacheItem *item = (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:index];
		
		if (item != mostRecentCacheItem)
		{
			// Things we already know (based on logic that got us here):
			//   - count >= 1
			//   - mostRecentCacheItem  != item
			//   - mostRecentCacheItem  != nil
			//   - leastRecentCacheItem != nil
			
			// Remove item from current position in linked-list
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			else
				item->next->prev = item->prev;
			
			item->prev->next = item->next;
			
			// Move item to beginning of linked-list
			
			item->prev = nil;
			item->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = item;
			mostRecentCacheItem = item;
		}
	}
}

- (void)enumerateKeysForValue:(id)value withBlock:(void (^)(id value, id metadata, BOOL *stop))block
{
	if (value == nil) return;
	if (block == NULL) return;
	
	NSRange range = [self findRangeForObject:value isKey:NO quitAfterOne:NO];
	
	if (range.length == 0) return;
	
	__unsafe_unretained NSPointerArray *sorted = sortedByValue;
	
	NSUInteger enumIndex = range.location;
	NSUInteger stopIndex = range.location + range.length;
	
	BOOL stop = NO;
	
	while (enumIndex < stopIndex)
	{
		__unsafe_unretained YapManyToManyCacheItem *item =
		          (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:enumIndex];
		
		block(item->key, item->metadata, &stop);
		
		enumIndex++;
		if (stop) break;
	}
	
	// For every item that was touched during enumeration,
	// move it to the beginning of the (most recently used) linked-list.
	
	for (NSUInteger index = range.location; index < enumIndex; index++)
	{
		__strong YapManyToManyCacheItem *item = (__bridge YapManyToManyCacheItem *)[sorted pointerAtIndex:index];
		
		if (item != mostRecentCacheItem)
		{
			// Things we already know (based on logic that got us here):
			//   - count >= 1
			//   - mostRecentCacheItem  != item
			//   - mostRecentCacheItem  != nil
			//   - leastRecentCacheItem != nil
			
			// Remove item from current position in linked-list
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			else
				item->next->prev = item->prev;
			
			item->prev->next = item->next;
			
			// Move item to beginning of linked-list
			
			item->prev = nil;
			item->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = item;
			mostRecentCacheItem = item;
		}
	}
}

/**
 * Removes the tuple that matches the given key/value pair.
 *
 * The key & value must be non-nil.
 * If you're only interested in matches for a key or value (but not together) use a different method.
**/
- (void)removeItemWithKey:(id)key value:(id)value
{
	if (key == nil) return;
	if (value == nil) return;
	
	NSRange keyRange = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	if (keyRange.length == 0) return; // key doesn't exist
	
	__strong YapManyToManyCacheItem *foundItem = nil;
	
	NSUInteger keyIndex = keyRange.location;
	NSUInteger stopIndex = keyRange.location + keyRange.length;
	
	while (keyIndex < stopIndex)
	{
		__unsafe_unretained YapManyToManyCacheItem *item =
		          (__bridge YapManyToManyCacheItem *)[sortedByKey pointerAtIndex:keyIndex];
		
		if ([item->value isEqual:value])
		{
			foundItem = item;
			break;
		}
		
		keyIndex++;
	}
	
	if (foundItem == nil) return; // key/value pair doesn't exist
	
	{ // remove from sortedKeys
		
		[sortedByKey removePointerAtIndex:keyIndex];
	}
	{ // remove from sortedValues
		
		NSUInteger valueIndex = 0;
		if ([self getIndex:&valueIndex ofCacheItem:foundItem inPointerArray:sortedByValue])
		{
			[sortedByValue removePointerAtIndex:valueIndex];
		}
	}
	{ // remove from MRU linked-list
		
		if (mostRecentCacheItem == foundItem)
			mostRecentCacheItem = foundItem->next;
		
		if (leastRecentCacheItem == foundItem)
			leastRecentCacheItem = foundItem->prev;
		
		if (foundItem->next)
			foundItem->next->prev = foundItem->prev;
		
		if (foundItem->prev)
			foundItem->prev->next = foundItem->next;
		
		if (evictedCacheItem == nil)
		{
			evictedCacheItem = foundItem;
			evictedCacheItem->prev     = nil;
			evictedCacheItem->next     = nil;
			evictedCacheItem->key      = nil;
			evictedCacheItem->value    = nil;
			evictedCacheItem->metadata = nil;
		}
	}
}

/**
 * Enumerates all key/value pairs in the cache.
 * 
 * As this method is designed to enumerate all values, it ddes not affect the most-recently-used linked-list.
**/
- (void)enumerateWithBlock:(void (^)(id key, id value, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	BOOL stop = NO;
	
	__unsafe_unretained YapManyToManyCacheItem *item = mostRecentCacheItem;
	while (item)
	{
		block(item->key, item->value, item->metadata, &stop);
		
		if (stop) break;
		
		// Todo: Need mutation detection (YapMutationStack)
		item = item->next;
	}
}

/**
 * Removes all tuples that match the given key.
**/
- (void)removeAllItemsWithKey:(id)key
{
	if (key == nil) return;
	
	NSRange range = [self findRangeForObject:key isKey:YES quitAfterOne:NO];
	
	if (range.length == 0) return;
	
	NSUInteger keyIndex = range.location; // doesn't change since we remove from array on each iteration
	
	for (NSUInteger i = 0; i < range.length; i++)
	{
		__strong YapManyToManyCacheItem *item =
		    (__bridge YapManyToManyCacheItem *)[sortedByKey pointerAtIndex:keyIndex];
		
		{ // remove from sortedKeys
		
			[sortedByKey removePointerAtIndex:keyIndex];
		}
		{ // remove from sortedValues
			
			NSUInteger valueIndex = 0;
			if ([self getIndex:&valueIndex ofCacheItem:item inPointerArray:sortedByValue])
			{
				[sortedByValue removePointerAtIndex:valueIndex];
			}
		}
		{ // remove from MRU linked-list
			
			if (mostRecentCacheItem == item)
				mostRecentCacheItem = item->next;
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			
			if (item->next)
				item->next->prev = item->prev;
			
			if (item->prev)
				item->prev->next = item->next;
			
			if (evictedCacheItem == nil)
			{
				evictedCacheItem = item;
				evictedCacheItem->prev     = nil;
				evictedCacheItem->next     = nil;
				evictedCacheItem->key      = nil;
				evictedCacheItem->value    = nil;
				evictedCacheItem->metadata = nil;
			}
		}
	}
}

/**
 * Removes all tuples that match the given value.
**/
- (void)removeAllItemsWithValue:(id)value
{
	if (value == nil) return;
	
	NSRange range = [self findRangeForObject:value isKey:NO quitAfterOne:NO];
	
	if (range.length == 0) return;
	
	NSUInteger valueIndex = range.location; // doesn't change since we remove from array on each iteration
	
	for (NSUInteger i = 0; i < range.length; i++)
	{
		__strong YapManyToManyCacheItem *item =
		    (__bridge YapManyToManyCacheItem *)[sortedByValue pointerAtIndex:valueIndex];
		
		{ // remove from sortedKeys
			
			NSUInteger keyIndex = 0;
			if ([self getIndex:&keyIndex ofCacheItem:item inPointerArray:sortedByKey])
			{
				[sortedByKey removePointerAtIndex:keyIndex];
			}
		}
		{ // remove from sortedValues
			
			[sortedByValue removePointerAtIndex:valueIndex];
		}
		{ // remove from MRU linked-list
			
			if (mostRecentCacheItem == item)
				mostRecentCacheItem = item->next;
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			
			if (item->next)
				item->next->prev = item->prev;
			
			if (item->prev)
				item->prev->next = item->next;
			
			if (evictedCacheItem == nil)
			{
				evictedCacheItem = item;
				evictedCacheItem->prev     = nil;
				evictedCacheItem->next     = nil;
				evictedCacheItem->key      = nil;
				evictedCacheItem->value    = nil;
				evictedCacheItem->metadata = nil;
			}
		}
	}
}

/**
 * Removes all items in the cache.
 * Upon return the count will be zero.
**/
- (void)removeAllItems
{
	NSUInteger count = [sortedByKey count];
	
	for (NSUInteger i = count; i > 0; i--)
	{
		[sortedByKey removePointerAtIndex:(i-1)];
	}
	for (NSUInteger i = count; i > 0; i--)
	{
		[sortedByValue removePointerAtIndex:(i-1)];
	}
	
	if ((evictedCacheItem == nil) && (mostRecentCacheItem != nil))
	{
		evictedCacheItem = mostRecentCacheItem;
		evictedCacheItem->prev     = nil;
		evictedCacheItem->next     = nil;
		evictedCacheItem->key      = nil;
		evictedCacheItem->value    = nil;
		evictedCacheItem->metadata = nil;
	}
	
	mostRecentCacheItem = nil;
	leastRecentCacheItem = nil;
}

@end
