#import "YapCache.h"
#import "YapDatabaseLogging.h"

#import <libkern/OSAtomic.h>

/**
 * Does ARC support support GCD objects?
 * It does if the minimum deployment target is iOS 6+ or Mac OS X 10.8+
**/
#if TARGET_OS_IPHONE

  // Compiling for iOS

  #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000 // iOS 6.0 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else                                         // iOS 5.X or earlier
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1
  #endif

#else

  // Compiling for Mac OS X

  #if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080     // Mac OS X 10.8 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1     // Mac OS X 10.7 or earlier
  #endif

#endif

#if DEBUG && robbie_hanson
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_OFF;
#elif DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_OFF;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_OFF;
#endif

/**
 * Default countLimit, as specified in header file.
**/
#define YAP_CACHE_DEFAULT_COUNT_LIMIT 40


@interface YapCacheItem : NSObject {
@public
	__unsafe_unretained YapCacheItem *prev; // retained by cfdict
	__unsafe_unretained YapCacheItem *next; // retained by cfdict

	__unsafe_unretained id key; // retained by cfdict as key (immutable copy of original key is always made)
	__strong id value;          // retained only by us
}

- (id)initWithKey:(id)key value:(id)value;

@end

@implementation YapCacheItem

- (id)initWithKey:(id <NSCopying>)aKey value:(id)aValue
{
	if ((self = [super init]))
	{
		key = aKey;
		value = aValue;
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapCacheItem[%p] key(%@)>", self, key];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapThreadUnsafeCache
{
	Class keyClass;
	CFMutableDictionaryRef cfdict;
	
	NSUInteger countLimit;
	
	NSUInteger hitCount;
	NSUInteger missCount;
	NSUInteger evictionCount;
	
	__unsafe_unretained YapCacheItem *mostRecentCacheItem;
	__unsafe_unretained YapCacheItem *leastRecentCacheItem;
	
	__strong YapCacheItem *evictedCacheItem;
}

@synthesize hitCount = hitCount;
@synthesize missCount = missCount;
@synthesize evictionCount = evictionCount;

- (id)init
{
	return [self initWithKeyClass:NULL countLimit:0];
}

- (id)initWithKeyClass:(Class)inKeyClass
{
	return [self initWithKeyClass:inKeyClass countLimit:0];
}

- (id)initWithKeyClass:(Class)inKeyClass countLimit:(NSUInteger)inCountLimit
{
	if ((self = [super init]))
	{
		if (inKeyClass == NULL)
			keyClass = [NSString class];
		else
			keyClass = inKeyClass;
		
		if (inCountLimit == 0)
			countLimit = YAP_CACHE_DEFAULT_COUNT_LIMIT;
		else
			countLimit = inCountLimit;
		
		// We actually use countLimit plus one.
		// This is because we evict items after the count surpasses the countLimit.
		// In other words, we evict items when the count reaches countLimit plus one.
		
		cfdict = CFDictionaryCreateMutable(kCFAllocatorDefault,
		                                   0,
		                                   &kCFTypeDictionaryKeyCallBacks,
		                                   &kCFTypeDictionaryValueCallBacks);
	}
	return self;
}

- (void)dealloc
{
	if (cfdict) CFRelease(cfdict);
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
		
		if (countLimit != 0) {
			while (CFDictionaryGetCount(cfdict) > countLimit)
			{
				leastRecentCacheItem->prev->next = nil;
				
				evictedCacheItem = leastRecentCacheItem;
				leastRecentCacheItem = leastRecentCacheItem->prev;
				
				CFDictionaryRemoveValue(cfdict, (const void *)(evictedCacheItem->key));
				
				evictedCacheItem->prev = nil;
				evictedCacheItem->next = nil;
				evictedCacheItem->key = nil;
				evictedCacheItem->value = nil;
				
				evictionCount++;
			}
		}
	}
}

- (id)objectForKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Unexpected key class. Expected %@, passed %@", keyClass, [key class]);
	
	YapCacheItem *item = CFDictionaryGetValue(cfdict, (const void *)key);
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
		
		hitCount++;
		return item->value;
	}
	else
	{
		missCount++;
		return nil;
	}
}

