#import "YapSharedCache.h"
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


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * There may be multiple simulatneous database connections, each using different atomic snapshots.
 * In other words, the value in the database at snapshot A may be different than at snapshot B.
 * Each value is correct, and depends entirely on the snapshot being used by the connection.
 * 
 * Note: Do not think about a snapshot as a moment in time.
 * Instead, think about it as the last time the database was modified.
 * Thus if the database isn't modified, all read-only connections will be looking at the same "snapshot".
 *
 * This presents a unique property of the cache:
 * - the cache may store multiple values for a single key.
 * - the stored values are associated with a timestamp (which represents the last time the db was modified)
 * 
 * This class represents a single stored value and its associated timestamp.
 * It is one value contained within a linked-list of possibly multiple values for the same key.
 * The linked-list remains sorted, with the most recent value at the front of the linked-list.
**/
@interface YapSharedCacheValue : NSObject {
@public
	YapSharedCacheValue *olderValue;
	
	NSTimeInterval lastWriteTimestamp;
	id object;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This class represents the value(s) stored in the shared cache database for a particular key.
 * It is thread-safe, and may be accessed or modified from multiple connections simultaneously.
 *
 * As contention within a single cache item is extremely low,
 * it uses a spinlock to implement the thread-safety measures, which results in faster execution.
**/
@interface YapSharedCacheItem : NSObject {
@private
	YapSharedCacheValue *values; // Linked list, from newest to oldest

@public
	int32_t ownerCount; // Can only read/modify this value from within YapSharedCache->shared_queue
}

/**
 * Create a new shared cache item with the given object and timestamp.
**/
- (id)initWithObject:(id)object timestamp:(NSTimeInterval)lastWriteTimestamp;

/**
 * Older connections (those viewing an older snapshot of the database)
 * are still able to add objects to the shared cache. But it's important that newer connections don't use
 * potentially stale data from the older connections. Thus the changeset information is required when a new value
 * is added to the shared cache. The changeset info is inspected, and if the value changes in the future,
 * then proper placeholders are added for the change.
**/
- (void)updateWithRecentChangesetBlocksAndTimestamps:(NSArray *)recentChanges forKey:(id)key;

/**
 * Adds/sets the value corresponding to the given timestamp.
 * The value will only be readable by other connections with a timestamp greater-than or equal to the given timestamp.
 * This method does not delete older values associated with older timestamps.
 *
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (void)setObject:(id)object forTimestamp:(NSTimeInterval)lastWriteTimestamp;

/**
 * Returns the most recently set value associated with a timestamp less-than or equal to the given timestamp.
 * 
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (id)objectForTimestamp:(NSTimeInterval)lastWriteTimestamp;

/**
 * - If the most recent YapSharedCacheValue has a timestamp equal to the given timestamp, does nothing.
 * - If the most recent YapSharedCacheValue has a timestamp less than the given timestamp,
 *   then adds a new YapSharedCacheValue with a nil object,
**/
- (void)markUpdatedForTimestamp:(NSTimeInterval)updatedLastWriteTimestamp;

/**
 * Deletes values associated with timestamps less than the given minimum.
**/
- (void)cleanWithMinTimestamp:(NSTimeInterval)minLastWriteTimestamp;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Represents an item in the local cache.
 * 
 * One primitive strategy is to simply set a limit on the global cache.
 * However, this means that each connection would be fighting with each other.
 * Connection A would be constantly evicting items cached by connection B,
 * only to have connection B turn around and do the same thing back to connection A.
 * 
 * Instead, each connection maintains its own list of cached items.
 * The list is simply a reference to the shared item stored in the global cache.
 * The local connection maintains:
 * - a dictionary providing quick lookups
 * - a linked list providing the eviction order
**/
@interface YapLocalCacheItem : NSObject {
@public
	__unsafe_unretained YapLocalCacheItem *prev; // retained by local_cfdict
	__unsafe_unretained YapLocalCacheItem *next; // retained by local_cfdict

	__unsafe_unretained id key;                          // retained by shared_cfdict as key
	__unsafe_unretained YapSharedCacheItem *shared_item; // retained by shared_cfdict as value
	
