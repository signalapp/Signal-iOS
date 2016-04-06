#import "YapBidirectionalCache.h"
#import "YapDatabaseLogging.h"

static NSUInteger const YapBidirectionalCache_Default_CountLimit = 40;

const YapBidirectionalCacheCallBacks kYapBidirectionalCacheDefaultCallBacks = (YapBidirectionalCacheCallBacks){
	.version = 0,
	.shouldCopy = NO,
	.equal = CFEqual,
	.hash = CFHash
};

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_OFF;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_OFF;
#endif


@interface YapBidirectionalCacheItem : NSObject {
@public
	
	// Memory Management Architecture:
	//
	// The prev & next pointers are updated regularly, so it's critical that they
	// don't have the overhead of memory management (__strong).
	// The end goal is to have the following retained once, and only once:
	// - key
	// - value
	// - YapBidirectionalCacheItem
	//
	// To achieve this, the key_obj_dict retains the key & YapCacheItem.
	// And the YapBidirectionalCacheItem retains the value.
	
	__unsafe_unretained YapBidirectionalCacheItem *prev;
	__unsafe_unretained YapBidirectionalCacheItem *next;
	
	__unsafe_unretained id key;
	__strong id obj;
}

@end

@implementation YapBidirectionalCacheItem

//- (void)dealloc
//{
//	NSLog(@"[YapBidirectionalCacheItem dealloc]: key: %@, obj: %@", key, obj);
//}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapBidirectionalCacheItem: key(%@) object(%@)>", key, obj];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapBidirectionalCache
{
	YapBidirectionalCacheCallBacks keyCallBacks;
	YapBidirectionalCacheCallBacks objCallBacks;
	
	CFMutableDictionaryRef key_obj_dict;
	CFMutableDictionaryRef obj_key_dict;
	
	__unsafe_unretained YapBidirectionalCacheItem *mostRecentCacheItem;
	__unsafe_unretained YapBidirectionalCacheItem *leastRecentCacheItem;
	
	__strong YapBidirectionalCacheItem *evictedCacheItem;
}

@synthesize countLimit = countLimit;

@synthesize allowedKeyClasses = allowedKeyClasses;
@synthesize allowedObjectClasses = allowedObjectClasses;

#if YapBidirectionalCache_Enable_Statistics
@synthesize hitCount = hitCount;
@synthesize missCount = missCount;
@synthesize evictionCount = evictionCount;
#endif

- (instancetype)init
{
	return [self initWithCountLimit:YapBidirectionalCache_Default_CountLimit
	                   keyCallbacks:NULL
	                objectCallbacks:NULL];
}

- (instancetype)initWithCountLimit:(NSUInteger)inCountLimit
{
	return [self initWithCountLimit:inCountLimit
	                   keyCallbacks:NULL
	                objectCallbacks:NULL];
}

- (instancetype)initWithCountLimit:(NSUInteger)inCountLimit
                      keyCallbacks:(const YapBidirectionalCacheCallBacks *)inKeyCallBacks
                   objectCallbacks:(const YapBidirectionalCacheCallBacks *)inObjCallBacks
{
	if ((self = [super init]))
	{
		if (inKeyCallBacks == NULL)
			inKeyCallBacks = &kYapBidirectionalCacheDefaultCallBacks;
		
		if (inObjCallBacks == NULL)
			inObjCallBacks = &kYapBidirectionalCacheDefaultCallBacks;
		
		memcpy(&keyCallBacks, inKeyCallBacks, sizeof(YapBidirectionalCacheCallBacks));
		memcpy(&objCallBacks, inObjCallBacks, sizeof(YapBidirectionalCacheCallBacks));
		
		// Setup key_obj_dict.
		// This retains the key & YapBidirectionalItem.
		
		CFDictionaryKeyCallBacks kcb = kCFTypeDictionaryKeyCallBacks;
		kcb.equal   = keyCallBacks.equal;
		kcb.hash    = keyCallBacks.hash;
		
		CFDictionaryValueCallBacks vcb = kCFTypeDictionaryValueCallBacks;
		vcb.equal   = objCallBacks.equal;
		
		key_obj_dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kcb, &vcb);
		
		// Setup obj_key_dict.
		// This does NOT retain its key or value.
		
		kcb.retain  = NULL;
		kcb.release = NULL;
		kcb.equal = objCallBacks.equal;
		kcb.hash  = objCallBacks.hash;
		
		vcb.retain  = NULL;
		vcb.release = NULL;
		vcb.equal = keyCallBacks.equal;
		
		obj_key_dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kcb, &vcb);
		
		// zero is a valid countLimit (it means unlimited)
		countLimit = inCountLimit;
	}
	return self;
}

