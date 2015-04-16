#import "YapMemoryTable.h"


/**
 * There may be multiple simulatneous database transactions, each using different atomic snapshots.
 * In other words, the value in the database at snapshot A may be different than at snapshot B.
 * Each value is correct, and depends entirely on the snapshot being used by the transaction.
 *
 * This presents a unique property of the table:
 * - the table may store multiple values for a single key.
 * - the stored values are associated with a snapshot
 *
 * This class represents a single stored value and its associated snapshot.
 * It is one value contained within a linked-list of possibly multiple values for the same key.
 * The linked-list remains sorted, with the most recent value at the front of the linked-list.
 **/
@interface YapMemoryTableValue : NSObject {
@public
	YapMemoryTableValue *olderValue;
	
	uint64_t snapshot;
	id object;
}

@end

@implementation YapMemoryTableValue

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapMemoryTableValue[%p]: snapshot(%llu), olderValue(%p), object(%@)>",
	        self, snapshot, olderValue, object];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapMemoryTable () {
@public
	
	Class keyClass;
	
	NSMutableDictionary *dict;
	
	dispatch_queue_t queue;
	void *IsOnQueueKey;
	
	NSMutableArray *snapshots;
	NSMutableArray *changes;
	NSLock *lock;
}
@end

@interface YapMemoryTableTransaction () {
@public
	
	__unsafe_unretained YapMemoryTable *table;
	
	uint64_t snapshot;
	BOOL isReadWriteTransaction;
	
	NSMutableSet *changedKeys;
}
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapMemoryTable

- (id)initWithKeyClass:(Class)inKeyClass
{
	if ((self = [super init]))
	{
		keyClass = inKeyClass;
		
		dict = [[NSMutableDictionary alloc] init];
		queue = dispatch_queue_create("YapMemoryTable", DISPATCH_QUEUE_CONCURRENT);
		
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		snapshots = [[NSMutableArray alloc] init];
		changes   = [[NSMutableArray alloc] init];
		lock = [[NSLock alloc] init];
	}
	return self;
}
- (YapMemoryTableTransaction *)newReadTransactionWithSnapshot:(uint64_t)snapshot
{
	YapMemoryTableTransaction *transaction = [[YapMemoryTableTransaction alloc] init];
	transaction->table = self;
	transaction->snapshot = snapshot;
	transaction->isReadWriteTransaction = NO;
	
	return transaction;
}

- (YapMemoryTableTransaction *)newReadWriteTransactionWithSnapshot:(uint64_t)snapshot
{
	YapMemoryTableTransaction *transaction = [[YapMemoryTableTransaction alloc] init];
	transaction->table = self;
	transaction->snapshot = snapshot;
	transaction->isReadWriteTransaction = YES;
	
	return transaction;
}

- (void)asyncCheckpoint:(int64_t)minSnapshot
{
	dispatch_barrier_async(queue, ^{ @autoreleasepool {
		
		while (YES) // using manual return
		{
			int64_t snapshot = 0;
			NSSet *changedKeys = nil;
			
			[lock lock];
			
			if ([snapshots count] > 0)
			{
				snapshot = [[snapshots objectAtIndex:0] longLongValue];
				
				if (snapshot < minSnapshot)
				{
					changedKeys = [changes objectAtIndex:0];
			
					[snapshots removeObjectAtIndex:0];
					[changes removeObjectAtIndex:0];
				}
			}
			
			[lock unlock];
			
			if (changedKeys == nil)
			{
				return; // Done
			}
			
			for (id key in changedKeys)
			{
				BOOL hasObject = NO;
				
				__unsafe_unretained YapMemoryTableValue *prvValue = nil;
				__unsafe_unretained YapMemoryTableValue *value = [dict objectForKey:key];
				
				while (value && value->snapshot >= (uint64_t)minSnapshot)
				{
					if (hasObject == NO)
						hasObject = (value->object != nil);
					
					prvValue = value;
					value = value->olderValue;
				}
				
				if (value)
				{
					if (prvValue)
					{
						// The 'value' is not the latest value
						
						if (!hasObject)
						{
							// All values >= minSnapshot represent a deletion.
							// So we can just dump all values.
							
							[dict removeObjectForKey:key];
						}
						else
						{
							// There are values >= minSnapshot in the table.
							// So the stay in the dict.
							// But everything older than minSnapshot can go.
							
							prvValue->olderValue = nil;
						}
					}
					else
					{
						// The 'value' is the latest value
						
						if (value->object == nil)
						{
							// The 'value' is the latest value.
							// And 'value' represents a deletion.
							// So we can just dump all values.
							
							[dict removeObjectForKey:key];
						}
						else
						{
							// The 'value' is the latest value.
							// So it stays in the dict.
							// But everything after it can go (if there is anything).
							
							value->olderValue = nil;
						}
					}
					
				} // end: if (value)
				
			} // end: for (id key in changedKeys)
			
		} // end: while (YES)
	}});
}

