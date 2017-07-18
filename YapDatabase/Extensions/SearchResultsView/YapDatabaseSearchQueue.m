#import "YapDatabaseSearchQueue.h"
#import "YapDatabaseSearchQueuePrivate.h"
#import "YapDatabaseAtomic.h"

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
	YAPUnfairLock lock;
	
	BOOL queueHasAbort;
	BOOL queueHasRollback;
}

- (id)init
{
	if ((self = [super init]))
	{
		queue = [[NSMutableArray alloc] init];
		lock = YAP_UNFAIR_LOCK_INIT;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enqueueQuery:(NSString *)query
{
	if (query == nil) return;
	
	YAPUnfairLockLock(&lock);
	{
		[queue addObject:[query copy]];
	}
	YAPUnfairLockUnlock(&lock);
}

- (void)abortSearchInProgressAndRollback:(BOOL)shouldRollback
{
	YAPUnfairLockLock(&lock);
	{
		YapDatabaseSearchQueueControl *control =
		  [[YapDatabaseSearchQueueControl alloc] initWithRollback:shouldRollback];
		
		[queue addObject:control];
		
		queueHasAbort = YES;
		queueHasRollback = queueHasRollback || shouldRollback;
	}
	YAPUnfairLockUnlock(&lock);
}

- (NSArray *)enqueuedQueries
{
	NSMutableArray *queries = nil;
	
	YAPUnfairLockLock(&lock);
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
	YAPUnfairLockUnlock(&lock);
	
	return queries;
}

- (NSUInteger)enqueuedQueryCount
{
	NSUInteger count = 0;
	
	YAPUnfairLockLock(&lock);
	{
		for (id obj in queue)
		{
			if ([obj isKindOfClass:[NSString class]])
			{
				count++;
			}
		}
	}
	YAPUnfairLockUnlock(&lock);
	
	return count;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)flushQueue
{
	NSString *lastQuery = nil;
	
	YAPUnfairLockLock(&lock);
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
	YAPUnfairLockUnlock(&lock);
	
	return lastQuery;
}

- (BOOL)shouldAbortSearchInProgressAndRollback:(BOOL *)shouldRollbackPtr
{
	BOOL shouldAbort = NO;
	BOOL shouldRollback = NO;
	
	YAPUnfairLockLock(&lock);
	{
		shouldAbort = queueHasAbort;
		shouldRollback = queueHasRollback;
	}
	YAPUnfairLockUnlock(&lock);
	
	if (shouldRollbackPtr) *shouldRollbackPtr = shouldRollback;
	return shouldAbort;
}

@end