	__strong id object; // retained by us as it could disappear from shared_cfdict at any point
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapSharedCache () {
@private
	NSMutableArray *changesetBlocksAndTimestamps;
	
@public
	Class keyClass;
	
	dispatch_queue_t shared_queue;
	CFMutableDictionaryRef shared_cfdict;
}

- (NSArray *)pendingAndCommittedChangesetBlocksAndTimestampsSince:(NSTimeInterval)writeTimestamp;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapSharedCacheConnection () {
@private
	
	__strong YapSharedCache *parent;
	NSUInteger countLimit;
	
	NSTimeInterval timestamp;
	
	int (^changesetBlock)(id key);
	
	CFMutableDictionaryRef local_cfdict;
	
	BOOL isReadWriteTransaction;
	
	__unsafe_unretained YapLocalCacheItem *mostRecentCacheItem;
	__unsafe_unretained YapLocalCacheItem *leastRecentCacheItem;
	
	__strong YapLocalCacheItem *evictedCacheItem;
}

- (id)initWithParent:(YapSharedCache *)parent;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapSharedCache

- (id)init
{
	return [self initWithKeyClass:NULL];
}

- (id)initWithKeyClass:(Class)inKeyClass
{
	if ((self = [super init]))
	{
		if (inKeyClass == NULL)
			keyClass = [NSString class];
		else
			keyClass = inKeyClass;
		
		changesetBlocksAndTimestamps = [[NSMutableArray alloc] init];
		
		// Multiple concurrent readers, single atomic writer
		shared_queue = dispatch_queue_create("YapSharedCache", DISPATCH_QUEUE_CONCURRENT);
		
		shared_cfdict = CFDictionaryCreateMutable(kCFAllocatorDefault,
		                                          0,
		                                         &kCFTypeDictionaryKeyCallBacks,
		                                         &kCFTypeDictionaryValueCallBacks);
	}
	return self;
}

- (void)dealloc
{
	if (shared_cfdict)
		CFRelease(shared_cfdict);
	
#if NEEDS_DISPATCH_RETAIN_RELEASE
	if (shared_queue)
		dispatch_release(shared_queue);
#endif
}

- (NSUInteger)count
{
	__block NSUInteger count;
	
	dispatch_sync(shared_queue, ^{
		
		count = (NSUInteger)CFDictionaryGetCount(shared_cfdict);
	});
	
	return count;
}

- (YapSharedCacheConnection *)newConnection
{
	return [[YapSharedCacheConnection alloc] initWithParent:self];
}

/**
 * This method works in conjuction with [YapAbstractDatabase notePendingChanges:fromConnection:].
 * It allows the shared cache to update the shared data.
 *
 * The changeset block is retained until noteCommittedChangesetBlock:: is invoked.
**/
- (void)notePendingChangesetBlock:(int (^)(id key))changesetBlock
                   writeTimestamp:(NSTimeInterval)writeTimestamp
{
	// This method is invoked from (stack trace):
	//
	// - YapAbstractDatabase - notePendingChanges:fromConnection:
	// - YapAbstractDatabaseConnection - postReadWriteTransaction:
	// - YapAbstractDatabaseConnection - _readWriteWithBlock:
	//
	// In other words, it is invoked at the end of a readwrite transaction, before the sql commit is finalized.
	// The goal is to update the shared cache/dictionary before another transaction begins which uses this changeset.
	//
	// Immediately after this method executes, other YapAbstractDatabaseConnection's will receive the
	// noteCommittedChanges notification, and will begin updating their YapSharedCacheConnection via the
	// noteCommittedChangesetBlock method.
	
	dispatch_barrier_async(shared_queue, ^{
		
		// And to list of changesets (will be removed once committed)
		
		NSArray *changesetAndTimestampPair = @[ changesetBlock, @(writeTimestamp) ];
		[changesetBlocksAndTimestamps addObject:changesetAndTimestampPair];
		
		// Update shared dictionary, which allows multiple values per key.
		//
		// Each database key points to a YapSharedCacheItem.
		// Each YapSharedCacheItem contains a linked list of YapSharedCacheValue's, ordered by timestamp.
		
		NSDictionary *shared_nsdict = (__bridge NSDictionary *)shared_cfdict;
		
		[shared_nsdict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			int status = changesetBlock(key);
			if (status != 0)
			{
				// Object was deleted or modified during transaction.
				//
				// We use a method that checks for a corresponding YapSharedCacheValue with the writeTimestamp.
				// If the value exists, the value is left alone.
				// Otherwise a placeholder value (with object == nil) is inserted.
				
				__unsafe_unretained YapSharedCacheItem *sharedItem = (YapSharedCacheItem *)obj;
				
				[sharedItem markUpdatedForTimestamp:writeTimestamp];
			}
		}];
	});
}

/**
 * Returns recent changesetBlocks (and associated timestamps) since the given timestamp.
 * These changesets should be consulted when adding new YapSharedCacheItem's to the shared cache.
**/
- (NSArray *)pendingAndCommittedChangesetBlocksAndTimestampsSince:(NSTimeInterval)writeTimestamp
{
	NSMutableArray *relevantItems = [NSMutableArray arrayWithCapacity:[changesetBlocksAndTimestamps count]];
	
	for (NSArray *changesetAndTimestampPair in changesetBlocksAndTimestamps)
	{
		NSTimeInterval changesetWriteTimestamp = [[changesetAndTimestampPair objectAtIndex:1] doubleValue];
		
		if (changesetWriteTimestamp > writeTimestamp)
		{
			[relevantItems addObject:changesetAndTimestampPair];
		}
	}
	
	return relevantItems;
}

- (void)noteCommittedChangesetBlock:(int (^)(id key))changesetBlock
                     writeTimestamp:(NSTimeInterval)writeTimestamp
{
	dispatch_barrier_async(shared_queue, ^{
		
		// Remove from list of changesets (was added in notePendingChangesetBlock::)
		
		[changesetBlocksAndTimestamps removeObjectAtIndex:0];
		
		// Clean the shared dictionary by deleting stale YapSharedCacheValue's.
		
		NSDictionary *shared_nsdict = (__bridge NSDictionary *)shared_cfdict;
		
		[shared_nsdict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			int status = changesetBlock(key);
			if (status != 0)
			{
				// Object was deleted or modified during transaction.
				// All connections have updated their local cache accordingly.
				// We can now delete outdated YapSharedCacheValue's.
				
				__unsafe_unretained YapSharedCacheItem *sharedItem = (YapSharedCacheItem *)obj;
				
				[sharedItem cleanWithMinTimestamp:writeTimestamp];
			}
		}];
	});
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapSharedCacheConnection

- (id)initWithParent:(YapSharedCache *)inParent
{
	if ((self = [super init]))
	{
		parent = inParent;
		countLimit = YAP_CACHE_DEFAULT_COUNT_LIMIT;
		
		local_cfdict = CFDictionaryCreateMutable(kCFAllocatorDefault,
		                                         0,
		                                        &kCFTypeDictionaryKeyCallBacks,
		                                        &kCFTypeDictionaryValueCallBacks);
	}
	return self;
}

- (void)dealloc
{
	if (local_cfdict)
		CFRelease(local_cfdict);
	
	parent = nil;
}

#pragma mark Transaction State

- (void)startReadTransaction:(NSTimeInterval)inTimestamp
{
	NSAssert(timestamp == 0.0, @"Transaction already in progress");
	
	isReadWriteTransaction = NO;
	timestamp = inTimestamp;
}

- (void)startReadWriteTransaction:(NSTimeInterval)inNewTimestamp
                   changesetBlock:(int (^)(id key))inChangesetBlock
{
	NSAssert(timestamp == 0.0, @"Transaction already in progress");
	
	isReadWriteTransaction = YES;
	timestamp = inNewTimestamp;
	changesetBlock = inChangesetBlock;
}

- (void)endTransaction
{
	NSAssert(timestamp != 0.0, @"There is no transaction in progress");
	
	isReadWriteTransaction = NO;
	timestamp = 0.0;
}

#pragma mark Properties & Count

@synthesize sharedCache = parent;
@synthesize countLimit = countLimit;

- (void)setCountLimit:(NSUInteger)newCountLimit
{
	if (countLimit != newCountLimit)
	{
		countLimit = newCountLimit;
		
		if (countLimit == 0)
		{
			// Inifinity count limit
			return;
		}
		
		NSUInteger localCount = CFDictionaryGetCount(local_cfdict);
		if (localCount <= countLimit)
		{
			// Within count limit, nothing to evict
			return;
		}
		
		NSUInteger evictionCount = localCount - countLimit;
		
		NSMutableArray *evictedKeys = [NSMutableArray arrayWithCapacity:evictionCount];
		NSMutableArray *evictedSharedItems = [NSMutableArray arrayWithCapacity:evictionCount];
		
		for (NSUInteger i = 0; i < evictionCount; i++)
		{
			[evictedKeys addObject:leastRecentCacheItem->key];
			[evictedSharedItems addObject:leastRecentCacheItem->shared_item];
			
			leastRecentCacheItem->prev->next = nil;
			
			evictedCacheItem = leastRecentCacheItem;
			leastRecentCacheItem = leastRecentCacheItem->prev;
			
			CFDictionaryRemoveValue(local_cfdict, (const void *)evictedCacheItem->key);
			
			evictedCacheItem->prev = nil;
			evictedCacheItem->next = nil;
			evictedCacheItem->key = nil;
			evictedCacheItem->object = nil;
			evictedCacheItem->shared_item = nil;
		}
		
		dispatch_barrier_async(parent->shared_queue, ^{
			
			for (NSUInteger i = 0; i < evictionCount; i++)
			{
				YapSharedCacheItem *evictedSharedItem = [evictedSharedItems objectAtIndex:i];
					
				if (evictedSharedItem->ownerCount == 1)
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)[evictedKeys objectAtIndex:i]);
				else
					evictedSharedItem->ownerCount--;
			}
		});
	}
}

