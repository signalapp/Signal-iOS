#import "YapDatabaseSearchQueue.h"
#import <libkern/OSAtomic.h>


@implementation YapDatabaseSearchQueue
{
	NSMutableArray *queue;
	OSSpinLock lock;
	
	BOOL abort;
	BOOL rollback;
}

- (id)init
{
	if ((self = [super init]))
	{
		queue = [[NSMutableArray alloc] init];
		lock = OS_SPINLOCK_INIT;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enqueueQuery:(NSString *)query
{
	if (query == nil) return;
	
	OSSpinLockLock(&lock);
	{
		[queue addObject:query];
	}
	OSSpinLockUnlock(&lock);
}

- (void)abortSearchInProgressAndRollback:(BOOL)shouldRollback
{
	OSSpinLockLock(&lock);
	{
		abort = YES;
		rollback = YES;
	}
	OSSpinLockUnlock(&lock);
}

- (NSArray *)enqueuedQueries
{
	NSArray *queries = nil;
	
	OSSpinLockLock(&lock);
	{
		queries = [queue copy];
	}
	OSSpinLockUnlock(&lock);
	
	return queries;
}

- (NSUInteger)enqueuedQueryCount
{
	NSUInteger count = 0;
	
	OSSpinLockLock(&lock);
	{
		count = [queue count];
	}
	OSSpinLockUnlock(&lock);
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)flushQueue
{
	NSString *lastQuery = nil;
	
	OSSpinLockLock(&lock);
	{
		lastQuery = [queue lastObject];
		[queue removeAllObjects];
	}
	OSSpinLockUnlock(&lock);
	
	return lastQuery;
}

- (BOOL)shouldAbortSearchInProgressAndRollback:(BOOL *)shouldRollbackPtr
{
	BOOL shouldAbort = NO;
	BOOL shouldRollback = NO;
	
	OSSpinLockLock(&lock);
	{
		shouldAbort = abort;
		shouldRollback = rollback;
		
		abort = rollback = NO;
	}
	OSSpinLockUnlock(&lock);
	
	if (shouldRollbackPtr) *shouldRollbackPtr = shouldRollback;
	return shouldAbort;
}

@end
