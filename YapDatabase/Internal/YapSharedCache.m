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
 * - the stored values are associated with a snapshot (which represents the last time the db was modified)
 * 
 * This class represents a single stored value and its associated snapshot.
 * It is one value contained within a linked-list of possibly multiple values for the same key.
 * The linked-list remains sorted, with the most recent value at the front of the linked-list.
**/
@interface YapSharedCacheValue : NSObject {
@public
	YapSharedCacheValue *olderValue;
	
	uint64_t snapshot;
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
 * Create a new shared cache item with the given object and snapshot.
 * It then inserts placeholders (if needed) for any changes to this object that have occurred after the given snapshot.
 *
 * The recentChanges parameter should come from [YapSharedCache pendingAndCommittedChangesetBlocksAndSnapshotsSince:].
 * 
 * Older connections (those viewing an older snapshot of the database)
 * are still able to add objects to the shared cache. But it's important that newer connections don't use
 * potentially stale data from the older connections. Thus the changeset information is required when a new value
 * is added to the shared cache. The changeset info is inspected, and if the value changes in the future,
 * then proper placeholders are added for the change.
**/
- (id)initWithObject:(id)object snapshot:(uint64_t)snapshot andRecentChanges:(NSArray *)recentChanges forKey:(id)key;

/**
 * Adds/sets the value corresponding to the given snapshot.
 * The value will only be readable by other connections with a snapshot greater-than or equal to the given snapshot.
 * This method does not delete older values associated with older snapshots.
 *
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (void)setObject:(id)object forSnapshot:(uint64_t)snapshot;

/**
 * Returns the most recently set value associated with a snapshot less-than or equal to the given snapshot.
 * 
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (id)objectForSnapshot:(uint64_t)snapshot;

/**
 * - If the most recent YapSharedCacheValue has a snapshot equal to the given snapshot, does nothing.
 * - If the most recent YapSharedCacheValue has a snapshot less than the given snapshot,
 *   then adds a new YapSharedCacheValue with a nil object.
 * 
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (void)markUpdatedForSnapshot:(uint64_t)snapshot;

/**
 * Deletes values associated with snapshots less than the given minimum.
 * 
 * A YapSharedCacheItem must only be updated from withing YapSharedCache->shared_queue.
**/
- (void)cleanWithMinSnapshot:(uint64_t)minSnapshot;

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
	NSMutableArray *changesetBlocksAndSnapshots;
	
@public
	Class keyClass;
	
	dispatch_queue_t shared_queue;
	CFMutableDictionaryRef shared_cfdict;
}

- (NSArray *)pendingAndCommittedChangesetBlocksAndSnapshotsSince:(uint64_t)snapshot;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapSharedCacheConnection () {
@private
	
	__strong YapSharedCache *parent;
	NSUInteger countLimit;
	
	uint64_t snapshot;
	
	int (^changesetBlock)(id key);
	
	CFMutableDictionaryRef local_cfdict;
	
	BOOL isReadWriteTransaction;
	
	__unsafe_unretained YapLocalCacheItem *mostRecentCacheItem;
	__unsafe_unretained YapLocalCacheItem *leastRecentCacheItem;
	
	__strong YapLocalCacheItem *evictedCacheItem;
	
#if YAP_SHARED_CACHE_STATISTICS
	NSUInteger localHitCount;
	NSUInteger sharedHitCount;
	NSUInteger missCount;
	NSUInteger evictionCount;
#endif
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
		
		changesetBlocksAndSnapshots = [[NSMutableArray alloc] init];
		
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
		
		// Concurrent access to shared_queue:
		//
		// We can read from shared_dict and from shared_item(s), but we cannot make modifications.
		// If we increment ownerCount, it must be done atomically.
		
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
                         snapshot:(uint64_t)snapshot
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
		
		// Serial access to shared_queue:
		//
		// We can freely modify shared_dict and shared_item(s).
		// Shared_items should only be removed if ownerCount drops to zero.
		
		// And to list of changesets (will be removed once committed)
		
		NSArray *changesetAndSnapshotPair = @[ changesetBlock, @(snapshot) ];
		[changesetBlocksAndSnapshots addObject:changesetAndSnapshotPair];
		
		// Update shared dictionary, which allows multiple values per key.
		//
		// Each database key points to a YapSharedCacheItem.
		// Each YapSharedCacheItem contains a linked list of YapSharedCacheValue's, ordered descending by snapshot.
		
		NSDictionary *shared_nsdict = (__bridge NSDictionary *)shared_cfdict;
		
		[shared_nsdict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			int status = changesetBlock(key);
			if (status != 0)
			{
				// Object was deleted or modified during transaction.
				//
				// We use a method that checks for a corresponding YapSharedCacheValue with the snapshot.
				// If the value exists, the value is left alone.
				// Otherwise a placeholder value (with object == nil) is inserted.
				
				__unsafe_unretained YapSharedCacheItem *sharedItem = (YapSharedCacheItem *)obj;
				
				[sharedItem markUpdatedForSnapshot:snapshot];
			}
		}];
	});
}