- (NSUInteger)count
{
	return CFDictionaryGetCount(local_cfdict);
}

#pragma mark Cache Access

- (id)objectForKey:(id)key
{
	NSAssert(timestamp > 0.0, @"Must be in a transaction.");
	NSAssert([key isKindOfClass:parent->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", parent->keyClass, [key class]);
	
	// Check local cache first for direct access to value.
	// If that fails we will then check the global/master cache.
	
	YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
	if (localItem)
	{
		// Local cache hit.
		// Make the item the mostRecentCacheItem.
		
		if (localItem != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list.
			//
			// Notes:
			// We fetched the item from the list,
			// so we know there's a valid mostRecentCacheItem & leastRecentCacheItem.
			// Furthermore, we know the item isn't the mostRecentCacheItem.
			
			localItem->prev->next = localItem->next;
			
			if (localItem == leastRecentCacheItem)
				leastRecentCacheItem = localItem->prev;
			else
				localItem->next->prev = localItem->prev;
			
			// Move item to beginning of linked-list
			
			localItem->prev = nil;
			localItem->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = localItem;
			mostRecentCacheItem = localItem;
		}
		
		return localItem->object;
	}
	else
	{
		// Local cache miss.
		
		if (isReadWriteTransaction)
		{
			int status = changesetBlock(key);
			if (status != 0)
			{
				// The value for this key has been deleted or modified during this transaction.
				// Ignore any previous values in shared cache.
				
				return nil;
			}
		}
		
		// Check master cache and, if found, add to local cache.
		
		__block YapSharedCacheItem *sharedItem = nil;
		__block id object = nil;
		
		dispatch_sync(parent->shared_queue, ^{
			
			sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			if (sharedItem)
			{
				// An associated item exists in the master cache.
				// However, this doesn't necessarily mean it contains an appropriate object for our timestamp.
				// For example, it may contain an object for a future timestamp.
				// Or it may be empty (with a modified/deleted "flag").
				//
				// We only care about the item if it has an object for us.
				// Otherwise we don't want to become an owner / add it to our local cache.
				
				object = [sharedItem objectForTimestamp:timestamp];
				if (object)
				{
					sharedItem->ownerCount++;
				}
			}
		});
		
		if (sharedItem && object)
		{
			// Create new item (or recycle old evicted item) and add to local cache
			
			if (evictedCacheItem)
			{
				localItem = evictedCacheItem;
				localItem->key = key;
				localItem->object = object;
				localItem->shared_item = sharedItem;
				
				evictedCacheItem = nil;
			}
			else
			{
				localItem = [[YapLocalCacheItem alloc] init];
				localItem->key = key;
				localItem->object = object;
				localItem->shared_item = sharedItem;
			}
			
			CFDictionarySetValue(local_cfdict, (const void *)key, (const void *)localItem);
			
			// Add item to beginning of linked-list
			
			localItem->next = mostRecentCacheItem;
			
			if (mostRecentCacheItem)
				mostRecentCacheItem->prev = localItem;
			
			mostRecentCacheItem = localItem;
			
			// Evict leastRecentCacheItem if needed
			
			if ((countLimit != 0) && (CFDictionaryGetCount(local_cfdict) > countLimit))
			{
				YDBLogVerbose(@"key(%@), out(%@)", key, leastRecentCacheItem->key);
				
				leastRecentCacheItem->prev->next = nil;
				
				evictedCacheItem = leastRecentCacheItem;
				leastRecentCacheItem = leastRecentCacheItem->prev;
				
				id evictedKey = evictedCacheItem->key;
				YapSharedCacheItem *evictedSharedItem = evictedCacheItem->shared_item;
				
				evictedCacheItem->prev = nil;
				evictedCacheItem->next = nil;
				evictedCacheItem->key = nil;
				evictedCacheItem->object = nil;
				evictedCacheItem->shared_item = nil;
				
				CFDictionaryRemoveValue(local_cfdict, (const void *)evictedKey);
				
				#if YAP_CACHE_DEBUG
				evictionCount++;
				#endif
				
				dispatch_barrier_async(parent->shared_queue, ^{
					
					if (evictedSharedItem->ownerCount == 1)
						CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)evictedKey);
					else
						evictedSharedItem->ownerCount--;
				});
			}
			else
			{
				if (leastRecentCacheItem == nil)
					leastRecentCacheItem = localItem;
				
				YDBLogVerbose(@"key(%@) <- new, new mostRecent [%ld of %d]",
							  key, CFDictionaryGetCount(local_cfdict), countLimit);
			}
			
			return object;
		}
		else
		{
			return nil;
		}
	}
}

