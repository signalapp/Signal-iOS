#import "YapDatabaseSearchQueue.h"
#import "YapDatabaseSearchQueuePrivate.h"

#import <libkern/OSAtomic.h>

@interface YapDatabaseSearchQueueControl : NSObject

- (id)initWithRollback:(BOOL)rollback;

@property (nonatomic, readonly) BOOL abort;
@property (nonatomic, readonly) BOOL rollback;

@end

@implementation YapDatabaseSearchQueueControl

@synthesize rollback = rollback;

- (id)initWithRollback:(BOOL)inRollback
{
	if ((self = [super init]))
	{
		rollback = inRollback;
	}
	return self;
}

- (BOOL)abort {
	return YES;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseSearchQueue
{
	NSMutableArray *queue;
	OSSpinLock lock;
	
	BOOL queueHasAbort;
	BOOL queueHasRollback;
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
		[queue addObject:[query copy]];
	}
	OSSpinLockUnlock(&lock);
}

- (void)abortSearchInProgressAndRollback:(BOOL)shouldRollback
{
	OSSpinLockLock(&lock);
	{
		YapDatabaseSearchQueueControl *control =
		  [[YapDatabaseSearchQueueControl alloc] initWithRollback:shouldRollback];
		
		[queue addObject:control];
		
		queueHasAbort = YES;
		queueHasRollback = queueHasRollback || shouldRollback;
	}
	OSSpinLockUnlock(&lock);
}

- (NSArray *)enqueuedQueries
{
	NSMutableArray *queries = nil;
	
	OSSpinLockLock(&lock);
	{
		queries = [NSMutableArray arrayWithCapacity:[queue count]];
		
		for (id obj in queue)
		{
			if ([obj isKindOfClass:[NSString class]])
			{
				[queries addObject:obj];
			}
		}
	}
	OSSpinLockUnlock(&lock);
	
	return queries;
}

- (NSUInteger)enqueuedQueryCount
{
	NSUInteger count = 0;
	
	OSSpinLockLock(&lock);
	{
		for (id obj in queue)
		{
			if ([obj isKindOfClass:[NSString class]])
			{
				count++;
			}
		}
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
		id lastObject = [queue lastObject];
		[queue removeAllObjects];
		
		queueHasAbort = NO;
		queueHasRollback = NO;
		
		if ([lastObject isKindOfClass:[NSString class]])
		{
			lastQuery = (NSString *)lastObject;
		}
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
		shouldAbort = queueHasAbort;
		shouldRollback = queueHasRollback;
	}
	OSSpinLockUnlock(&lock);
	
	if (shouldRollbackPtr) *shouldRollbackPtr = shouldRollback;
	return shouldAbort;
}

@end