- (void)asyncRollback:(int64_t)snapshot withChanges:(NSSet *)changedKeys
{
	dispatch_barrier_async(queue, ^{ @autoreleasepool {
		
		for (id key in changedKeys)
		{
			__unsafe_unretained YapMemoryTableValue *value = [dict objectForKey:key];
			
			if (value && value->snapshot == (uint64_t)snapshot)
			{
				if (value->olderValue == nil)
				{
					[dict removeObjectForKey:key];
				}
				else
				{
					[dict setObject:value->olderValue forKey:key];
				}
			}
		}
	}});
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapMemoryTableTransaction

@synthesize snapshot = snapshot;
@synthesize isReadWriteTransaction = isReadWriteTransaction;

- (id)objectForKey:(id)key
{
	NSAssert([key isKindOfClass:table->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", table->keyClass, [key class]);
	
	__block id result = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__unsafe_unretained YapMemoryTableValue *value = [table->dict objectForKey:key];
		
		while (value)
		{
			if (value->snapshot <= snapshot)
			{
				result = value->object;
				break;
			}
			else
			{
				value = value->olderValue;
			}
		}
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_sync(table->queue, block);
	
	return result;
}

- (void)enumerateKeysWithBlock:(void (^)(id key, BOOL *stop))userBlock
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[table->dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			__unsafe_unretained YapMemoryTableValue *value = (YapMemoryTableValue *)obj;
			while (value)
			{
				if (value->snapshot <= snapshot)
				{
					if (value->object)
					{
						userBlock(key, stop);
					}
					break;
				}
				else
				{
					value = value->olderValue;
				}
			}
		}];
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_sync(table->queue, block);
}

- (void)enumerateKeysAndObjectsWithBlock:(void (^)(id key, id obj, BOOL *stop))userBlock
{
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[table->dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			__unsafe_unretained YapMemoryTableValue *value = (YapMemoryTableValue *)obj;
			while (value)
			{
				if (value->snapshot <= snapshot)
				{
					if (value->object)
					{
						userBlock(key, value->object, stop);
					}
					break;
				}
				else
				{
					value = value->olderValue;
				}
			}
		}];
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_sync(table->queue, block);
}

