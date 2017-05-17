/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseCloudCorePrivate.h"
#import "YapDatabaseLogging.h"

#import <libkern/OSAtomic.h>

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG && robbie_hanson
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE; // | YDB_LOG_FLAG_TRACE;
#elif DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

NSString *const YDBCloudCorePipelineQueueChangedNotification = @"YDBCloudCorePipelineQueueChangedNotification";
NSString *const YDBCloudCorePipelineSuspendCountChangedNotification = @"YDBCloudCorePipelineSuspendCountChangedNotification";

NSString *const YDBCloudCore_EphemeralKey_Status   = @"status";
NSString *const YDBCloudCore_EphemeralKey_Hold     = @"hold";


@implementation YapDatabaseCloudCorePipeline
{
	NSUInteger suspendCount;
	OSSpinLock suspendCountLock;
	
	dispatch_queue_t queue;
	void *IsOnQueueKey;
	
	id ephemeralInfoSharedKeySet;
	
	NSMutableDictionary<NSUUID *, NSMutableDictionary *> *ephemeralInfo; // must only be accessed/modified within queue
	NSMutableArray<YapDatabaseCloudCoreGraph *> *graphs;                 // must only be accessed/modified within queue
	NSMutableSet<NSUUID *> *startedOpUUIDs;                              // must only be accessed/modified within queue
	
	int needsStartNextOperationFlag; // access/modify via OSAtomic
	
	dispatch_source_t holdTimer;
	BOOL holdTimerSuspended;
}

@synthesize name = name;
@synthesize delegate = delegate;

@synthesize previousNames = previousNames;
@synthesize maxConcurrentOperationCount = _atomic_maxConcurrentOperationCount;

@synthesize rowid = rowid;

- (instancetype)init
{
	return [self initWithName:nil delegate:nil];
}

