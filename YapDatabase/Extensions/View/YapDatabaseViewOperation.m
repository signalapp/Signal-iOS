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
}

@synthesize key;
@synthesize type;
@synthesize originalIndex;
@synthesize finalIndex;

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->type = YapDatabaseViewOperationInsert;
	op->key = key;
	
	op->originalGroup = nil;                                 // invalid in insert type
	op->originalIndex = op->opOriginalIndex = NSUIntegerMax; // invalid in insert type
	
	op->finalGroup = group;
	op->finalIndex = op->opFinalIndex = index;
	
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
	
	return op;
}

+ (void)postProcessAndConsolidateOperations:(NSMutableArray *)operations
{
	NSUInteger count = [operations count];
	NSUInteger i;
	NSUInteger j;
	
	//
	// PART 1 : Post-Processing
	//
	
	// First we enumerate the items BACKWARDS,
	// and update the ORIGINAL values.
	
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
	// PART 2 : Consolidation
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
					// This is a move operation
					
					firstOperationForKey->type = YapDatabaseViewOperationMove;
					firstOperationForKey->finalIndex = lastOperationForKey->finalIndex;
					firstOperationForKey->finalGroup = lastOperationForKey->finalGroup;
					
					[operations removeObjectsAtIndexes:indexSet];
					i++;
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
		}
	}
}

- (NSString *)description
{
	if (type == YapDatabaseViewOperationDelete)
		return [NSString stringWithFormat:
		    @"<YapDatabaseViewOperation: Delete pre(%lu -> ~) post(%lu -> ~) group(%@) key(%@)",
		        (unsigned long)opOriginalIndex, (unsigned long)originalIndex, originalGroup, key];
	
	if (type == YapDatabaseViewOperationInsert)
		return [NSString stringWithFormat:
		    @"<YapDatabaseViewOperation: Insert pre(~ -> %lu) post(~ -> %lu) group(%@) key(%@)",
		        (unsigned long)opFinalIndex, (unsigned long)finalIndex, finalGroup, key];
	
	return [NSString stringWithFormat:
	    @"<YapDatabaseViewOperation: Move pre(%lu -> %lu) post(%lu -> %lu) group(%@ -> %@)key(%@)",
	        (unsigned long)opOriginalIndex, (unsigned long)opFinalIndex,
	        (unsigned long)originalIndex,   (unsigned long)finalIndex,
	        originalGroup, finalGroup, key];
}

@end
