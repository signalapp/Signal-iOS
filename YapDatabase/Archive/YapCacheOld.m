#import "YapCacheOld.h"

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

/**
 * Default countLimit, as specified in header file.
**/
#define YAP_CACHE_DEFAULT_COUNT_LIMIT 40


@implementation YapCacheOld
{
	dispatch_queue_t internalSerialQueue;
	
	NSMutableDictionary *dict;
	NSMutableOrderedSet *keys;
	
	NSUInteger countLimit;
}

- (id)init
{
	return [self initWithCountLimit:0];
}

- (id)initWithCountLimit:(NSUInteger)inCountLimit
{
	return [self initWithCountLimit:inCountLimit threadSafe:YES];
}

- (id)initWithCountLimit:(NSUInteger)inCountLimit threadSafe:(BOOL)threadSafe
{
	if ((self = [super init]))
	{
		if (inCountLimit == 0)
			countLimit = inCountLimit;
		else
			countLimit = YAP_CACHE_DEFAULT_COUNT_LIMIT;
		
		// We actually use countLimit plus one.
		// This is because we evict items after the count surpasses the countLimit.
		// In other words, we evict items when the count reaches countLimit plus one.
		
		dict = [[NSMutableDictionary alloc] initWithCapacity:(countLimit + 1)];
		keys = [[NSMutableOrderedSet alloc] initWithCapacity:(countLimit + 1)];
		
		if (threadSafe) {
			internalSerialQueue = dispatch_queue_create("YapCache", NULL);
		}
		
		#if TARGET_OS_IPHONE
		if (threadSafe) {
			[[NSNotificationCenter defaultCenter] addObserver:self
			                                         selector:@selector(didReceiveMemoryWarning:)
			                                             name:UIApplicationDidReceiveMemoryWarningNotification
			                                           object:nil];
		}
		#endif
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	#if NEEDS_DISPATCH_RETAIN_RELEASE
	if (internalSerialQueue)
		dispatch_release(internalSerialQueue);
	#endif
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
	[self removeAllObjects];
}

- (NSUInteger)countLimit
{
	__block NSUInteger result = 0;
	
	dispatch_block_t block = ^{
		
		result = countLimit;
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
	
	return result;
}

- (void)setCountLimit:(NSUInteger)newCountLimit
{
	dispatch_block_t block = ^{
		
		if (countLimit != newCountLimit)
		{
			countLimit = newCountLimit;
			
			if (countLimit != 0) {
				while ([keys count] > countLimit)
				{
					id leastUsedKey = [keys lastObject];
					
					[dict removeObjectForKey:leastUsedKey];
					[keys removeObjectAtIndex:([keys count] - 1)];
				}
			}
		}
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

- (void)_setObject:(id)object forKey:(id)key
{
	[dict setObject:object forKey:key];
	
	if (![keys containsObject:key])
	{
		// Add key to the beginning, marking it as the most recently used key
		[keys insertObject:key atIndex:0];
	}
	else
	{
		// Move key to the beginning, marking it as the most recently used key
		NSUInteger index = [keys indexOfObject:key];
		if (index != 0) {
			[keys moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:index] toIndex:0];
		}
	}
	
	if (countLimit != 0 && [keys count] > countLimit)
	{
		id leastUsedKey = [keys lastObject];
		
		[dict removeObjectForKey:leastUsedKey];
		[keys removeObjectAtIndex:([keys count] - 1)];
	}
}

- (void)setObject:(id)object forKey:(id)key
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
		return;
	}
	if (key == nil) return;
	
	dispatch_block_t block = ^{
		
		[self _setObject:object forKey:key];
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

- (id)objectForKey:(id)key
{
	__block id object = nil;
	
	dispatch_block_t block = ^{
		
		object = [dict objectForKey:key];
		if (object == nil) return;
		
		// Move key to the beginning, marking it as the most recently used key
		
		NSUInteger index = [keys indexOfObject:key];
		if (index != 0) {
			[keys moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:index] toIndex:0];
		}
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
	
	return object;
}

- (NSUInteger)count
{
	__block NSUInteger count = 0;
	
	dispatch_block_t block = ^{
		
		count = [dict count];
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
	
	return count;
}

- (void)removeAllObjects
{
	dispatch_block_t block = ^{
		
		[dict removeAllObjects];
		[keys removeAllObjects];
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

- (void)removeObjectForKey:(id)key
{
	dispatch_block_t block = ^{
		
		[dict removeObjectForKey:key];
		[keys removeObject:key];
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

- (void)removeObjectsForKeys:(NSArray *)inKeys
{
	dispatch_block_t block = ^{
		
		[dict removeObjectsForKeys:inKeys];
		[keys removeObjectsInArray:inKeys];
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

- (void)replaceObjectIfExistsForKey:(id)key withObject:(id)object
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
		return;
	}
	if (key == nil) return;
	
	dispatch_block_t block = ^{
		
		if ([keys containsObject:key])
		{
			[self _setObject:object forKey:key];
		}
	};
	
	if (internalSerialQueue)
		dispatch_sync(internalSerialQueue, block);
	else
		block();
}

@end