- (void)setObject:(id)object forKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Unexpected key class. Expected %@, passed %@", keyClass, [key class]);
	
	YapCacheItem *item = CFDictionaryGetValue(cfdict, (const void *)key);
	if (item)
	{
		// Update item value
		item->value = object;
		
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
			item->key = key;
			item->value = object;
			
			evictedCacheItem = nil;
		}
		else
		{
			item = [[YapCacheItem alloc] initWithKey:key value:object];
		}
		
		// Add item to set
		CFDictionarySetValue(cfdict, (const void *)key, (const void *)item);
		
		// Add item to beginning of linked-list
		
		item->next = mostRecentCacheItem;
		
		if (mostRecentCacheItem)
			mostRecentCacheItem->prev = item;
		
		mostRecentCacheItem = item;
		
		// Evict leastRecentCacheItem if needed
		
		if ((countLimit != 0) && (CFDictionaryGetCount(cfdict) > countLimit))
		{
			YDBLogVerbose(@"key(%@), out(%@)", key, leastRecentCacheItem->key);
			
			leastRecentCacheItem->prev->next = nil;
			
			evictedCacheItem = leastRecentCacheItem;
			leastRecentCacheItem = leastRecentCacheItem->prev;

			NSString *evictedKey = evictedCacheItem->key;
			CFDictionaryRemoveValue(cfdict, (const void *)evictedKey);
			
			evictedCacheItem->prev = nil;
			evictedCacheItem->next = nil;
			evictedCacheItem->key = nil;
			evictedCacheItem->value = nil;
			
			evictionCount++;
		}
		else
		{
			if (leastRecentCacheItem == nil)
				leastRecentCacheItem = item;
			
			YDBLogVerbose(@"key(%@) <- new, new mostRecent [%ld of %d]",
			              key, CFDictionaryGetCount(cfdict), countLimit);
		}
	}
	
	if (YDBLogLevel & YDB_LOG_FLAG_VERBOSE)
	{
		YDBLogVerbose(@"cfdict: %@", cfdict);
		
		YapCacheItem *loopItem = mostRecentCacheItem;
		NSUInteger i = 0;
		
		while (loopItem != nil)
		{
			YDBLogVerbose(@"%d: %@", i, loopItem);
			
			loopItem = loopItem->next;
			i++;
		}
	}
}

- (NSUInteger)count
{
	return CFDictionaryGetCount(cfdict);
}

- (void)removeAllObjects
{
	mostRecentCacheItem = nil;
	leastRecentCacheItem = nil;
	
	CFDictionaryRemoveAllValues(cfdict);
}

- (void)removeObjectForKey:(id)key
{
	NSAssert([key isKindOfClass:keyClass], @"Unexpected key class. Expected %@, passed %@", keyClass, [key class]);
	
	YapCacheItem *item = CFDictionaryGetValue(cfdict, (const void *)key);
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
		
		CFDictionaryRemoveValue(cfdict, (const void *)key);
	}
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	for (id key in keys)
	{
		NSAssert([key isKindOfClass:keyClass], @"Unexpected key class. Expected %@, passed %@", keyClass, [key class]);
		
		YapCacheItem *item = CFDictionaryGetValue(cfdict, (const void *)key);
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
			
			CFDictionaryRemoveValue(cfdict, (const void *)key);
		}
	}
}

- (NSSet *)keysOfEntriesPassingTest:(BOOL (^)(id key, id obj, BOOL *stop))block
{
	NSMutableArray *keys = [NSMutableArray arrayWithCapacity:(CFDictionaryGetCount(cfdict) / 2)];
	
	[(__bridge NSDictionary *)cfdict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		if (block(key, obj, stop))
		{
			[keys addObject:key];
		}
	}];
	
	return [NSSet setWithArray:keys];
}

- (NSString *)description
{
	NSMutableString *description = [NSMutableString string];
	[description appendFormat:@"%@, count=%ld, keys=\n", NSStringFromClass([self class]), CFDictionaryGetCount(cfdict)];
	
	YapCacheItem *item = mostRecentCacheItem;
	NSUInteger itemIndex = 0;
	
	while (item != nil)
	{
		[description appendFormat:@"  %lu: %@\n", (unsigned long)itemIndex, item->key];
		
		item = item->next;
		itemIndex++;
	}
	
	return description;
}

/*
- (void)debug
{
	CFIndex count = CFDictionaryGetCount(cfdict);
	NSAssert(count <= countLimit, @"Invalid count");
	
	NSMutableArray *forwardsKeys = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray *backwardsKeys = [NSMutableArray arrayWithCapacity:count];
	
	__unsafe_unretained YapCacheItem *loopItem;
	
	loopItem = mostRecentCacheItem;
	while (loopItem != nil)
	{
		[forwardsKeys addObject:loopItem->key];
		loopItem = loopItem->next;
	}
	
	loopItem = leastRecentCacheItem;
	while (loopItem != nil)
	{
		[backwardsKeys insertObject:loopItem->key atIndex:0];
		loopItem = loopItem->prev;
	}
	
	NSAssert([forwardsKeys isEqual:backwardsKeys], @"Invalid order");
}
*/

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * How should we implement the thread-safety mechanism?
 * 
 * If contention for the cache is low (not many simulataneous invocations on the cache from multiple threads)
 * then a spinlock is the fastest implementation.
 * 
 * However, if contention is an issue, then using GCD dispatch queues is a better way to go.
