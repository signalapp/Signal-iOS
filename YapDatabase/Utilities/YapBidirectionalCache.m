#import "YapBidirectionalCache.h"
#import "YapDatabaseLogging.h"

static NSUInteger const YapBidirectionalCache_Default_CountLimit = 40;

const YapBidirectionalCacheCallBacks kYapBidirectionalCacheDefaultCallBacks = (YapBidirectionalCacheCallBacks){
	.version = 0,
	.shouldCopy = YES,
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
	__unsafe_unretained YapBidirectionalCacheItem *prev;
	__strong            YapBidirectionalCacheItem *next;
	
	__strong id key;
	__strong id obj;
}

@end

@implementation YapBidirectionalCacheItem

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
	
	// Memory managemnet architecture:
	//
	// - ONLY the YapBidirectionalCacheItem retains the key and object
	// - ONLY the forward-linked-list retains the YapBidirectionalCacheItem(s)
	//
	// It's important to note that:
	// - key_obj_dict does NOT retain its keys or objects
	// - obj_key_dict does NOT retain its keys or objects
	// - the backward-linked-list does NOT retain the items
	//
	// This is done for performance reasons.
	// We can skip a LOT of extraneous retain/release operations this way.
	
	CFMutableDictionaryRef key_obj_dict;
	CFMutableDictionaryRef obj_key_dict;
	
	__strong            YapBidirectionalCacheItem *mostRecentCacheItem;
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
		YapBidirectionalCacheCallBacks defaultCallBacks;
		defaultCallBacks.version = 0;
		defaultCallBacks.shouldCopy = NO;
		defaultCallBacks.equal = CFEqual;
		defaultCallBacks.hash = CFHash;
		
		if (inKeyCallBacks == NULL)
			inKeyCallBacks = &defaultCallBacks;
		
		if (inObjCallBacks == NULL)
			inObjCallBacks = &defaultCallBacks;
		
		memcpy(&keyCallBacks, inKeyCallBacks, sizeof(YapBidirectionalCacheCallBacks));
		memcpy(&objCallBacks, inObjCallBacks, sizeof(YapBidirectionalCacheCallBacks));
		
		CFDictionaryKeyCallBacks kcb = kCFTypeDictionaryKeyCallBacks;
		kcb.retain  = NULL;
		kcb.release = NULL;
		kcb.equal   = keyCallBacks.equal;
		kcb.hash    = keyCallBacks.hash;
		
		CFDictionaryValueCallBacks vcb = kCFTypeDictionaryValueCallBacks;
		vcb.retain  = NULL;
		vcb.release = NULL;
		vcb.equal   = objCallBacks.equal;
		
		key_obj_dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kcb, &vcb);
		
		kcb.equal = objCallBacks.equal;
		kcb.hash  = objCallBacks.hash;
		
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
				CFDictionaryRemoveValue(key_obj_dict, (const void *)(leastRecentCacheItem->key));
				CFDictionaryRemoveValue(obj_key_dict, (const void *)(leastRecentCacheItem->key));
				
				if (evictedCacheItem == nil)
				{
					evictedCacheItem = leastRecentCacheItem;
					
					leastRecentCacheItem = leastRecentCacheItem->prev;
					leastRecentCacheItem->next = nil;
					
					evictedCacheItem->prev = nil;
					evictedCacheItem->next = nil;
					evictedCacheItem->key  = nil;
					evictedCacheItem->obj  = nil;
				}
				else
				{
					leastRecentCacheItem = leastRecentCacheItem->prev;
					leastRecentCacheItem->next = nil;
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
	
	YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
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
	
	YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
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
	
	YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
	if (item)
	{
		// Update item value
		if (!objCallBacks.equal((__bridge const void *)item->obj, (__bridge const void *)object))
		{
			CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj);
			
			if (objCallBacks.shouldCopy)
				item->obj = [object copy];
			else
				item->obj = object;
			
			CFDictionarySetValue(obj_key_dict, (const void *)item->obj, (const void *)item);
		}
		
		if (item != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list
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
		
		if (evictedCacheItem)
		{
			item = evictedCacheItem;
			evictedCacheItem = nil;
		}
		else
		{
			item = [[YapBidirectionalCacheItem alloc] init];
		}
		
		if (keyCallBacks.shouldCopy)
			item->key = [key copy];
		else
			item->key = key;
		
		if (objCallBacks.shouldCopy)
			item->obj = [object copy];
		else
			item->obj = object;
		
		// Add item to dicts
		
		CFDictionarySetValue(key_obj_dict, (const void *)item->key, (const void *)item);
		CFDictionarySetValue(obj_key_dict, (const void *)item->obj, (const void *)item);
		
		// Add item to beginning of linked-list
		
		item->next = mostRecentCacheItem;
		
		if (mostRecentCacheItem)
			mostRecentCacheItem->prev = item;
		
		mostRecentCacheItem = item;
		
		// Evict leastRecentCacheItem if needed
		
		if ((countLimit != 0) && (CFDictionaryGetCount(key_obj_dict) > (CFIndex)countLimit))
		{
			YDBLogVerbose(@"in(%@), out(%@)", key, leastRecentCacheItem->key);
			
			CFDictionaryRemoveValue(key_obj_dict, (const void *)(leastRecentCacheItem->key));
			CFDictionaryRemoveValue(obj_key_dict, (const void *)(leastRecentCacheItem->key));
			
			if (evictedCacheItem == nil)
			{
				evictedCacheItem = leastRecentCacheItem;
				
				leastRecentCacheItem = leastRecentCacheItem->prev;
				leastRecentCacheItem->next = nil;
				
				evictedCacheItem->prev = nil;
				evictedCacheItem->next = nil;
				evictedCacheItem->key  = nil;
				evictedCacheItem->obj  = nil;
			}
			else
			{
				leastRecentCacheItem = leastRecentCacheItem->prev;
				leastRecentCacheItem->next = nil;
			}
			
			#if YapBidirectionalCache_Enable_Statistics
			evictionCount++;
			#endif
		}
		else
		{
			if (leastRecentCacheItem == nil)
				leastRecentCacheItem = item;
			
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
	CFDictionaryRemoveAllValues(key_obj_dict);
	CFDictionaryRemoveAllValues(obj_key_dict);
	
	leastRecentCacheItem = nil;
	mostRecentCacheItem = nil;
	
	evictedCacheItem = nil;
}

- (void)removeObjectForKey:(id)key
{
	#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedKeyClass(key, allowedKeyClasses);
	#endif
	
	YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
	if (item)
	{
		if (item->prev)
			item->prev->next = item->next;
		
		if (item->next)
			item->next->prev = item->prev;
		
		if (mostRecentCacheItem == item)
			mostRecentCacheItem = item->next;
		
		if (leastRecentCacheItem == item)
			leastRecentCacheItem = item->prev;
		
		CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key);
		CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj);
	}
}