- (void)dealloc
{
	if (key_obj_dict) {
		CFRelease(key_obj_dict);
	}
	if (obj_key_dict) {
		CFRelease(obj_key_dict);
	}
}

- (void)setCountLimit:(NSUInteger)newCountLimit
{
	if (countLimit != newCountLimit)
	{
		countLimit = newCountLimit;
		if (countLimit != 0)
		{
			while (CFDictionaryGetCount(key_obj_dict) > (CFIndex)countLimit)
			{
				__unsafe_unretained id keyToEvict = leastRecentCacheItem->key;
				__unsafe_unretained id objToEvict = leastRecentCacheItem->obj;
				
				if (evictedCacheItem == nil)
				{
					evictedCacheItem = leastRecentCacheItem;
					
					leastRecentCacheItem = leastRecentCacheItem->prev;
					leastRecentCacheItem->next = nil;
					
					CFDictionaryRemoveValue(obj_key_dict, (const void *)(objToEvict)); // must be first
					CFDictionaryRemoveValue(key_obj_dict, (const void *)(keyToEvict)); // must be second
					
					evictedCacheItem->prev = nil;
					evictedCacheItem->next = nil;
					evictedCacheItem->key  = nil;
					evictedCacheItem->obj  = nil; // deallocates obj / objToEvict
				}
				else
				{
					leastRecentCacheItem = leastRecentCacheItem->prev;
					leastRecentCacheItem->next = nil;
					
					CFDictionaryRemoveValue(obj_key_dict, (const void *)(objToEvict)); // must be first
					CFDictionaryRemoveValue(key_obj_dict, (const void *)(keyToEvict)); // must be second
				}
				
			#if YapBidirectionalCache_Enable_Statistics
				evictionCount++;
			#endif
			}
		}
	}
}

- (id)objectForKey:(id)key
{
#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedKeyClass(key, allowedKeyClasses);
#endif
	
	__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
	if (item)
	{
		if (item != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list.
			//
			// Notes:
			// We fetched the item from the list,
			// so we know there's a valid mostRecentCacheItem & leastRecentCacheItem.
			// Furthermore, we know the item isn't the mostRecentCacheItem.
			
			item->prev->next = item->next;
			
			if (item == leastRecentCacheItem)
				leastRecentCacheItem = item->prev;
			else
				item->next->prev = item->prev;
			
			// Move item to beginning of linked-list
			
			item->prev = nil;
			item->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = item;
			mostRecentCacheItem = item;
		}
		
	#if YapBidirectionalCache_Enable_Statistics
		hitCount++;
	#endif
		return item->obj;
	}
	else
	{
	#if YapBidirectionalCache_Enable_Statistics
		missCount++;
	#endif
		return nil;
	}
}

- (BOOL)containsKey:(id)key
{
#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedKeyClass(key, allowedKeyClasses);
#endif
	
	return CFDictionaryContainsKey(key_obj_dict, (const void *)key);
}

- (id)keyForObject:(id)object
{
#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedObjectClass(object, allowedObjectClasses);
#endif
	
	__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
	if (item)
	{
		if (item != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list.
			//
			// Notes:
			// We fetched the item from the list,
			// so we know there's a valid mostRecentCacheItem & leastRecentCacheItem.
			// Furthermore, we know the item isn't the mostRecentCacheItem.
			
			item->prev->next = item->next;
			
			if (item == leastRecentCacheItem)
				leastRecentCacheItem = item->prev;
			else
				item->next->prev = item->prev;
			
			// Move item to beginning of linked-list
			
			item->prev = nil;
			item->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = item;
			mostRecentCacheItem = item;
		}
		
	#if YapBidirectionalCache_Enable_Statistics
		hitCount++;
	#endif
		return item->key;
	}
	else
	{
	#if YapBidirectionalCache_Enable_Statistics
		missCount++;
	#endif
		return nil;
	}
}