**/
#define USE_SPINLOCK 1
#define USE_DISPATCH !USE_SPINLOCK

@implementation YapThreadSafeCache
{
#if USE_SPINLOCK
	OSSpinLock lock;
#else
	dispatch_queue_t internalSerialQueue;
#endif
}

- (id)initWithKeyClass:(Class)inKeyClass countLimit:(NSUInteger)inCountLimit
{
	if ((self = [super initWithKeyClass:inKeyClass countLimit:inCountLimit]))
	{
	#if USE_SPINLOCK
		lock = OS_SPINLOCK_INIT;
	#else
		internalSerialQueue = dispatch_queue_create("YapCache", NULL);
	#endif
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(didReceiveMemoryWarning:)
		                                             name:UIApplicationDidReceiveMemoryWarningNotification
		                                           object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
#if USE_DISPATCH
#if NEEDS_DISPATCH_RETAIN_RELEASE
	if (internalSerialQueue)
		dispatch_release(internalSerialQueue);
#endif
#endif
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
	[self removeAllObjects];
}

- (NSUInteger)countLimit
{
#if USE_SPINLOCK
	
	NSUInteger result = 0;
	
	OSSpinLockLock(&lock);
	result = [super countLimit];
	OSSpinLockUnlock(&lock);
	
	return result;
#else
	
	__block NSUInteger result = 0;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super countLimit];
	});
	
	return result;
	
#endif
}

- (void)setCountLimit:(NSUInteger)newCountLimit
{
#if USE_SPINLOCK
	
	OSSpinLockLock(&lock);
	[super setCountLimit:newCountLimit];
	OSSpinLockUnlock(&lock);
	
#else
	
	dispatch_sync(internalSerialQueue, ^{
		[super setCountLimit:newCountLimit];
	});
	
#endif
}

- (NSUInteger)hitCount
{
#if USE_SPINLOCK
	
	NSUInteger result = 0;
	
	OSSpinLockLock(&lock);
	result = [super hitCount];
	OSSpinLockUnlock(&lock);
	
	return result;
	
#else
	
	__block NSUInteger result = 0;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super hitCount];
	});
	
	return result;
	
#endif
}

- (NSUInteger)missCount
{
#if USE_SPINLOCK
	
	NSUInteger result = 0;
	
	OSSpinLockLock(&lock);
	result = [super missCount];
	OSSpinLockUnlock(&lock);
	
	return result;
	
#else
	
	__block NSUInteger result = 0;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super missCount];
	});
	
	return result;
	
#endif
}

- (NSUInteger)evictionCount
{
#if USE_SPINLOCK
	
	NSUInteger result = 0;
	
	OSSpinLockLock(&lock);
	result = [super evictionCount];
	OSSpinLockUnlock(&lock);
	
	return result;
	
#else
	
	__block NSUInteger result = 0;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super evictionCount];
	});
	
	return result;
	
#endif
}

- (id)objectForKey:(id)key
{
#if USE_SPINLOCK
	
	id result = nil;
	
	OSSpinLockLock(&lock);
	result = [super objectForKey:key];
	OSSpinLockUnlock(&lock);
	
	return result;
#else
	
	__block id result = nil;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super objectForKey:key];
	});
	
	return result;
	
#endif
}

- (void)setObject:(id)object forKey:(id)key
{
#if USE_SPINLOCK
	
	OSSpinLockLock(&lock);
	[super setObject:object forKey:key];
	OSSpinLockUnlock(&lock);
	
#else
	
	dispatch_sync(internalSerialQueue, ^{
		[super setObject:object forKey:key];
	});
	
#endif
}

- (NSUInteger)count
{
#if USE_SPINLOCK
	
	NSUInteger result = 0;
	
	OSSpinLockLock(&lock);
	result = [super count];
	OSSpinLockUnlock(&lock);
	
	return result;
#else
	
	__block NSUInteger result = 0;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super count];
	});
	
	return result;
	
#endif
}

- (void)removeAllObjects
{
#if USE_SPINLOCK
	
	OSSpinLockLock(&lock);
	[super removeAllObjects];
	OSSpinLockUnlock(&lock);
	
#else
	
	dispatch_sync(internalSerialQueue, ^{
		[super removeAllObjects];
	});
	
#endif
}

