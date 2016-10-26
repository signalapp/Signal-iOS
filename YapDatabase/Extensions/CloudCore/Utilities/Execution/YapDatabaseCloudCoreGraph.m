/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreGraph.h"
#import "YapDatabaseCloudCorePrivate.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"


@implementation YapDatabaseCloudCoreGraph

@synthesize uuid = uuid;
@synthesize operations = operations;
@synthesize pipeline = pipeline;

- (instancetype)initWithUUID:(NSUUID *)inUUID operations:(NSArray<YapDatabaseCloudCoreOperation *> *)inOperations
{
	if ((self = [super init]))
	{
		uuid = inUUID ? inUUID : [NSUUID UUID];
		
		operations = [[self class] sortOperationsByPriority:inOperations];
	
		if ([self hasCircularDependency])
		{
			@throw [self circularDependencyException];
		}
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSArray *)sortOperationsByPriority:(NSArray *)operations
{
	return [operations sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
		
		__unsafe_unretained YapDatabaseCloudCoreOperation *op1 = obj1;
		__unsafe_unretained YapDatabaseCloudCoreOperation *op2 = obj2;
		
		int32_t priority1 = op1.priority;
		int32_t priority2 = op2.priority;
		
		// From the docs:
		//
		// NSOrderedAscending  : The left operand is smaller than the right operand.
		// NSOrderedDescending : The left operand is greater than the right operand.
		//
		// HOWEVER - NSArray's sort method will order the items in Ascending order.
		// But we want the highest priority item to be at index 0.
		// So we're going to reverse this.
		
		if (priority1 < priority2) return NSOrderedDescending;
		if (priority1 > priority2) return NSOrderedAscending;
		
		return NSOrderedSame;
	}];
}

- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)opUUID
{
	for (YapDatabaseCloudCoreOperation *op in operations)
	{
		if ([op.uuid isEqual:opUUID])
		{
			return op;
		}
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method allows the graph to be updated by inserting & modifying operations.
 * 
 * After modification, the graph will automatically re-sort itself.
 *
 * @param insertedOperations
 *   An array of operations that are to be added to the graph.
 * 
 * @param modifiedOperations
 *   A mapping from operationUUID to modified operation.
 *   The dictionary can include operations that don't apply to this graph.
 *   E.g. it may contain a list of every modified/replaced operation from a recent transaction.
 *   Any that don't apply to this graph will be ignored.
 * 
 * @param matchedModifiedOperations
 *   Each modified operation may or may not belong to this graph.
 *   When the method identifies ones that do, they are added to matchedOperations.
**/
- (void)insertOperations:(NSArray<YapDatabaseCloudCoreOperation *> *)insertedOperations
        modifyOperations:(NSDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *)modifiedOperations
                modified:(NSMutableArray<YapDatabaseCloudCoreOperation *> *)matchedModifiedOperations
{
	__block NSMutableIndexSet *indexesToReplace = nil;
	
	[operations enumerateObjectsUsingBlock:^(YapDatabaseCloudCoreOperation *operation, NSUInteger index, BOOL *stop) {
		
		if ([modifiedOperations objectForKey:operation.uuid])
		{
			if (indexesToReplace == nil)
				indexesToReplace = [NSMutableIndexSet indexSet];
			
			[indexesToReplace addIndex:index];
		}
	}];
	
	if ((insertedOperations.count > 0) || indexesToReplace)
	{
		NSMutableArray *newOperations = [operations mutableCopy];
		
		if (insertedOperations)
			[newOperations addObjectsFromArray:insertedOperations];
		
		[indexesToReplace enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
			
			YapDatabaseCloudCoreOperation *oldOperation = operations[index];
			YapDatabaseCloudCoreOperation *newOperation = modifiedOperations[oldOperation.uuid];
			
			[newOperations replaceObjectAtIndex:index withObject:newOperation];
			[matchedModifiedOperations addObject:newOperation];
		}];
		
		operations = [[self class] sortOperationsByPriority:newOperations];
	}
}

/**
 * Removes any operations from the graph that have been marked as completed.
**/
- (NSArray *)removeCompletedAndSkippedOperations
{
	NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
	NSMutableArray *operationsToRemove = [NSMutableArray arrayWithCapacity:1];
	
	NSUInteger index = 0;
	for (YapDatabaseCloudCoreOperation *operation in operations)
	{
		YDBCloudCoreOperationStatus status = [pipeline statusForOperationWithUUID:operation.uuid];
		
		if (status == YDBCloudOperationStatus_Completed ||
		    status == YDBCloudOperationStatus_Skipped)
		{
			[indexesToRemove addIndex:index];
			[operationsToRemove addObject:operation];
		}
		
		index++;
	}
	
	if (indexesToRemove.count > 0)
	{
		NSMutableArray *newOperations = [operations mutableCopy];
		[newOperations removeObjectsAtIndexes:indexesToRemove];
		
		operations = [newOperations copy];
	}
	
	return operationsToRemove;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Dequeue Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method searches for the next operation that can immediately be started.
 *
 * If found, sets the isStarted property to YES, and returns the next operation.
 * Otherwise returns nil.
**/
- (YapDatabaseCloudCoreOperation *)dequeueNextOperation
{
	YapDatabaseCloudCoreOperation *nextOpToStart = nil;
	
	for (YapDatabaseCloudCoreOperation *op in operations)
	{
		// Recursive depth-first search.
		// If this op dependends on another, and that op isn't completed yet, then returns that op.
		
		YapDatabaseCloudCoreOperation *opOrDepOp = [self _dequeueNextOperation:op];
		if (opOrDepOp)
		{
			YDBCloudCoreOperationStatus status = YDBCloudOperationStatus_Pending;
			BOOL isOnHold = NO;
			[pipeline getStatus:&status isOnHold:&isOnHold forOperationUUID:opOrDepOp.uuid];
			
			if ((status == YDBCloudOperationStatus_Pending) && !isOnHold)
			{
				nextOpToStart = opOrDepOp;
				break;
			}
		}
	}
	
	return nextOpToStart;
}

/**
 * Recursive helper method.
 *
 * A baseOperation cannot be started until all of its dependencies have completed (or been skipped).
 *
 * This method searches for a dependent operation that can be started.
 * If found, this dependent operation is returned.
 * 
 * Otherwise it will search for a dependent operation that is not yet completed.
 * If found, this dependent operation is returned.
 * 
 * Otherwise it will return nil, if there are no dependent operations that aren't completed.
**/
- (YapDatabaseCloudCoreOperation *)_dequeueNextOperation:(YapDatabaseCloudCoreOperation *)baseOp
{
	// Recursion - depth first search for dependent operation we can start, or that's blocking us
	{
		YapDatabaseCloudCoreOperation *dependentOpToStart = nil;
		YapDatabaseCloudCoreOperation *dependentOpNotDone = nil;
		
		for (NSUUID *depUUID in [baseOp dependencyUUIDs])
		{
			YapDatabaseCloudCoreOperation *dependentOp = [self operationWithUUID:depUUID];
			if (dependentOp)
			{
				// Recursion step.
				// Here's where we look for dependencies of dependencies of dependencies...
				//
				dependentOp = [self _dequeueNextOperation:dependentOp];
				
				if (dependentOp)
				{
					YDBCloudCoreOperationStatus status = YDBCloudOperationStatus_Pending;
					BOOL isOnHold = NO;
					[pipeline getStatus:&status isOnHold:&isOnHold forOperationUUID:dependentOp.uuid];
					
					if (status == YDBCloudOperationStatus_Pending && !isOnHold)
					{
						if (dependentOpToStart == nil)
							dependentOpToStart = dependentOp;
					}
					else if (status != YDBCloudOperationStatus_Completed &&
					         status != YDBCloudOperationStatus_Skipped)
					{
						if (dependentOpNotDone == nil)
							dependentOpNotDone = dependentOp;
					}
				}
			}
		}
		
		if (dependentOpToStart) return dependentOpToStart;
		if (dependentOpNotDone) return dependentOpNotDone;
	}
	
	// Nothing found via recursion - apply algorithm to baseOp
	{
		YDBCloudCoreOperationStatus status = YDBCloudOperationStatus_Pending;
		BOOL isOnHold = NO;
		[pipeline getStatus:&status isOnHold:&isOnHold forOperationUUID:baseOp.uuid];
		
		if (status == YDBCloudOperationStatus_Pending && !isOnHold)
			return baseOp;
		
		if (status != YDBCloudOperationStatus_Completed &&
		    status != YDBCloudOperationStatus_Skipped)
			return baseOp;
		
		return nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cicular Dependency Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)hasCircularDependency
{
	BOOL result = NO;
	
	NSMutableSet<NSUUID *> *visitedOps = [NSMutableSet setWithCapacity:operations.count];
	
	for (YapDatabaseCloudCoreOperation *op in operations)
	{
		if ([self _hasCircularDependency:op withVisitedOps:visitedOps])
		{
			result = YES;
			break;
		}
	}
	
	return result;
}

/**
 * Recursive helper method.
**/
- (BOOL)_hasCircularDependency:(YapDatabaseCloudCoreOperation *)op
                withVisitedOps:(NSMutableSet<NSUUID *> *)visitedOps
{
	if ([visitedOps containsObject:op.uuid])
	{
		return YES;
	}
	else
	{
		BOOL result = NO;
		
		[visitedOps addObject:op.uuid];
		
		for (NSUUID *depUUID in [op dependencyUUIDs])
		{
			YapDatabaseCloudCoreOperation *depOp = [self operationWithUUID:depUUID];
			if (depOp)
			{
				if ([self _hasCircularDependency:depOp withVisitedOps:visitedOps])
				{
					result = YES;
					break;
				}
			}
		}
		
		[visitedOps removeObject:op.uuid];
		
		return result;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)circularDependencyException
{
	NSString *reason = @"Circular dependency found in operations!";
	
	return [NSException exceptionWithName:@"YapDatabaseCloudCore" reason:reason userInfo:nil];
}

@end
