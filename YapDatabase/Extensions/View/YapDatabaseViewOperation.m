#import "YapDatabaseViewOperation.h"


@implementation YapDatabaseViewOperation
{
	id key; // consider immutable
	
	NSString *originalGroup; // mutable during consolidation
	NSString *finalGroup;    // mutable during consolidation
	
	YapDatabaseViewOperationType type; // mutable during consolidation
	
	NSUInteger opOriginalIndex;  // consider immutable
	NSUInteger opFinalIndex;     // consider immutable
	
	NSUInteger originalIndex; // mutable during post-processing
	NSUInteger finalIndex;    // mutable during post-processing
	
	NSUInteger originalSection;
	NSUInteger finalSection;
}

@synthesize key = key;
@synthesize type = type;
@synthesize originalGroup = originalGroup;
@synthesize finalGroup = finalGroup;
@synthesize originalIndex = originalIndex;
@synthesize finalIndex = finalIndex;

- (NSIndexPath *)indexPath
{
	if (type == YapDatabaseViewOperationInsert)
		return nil; // <-- You should be using newIndexPath
	else
		return [NSIndexPath indexPathForRow:originalIndex inSection:originalSection];
}

- (NSIndexPath *)newIndexPath
{
	if (type == YapDatabaseViewOperationDelete)
		return nil; // <-- You should be using indexPath
	else
		return [NSIndexPath indexPathForRow:finalIndex inSection:finalSection];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->key = key;
	op->originalGroup = originalGroup;
	op->finalGroup = finalGroup;
	op->type = type;
	op->opOriginalIndex = opOriginalIndex;
	op->opFinalIndex = opFinalIndex;
	op->originalIndex = originalIndex;
	op->finalIndex = finalIndex;
	op->originalSection = originalSection;
	op->finalSection = finalSection;
	
	return op;
}

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->type = YapDatabaseViewOperationInsert;
	op->key = key;
	
	op->originalGroup = nil;                                 // invalid in insert type
	op->originalIndex = op->opOriginalIndex = NSUIntegerMax; // invalid in insert type
	
	op->finalGroup = group;
	op->finalIndex = op->opFinalIndex = index;
	
	op->originalSection = op->finalSection = NSNotFound;
	
	return op;
}

+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->type = YapDatabaseViewOperationDelete;
	op->key = key;
	
	op->originalGroup = group;
	op->originalIndex = op->opOriginalIndex = index;
	
	op->finalGroup = nil;                    // invalid in delete type
	op->finalIndex = op->opFinalIndex = NSUIntegerMax; // invalid in delete type
	
	op->originalSection = op->finalSection = NSNotFound;
	
	return op;
}