- (void)setObject:(id)object forKey:(id)key
{
	NSAssert(timestamp > 0.0, @"Must be in a transaction.");
	NSAssert([key isKindOfClass:parent->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", parent->keyClass, [key class]);
	
	YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
	if (localItem)
	{
		// Add the updated object to the sharedItem.
		// The object is tied to the timestamp, so older connections will ignore it.
		
		dispatch_barrier_sync(parent->shared_queue, ^{
			
			[localItem->shared_item setObject:object forTimestamp:timestamp];
		});
		
		// Since we accessed the item, move it to the front of our access list
		
		if (localItem != mostRecentCacheItem)
		{
			// Remove item from current position in linked-list
			//
			// Notes:
			// We fetched the item from the list,
			// so we know there's a valid mostRecentCacheItem & leastRecentCacheItem.
			// Furthermore, we know the item isn't the mostRecentCacheItem.
			
			localItem->prev->next = localItem->next;
			
			if (localItem == leastRecentCacheItem)
				leastRecentCacheItem = localItem->prev;
			else
				localItem->next->prev = localItem->prev;
			
			// Move item to beginning of linked-list
			
			localItem->prev = nil;
			localItem->next = mostRecentCacheItem;
			
			mostRecentCacheItem->prev = localItem;
			mostRecentCacheItem = localItem;
			
			YDBLogVerbose(@"key(%@) <- existing, new mostRecent", key);
		}
		else
		{
			YDBLogVerbose(@"key(%@) <- existing, already mostRecent", key);
		}
	}
	else
	{
		__block YapSharedCacheItem *sharedItem = nil;
		
		dispatch_barrier_sync(parent->shared_queue, ^{
			
			sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			
			if (sharedItem)
			{
				[sharedItem setObject:object forTimestamp:timestamp];
			}
			else
			{
				sharedItem = [[YapSharedCacheItem alloc] initWithObject:object timestamp:timestamp];
				
				NSArray *recentChanges =
				    [parent pendingAndCommittedChangesetBlocksAndTimestampsSince:timestamp];
				
				[sharedItem updateWithRecentChangesetBlocksAndTimestamps:recentChanges forKey:key];
				
				CFDictionarySetValue(parent->shared_cfdict, (const void *)key, (const void *)sharedItem);
			}
		});
		
		// Create new local item (or recycle old evicted item) and add to local cache
		
		if (evictedCacheItem)
		{
			localItem = evictedCacheItem;
			localItem->key = key;
			localItem->object = object;
			localItem->shared_item = sharedItem;
			
			evictedCacheItem = nil;
		}
		else
		{
			localItem = [[YapLocalCacheItem alloc] init];
			localItem->key = key;
			localItem->object = object;
			localItem->shared_item = sharedItem;
		}
		
		CFDictionarySetValue(local_cfdict, (const void *)key, (const void *)localItem);
		
		// Add item to beginning of linked-list
		
		localItem->next = mostRecentCacheItem;
		
		if (mostRecentCacheItem)
			mostRecentCacheItem->prev = localItem;
		
		mostRecentCacheItem = localItem;
		
		// Evict leastRecentCacheItem if needed
		
		if ((countLimit != 0) && (CFDictionaryGetCount(local_cfdict) > countLimit))
		{
			YDBLogVerbose(@"key(%@), out(%@)", key, leastRecentCacheItem->key);
			
			leastRecentCacheItem->prev->next = nil;
			
			evictedCacheItem = leastRecentCacheItem;
			leastRecentCacheItem = leastRecentCacheItem->prev;
			
			id evictedKey = evictedCacheItem->key;
			YapSharedCacheItem *evictedSharedItem = evictedCacheItem->shared_item;
			
			evictedCacheItem->prev = nil;
			evictedCacheItem->next = nil;
			evictedCacheItem->key = nil;
			evictedCacheItem->object = nil;
			evictedCacheItem->shared_item = nil;
			
			CFDictionaryRemoveValue(local_cfdict, (const void *)(evictedCacheItem->key));
			
			#if YAP_CACHE_DEBUG
			evictionCount++;
			#endif
			
			dispatch_barrier_async(parent->shared_queue, ^{
				
				if (evictedSharedItem->ownerCount > 1)
					evictedSharedItem->ownerCount--;
				else
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)evictedKey);
			});
		}
		else
		{
			if (leastRecentCacheItem == nil)
				leastRecentCacheItem = localItem;
			
			YDBLogVerbose(@"key(%@) <- new, new mostRecent [%ld of %d]",
			              key, CFDictionaryGetCount(local_cfdict), countLimit);
		}
	}
}