- (BOOL)containsObject:(id)object
{
#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedObjectClass(object, allowedObjectClasses);
#endif
	
	return CFDictionaryContainsKey(obj_key_dict, (const void *)object);
}

- (NSUInteger)count
{
	return CFDictionaryGetCount(key_obj_dict);
}

- (void)setObject:(id)object forKey:(id)key
{
	#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedKeyClass(key, allowedKeyClasses);
	AssertAllowedObjectClass(object, allowedObjectClasses);
	#endif
	
	__unsafe_unretained YapBidirectionalCacheItem *existingItem = CFDictionaryGetValue(key_obj_dict, (const void *)key);
	if (existingItem)
	{
		// Update item value
		if (!objCallBacks.equal((__bridge const void *)existingItem->obj, (__bridge const void *)object))
		{
			CFDictionaryRemoveValue(obj_key_dict, (const void *)existingItem->obj);
			
			if (objCallBacks.shouldCopy)
				existingItem->obj = [object copy];
			else
				existingItem->obj = object;
			
			CFDictionarySetValue(obj_key_dict, (const void *)existingItem->obj, (const void *)existingItem);
		}
		
		if (existingItem != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list
			//
			// Notes:
			// We fetched the item from the list,
			// so we know there's a valid mostRecentCacheItem & leastRecentCacheItem.
			// Furthermore, we know the item isn't the mostRecentCacheItem.
			
			existingItem->prev->next = existingItem->next;
			
			if (existingItem == leastRecentCacheItem)
				leastRecentCacheItem = existingItem->prev;
			else
				existingItem->next->prev = existingItem->prev;
			
			// Move item to beginning of linked-list
			
			existingItem->prev = nil;
			existingItem->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = existingItem;
			mostRecentCacheItem = existingItem;
			
			YDBLogVerbose(@"key(%@) <- existing, new mostRecent", key);
		}
		else
		{
			YDBLogVerbose(@"key(%@) <- existing, already mostRecent", key);
		}
	}
	else
	{
		// Create new item (or recycle old evicted item)
		
		__strong YapBidirectionalCacheItem *newItem = nil;
		
		if (evictedCacheItem)
		{
			newItem = evictedCacheItem;
			evictedCacheItem = nil;
		}
		else
		{
			newItem = [[YapBidirectionalCacheItem alloc] init];
		}
		
		__strong id newKey = nil;
		
		if (keyCallBacks.shouldCopy)
			newKey = [key copy];
		else
			newKey = key;
		
		newItem->key = newKey; // __unsafe_unretained assignment
		
		if (objCallBacks.shouldCopy)
			newItem->obj = [object copy];
		else
			newItem->obj = object;
		
		// Add item to dicts
		
		CFDictionarySetValue(key_obj_dict, (const void *)newKey, (const void *)newItem);
		CFDictionarySetValue(obj_key_dict, (const void *)newItem->obj, (const void *)newItem);
		
		// Add item to beginning of linked-list
		
		newItem->next = mostRecentCacheItem;
		
		if (mostRecentCacheItem)
			mostRecentCacheItem->prev = newItem;
		
		mostRecentCacheItem = newItem;
		
		// Evict leastRecentCacheItem if needed
		
		if ((countLimit != 0) && (CFDictionaryGetCount(key_obj_dict) > (CFIndex)countLimit))
		{
			YDBLogVerbose(@"in(%@), out(%@)", key, leastRecentCacheItem->key);
			
			__unsafe_unretained id keyToEvict = leastRecentCacheItem->key;
			__unsafe_unretained id objToEvict = leastRecentCacheItem->obj;
			
			if (evictedCacheItem == nil)
			{
				evictedCacheItem = leastRecentCacheItem;
				
				leastRecentCacheItem = leastRecentCacheItem->prev;
				leastRecentCacheItem->next = nil;
				
				CFDictionaryRemoveValue(obj_key_dict, (const void *)(objToEvict)); // must be first
				CFDictionaryRemoveValue(key_obj_dict, (const void *)(keyToEvict)); // must be second
				
				evictedCacheItem->prev = nil;
				evictedCacheItem->next = nil;
				evictedCacheItem->key  = nil;
				evictedCacheItem->obj  = nil; // deallocates obj / objToEvict
			}
			else
			{
				leastRecentCacheItem = leastRecentCacheItem->prev;
				leastRecentCacheItem->next = nil;
				
				CFDictionaryRemoveValue(obj_key_dict, (const void *)(objToEvict)); // must be first
				CFDictionaryRemoveValue(key_obj_dict, (const void *)(keyToEvict)); // must be second
			}
			
			#if YapBidirectionalCache_Enable_Statistics
			evictionCount++;
			#endif
		}
		else
		{
			if (leastRecentCacheItem == nil)
				leastRecentCacheItem = newItem;
			
			YDBLogVerbose(@"key(%@) <- new mostRecent [%ld of %lu]",
			              key, CFDictionaryGetCount(key_obj_dict), (unsigned long)countLimit);
		}
	}
	
	if (ydbLogLevel & YDB_LOG_FLAG_VERBOSE)
	{
		YDBLogVerbose(@"key_obj_dict: %@", key_obj_dict);
		YDBLogVerbose(@"obj_key_dict: %@", obj_key_dict);
		
		YapBidirectionalCacheItem *loopItem = mostRecentCacheItem;
		NSUInteger i = 0;
		
		while (loopItem != nil)
		{
			YDBLogVerbose(@"%lu: %@", (unsigned long)i, loopItem);
			
			loopItem = loopItem->next;
			i++;
		}
	}
}