- (instancetype)initWithName:(NSString *)inName delegate:(id <YapDatabaseCloudCorePipelineDelegate>)inDelegate
{
	if (!inName || !inDelegate)
	{
		YDBLogWarn(@"Init method requires valid name & delegate !");
		return nil;
	}
	
	if ((self = [super init]))
	{
		name = [inName copy];
		delegate = inDelegate;
		
		suspendCountLock = OS_SPINLOCK_INIT;
		
		queue = dispatch_queue_create("YapDatabaseCloudCorePipeline", DISPATCH_QUEUE_SERIAL);
		
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		ephemeralInfoSharedKeySet = [NSDictionary sharedKeySetForKeys:@[
		  YDBCloudCore_EphemeralKey_Status,
		  YDBCloudCore_EphemeralKey_Hold
		]];
		
		ephemeralInfo    = [[NSMutableDictionary alloc] initWithCapacity:8];
		graphs           = [[NSMutableArray alloc] initWithCapacity:8];
		
		startedOpUUIDs   = [[NSMutableSet alloc] initWithCapacity:8];
		
		self.maxConcurrentOperationCount = 8;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Deallocating a suspended timer will cause a crash
	if (holdTimer && holdTimerSuspended) {
		dispatch_resume(holdTimer);
		holdTimerSuspended = NO;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Searching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid
{
	return [[self _operationWithUUID:uuid] copy];
}

- (YapDatabaseCloudCoreOperation *)_operationWithUUID:(NSUUID *)uuid
{
	if (uuid == nil) return nil;
	
	__block YapDatabaseCloudCoreOperation *match = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		for (YapDatabaseCloudCoreGraph *graph in graphs)
		{
			for (YapDatabaseCloudCoreOperation *operation in graph.operations)
			{
				if ([operation.uuid isEqual:uuid])
				{
					match = operation;
					return;
				}
			}
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return match;
}

- (void)enumerateOperationsUsingBlock:(void (^)(YapDatabaseCloudCoreOperation *operation,
                                                NSUInteger graphIdx, BOOL *stop))enumBlock
{
	[self _enumerateOperationsUsingBlock:^(YapDatabaseCloudCoreOperation *operation, NSUInteger graphIdx, BOOL *stop) {
		
		enumBlock([operation copy], graphIdx, stop);
	}];
}

- (void)_enumerateOperationsUsingBlock:(void (^)(YapDatabaseCloudCoreOperation *operation,
                                                 NSUInteger graphIdx, BOOL *stop))enumBlock
{
	__block NSMutableArray<NSArray<YapDatabaseCloudCoreOperation *> *> *graphOperations = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		graphOperations = [NSMutableArray arrayWithCapacity:graphs.count];
		
		for (YapDatabaseCloudCoreGraph *graph in graphs)
		{
			[graphOperations addObject:graph.operations];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	
	NSUInteger graphIdx = 0;
	BOOL stop = NO;
	
	for (NSArray<YapDatabaseCloudCoreOperation *> *operations in graphOperations)
	{
		for (YapDatabaseCloudCoreOperation *operation in operations)
		{
			enumBlock(operation, graphIdx, &stop);
			
			if (stop) break;
		}
		
		if (stop) break;
		graphIdx++;
	}
}

- (NSUInteger)graphCount
{
	__block NSUInteger graphCount = 0;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		graphCount = graphs.count;
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return graphCount;
}

- (NSArray<NSArray<YapDatabaseCloudCoreOperation *> *> *)graphOperations
{
	__block NSMutableArray<NSArray<YapDatabaseCloudCoreOperation *> *> *graphOperations = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		graphOperations = [NSMutableArray arrayWithCapacity:graphs.count];
		
		for (YapDatabaseCloudCoreGraph *graph in graphs)
		{
			[graphOperations addObject:graph.operations];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return graphOperations;
}

- (void)getGraphUUID:(NSUUID **)outGraphUUID
       prevGraphUUID:(NSUUID **)outPrevGraphUUID
         forGraphIdx:(NSUInteger)graphIdx
{
	__block NSUUID *graphUUID = nil;
	__block NSUUID *prevGraphUUID = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		if (graphIdx < graphs.count)
		{
			YapDatabaseCloudCoreGraph *graph = graphs[graphIdx];
			graphUUID = graph.uuid;
			
			if (graphIdx > 0)
			{
				YapDatabaseCloudCoreGraph *prevGraph = graphs[graphIdx - 1];
				prevGraphUUID = prevGraph.uuid;
			}
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	if (outGraphUUID) *outGraphUUID = graphUUID;
	if (outPrevGraphUUID) *outPrevGraphUUID = prevGraphUUID;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utility Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Internal method to fetch root key/value pairs from the ephemeralInfo dictionay.
**/
- (id)_ephemeralInfoForKey:(NSString *)key operationUUID:(NSUUID *)opUUID
{
	if (key == nil) return nil;
	if (opUUID == nil) return nil;
	
	__block id result = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSMutableDictionary *opInfo = ephemeralInfo[opUUID];
		result = opInfo[key];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return result;
}

/**
 * Internal method to modify root key/value pairs in the ephemeralInfo dictionay.
**/
- (void)_setEphemeralInfo:(id)object forKey:(NSString *)key operationUUID:(NSUUID *)uuid
{
	if (key == nil) return;
	if (uuid == nil) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSMutableDictionary *opInfo = ephemeralInfo[uuid];
		if (opInfo)
		{
			opInfo[key] = object;
			
			if (!object && (opInfo.count == 0))
			{
				ephemeralInfo[uuid] = nil;
			}
		}
		else if (object)
		{
			opInfo = [NSMutableDictionary dictionaryWithSharedKeySet:ephemeralInfoSharedKeySet];
			ephemeralInfo[uuid] = opInfo;
			
			opInfo[key] = object;
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

/**
 * Internal method to fetch status & hold in an atomic manner.
**/
- (BOOL)getStatus:(YDBCloudCoreOperationStatus *)statusPtr
         isOnHold:(BOOL *)isOnHoldPtr
 forOperationUUID:(NSUUID *)opUUID
{
	__block BOOL found = NO;
	__block NSNumber *status = nil;
	__block NSDate *hold = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSMutableDictionary *opInfo = ephemeralInfo[opUUID];
		if (opInfo)
		{
			found  = YES;
			status = opInfo[YDBCloudCore_EphemeralKey_Status];
			hold   = opInfo[YDBCloudCore_EphemeralKey_Hold];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	if (statusPtr)
	{
		if (status)
			*statusPtr = (YDBCloudCoreOperationStatus)[status integerValue];
		else
			*statusPtr = YDBCloudOperationStatus_Pending;
	}
	if (isOnHoldPtr)
	{
		if (hold)
			*isOnHoldPtr = ([hold timeIntervalSinceNow] > 0.0);
		else
			*isOnHoldPtr = NO;
	}
	
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the current status for the given operation.
**/
- (YDBCloudCoreOperationStatus)statusForOperationWithUUID:(NSUUID *)opUUID
{
	NSNumber *status = [self _ephemeralInfoForKey:YDBCloudCore_EphemeralKey_Status operationUUID:opUUID];
	if (status)
		return (YDBCloudCoreOperationStatus)[status integerValue];
	else
		return YDBCloudOperationStatus_Pending;
}

/**
 * Typically you are strongly discouraged from manually starting an operation.
 * You should allow the pipeline to mange the queue, and only start operations when told to.
 *
 * However, there is one particular edge case in which is is unavoidable: background network tasks.
 * If the app is relaunched, and you discover there are network task from a previously app session,
 * you'll obviously want to avoid starting the corresponding operation again.
 * In this case, you should use this method to inform the pipeline that the operation is already started.
**/
- (void)setStatusAsStartedForOperationWithUUID:(NSUUID *)opUUID
{
	if (opUUID == nil) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[self _setEphemeralInfo:@(YDBCloudOperationStatus_Started)
		                 forKey:YDBCloudCore_EphemeralKey_Status
		          operationUUID:opUUID];
		
		[startedOpUUIDs addObject:opUUID];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // ASYNC
}

/**
 * The PipelineDelegate may invoke this method to reset a failed operation.
 * This gives control over the operation back to the pipeline,
 * and it will dispatch it back to the PipelineDelegate again when ready.
**/
- (void)setStatusAsPendingForOperationWithUUID:(NSUUID *)opUUID
{
	if (opUUID == nil) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[self _setEphemeralInfo:@(YDBCloudOperationStatus_Pending)
		                 forKey:YDBCloudCore_EphemeralKey_Status
		          operationUUID:opUUID];
		
		[startedOpUUIDs removeObject:opUUID];
		[self startNextOperationIfPossible];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // ASYNC
}

/**
 * The PipelineDelegate may invoke this method to reset a failed operation,
 * and simultaneously tell the pipeline to delay retrying it again for a period of time.
 *
 * This is typically used when implementing retry logic such as exponential backoff.
 * It works by setting a hold on the operation to [now dateByAddingTimeInterval:delay].
**/
- (void)setStatusAsPendingForOperationWithUUID:(NSUUID *)opUUID
                                    retryDelay:(NSTimeInterval)delay
{
	NSDate *hold = nil;
	if (delay > 0.0)
		hold = [NSDate dateWithTimeIntervalSinceNow:delay];
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[self _setEphemeralInfo:@(YDBCloudOperationStatus_Pending)
		                 forKey:YDBCloudCore_EphemeralKey_Status
		          operationUUID:opUUID];
		
		[self _setEphemeralInfo:hold
		                 forKey:YDBCloudCore_EphemeralKey_Hold
		          operationUUID:opUUID];
		
		[startedOpUUIDs removeObject:opUUID];
		[self updateHoldTimer];
		[self startNextOperationIfPossible];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // ASYNC
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Hold
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the current hold for the operation, or nil if there is no hold.
**/
- (NSDate *)holdDateForOperationWithUUID:(NSUUID *)opUUID
{
	return [self _ephemeralInfoForKey:YDBCloudCore_EphemeralKey_Hold operationUUID:opUUID];
}

/**
 * And operation can be put on "hold" until a specified date.
 * This is typically used in conjunction with retry logic such as exponential backoff.
 *
 * The operation won't be delegated again until the given date.
 * You can pass a nil date to remove a hold on an operation.
 *
 * @see setStatusAsPendingForOperation:withRetryDelay:
**/
- (void)setHoldDate:(NSDate *)date forOperationWithUUID:(NSUUID *)opUUID
{
	if (opUUID == nil) return;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		[self _setEphemeralInfo:date
		                 forKey:YDBCloudCore_EphemeralKey_Hold
		          operationUUID:opUUID];
		
		[self updateHoldTimer];
		[self startNextOperationIfPossible];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // ASYNC
}

/**
 * The pipeline manages its own timer, that's configured to fire when the next "hold" for an operation expires.
 * Having a single timer is more efficient when multiple operations are on hold.
**/
- (void)updateHoldTimer
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	// Create holdTimer (if needed)
	
	if (holdTimer == NULL)
	{
		holdTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
		
		__weak typeof(self) weakSelf = self;
		dispatch_source_set_event_handler(holdTimer, ^{ @autoreleasepool {
		
			__strong typeof(self) strongSelf = weakSelf;
			if (strongSelf)
			{
				[strongSelf fireHoldTimer];
			}
		}});
		
		holdTimerSuspended = YES;
	}
	
	// Calculate when to fire next
	
	__block NSDate *nextFireDate = nil;
	
	[ephemeralInfo enumerateKeysAndObjectsUsingBlock:^(NSUUID *uuid, NSMutableDictionary *opInfo, BOOL *stop) {
		
		NSDate *hold = opInfo[YDBCloudCore_EphemeralKey_Hold];
		if (hold)
		{
			if (nextFireDate == nil)
				nextFireDate = hold;
			else
				nextFireDate = [nextFireDate earlierDate:hold];
		}
	}];
	
	// Update timer
	
	if (nextFireDate)
	{
		NSTimeInterval startOffset = [nextFireDate timeIntervalSinceNow];
		if (startOffset < 0.0)
			startOffset = 0.0;
		
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (startOffset * NSEC_PER_SEC));
		
		uint64_t interval = DISPATCH_TIME_FOREVER;
		uint64_t leeway = (0.1 * NSEC_PER_SEC);
		
		dispatch_source_set_timer(holdTimer, start, interval, leeway);
		
		if (holdTimerSuspended) {
			holdTimerSuspended = NO;
			dispatch_resume(holdTimer);
		}
	}
	else
	{
		if (!holdTimerSuspended) {
			holdTimerSuspended = YES;
			dispatch_suspend(holdTimer);
		}
	}
}

/**
 * Invoked when the hold timer fires.
 * This means that one or more operations are no longer on hold, and may be re-started.
**/
- (void)fireHoldTimer
{
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	// Remove the stored hold date for any items in which: hold < now
	
	NSDate *now = [NSDate date];
	__block NSMutableArray *uuidsToRemove = nil;
	
	[ephemeralInfo enumerateKeysAndObjectsUsingBlock:^(NSUUID *uuid, NSMutableDictionary *opInfo, BOOL *stop) {
		
		NSDate *hold = opInfo[YDBCloudCore_EphemeralKey_Hold];
		if (hold)
		{
			NSTimeInterval interval = [hold timeIntervalSinceDate:now];
			if (interval <= 0)
			{
				opInfo[YDBCloudCore_EphemeralKey_Hold] = nil;
				
				if (opInfo.count == 0)
				{
					if (uuidsToRemove == nil)
						uuidsToRemove = [[NSMutableArray alloc] initWithCapacity:4];
					
					[uuidsToRemove addObject:uuid];
				}
			}
		}
	}];
	
	if (uuidsToRemove)
	{
		[ephemeralInfo removeObjectsForKeys:uuidsToRemove];
	}
	
	[self updateHoldTimer];
	[self startNextOperationIfPossible];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Suspend & Resume
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isSuspended
{
	return ([self suspendCount] > 0);
}

- (NSUInteger)suspendCount
{
	NSUInteger currentSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		currentSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	return currentSuspendCount;
}

/**
 * Increments the suspendCount.
 * All calls to 'suspend' need to be matched with an equal number of calls to 'resume'.
 *
 * @return
 *   The new suspend count.
 *   This will be 1 if the pipeline was previously active, and is now suspended due to this call.
 *   Otherwise it will be greater than one, meaning it was previously suspended,
 *   and you just incremented the suspend count.
 *
 * @see resume
 * @see suspendCount
**/
- (NSUInteger)suspend
{
	return [self suspendWithCount:1];
}

/**
 * This method operates the same as invoking the suspend method the given number of times.
 * That is, it increments the suspend count by the given number.
 *
 * If you invoke this method with a zero parameter,
 * it will simply return the current suspend count, without modifying it.
 *
 * @see suspend
 * @see suspendCount
**/
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement
{
	BOOL overflow = NO;
	NSUInteger newSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		if (suspendCount <= (NSUIntegerMax - suspendCountIncrement))
			suspendCount += suspendCountIncrement;
		else {
			suspendCount = NSUIntegerMax;
			overflow = YES;
		}
		
		newSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	if (overflow)
	{
		YDBLogWarn(@"%@ - The suspendCount has reached NSUIntegerMax!", THIS_METHOD);
	}
	else if (suspendCountIncrement > 0)
	{
		YDBLogInfo(@"=> SUSPENDED : incremented suspendCount == %lu", (unsigned long)newSuspendCount);
	}
	
	[self postSuspendCountChangedNotification];
	
	return newSuspendCount;
}

/**
 * Decrements the suspendCount.
 * All calls to 'suspend' need to be matched with an equal number of calls to 'resume'.
 *
 * @return
 *   The current suspend count.
 *   This will be 0 if the extension was previously suspended, and is now resumed due to this call.
 *   Otherwise it will be greater than one, meaning it's still suspended,
 *   and you just decremented the suspend count.
 *
 * @see suspend
 * @see suspendCount
**/
- (NSUInteger)resume
{
	BOOL underflow = 0;
	NSUInteger newSuspendCount = 0;
	
	OSSpinLockLock(&suspendCountLock);
	{
		if (suspendCount > 0)
			suspendCount--;
		else
			underflow = YES;
		
		newSuspendCount = suspendCount;
	}
	OSSpinLockUnlock(&suspendCountLock);
	
	if (underflow) {
		YDBLogWarn(@"%@ - Attempting to resume with suspendCount already at zero.", THIS_METHOD);
	}
	else
	{
		if (newSuspendCount == 0)
		{
			YDBLogInfo(@"=> RESUMED");
			[self queueStartNextOperationIfPossible];
		}
		else {
			YDBLogInfo(@"=> SUSPENDED : decremented suspendCount == %lu", (unsigned long)newSuspendCount);
		}
		
		[self postSuspendCountChangedNotification];
	}
	
	return newSuspendCount;
}

- (void)postSuspendCountChangedNotification
{
	dispatch_block_t block = ^{
		
		[[NSNotificationCenter defaultCenter] postNotificationName:YDBCloudCorePipelineSuspendCountChangedNotification
		                                                    object:self];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Graph Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)restoreGraphs:(NSArray *)inGraphs
{
	YDBLogAutoTrace();
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		for (YapDatabaseCloudCoreGraph *graph in inGraphs)
		{
			graph.pipeline = self;
		}
		
		[graphs addObjectsFromArray:inGraphs];
		
		if (graphs.count > 0) {
			[self startNextOperationIfPossible];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block); // ASYNC
}

- (void)processAddedGraph:(YapDatabaseCloudCoreGraph *)graph
		 insertedOperations:(NSDictionary<NSNumber *, NSArray<YapDatabaseCloudCoreOperation *> *> *)insertedOperations
       modifiedOperations:(NSDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *)modifiedOperations
{
	YDBLogAutoTrace();
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		if (graph)
		{
			graph.pipeline = self;
			[graphs addObject:graph];
			
			for (YapDatabaseCloudCoreOperation *operation in graph.operations)
			{
				[operation clearTransactionVariables];
			}
		}
		
		NSMutableArray *modifiedOperationsInPipeline = nil;
		
		if ((insertedOperations.count > 0) || (modifiedOperations.count > 0))
		{
			// The modifiedOperations dictionary contains a list of every pre-existing operation
			// that was modified/replaced in the read-write transaction.
			//
			// Each operation may or may not belong to this pipeline.
			// When we identify the ones that do, we need to add them to matchedOperations.
			
			modifiedOperationsInPipeline = [NSMutableArray array];
			
			NSUInteger graphIdx = 0;
			for (YapDatabaseCloudCoreGraph *graph in graphs)
			{
				NSArray<YapDatabaseCloudCoreOperation *> *insertedInGraph = insertedOperations[@(graphIdx)];
				
				if (insertedInGraph)
					[modifiedOperationsInPipeline addObjectsFromArray:insertedInGraph];
				
				[graph insertOperations:insertedInGraph
				       modifyOperations:modifiedOperations
				               modified:modifiedOperationsInPipeline];
				
				graphIdx++;
			}
			
			for (YapDatabaseCloudCoreOperation *operation in modifiedOperationsInPipeline)
			{
				NSNumber *pendingStatus = operation.pendingStatus;
				if (pendingStatus)
				{
					[self _setEphemeralInfo:pendingStatus
					                 forKey:YDBCloudCore_EphemeralKey_Status
					          operationUUID:operation.uuid];
				}
				
				[operation clearTransactionVariables];
			}
		}
		
		if (graph || (modifiedOperationsInPipeline.count > 0))
		{
			// Although we could do this synchronously here (since we're inside the queue),
			// it may be better to perform this task async so we don't delay
			// the readWriteTransaction (which invoked this method).
			//
			[self queueStartNextOperationIfPossible];
			
			// Notify listeners that the operation list in the queue changed.
			[self postQueueChangedNotification];
		}
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

- (YapDatabaseCloudCoreGraph *)lastGraph
{
	__block YapDatabaseCloudCoreGraph *graph = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		graph = [graphs lastObject];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return graph;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Dequeue Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method may be invoked from any thread.
 * It uses an efficient mechanism to consolidate invocations of the 'startNextOperationIfPossible' method.
 * 
 * That is, invoking this method 50 times may result in only a single invocation of 'startNextOperationIfPossible'.
**/
- (void)queueStartNextOperationIfPossible
{
	int const flagOff = 0;
	int const flagOn  = 1;
	
	BOOL didSetFlagOn = OSAtomicCompareAndSwapInt(flagOff, flagOn, &needsStartNextOperationFlag);
	
	if (didSetFlagOn)
	{
		dispatch_async(queue, ^{ @autoreleasepool {
			
			OSAtomicCompareAndSwapInt(flagOn, flagOff, &needsStartNextOperationFlag);
			
			[self startNextOperationIfPossible];
		}});
	}
}

/**
 * Core logic for starting operations via the PipelineDelegate.
**/
- (void)startNextOperationIfPossible
{
	YDBLogAutoTrace();
	NSAssert(dispatch_get_specific(IsOnQueueKey), @"Must be executed within queue");
	
	if ([self isSuspended]) {
		// Waiting to be resumed
		return;
	}
	
	YapDatabaseCloudCoreGraph *currentGraph = [graphs firstObject];
	
	// Purge any completed/skipped operations
	
	BOOL queueChanged = NO;
	while (currentGraph)
	{
		NSArray *removedOperations = [currentGraph removeCompletedAndSkippedOperations];
		if (removedOperations.count > 0)
		{
			queueChanged = YES;
			
			for (YapDatabaseCloudCoreOperation *operation in removedOperations)
			{
				[startedOpUUIDs removeObject:operation.uuid];
				[ephemeralInfo removeObjectForKey:operation.uuid];
			}
		}
		
		if (currentGraph.operations.count == 0)
		{
			[graphs removeObjectAtIndex:0];
			currentGraph = [graphs firstObject];
		}
		else
		{
			break;
		}
	}
	
	if (queueChanged) {
		[self postQueueChangedNotification];
	}
	
	if (currentGraph == nil) {
		// Waiting for another graph to be added
		return;
	}
	
	NSUInteger maxConcurrentOperationCount = self.maxConcurrentOperationCount;
	if (maxConcurrentOperationCount == 0)
		maxConcurrentOperationCount = NSUIntegerMax;
	
	if (startedOpUUIDs.count >= maxConcurrentOperationCount)
	{
		// Waiting for one or more operations to complete
		return;
	}
	
	YapDatabaseCloudCoreOperation *nextOp = [currentGraph dequeueNextOperation];
	if (nextOp)
	{
		__weak YapDatabaseCloudCorePipeline *weakSelf = self;
		dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		
		do {
			
			[self _setEphemeralInfo:@(YDBCloudOperationStatus_Started)
			                 forKey:YDBCloudCore_EphemeralKey_Status
			          operationUUID:nextOp.uuid];
			
			YapDatabaseCloudCoreOperation *opToStart = nextOp;
			dispatch_async(globalQueue, ^{ @autoreleasepool {
				
				__strong YapDatabaseCloudCorePipeline *strongSelf = weakSelf;
				if (strongSelf) {
					[strongSelf.delegate startOperation:opToStart forPipeline:strongSelf];
				}
			}});
			
			[startedOpUUIDs addObject:nextOp.uuid];
			if (startedOpUUIDs.count >= maxConcurrentOperationCount) {
				break;
			}
			
			nextOp = [currentGraph dequeueNextOperation];
			
		} while (nextOp);
	}
}

- (void)postQueueChangedNotification
{
	dispatch_block_t block = ^{
		
		[[NSNotificationCenter defaultCenter] postNotificationName:YDBCloudCorePipelineQueueChangedNotification
		                                                    object:self];
	};
	
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

@end