+ (void)processAndConsolidateOperations:(NSMutableArray *)operations
{
	// Every modification to the view resulted in one or more operations being appended to an array.
	// Each modification was either an insert or a delete.
	// If a item was moved, then it is represented as a delete followed by a move.
	//
	// At the end of the transaction we have a big list of modifications that have occurred.
	// Each represents the change state AT THE MOMENT THE CHANGE TOOK PLACE.
	// This is very important to understand.
	//
	// Please see the unit tests for a bunch of examples that will shed light on the problem:
	// TestViewOperationLogic.m
	
	NSUInteger i;
	NSUInteger j;
	
	//
	// PROCESSING
	//
	
	// First we enumerate the items BACKWARDS,
	// and update the ORIGINAL values.
	
	NSUInteger count = [operations count];
	
	for (i = count; i > 0; i--)
	{
		YapDatabaseViewOperation *operation = [operations objectAtIndex:(i-1)];
		
		if (operation->type == YapDatabaseViewOperationDelete)
		{
			// A DELETE operation may affect the ORIGINAL index value of operations that occurred AFTER it,
			//  IF the later operation occurs at a greater or equal index value.  ( +1 )
			
			for (j = i; j < count; j++)
			{
				YapDatabaseViewOperation *laterOperation = [operations objectAtIndex:j];
				
				if (laterOperation->type == YapDatabaseViewOperationDelete &&
				    laterOperation->originalIndex >= operation->opOriginalIndex &&
				   [laterOperation->originalGroup isEqualToString:operation->originalGroup])
				{
					laterOperation->originalIndex += 1;
				}
			}
		}
		else // if (operation->type == YapDatabaseViewOperationInsert)
		{
			// An INSERT operation may affect the ORIGINAL index value of operations that occurred AFTER it,
			//   IF the later operation occurs at a greater or equal index value. ( -1 )
			
			for (j = i; j < count; j++)
			{
				YapDatabaseViewOperation *laterOperation = [operations objectAtIndex:j];
				
				if (laterOperation->type == YapDatabaseViewOperationDelete &&
				    laterOperation->originalIndex >= operation->opFinalIndex &&
				   [laterOperation->originalGroup isEqualToString:operation->finalGroup])
				{
					laterOperation->originalIndex -= 1;
				}
			}
		}
	}
	
	// Next we enumerate the items FORWARDS,
	// and update the FINAL values.
	
	for (i = 1; i < count; i++)
	{
		YapDatabaseViewOperation *operation = [operations objectAtIndex:i];
		
		if (operation->type == YapDatabaseViewOperationDelete)
		{
			// A DELETE operation may affect the FINAL index value of operations that occurred BEFORE it,
			//  IF the earlier operation occurs at a greater (but not equal) index value. ( -1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewOperation *earlierOperation = [operations objectAtIndex:(j-1)];
				
				if (earlierOperation->type == YapDatabaseViewOperationInsert &&
				    earlierOperation->finalIndex > operation->opOriginalIndex &&
				   [earlierOperation->finalGroup isEqualToString:operation->originalGroup])
				{
					earlierOperation->finalIndex -= 1;
				}
			}
		}
		else // if (operation->type == YapDatabaseViewOperationInsert)
		{
			// An INSERT operation may affect the FINAL index value of operations that occurred BEFORE it,
			//   IF the earlier operation occurs at a greater index value ( +1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewOperation *earlierOperation = [operations objectAtIndex:(j-1)];
				
				if (earlierOperation->type == YapDatabaseViewOperationInsert &&
				    earlierOperation->finalIndex >= operation->opFinalIndex &&
				   [earlierOperation->finalGroup isEqualToString:operation->finalGroup])
				{
					earlierOperation->finalIndex += 1;
				}
			}
		}
	}
	
	//
	// CONSOLIDATION
	//
	
	NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
	
	i = 0;
	while (i < [operations count])
	{
		YapDatabaseViewOperation *operation = [operations objectAtIndex:i];
		
		// Find later operations with the same key
		
		for (j = i+1; j < [operations count]; j++)
		{
			YapDatabaseViewOperation *laterOperation = [operations objectAtIndex:j];
			
			if ([laterOperation->key isEqual:operation->key])
			{
				[indexSet addIndex:j];
			}
		}
		
		if ([indexSet count] == 0)
		{
			i++; // continue;
		}
		else
		{
			NSUInteger lastIndexForKey = [indexSet lastIndex];
			
			YapDatabaseViewOperation *firstOperationForKey = operation;
			YapDatabaseViewOperation *lastOperationForKey = [operations objectAtIndex:lastIndexForKey];
			
			if (firstOperationForKey->type == YapDatabaseViewOperationDelete)
			{
				if (lastOperationForKey->type == YapDatabaseViewOperationDelete)
				{
					// Delete, Insert, ... , Delete
					//
					// All operations except the first are no-ops
					
					[operations removeObjectsAtIndexes:indexSet];
					i++;
				}
				else // if (lastOperationForKey->type == YapDatabaseViewOperationInsert)
				{
					// Delete, Insert
					//
					// This is a move operation.
					// However, if the final index hasn't ultimately changed, then it becomes a no-op.
					
					if (firstOperationForKey->originalIndex == lastOperationForKey->finalIndex)
					{
						// No-op (& i remains the same)
						
						[operations removeObjectsAtIndexes:indexSet];
						[operations removeObjectAtIndex:i];
					}
					else
					{
						// Move
						
						firstOperationForKey->type = YapDatabaseViewOperationMove;
						firstOperationForKey->finalIndex = lastOperationForKey->finalIndex;
						firstOperationForKey->finalGroup = lastOperationForKey->finalGroup;
						firstOperationForKey->finalSection = lastOperationForKey->finalSection;
						
						[operations removeObjectsAtIndexes:indexSet];
						i++;
					}
				}
			}
			else // if (firstOperationForKey->type == YapDatabaseViewOperationInsert)
			{
				if (lastOperationForKey->type == YapDatabaseViewOperationDelete)
				{
					// Insert, Delete
					//
					// All operations are no-ops (& i remains the same)
					
					[operations removeObjectsAtIndexes:indexSet];
					[operations removeObjectAtIndex:i];
					
				}
				else // if (lastOperationForKey->type == YapDatabaseViewOperationInsert)
				{
					// Insert, Delete, ... , Insert
					//
					// All operations except the last are no-ops
					
					[operations removeObjectsAtIndexes:indexSet];
					[operations replaceObjectAtIndex:i withObject:lastOperationForKey];
					i++;
				}
			}
			
			[indexSet removeAllIndexes];
			
		} // ([indexSet count] > 0)
		
	} // while (i < [operations count])
}