- (void)removeAllObjects
{
	leastRecentCacheItem = nil;
	mostRecentCacheItem = nil;
	evictedCacheItem = nil;
	
	CFDictionaryRemoveAllValues(obj_key_dict); // must be first
	CFDictionaryRemoveAllValues(key_obj_dict); // must be second
}

- (void)removeObjectForKey:(id)key
{
	#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedKeyClass(key, allowedKeyClasses);
	#endif
	
	__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
	if (item)
	{
		if (item == mostRecentCacheItem)
			mostRecentCacheItem = item->next;
		else if (item->prev)
			item->prev->next = item->next;
		
		if (item == leastRecentCacheItem)
			leastRecentCacheItem = item->prev;
		else if (item->next)
			item->next->prev = item->prev;
		
		CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj); // must be first
		CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key); // must be second
	}
}

- (void)removeObjectsForKeys:(id <NSFastEnumeration>)keys
{
	for (id key in keys)
	{
		#ifndef NS_BLOCK_ASSERTIONS
		AssertAllowedKeyClass(key, allowedKeyClasses);
		#endif
		
		__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
		if (item)
		{
			if (item == mostRecentCacheItem)
				mostRecentCacheItem = item->next;
			else if (item->prev)
				item->prev->next = item->next;
			
			if (item == leastRecentCacheItem)
				leastRecentCacheItem = item->prev;
			else if (item->next)
				item->next->prev = item->prev;
			
			CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj); // must be first
			CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key); // must be second
		}
	}
}

- (void)removeKeyForObject:(id)object
{
	#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedObjectClass(object, allowedObjectClasses);
	#endif
	
	__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
	if (item)
	{
		if (item == mostRecentCacheItem)
			mostRecentCacheItem = item->next;
		else if (item->prev)
			item->prev->next = item->next;
		
		if (item == leastRecentCacheItem)
			leastRecentCacheItem = item->prev;
		else if (item->next)
			item->next->prev = item->prev;
		
		CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj); // must be first
		CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key); // must be second
	}
}

- (void)removeKeysForObjects:(id <NSFastEnumeration>)objects
{
	for (id object in objects)
	{
		#ifndef NS_BLOCK_ASSERTIONS
		AssertAllowedObjectClass(object, allowedObjectClasses);
		#endif
		
		__unsafe_unretained YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
		if (item)
		{
			if (item == mostRecentCacheItem)
				mostRecentCacheItem = item->next;
			else if (item->prev)
				item->prev->next = item->next;
			
			if (item == leastRecentCacheItem)
				leastRecentCacheItem = item->prev;
			else if (item->next)
				item->next->prev = item->prev;
			
			CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj); // must be first
			CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key); // must be second
		}
	}
}

- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))block
{
	// We could simply walk the linked-list starting with mostRecentCacheItem,
	// but that breaks the API contract in certain cases.
	//
	// 1. The user wouldn't expect that reading from the cache during enumeration would mutate the cache.
	//    But it would change the linked-list order, and would break the in-progress enumeration.
	//
	// 2. We still need to detect and throw "modified during enumeration" exceptions.
	//    We get this for free if we use the underlying dictionary for enumeration.
	
	NSDictionary *nsdict = (__bridge NSDictionary *)key_obj_dict;
	BOOL stop = NO;
	
	for (id key in [nsdict keyEnumerator])
	{
		block(key, &stop);
		
		if (stop) break;
	}
}

- (void)enumerateObjectsWithBlock:(void (^)(id object, BOOL *stop))block
{
	// We could simply walk the linked-list starting with mostRecentCacheItem,
	// but that breaks the API contract in certain cases.
	//
	// 1. The user wouldn't expect that reading from the cache during enumeration would mutate the cache.
	//    But it would change the linked-list order, and would break the in-progress enumeration.
	//
	// 2. We still need to detect and throw "modified during enumeration" exceptions.
	//    We get this for free if we use the underlying dictionary for enumeration.
	
	NSDictionary *nsdict = (__bridge NSDictionary *)obj_key_dict;
	BOOL stop = NO;
	
	for (id obj in [nsdict keyEnumerator])
	{
		block(obj, &stop);
		
		if (stop) break;
	}
}

- (void)enumerateKeysAndObjectsWithBlock:(void (^)(id key, id obj, BOOL *stop))block
{
	// We could simply walk the linked-list starting with mostRecentCacheItem,
	// but that breaks the API contract in certain cases.
	//
	// 1. The user wouldn't expect that reading from the cache during enumeration would mutate the cache.
	//    But it would change the linked-list order, and would break the in-progress enumeration.
	//
	// 2. We still need to detect and throw "modified during enumeration" exceptions.
	//    We get this for free if we use the underlying dictionary for enumeration.
	
	NSDictionary *nsdict = (__bridge NSDictionary *)key_obj_dict;
	
	[nsdict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained YapBidirectionalCacheItem *cacheItem = (YapBidirectionalCacheItem *)obj;
		
		block(key, cacheItem->obj, stop);
	}];
}

#ifndef NS_BLOCK_ASSERTIONS
static void AssertAllowedKeyClass(id key, NSSet *allowedKeyClasses)
{
	if (allowedKeyClasses == nil) return;

//	This doesn't work.
//	For example, @(number) gives us class '__NSCFNumber', which is not NSNumber.
//	And there are also class clusters which break this technique too.
//
//	return [allowedKeyClasses containsObject:[key class]];
	
	// So we have to use the isKindOfClass method,
	// which means we need to enumerate the allowedKeyClasses.
	
	for (Class allowedKeyClass in allowedKeyClasses)
	{
		if ([key isKindOfClass:allowedKeyClass]) return;
	}
	
	NSCAssert(NO, @"Unexpected key class. Passed %@, expected: %@", [key class], allowedKeyClasses);
}
#endif

#ifndef NS_BLOCK_ASSERTIONS
static void AssertAllowedObjectClass(id obj, NSSet *allowedObjectClasses)
{
	if (allowedObjectClasses == nil) return;
	
//	This doesn't work.
//	For example, @(number) gives us class '__NSCFNumber', which is not NSNumber.
//	And there are also class clusters which break this technique too.
//
//	return [allowedObjectClasses containsObject:[obj class]];
	
	// So we have to use the isKindOfClass method,
	// which means we need to enumerate the allowedKeyClasses.
	
	for (Class allowedObjectClass in allowedObjectClasses)
	{
		if ([obj isKindOfClass:allowedObjectClass]) return;
	}
	
	NSCAssert(NO, @"Unexpected object class. Passed %@, expected: %@", [obj class], allowedObjectClasses);
}
#endif

@end