/**
 * Returns recent changesetBlocks (and associated snapshots) since the given snapshot.
 * These changesets should be consulted when adding new YapSharedCacheItem's to the shared cache.
**/
- (NSArray *)pendingAndCommittedChangesetBlocksAndSnapshotsSince:(uint64_t)snapshot
{
	NSMutableArray *relevantItems = [NSMutableArray arrayWithCapacity:[changesetBlocksAndSnapshots count]];
	
	for (NSArray *changesetAndSnapshotPair in changesetBlocksAndSnapshots)
	{
		uint64_t changesetSnapshot = [[changesetAndSnapshotPair objectAtIndex:1] unsignedLongLongValue];
		
		if (changesetSnapshot > snapshot)
		{
			[relevantItems addObject:changesetAndSnapshotPair];
		}
	}
	
	return relevantItems;
}

- (void)noteCommittedChangesetBlock:(int (^)(id key))changesetBlock
                           snapshot:(uint64_t)snapshot
{
	dispatch_barrier_async(shared_queue, ^{
		
		// Serial access to shared_queue:
		//
		// We can freely modify shared_dict and shared_item(s).
		// Shared_items should only be removed if ownerCount drops to zero.
		
		// Remove from list of changesets (was added in notePendingChangesetBlock::)
		
		[changesetBlocksAndSnapshots removeObjectAtIndex:0];
		
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
				
				[sharedItem cleanWithMinSnapshot:snapshot];
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

- (void)startReadTransaction:(uint64_t)inSnapshot
{
	isReadWriteTransaction = NO;
	snapshot = inSnapshot;
}

- (void)startReadWriteTransaction:(uint64_t)inSnapshot
               withChangesetBlock:(int (^)(id key))inChangesetBlock
{
	isReadWriteTransaction = YES;
	snapshot = inSnapshot;
	changesetBlock = inChangesetBlock;
}

- (void)endTransaction
{
	isReadWriteTransaction = NO;
	snapshot = 0;
	changesetBlock = NULL;
}

#pragma mark Properties & Count

@synthesize sharedCache = parent;
@synthesize countLimit = countLimit;

#if YAP_SHARED_CACHE_STATISTICS
@synthesize localHitCount = localHitCount;
@synthesize sharedHitCount = sharedHitCount;
@synthesize missCount = missCount;
@synthesize evictionCount = evictionCount;
#endif

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
		
		NSUInteger evictCount = localCount - countLimit;
		
		NSMutableArray *evictedKeys = [NSMutableArray arrayWithCapacity:evictCount];
		NSMutableArray *evictedSharedItems = [NSMutableArray arrayWithCapacity:evictCount];
		
		for (NSUInteger i = 0; i < evictCount; i++)
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
			
			#if YAP_SHARED_CACHE_STATISTICS
			evictionCount++;
			#endif
		}
		
		dispatch_barrier_async(parent->shared_queue, ^{
			
			// Serial access to shared_queue:
			//
			// We can freely modify shared_dict and shared_item(s).
			// Shared_items should only be removed if ownerCount drops to zero.
			
			for (NSUInteger i = 0; i < evictCount; i++)
			{
				YapSharedCacheItem *evictedSharedItem = [evictedSharedItems objectAtIndex:i];
				
				if (evictedSharedItem->ownerCount > 1)
					evictedSharedItem->ownerCount--;
				else
					CFDictionaryRemoveValue(parent->shared_cfdict, (const void *)[evictedKeys objectAtIndex:i]);
			}
		});
	}
}

- (NSUInteger)count
{
	return CFDictionaryGetCount(local_cfdict);
}

#if YAP_SHARED_CACHE_STATISTICS
- (void)resetStatistics
{
	localHitCount = 0;
	sharedHitCount = 0;
	missCount = 0;
	evictionCount = 0;
}
#endif

#pragma mark Cache Access