- (void)removeObjectForKey:(id)key
{
	NSAssert([key isKindOfClass:parent->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", parent->keyClass, [key class]);
	
	// Remove item from local cache (if there), and remove from access-order linked-list
	
	YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
	if (localItem)
	{
		if (localItem->prev)
			localItem->prev->next = localItem->next;
		
		if (localItem->next)
			localItem->next->prev = localItem->prev;
		
		if (mostRecentCacheItem == localItem)
			mostRecentCacheItem = localItem->next;
		
		if (leastRecentCacheItem == localItem)
			leastRecentCacheItem = localItem->prev;
		
		CFDictionaryRemoveValue(local_cfdict, (const void *)key);
		
		dispatch_barrier_async(parent->shared_queue, ^{
			
			YapSharedCacheItem *sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			if (sharedItem)
			{
				if (sharedItem->ownerCount > 1)
					sharedItem->ownerCount--;
				else
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)key);
			}
		});
	}
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	if ([keys count] == 0) return;
	
	NSMutableArray *removedLocalKeys = [NSMutableArray arrayWithCapacity:[keys count]];
	
	for (id key in keys)
	{
		NSAssert([key isKindOfClass:parent->keyClass],
		         @"Unexpected key class. Expected %@, passed %@", parent->keyClass, [key class]);
		
		YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
		if (localItem)
		{
			if (localItem->prev)
				localItem->prev->next = localItem->next;
			
			if (localItem->next)
				localItem->next->prev = localItem->prev;
			
			if (mostRecentCacheItem == localItem)
				mostRecentCacheItem = localItem->next;
			
			if (leastRecentCacheItem == localItem)
				leastRecentCacheItem = localItem->prev;
			
			CFDictionaryRemoveValue(local_cfdict, (const void *)key);
			
			[removedLocalKeys addObject:key];
		}
	}
	
	dispatch_barrier_async(parent->shared_queue, ^{
		
		for (id key in removedLocalKeys) // Only remove keys which were removed locally
		{
			YapSharedCacheItem *sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			if (sharedItem)
			{
				if (sharedItem->ownerCount > 1)
					sharedItem->ownerCount--;
				else
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)key);
			}
		}
	});
}