- (void)removeObjectForKey:(id)key
{
#if USE_SPINLOCK
	
	OSSpinLockLock(&lock);
	[super removeObjectForKey:key];
	OSSpinLockUnlock(&lock);
	
#else
	
	dispatch_sync(internalSerialQueue, ^{
		[super removeObjectForKey:key];
	});
	
#endif
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
#if USE_SPINLOCK
	
	OSSpinLockLock(&lock);
	[super removeObjectsForKeys:keys];
	OSSpinLockUnlock(&lock);
	
#else
	
	dispatch_sync(internalSerialQueue, ^{
		[super removeObjectsForKeys:keys];
	});
	
#endif
}

- (NSSet *)keysOfEntriesPassingTest:(BOOL (^)(id key, id obj, BOOL *stop))block
{
#if USE_SPINLOCK
	
	NSSet *result = nil;
	
	OSSpinLockLock(&lock);
	result = [super keysOfEntriesPassingTest:block];
	OSSpinLockUnlock(&lock);
	
	return result;
	
#else
	
	__block NSSet *result = nil;
	
	dispatch_sync(internalSerialQueue, ^{
		result = [super keysOfEntriesPassingTest:block];
	});
	
	return result;
	
#endif
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapCacheCollectionKey
{
	NSString *collection;
	NSString *key;
}

@synthesize collection = collection;
@synthesize key = key;

- (id)initWithCollection:(NSString *)aCollection key:(NSString *)aKey
{
	if ((self = [super init]))
	{
		collection = aCollection;
		key = aKey;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	return self; // Immutable
}

- (BOOL)isEqual:(id)obj
{
	if ([obj isMemberOfClass:[YapCacheCollectionKey class]])
	{
		YapCacheCollectionKey *ck = (YapCacheCollectionKey *)obj;
		
		return [key isEqualToString:ck->key] && [collection isEqualToString:ck->collection];
	}
	
	return NO;
}

- (NSUInteger)hash
{
	// We need a fast way to combine 2 hashes without creating a new string (which is slow).
	// To accomplish this we use the murmur hashing algorithm.
	//
	// MurmurHash2 was written by Austin Appleby, and is placed in the public domain.
	// http://code.google.com/p/smhasher
	
	NSUInteger chash = [collection hash];
	NSUInteger khash = [key hash];
	
	if (NSUIntegerMax == UINT32_MAX) // Should be optimized out via compiler since these are constants
	{
		// MurmurHash2 (32-bit)
		//
		// uint32_t MurmurHash2 ( const void * key, int len, uint32_t seed )
		//
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 2 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 8;          // 2 hashes, each 4 bytes = 8 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint32_t m = 0x5bd1e995;
		const int r = 24;
		
		// Initialize the hash to a 'random' value
		
		uint32_t h = seed ^ len;
		uint32_t k;
		
		// Mix chash
		
		k = chash;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Mix khash
		
		k = khash;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h *= m;
		h ^= k;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> 13;
		h *= m;
		h ^= h >> 15;
		
		return (NSUInteger)h;
	}
	else
	{
		// MurmurHash2 (64-bit)
		//
		// uint64_t MurmurHash64A ( const void * key, int len, uint64_t seed )
		//
		// Normally one would pass a chunk of data ('key') and associated data chunk length ('len').
		// Instead we're going to use our 3 hashes.
		// And we're going to randomly make up a 'seed'.
		
		const uint32_t seed = 0xa2f1b6f; // Some random value I made up
		const uint32_t len = 16;         // 2 hashes, each 8 bytes = 16 bytes
		
		// 'm' and 'r' are mixing constants generated offline.
		// They're not really 'magic', they just happen to work well.
		
		const uint64_t m = 0xc6a4a7935bd1e995LLU;
		const int r = 47;
		
		// Initialize the hash to a 'random' value
		
		uint64_t h = seed ^ (len * m);
		uint64_t k;
		
		// Mix chash
		
		k = chash;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h ^= k;
		h *= m;
		
		// Mix khash
		
		k = khash;
		
		k *= m;
		k ^= k >> r;
		k *= m;
		
		h ^= k;
		h *= m;
		
		// Do a few final mixes of the hash to ensure the last few
		// bytes are well-incorporated.
		
		h ^= h >> r;
		h *= m;
		h ^= h >> r;
		
		return (NSUInteger)h;
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapCacheCollectionKey[%p] collection(%@) key(%@)>", self, collection, key];
}

@end