- (id)objectForKey:(id)key
{
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
		
		#if YAP_SHARED_CACHE_STATISTICS
		localHitCount++;
		#endif
		
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
				
				#if YAP_SHARED_CACHE_STATISTICS
				missCount++;
				#endif
				
				return nil;
			}
		}
		
		// Check master cache and, if found, add to local cache.
		
		__block YapSharedCacheItem *sharedItem = nil;
		__block id object = nil;
		
		dispatch_sync(parent->shared_queue, ^{
			
			// Concurrent access to shared_queue:
			//
			// We can read from shared_dict and from shared_item(s), but we cannot make modifications.
			// If we increment ownerCount, it must be done atomically.
			
			sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			if (sharedItem)
			{
				// An associated item exists in the master cache.
				// However, this doesn't necessarily mean it contains an appropriate object for our snapstho.
				// For example, it may contain an object for a future snapshot.
				// Or it may be empty (with a modified/deleted "flag").
				//
				// We only care about the item if it has an object for us.
				// Otherwise we don't want to become an owner / add it to our local cache.
				
				object = [sharedItem objectForSnapshot:snapshot];
				if (object)
				{
					// We're concurrently (within a concurrent queue without a barrier),
					// so we need to maintain thread safety.
					
					OSAtomicIncrement32(&(sharedItem->ownerCount));
				}
			}
		});
		
		if (sharedItem && object)
		{
			#if YAP_SHARED_CACHE_STATISTICS
			sharedHitCount++;
			#endif
			
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
				
				#if YAP_SHARED_CACHE_STATISTICS
				evictionCount++;
				#endif
				
				dispatch_barrier_async(parent->shared_queue, ^{
					
					// Serial access to shared_queue:
					//
					// We can freely modify shared_dict and shared_item(s).
					// Shared_items should only be removed if ownerCount drops to zero.
					
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
			
			return object;
		}
		else
		{
			#if YAP_SHARED_CACHE_STATISTICS
			missCount++;
			#endif
			
			return nil;
		}
	}
}