- (void)removeAllObjects
{
	NSArray *removedLocalKeys = [(__bridge NSDictionary *)local_cfdict allKeys];
	
	CFDictionaryRemoveAllValues(local_cfdict);
	
	mostRecentCacheItem = nil;
	leastRecentCacheItem = nil;
	evictedCacheItem = nil;
	
	dispatch_barrier_async(parent->shared_queue, ^{
		
		for (id key in removedLocalKeys)
		{
			YapSharedCacheItem *sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			if (sharedItem)
			{
				if (sharedItem->ownerCount == 1)
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)key);
				else
					sharedItem->ownerCount--;
			}
		}
	});
}

- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))block;
{
	NSDictionary *local_nsdict = (__bridge NSDictionary *)local_cfdict;
	BOOL stop = NO;
	
	for (id key in [local_nsdict keyEnumerator])
	{
		block(key, &stop);
		
		if (stop) break;
	}
}

#pragma mark Changeset Management

/**
 * Incorporates a changeset from a sibling YapSharedCacheConnection,
 * and updates the local cache accordingly.
**/
- (void)noteCommittedChangesetBlock:(int (^)(id key))committedChangesetBlock
                     writeTimestamp:(NSTimeInterval)writeTimestamp
{
	NSDictionary *local_nsdict = (__bridge NSDictionary *)local_cfdict;
	
	// Step 1:
	// Enumerate over local cache and find keys that were deleted or updated.
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	NSMutableArray *keysToUpdate = [NSMutableArray array];
	
	for (id key in [local_nsdict keyEnumerator])
	{
		int status = committedChangesetBlock(key);
		
		if (status == -1)
			[keysToRemove addObject:key];
		else if (status == 1)
			[keysToUpdate addObject:key];
	}
	
	if ([keysToUpdate count] > 0)
	{
		// Step 2:
		// Update any keys in local cache that were updated.
		// If no update is available then add to delete list.
		
		dispatch_sync(parent->shared_queue, ^{
			
			for (id key in keysToUpdate)
			{
				YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
				
				localItem->object = [localItem->shared_item objectForTimestamp:writeTimestamp];
				if (localItem->object == nil)
				{
					[keysToRemove addObject:key];
				}
			}
		});
	}
	
	if ([keysToRemove count] > 0)
	{
		// Step 3:
		// Remove any keys from local cache that were deleted.
		
		for (id key in keysToRemove)
		{
			YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
			
			if (localItem->prev)
				localItem->prev->next = localItem->next;
			
			if (localItem->next)
				localItem->next->prev = localItem->prev;
			
			if (mostRecentCacheItem == localItem)
				mostRecentCacheItem = localItem->next;
			
			if (leastRecentCacheItem == localItem)
				leastRecentCacheItem = localItem->prev;
			
			CFDictionaryRemoveValue(local_cfdict, (const void *)key);
		}

		// Step 4:
		// Decrement ownerCount or remove items from shared cache that we deleted from local cache.
		
		dispatch_barrier_async(parent->shared_queue, ^{
			
			for (id key in keysToRemove)
			{
				YapSharedCacheItem *sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
				if (sharedItem)
				{
					if (sharedItem->ownerCount == 1)
						CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)key);
					else
						sharedItem->ownerCount--;
				}
			}
		});
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapSharedCacheValue

- (void)dealloc
{
	NSLog(@"Dealloc: <YapSharedCacheValue %@:%.4f>", (object ? @"obj" : @"nil"), lastWriteTimestamp);
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapSharedCacheValue %@:%.4f>", object, lastWriteTimestamp];
//	return [NSString stringWithFormat:@"<YapSharedCacheValue %@:%.4f>", (object ? @"obj" : @"nil"), lastWriteTimestamp];
}

@end


@implementation YapSharedCacheItem

- (id)initWithObject:(id)object timestamp:(NSTimeInterval)lastWriteTimestamp
{
	if ((self = [super init]))
	{
		YapSharedCacheValue *value = [[YapSharedCacheValue alloc] init];
		value->object = object;
		value->lastWriteTimestamp = lastWriteTimestamp;
		
		values = value;
		ownerCount = 1;
	}
	return self;
}

/**
 * Older connections (those viewing an older snapshot of the database)
 * are still able to add objects to the shared cache. But it's important that newer connections don't use
 * potentially stale data from the older connections. Thus the changeset information is required when a new value
 * is added to the shared cache. The changeset info is inspected, and if the value changes in the future,
 * then proper placeholders are added for the change.
**/
- (void)updateWithRecentChangesetBlocksAndTimestamps:(NSArray *)recentChanges forKey:(id)key
{
	for (NSArray *changesetBlockAndTimestampPair in recentChanges)
	{
		int (^changesetBlock)(id key) = (int(^)(id))[changesetBlockAndTimestampPair objectAtIndex:0];
		
		if (changesetBlock(key) != 0)
		{
			NSTimeInterval writeTimestamp = [[changesetBlockAndTimestampPair objectAtIndex:1] doubleValue];
			
			[self setObject:nil forTimestamp:writeTimestamp];
		}
	}
}