+ (void)processAndConsolidateOperations:(NSMutableArray *)operations
             withGroupToSectionMappings:(NSDictionary *)mappings
{
	//
	// PRE-PROCESSING
	//
	// Remove any items from the operations array that don't concern us.
	// That is, the mappings array will look something like this:
	// @{
	//     @"groupA" : @(0),
	//     @"groupB" : @(1)
	// }
	//
	// So operations that are in groupC can simply be dropped from the array.
	// That way we can skip any unneeded processing on them.
	
	for (NSUInteger i = [operations count]; i > 0; i--)
	{
		YapDatabaseViewOperation *operation = [operations objectAtIndex:(i-1)];
		
		if (operation->type == YapDatabaseViewOperationDelete)
		{
			NSNumber *section = [mappings objectForKey:operation->originalGroup];
			
			if (section)
				operation->originalSection = [section unsignedIntegerValue];
			else
				[operations removeObjectAtIndex:(i-1)];
		}
		else // if (operation->type == YapDatabaseViewOperationInsert)
		{
			NSNumber *section = [mappings objectForKey:operation->finalGroup];
			
			if (section)
				operation->finalSection = [section unsignedIntegerValue];
			else
				[operations removeObjectAtIndex:(i-1)];
		}
	}
	
	// PROCESSING & CONSOLIDATION
	
	[self processAndConsolidateOperations:operations];
}

- (NSString *)description
{
	if (type == YapDatabaseViewOperationDelete)
	{
		if (originalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewOperation: Delete pre(%lu -> ~) post(%lu -> ~) group(%@) key(%@)",
			        (unsigned long)opOriginalIndex, (unsigned long)originalIndex, originalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewOperation: Delete indexPath(%lu, %lu) newIndexPath(nil) group(%@) key(%@)>",
			        (unsigned long)originalSection, (unsigned long)originalIndex, originalGroup, key];
		}
	}
	else if (type == YapDatabaseViewOperationInsert)
	{
		if (finalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewOperation: Insert pre(~ -> %lu) post(~ -> %lu) group(%@) key(%@)",
			        (unsigned long)opFinalIndex, (unsigned long)finalIndex, finalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewOperation: Insert indexPath(nil) newIndexPath(%lu, %lu) group(%@) key(%@)>",
			        (unsigned long)finalSection, (unsigned long)finalIndex, finalGroup, key];
		}
	}
	else
	{
		if (originalSection == NSNotFound && finalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewOperation: Move pre(%lu -> %lu) post(%lu -> %lu) group(%@ -> %@)key(%@)",
					(unsigned long)opOriginalIndex, (unsigned long)opFinalIndex,
					(unsigned long)originalIndex,   (unsigned long)finalIndex,
					originalGroup, finalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewOperation: Move indexPath(%lu, %lu) newIndexPath(%lu, %lu) group(%@ -> %@) key(%@)",
					(unsigned long)originalSection, (unsigned long)originalIndex,
					(unsigned long)finalSection,    (unsigned long)finalIndex,
					originalGroup, finalGroup, key];
		}
	}
}

@end