- (void)setObject:(id)object forKey:(id)key
{
	NSAssert([key isKindOfClass:parent->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", parent->keyClass, [key class]);
	
	YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
	if (localItem)
	{
		// Update the local value
		
		localItem->object = object;
		
		// Update the shared value.
		// The shared value is tied to the snapshot, so older connections will ignore it.
		
		dispatch_barrier_sync(parent->shared_queue, ^{
			
			// Serial access to shared_queue:
			//
			// We can freely modify shared_dict and shared_item(s).
			// Shared_items should only be removed if ownerCount drops to zero.
			
			[localItem->shared_item setObject:object forSnapshot:snapshot];
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
			
			// Serial access to shared_queue:
			//
			// We can freely modify shared_dict and shared_item(s).
			// Shared_items should only be removed if ownerCount drops to zero.
			
			sharedItem = CFDictionaryGetValue(parent->shared_cfdict, (const void *)key);
			
			if (sharedItem)
			{
				sharedItem->ownerCount++;
				[sharedItem setObject:object forSnapshot:snapshot];
			}
			else
			{
				NSArray *recentChanges =
				    [parent pendingAndCommittedChangesetBlocksAndSnapshotsSince:snapshot];
				
				sharedItem = [[YapSharedCacheItem alloc] initWithObject:object
				                                               snapshot:snapshot
				                                       andRecentChanges:recentChanges
				                                                 forKey:key];
				
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
			
			#if YAP_SHARED_CACHE_STATISTICS
			evictionCount++;
			#endif
			
			dispatch_barrier_async(parent->shared_queue, ^{
				
				// Serial access to shared_queue:
				//
				// We can freely modify shared_dict and shared_item(s).
				// Shared_items should only be removed if ownerCount drops to zero.
				
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
			
			// Serial access to shared_queue:
			//
			// We can freely modify shared_dict and shared_item(s).
			// Shared_items should only be removed if ownerCount drops to zero.
			
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
		
		// Serial access to shared_queue:
		//
		// We can freely modify shared_dict and shared_item(s).
		// Shared_items should only be removed if ownerCount drops to zero.
		
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
		
		// Serial access to shared_queue:
		//
		// We can freely modify shared_dict and shared_item(s).
		// Shared_items should only be removed if ownerCount drops to zero.
		
		for (id key in removedLocalKeys)
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
                           snapshot:(uint64_t)committedSnapshot
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
			
			// Concurrent access to shared_queue:
			// 
			// We can read from shared_dict and from shared_item(s), but we cannot make modifications.
			// If we increment ownerCount, it must be done atomically.
			
			for (id key in keysToUpdate)
			{
				YapLocalCacheItem *localItem = CFDictionaryGetValue(local_cfdict, (const void *)key);
				
				localItem->object = [localItem->shared_item objectForSnapshot:committedSnapshot];
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
			
			// Serial access to shared_queue:
			//
			// We can freely modify shared_dict and shared_item(s).
			// Shared_items should only be removed if ownerCount drops to zero.
			
			for (id key in keysToRemove)
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
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapSharedCacheValue

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapSharedCacheValue %@:%llu>", (object ? @"obj" : @"nil"), snapshot];
}

@end


@implementation YapSharedCacheItem

- (id)initWithObject:(id)object snapshot:(uint64_t)snapshot andRecentChanges:(NSArray *)recentChanges forKey:(id)key
{
	if ((self = [super init]))
	{
		YapSharedCacheValue *value = [[YapSharedCacheValue alloc] init];
		value->object = object;
		value->snapshot = snapshot;
		
		values = value;
		ownerCount = 1;
		
		for (NSArray *changesetBlockAndSnapshotPair in recentChanges)
		{
			int (^changesetBlock)(id key) = (int(^)(id))[changesetBlockAndSnapshotPair objectAtIndex:0];
			
			if (changesetBlock(key) != 0)
			{
				uint64_t changesetSnapshot = [[changesetBlockAndSnapshotPair objectAtIndex:1] unsignedLongLongValue];
				
				YapSharedCacheValue *placeholderValue = [[YapSharedCacheValue alloc] init];
				placeholderValue->snapshot = changesetSnapshot;
				placeholderValue->object = nil;
				
				placeholderValue->olderValue = values;
				values = placeholderValue;
			}
		}
	}
	return self;
}

- (void)setObject:(id)object forSnapshot:(uint64_t)snapshot
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	if (value == nil || value->snapshot < snapshot)
	{
		// Most common case.
		// We're appending the most recent value to the front of the linked list.
		
		YapSharedCacheValue *newValue = [[YapSharedCacheValue alloc] init];
		newValue->snapshot = snapshot;
		newValue->object = object;
		
		newValue->olderValue = value;
		values = newValue;
	}
	else if (value->snapshot == snapshot)
	{
		// Edge case #1.
		// The connection has set the object multiple times during a single transaction.
		
		value->object = object;
	}
	else
	{
		// Edge case #2
		// Another connection further ahead of us in snapshot,
		// most likely a readwrite transaction, has also set the value.
		// So we need to insert our value further back in the linked list.
		
		__unsafe_unretained YapSharedCacheValue *newerValue = value;
		__unsafe_unretained YapSharedCacheValue *olderValue = value->olderValue;
		
		while (olderValue && olderValue->snapshot > snapshot)
		{
			newerValue = olderValue;
			olderValue = olderValue->olderValue;
		}
		
		if (olderValue == nil || olderValue->snapshot < snapshot)
		{
			YapSharedCacheValue *insertedValue = [[YapSharedCacheValue alloc] init];
			insertedValue->snapshot = snapshot;
			insertedValue->object = object;
			
			insertedValue->olderValue = olderValue;
			newerValue->olderValue = insertedValue;
		}
		else // olderValue->snapshot == snapshot
		{
			olderValue->object = object;
		}
	}
}

- (id)objectForSnapshot:(uint64_t)snapshot
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	while (value)
	{
		if (value->snapshot <= snapshot) {
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
 * - If the most recent YapSharedCacheValue has a snapshot equal to the given snapshot, does nothing.
 * - If the most recent YapSharedCacheValue has a snapshot less than the given snapshot,
 *   then adds a new YapSharedCacheValue with a nil object,
**/
- (void)markUpdatedForSnapshot:(uint64_t)snapshot
{
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	if (value->snapshot < snapshot)
	{
		YapSharedCacheValue *newValue = [[YapSharedCacheValue alloc] init];
		newValue->snapshot = snapshot;
		newValue->object = nil;
		newValue->olderValue = value;
		
		values = newValue;
	}
}

/**
 * Deletes values associated with snapshots less than the given minimum.
**/
- (void)cleanWithMinSnapshot:(uint64_t)minSnapshot
{
	__unsafe_unretained YapSharedCacheValue *prvValue = nil;
	__unsafe_unretained YapSharedCacheValue *value = values;
	
	while (value && (value->snapshot >= minSnapshot))
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
	[string appendFormat:@"<YapSharedCacheItem[%p]: ownerCount(%i)", self, ownerCount];
	
	__unsafe_unretained YapSharedCacheValue *value = values;
	while (value)
	{
		[string appendFormat:@"%@%@:%llu",
		                       ((value == values) ? @" " : @", "),
		                       ((value->object == nil) ? @"nil" : @"obj"),
		                       value->snapshot];
		
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