- (void)setObject:(id)object forTimestamp:(NSTimeInterval)lastWriteTimestamp
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	if (value == nil || value->lastWriteTimestamp < lastWriteTimestamp)
	{
		// Most common case.
		// We're appending the most recent value to the front of the linked list.
		
		YapSharedCacheValue *newValue = [[YapSharedCacheValue alloc] init];
		newValue->lastWriteTimestamp = lastWriteTimestamp;
		newValue->object = object;
		
		newValue->olderValue = value;
		values = newValue;
	}
	else if (value->lastWriteTimestamp == lastWriteTimestamp)
	{
		// Edge case #1.
		// The connection has set the object multiple times during a single transaction.
		
		value->object = object;
	}
	else
	{
		// Edge case #2
		// Another connection further ahead of us in lastWriteTimestamp,
		// most likely a readwrite transaction, has also set the value.
		// So we need to insert our value further back in the linked list.
		
		__unsafe_unretained YapSharedCacheValue *newerValue = value;
		__unsafe_unretained YapSharedCacheValue *olderValue = value->olderValue;
		
		while (olderValue && olderValue->lastWriteTimestamp > lastWriteTimestamp)
		{
			newerValue = olderValue;
			olderValue = olderValue->olderValue;
		}
		
		if (olderValue == nil || olderValue->lastWriteTimestamp < lastWriteTimestamp)
		{
			YapSharedCacheValue *insertedValue = [[YapSharedCacheValue alloc] init];
			insertedValue->lastWriteTimestamp = lastWriteTimestamp;
			insertedValue->object = object;
			
			insertedValue->olderValue = olderValue;
			newerValue->olderValue = insertedValue;
		}
		else // olderValue->lastWriteTimestamp == lastWriteTimestamp
		{
			olderValue->object = object;
		}
	}
}

- (id)objectForTimestamp:(NSTimeInterval)lastWriteTimestamp
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	while (value)
	{
		if (value->lastWriteTimestamp <= lastWriteTimestamp) {
			break;
		}
		else {
			value = value->olderValue;
		}
	}
	
	if (value)
		return value->object;
	else
		return nil;
}

/**
 * - If the most recent YapSharedCacheValue has a timestamp equal to the given timestamp, does nothing.
 * - If the most recent YapSharedCacheValue has a timestamp less than the given timestamp,
 *   then adds a new YapSharedCacheValue with a nil object,
**/
- (void)markUpdatedForTimestamp:(NSTimeInterval)updatedLastWriteTimestamp
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	if (value->lastWriteTimestamp < updatedLastWriteTimestamp)
	{
		YapSharedCacheValue *newValue = [[YapSharedCacheValue alloc] init];
		newValue->lastWriteTimestamp = updatedLastWriteTimestamp;
		newValue->object = nil;
		newValue->olderValue = value;
		
		values = newValue;
	}
}

/**
 * Deletes values associated with timestamps less than the given minimum.
**/
- (void)cleanWithMinTimestamp:(NSTimeInterval)minLastWriteTimestamp
{
	__unsafe_unretained YapSharedCacheValue *prvValue = nil;
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	while (value && (value->lastWriteTimestamp >= minLastWriteTimestamp))
	{
		prvValue = value;
		value = value->olderValue;
	}
	
	if (value && prvValue)
	{
		// Cleanup: delete chain of older values
		prvValue->olderValue = nil;
	}
}

- (NSString *)description
{
	NSMutableString *string = [NSMutableString stringWithCapacity:30];
	[string appendString:@"<YapSharedCacheItem:"];
	
	__unsafe_unretained YapSharedCacheValue *value = values;
	while (value)
	{
		[string appendFormat:@"%@%@:%.4f",
		                       ((value == values) ? @" " : @", "),
		                       ((value->object == nil) ? @"nil" : @"obj"),
		                       value->lastWriteTimestamp];
		
		value = value->olderValue;
	}
	
	[string appendString:@">"];
	return string;
}

@end


@implementation YapLocalCacheItem

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapLocalCacheItem[%p] key(%@)>", self, key];
}

@end