- (void)removeObjectsForKeys:(id <NSFastEnumeration>)keys
{
	for (id key in keys)
	{
		#ifndef NS_BLOCK_ASSERTIONS
		AssertAllowedKeyClass(key, allowedKeyClasses);
		#endif
		
		YapBidirectionalCacheItem *item = CFDictionaryGetValue(key_obj_dict, (const void *)key);
		if (item)
		{
			if (item->prev)
				item->prev->next = item->next;
			
			if (item->next)
				item->next->prev = item->prev;
			
			if (mostRecentCacheItem == item)
				mostRecentCacheItem = item->next;
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			
			CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key);
			CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj);
		}
	}
}

- (void)removeKeyForObject:(id)object
{
	#ifndef NS_BLOCK_ASSERTIONS
	AssertAllowedObjectClass(object, allowedObjectClasses);
	#endif
	
	YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
	if (item)
	{
		if (item->prev)
			item->prev->next = item->next;
		
		if (item->next)
			item->next->prev = item->prev;
		
		if (mostRecentCacheItem == item)
			mostRecentCacheItem = item->next;
		
		if (leastRecentCacheItem == item)
			leastRecentCacheItem = item->prev;
		
		CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key);
		CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj);
	}
}

- (void)removeKeysForObjects:(id <NSFastEnumeration>)objects
{
	for (id object in objects)
	{
		#ifndef NS_BLOCK_ASSERTIONS
		AssertAllowedObjectClass(object, allowedObjectClasses);
		#endif
		
		YapBidirectionalCacheItem *item = CFDictionaryGetValue(obj_key_dict, (const void *)object);
		if (item)
		{
			if (item->prev)
				item->prev->next = item->next;
			
			if (item->next)
				item->next->prev = item->prev;
			
			if (mostRecentCacheItem == item)
				mostRecentCacheItem = item->next;
			
			if (leastRecentCacheItem == item)
				leastRecentCacheItem = item->prev;
			
			CFDictionaryRemoveValue(key_obj_dict, (const void *)item->key);
			CFDictionaryRemoveValue(obj_key_dict, (const void *)item->obj);
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