- (void)setObject:(id)object forKey:(id)key
{
	NSAssert([key isKindOfClass:table->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", table->keyClass, [key class]);
	
	if (!isReadWriteTransaction) {
		NSAssert(NO, @"Cannot modify table in read-only transaction.");
		return;
	}
	
	if (changedKeys == nil)
		changedKeys = [[NSMutableSet alloc] init];
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__unsafe_unretained YapMemoryTableValue *value = [table->dict objectForKey:key];
		
		if (value && value->snapshot == snapshot)
		{
			// We've already updated this key during this transaction.
			
			value->object = object;
		}
		else
		{
			// First update for this key during this transaction.
			
			YapMemoryTableValue *newValue = [[YapMemoryTableValue alloc] init];
			newValue->olderValue = value;
			newValue->object = object;
			newValue->snapshot = snapshot;
			
			[table->dict setObject:newValue forKey:key];
			
			[changedKeys addObject:key];
		}
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_barrier_sync(table->queue, block);
}

- (void)removeObjectForKey:(id)key
{
	NSAssert([key isKindOfClass:table->keyClass],
	         @"Unexpected key class. Expected %@, passed %@", table->keyClass, [key class]);
	
	if (!isReadWriteTransaction) {
		NSAssert(NO, @"Cannot modify table in read-only transaction.");
		return;
	}
	
	if (changedKeys == nil)
		changedKeys = [[NSMutableSet alloc] init];
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		__unsafe_unretained YapMemoryTableValue *value = [table->dict objectForKey:key];
		
		if (value)
		{
			if (value->snapshot == snapshot)
			{
				// We've already updated this key during this transaction.
				
				if (value->olderValue == nil)
				{
					// Removing a previously set value within this transaction.
					// And there are no other values outside this transaction.
					
					[table->dict removeObjectForKey:key];
					
					[changedKeys removeObject:key];
				}
				else
				{
					// Updating a previously set value within this transaction.
					// But there are other values for older snapshots.
					
					value->object = nil;
				}
			}
			else
			{
				// First update for this key during this transaction.
				
				YapMemoryTableValue *newValue = [[YapMemoryTableValue alloc] init];
				newValue->olderValue = value;
				newValue->object = nil;
				newValue->snapshot = snapshot;
				
				[table->dict setObject:newValue forKey:key];
				
				[changedKeys addObject:key];
			}
		}
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_barrier_sync(table->queue, block);
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	if (!isReadWriteTransaction) {
		NSAssert(NO, @"Cannot modify table in read-only transaction.");
		return;
	}
	
	if (changedKeys == nil)
		changedKeys = [[NSMutableSet alloc] init];
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		for (id key in keys)
		{
			NSAssert([key isKindOfClass:table->keyClass],
			         @"Unexpected key class. Expected %@, passed %@", table->keyClass, [key class]);
			
			__unsafe_unretained YapMemoryTableValue *value = [table->dict objectForKey:key];
			
			if (value)
			{
				if (value->snapshot == snapshot)
				{
					// We've already updated this key during this transaction.
					
					if (value->olderValue == nil)
					{
						// Removing a previously set value within this transaction.
						// And there are no other values outside this transaction.
						
						[table->dict removeObjectForKey:key];
						
						[changedKeys removeObject:key];
					}
					else
					{
						// Updating a previously set value within this transaction.
						// But there are other values for older snapshots.
						
						value->object = nil;
					}
				}
				else
				{
					// First update for this key during this transaction.
					
					YapMemoryTableValue *newValue = [[YapMemoryTableValue alloc] init];
					newValue->olderValue = value;
					newValue->object = nil;
					newValue->snapshot = snapshot;
					
					[table->dict setObject:newValue forKey:key];
					
					[changedKeys addObject:key];
				}
			}
		}
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_barrier_sync(table->queue, block);
}

- (void)removeAllObjects
{
	NSAssert(isReadWriteTransaction, @"Cannot modify table in read-only transaction.");
	
	if (changedKeys == nil)
		changedKeys = [[NSMutableSet alloc] init];
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		// Grab all keys
		NSArray *keys = [table->dict allKeys];
		
		// Mark all keys as changed
		[changedKeys addObjectsFromArray:keys];
		
		// Now enumerate all the keys, and update accordingly
		for (id key in keys)
		{
			__unsafe_unretained YapMemoryTableValue *value = [table->dict objectForKey:key];
			
			if (value->snapshot == snapshot)
			{
				// We've already updated this key during this transaction.
				
				if (value->olderValue == nil)
				{
					// Removing a previously set value within this transaction.
					// And there are no other values outside this transaction.
					
					[table->dict removeObjectForKey:key];
					[changedKeys removeObject:key];
				}
				else
				{
					// Updating a previously set value within this transaction.
					// But there are other values for older snapshots.
					
					value->object = nil;
				}
			}
			else
			{
				// First update for this key during this transaction.
				
				YapMemoryTableValue *newValue = [[YapMemoryTableValue alloc] init];
				newValue->olderValue = value;
				newValue->object = nil;
				newValue->snapshot = snapshot;
				
				[table->dict setObject:newValue forKey:key];
			}
		}
	}};
	
	if (dispatch_get_specific(table->IsOnQueueKey))
		block();
	else
		dispatch_barrier_sync(table->queue, block);
}

- (void)accessWithBlock:(dispatch_block_t)block
{
	dispatch_sync(table->queue, block);
}

- (void)modifyWithBlock:(dispatch_block_t)block
{
	dispatch_barrier_sync(table->queue, block);
}

- (void)commit
{
	if (isReadWriteTransaction && [changedKeys count] > 0)
	{
		[table->lock lock];
		{
			[table->snapshots addObject:@(snapshot)];
			[table->changes addObject:changedKeys];
		}
		[table->lock unlock];
	}
}

- (void)rollback
{
	if (isReadWriteTransaction && [changedKeys count] > 0)
	{
		[table asyncRollback:snapshot withChanges:changedKeys];
	}
}

@end
