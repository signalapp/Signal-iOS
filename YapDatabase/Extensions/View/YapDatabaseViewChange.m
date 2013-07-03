#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewChangePrivate.h"


@implementation YapDatabaseViewChange
{
	id key; // consider immutable
	
	NSString *originalGroup; // mutable during consolidation
	NSString *finalGroup;    // mutable during consolidation
	
	YapDatabaseViewChangeType type; // mutable during consolidation
	int columns;                       // mutable during consolidation
	
	NSUInteger opOriginalIndex;  // consider immutable
	NSUInteger opFinalIndex;     // consider immutable
	
	NSUInteger originalIndex; // mutable during post-processing
	NSUInteger finalIndex;    // mutable during post-processing
	
	NSUInteger originalSection;
	NSUInteger finalSection;
}

@synthesize type = type;
@synthesize modifiedColumns = columns;
@synthesize originalGroup = originalGroup;
@synthesize finalGroup = finalGroup;
@synthesize originalIndex = originalIndex;
@synthesize finalIndex = finalIndex;

- (NSIndexPath *)indexPath
{
	if (type == YapDatabaseViewChangeInsert) {
		return nil; // <-- You should be using newIndexPath
	}
	else {
	#if TARGET_OS_IPHONE
		return [NSIndexPath indexPathForRow:originalIndex inSection:originalSection];
	#else
		NSUInteger indexes[] = {originalSection, originalIndex};
		return [NSIndexPath indexPathWithIndexes:indexes length:2];
	#endif
	}
}

- (NSIndexPath *)newIndexPath
{
	if (type == YapDatabaseViewChangeDelete || type == YapDatabaseViewChangeUpdate) {
		return nil; // <-- You should be using indexPath
	}
	else {
	#if TARGET_OS_IPHONE
		return [NSIndexPath indexPathForRow:finalIndex inSection:finalSection];
	#else
		NSUInteger indexes[] = {finalSection, finalIndex};
		return [NSIndexPath indexPathWithIndexes:indexes length:2];
	#endif
	}
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewChange *op = [[YapDatabaseViewChange alloc] init];
	op->key = key;
	op->originalGroup = originalGroup;
	op->finalGroup = finalGroup;
	op->type = type;
	op->columns = columns;
	op->opOriginalIndex = opOriginalIndex;
	op->opFinalIndex = opFinalIndex;
	op->originalIndex = originalIndex;
	op->finalIndex = finalIndex;
	op->originalSection = originalSection;
	op->finalSection = finalSection;
	
	return op;
}

+ (YapDatabaseViewChange *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewChange *op = [[YapDatabaseViewChange alloc] init];
	op->type = YapDatabaseViewChangeInsert;
	op->key = key;
	op->columns = YapDatabaseViewChangeColumnObject | YapDatabaseViewChangeColumnMetadata;
	
	op->originalGroup = nil;                                 // invalid in insert type
	op->originalIndex = op->opOriginalIndex = NSUIntegerMax; // invalid in insert type
	
	op->finalGroup = group;
	op->finalIndex = op->opFinalIndex = index;
	
	op->originalSection = op->finalSection = NSNotFound;
	
	return op;
}

+ (YapDatabaseViewChange *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewChange *op = [[YapDatabaseViewChange alloc] init];
	op->type = YapDatabaseViewChangeDelete;
	op->key = key;
	op->columns = YapDatabaseViewChangeColumnObject | YapDatabaseViewChangeColumnMetadata;
	
	op->originalGroup = group;
	op->originalIndex = op->opOriginalIndex = index;
	
	op->finalGroup = nil;                              // invalid in delete type
	op->finalIndex = op->opFinalIndex = NSUIntegerMax; // invalid in delete type
	
	op->originalSection = op->finalSection = NSNotFound;
	
	return op;
}

+ (YapDatabaseViewChange *)updateKey:(id)key columns:(int)flags inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewChange *op = [[YapDatabaseViewChange alloc] init];
	op->type = YapDatabaseViewChangeUpdate;
	op->key = key;
	op->columns = flags;
	
	op->originalGroup = group;
	op->originalIndex = op->opOriginalIndex = index;
	
	op->finalGroup = group;
	op->finalIndex = op->opFinalIndex = index;
	
	op->originalSection = op->finalSection = NSNotFound;
	
	return op;
}

+ (void)processAndConsolidateChanges:(NSMutableArray *)changes
{
	// Every modification to the view resulted in one or more operations being appended to an array.
	// Each modification was either an insert, delete or update.
	// If a item was moved, then it is represented as a delete followed by an insert.
	//
	// At the end of the transaction we have a big list of modifications that have occurred.
	// Each represents the change state AT THE MOMENT THE CHANGE TOOK PLACE.
	// This is very important to understand.
	//
	// Please see the unit tests for a bunch of examples that will shed light on the setup and algorithm:
	// TestViewChangeLogic.m
	
	NSUInteger i;
	NSUInteger j;
	
	//
	// PROCESSING
	//
	
	// First we enumerate the items BACKWARDS,
	// and update the ORIGINAL values.
	
	NSUInteger count = [changes count];
	
	for (i = count; i > 0; i--)
	{
		YapDatabaseViewChange *change = [changes objectAtIndex:(i-1)];
		
		if (change->type == YapDatabaseViewChangeDelete)
		{
			// A DELETE operation may affect the ORIGINAL index value of operations that occurred AFTER it,
			//  IF the later operation occurs at a greater or equal index value.  ( +1 )
			
			for (j = i; j < count; j++)
			{
				YapDatabaseViewChange *laterChange = [changes objectAtIndex:j];
				
				if (laterChange->type == YapDatabaseViewChangeDelete ||
					laterChange->type == YapDatabaseViewChangeUpdate)
				{
					if (laterChange->originalIndex >= change->opOriginalIndex &&
					   [laterChange->originalGroup isEqualToString:change->originalGroup])
					{
						laterChange->originalIndex += 1;
					}
				}
			}
		}
		else if (change->type == YapDatabaseViewChangeInsert)
		{
			// An INSERT operation may affect the ORIGINAL index value of operations that occurred AFTER it,
			//   IF the later operation occurs at a greater or equal index value. ( -1 )
			
			for (j = i; j < count; j++)
			{
				YapDatabaseViewChange *laterChange = [changes objectAtIndex:j];
				
				if (laterChange->type == YapDatabaseViewChangeDelete ||
				    laterChange->type == YapDatabaseViewChangeUpdate)
				{
					if (laterChange->originalIndex >= change->opFinalIndex &&
					   [laterChange->originalGroup isEqualToString:change->finalGroup])
					{
						laterChange->originalIndex -= 1;
					}
				}
			}
		}
	}
	
	// Next we enumerate the items FORWARDS,
	// and update the FINAL values.
	
	for (i = 1; i < count; i++)
	{
		YapDatabaseViewChange *change = [changes objectAtIndex:i];
		
		if (change->type == YapDatabaseViewChangeDelete)
		{
			// A DELETE operation may affect the FINAL index value of operations that occurred BEFORE it,
			//  IF the earlier operation occurs at a greater (but not equal) index value. ( -1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewChange *earlierChange = [changes objectAtIndex:(j-1)];
				
				if (earlierChange->type == YapDatabaseViewChangeInsert ||
				    earlierChange->type == YapDatabaseViewChangeUpdate  )
				{
					if (earlierChange->finalIndex > change->opOriginalIndex &&
					   [earlierChange->finalGroup isEqualToString:change->originalGroup])
					{
						earlierChange->finalIndex -= 1;
					}
				}
			}
		}
		else if (change->type == YapDatabaseViewChangeInsert)
		{
			// An INSERT operation may affect the FINAL index value of operations that occurred BEFORE it,
			//   IF the earlier operation occurs at a greater index value ( +1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewChange *earlierChange = [changes objectAtIndex:(j-1)];
				
				if (earlierChange->type == YapDatabaseViewChangeInsert ||
				    earlierChange->type == YapDatabaseViewChangeUpdate)
				{
					if (earlierChange->finalIndex >= change->opFinalIndex &&
					   [earlierChange->finalGroup isEqualToString:change->finalGroup])
					{
						earlierChange->finalIndex += 1;
					}
				}
			}
		}
	}
	
	//
	// CONSOLIDATION
	//
	
	NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
	
	i = 0;
	while (i < [changes count])
	{
		YapDatabaseViewChange *firstChangeForKey = [changes objectAtIndex:i];
		
		// Find later operations with the same key
		
		for (j = i+1; j < [changes count]; j++)
		{
			YapDatabaseViewChange *laterChange = [changes objectAtIndex:j];
			
			if ([laterChange->key isEqual:firstChangeForKey->key])
			{
				firstChangeForKey->columns |= laterChange->columns;
				[indexSet addIndex:j];
			}
		}
		
		if ([indexSet count] == 0)
		{
			// Check to see if an Update turned into a Move
			
			if (firstChangeForKey->type == YapDatabaseViewChangeUpdate &&
				firstChangeForKey->originalIndex != firstChangeForKey->finalIndex)
			{
				firstChangeForKey->type = YapDatabaseViewChangeMove;
			}
			
			i++; // continue;
		}
		else
		{
			YapDatabaseViewChange *lastChangeForKey = [changes objectAtIndex:[indexSet lastIndex]];
			
			
			if (firstChangeForKey->type == YapDatabaseViewChangeDelete)
			{
				if (lastChangeForKey->type == YapDatabaseViewChangeDelete)
				{
					// Delete + Insert + ... + Delete
					//
					// All operations except the first are no-ops
					
					[changes removeObjectsAtIndexes:indexSet];
					i++;
				}
				else if (lastChangeForKey->type == YapDatabaseViewChangeInsert)
				{
					// Delete + Insert
					//
					// This is a move operation.
					// However, if the final location hasn't ultimately changed, then it becomes a no-op.
					
					if (firstChangeForKey->originalIndex == lastChangeForKey->finalIndex &&
					   [firstChangeForKey->originalGroup isEqualToString:lastChangeForKey->finalGroup])
					{
						// = Update
						//
						// The location didn't change, but the row may have been updated.
						
						firstChangeForKey->type = YapDatabaseViewChangeUpdate;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
					else
					{
						// = Move
						
						firstChangeForKey->type = YapDatabaseViewChangeMove;
						firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
						firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
						firstChangeForKey->finalSection = lastChangeForKey->finalSection;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
				}
				else if (lastChangeForKey->type == YapDatabaseViewChangeUpdate)
				{
					// Delete + Insert + ... + Update
					//
					// This is either a move or just an update.
					// It simply depends on the original and final index values.
					
					if (firstChangeForKey->originalIndex == lastChangeForKey->finalIndex &&
					   [firstChangeForKey->originalGroup isEqualToString:lastChangeForKey->finalGroup])
					{
						// = Update
						
						firstChangeForKey->type = YapDatabaseViewChangeUpdate;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
					else
					{
						// = Move
						
						firstChangeForKey->type = YapDatabaseViewChangeMove;
						firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
						firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
						firstChangeForKey->finalSection = lastChangeForKey->finalSection;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
				}
			}
			else if (firstChangeForKey->type == YapDatabaseViewChangeInsert)
			{
				if (lastChangeForKey->type == YapDatabaseViewChangeDelete)
				{
					// Insert + Delete
					//
					// All operations are no-ops (& i remains the same)
					
					[changes removeObjectsAtIndexes:indexSet];
					[changes removeObjectAtIndex:i];
					
				}
				else if (lastChangeForKey->type == YapDatabaseViewChangeInsert)
				{
					// Insert + Delete + ... + Insert
					//
					// All operations except the last are no-ops.
					
					firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
					firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
					firstChangeForKey->finalSection = lastChangeForKey->finalSection;
					
					[changes removeObjectsAtIndexes:indexSet];
					i++;
				}
				else // if (lastChangeForKey->type == YapDatabaseViewChangeUpdate)
				{
					// Insert + Update
					//
					// This is still an insert, but the final location may have changed.
					
					firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
					firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
					firstChangeForKey->finalSection = lastChangeForKey->finalSection;
					
					[changes removeObjectsAtIndexes:indexSet];
					i++;
				}
			}
			else if (firstChangeForKey->type == YapDatabaseViewChangeUpdate)
			{
				if (lastChangeForKey->type == YapDatabaseViewChangeDelete)
				{
					// Update + Delete
					//
					// This is ultimately a Delete.
					// We need to be sure to use the original original index.
					
					firstChangeForKey->type = YapDatabaseViewChangeDelete;
					
					[changes removeObjectsAtIndexes:indexSet];
					i++;
				}
				else if (lastChangeForKey->type == YapDatabaseViewChangeInsert)
				{
					// Update + Insert
					//
					// This is either an Update or a Move.
					// It simply depends on the original and final index values.
					
					if (firstChangeForKey->originalIndex == lastChangeForKey->finalIndex &&
					   [firstChangeForKey->originalGroup isEqualToString:lastChangeForKey->finalGroup])
					{
						// = Update
						//
						// First remains as is.
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
					else
					{
						// = Move
						//
						// The final location comes from the insert
						
						firstChangeForKey->type = YapDatabaseViewChangeMove;
						firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
						firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
						firstChangeForKey->finalSection = lastChangeForKey->finalSection;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
				}
				else // if (lastChangeForKey->type == YapDatabaseViewChangeUpdate)
				{
					// Update + Update
					//
					// This is either an Update or a Move.
					// It simply depends on the original and final index values.
					
					if (firstChangeForKey->originalIndex == lastChangeForKey->finalIndex &&
					   [firstChangeForKey->originalGroup isEqualToString:lastChangeForKey->finalGroup])
					{
						// = Update
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
					else
					{
						// = Move
						//
						// The final location comes from the last update
						
						firstChangeForKey->type = YapDatabaseViewChangeMove;
						firstChangeForKey->finalIndex = lastChangeForKey->finalIndex;
						firstChangeForKey->finalGroup = lastChangeForKey->finalGroup;
						firstChangeForKey->finalSection = lastChangeForKey->finalSection;
						
						[changes removeObjectsAtIndexes:indexSet];
						i++;
					}
				}
			}
			
			[indexSet removeAllIndexes];
			
		} // ([indexSet count] > 0)
		
	} // while (i < [changes count])
}

+ (void)processAndConsolidateChanges:(NSMutableArray *)changes
          withGroupToSectionMappings:(NSDictionary *)mappings
{
	//
	// PRE-PROCESSING
	//
	// Remove any items from the changes array that don't concern us.
	// That is, the mappings array will look something like this:
	// @{
	//     @"groupA" : @(0),
	//     @"groupB" : @(1)
	// }
	//
	// So changes that are in groupC can simply be dropped from the array.
	// That way we can skip any unneeded processing on them.
	
	for (NSUInteger i = [changes count]; i > 0; i--)
	{
		YapDatabaseViewChange *change = [changes objectAtIndex:(i-1)];
		
		if (change->type == YapDatabaseViewChangeDelete)
		{
			NSNumber *section = [mappings objectForKey:change->originalGroup];
			
			if (section)
				change->originalSection = [section unsignedIntegerValue];
			else
				[changes removeObjectAtIndex:(i-1)];
		}
		else if (change->type == YapDatabaseViewChangeInsert)
		{
			NSNumber *section = [mappings objectForKey:change->finalGroup];
			
			if (section)
				change->finalSection = [section unsignedIntegerValue];
			else
				[changes removeObjectAtIndex:(i-1)];
		}
		else if (change->type == YapDatabaseViewChangeUpdate)
		{
			NSNumber *section = [mappings objectForKey:change->originalGroup];
			
			if (section)
				change->originalSection = change->finalSection = [section unsignedIntegerValue];
			else
				[changes removeObjectAtIndex:(i-1)];
		}
	}
	
	// PROCESSING & CONSOLIDATION
	
	[self processAndConsolidateChanges:changes];
}

- (NSString *)description
{
	if (type == YapDatabaseViewChangeInsert)
	{
		if (finalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
					@"<YapDatabaseViewChange: Insert pre(~ -> %lu) post(~ -> %lu) group(%@) key(%@)",
			        (unsigned long)opFinalIndex, (unsigned long)finalIndex, finalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
					@"<YapDatabaseViewChange: Insert indexPath(nil) newIndexPath(%lu, %lu) group(%@) key(%@)>",
			        (unsigned long)finalSection, (unsigned long)finalIndex, finalGroup, key];
		}
	}
	else if (type == YapDatabaseViewChangeDelete)
	{
		if (originalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewChange: Delete pre(%lu -> ~) post(%lu -> ~) group(%@) key(%@)",
			        (unsigned long)opOriginalIndex, (unsigned long)originalIndex, originalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
			    @"<YapDatabaseViewChange: Delete indexPath(%lu, %lu) newIndexPath(nil) group(%@) key(%@)>",
			        (unsigned long)originalSection, (unsigned long)originalIndex, originalGroup, key];
		}
	}
	else if (type == YapDatabaseViewChangeMove)
	{
		if (originalSection == NSNotFound && finalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewChange: Move pre(%lu -> %lu) post(%lu -> %lu) group(%@ -> %@) key(%@)",
					(unsigned long)opOriginalIndex, (unsigned long)opFinalIndex,
					(unsigned long)originalIndex,   (unsigned long)finalIndex,
					originalGroup, finalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewChange: Move indexPath(%lu, %lu) newIndexPath(%lu, %lu) group(%@ -> %@) key(%@)",
					(unsigned long)originalSection, (unsigned long)originalIndex,
					(unsigned long)finalSection,    (unsigned long)finalIndex,
					originalGroup, finalGroup, key];
		}
	}
	else // if (type == YapDatabaseViewChangeUpdate)
	{
		if (originalSection == NSNotFound && finalSection == NSNotFound)
		{
			// Internal style (for debugging the processAndConsolidateOperations method)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewChange: Update pre(%lu) post(%lu -> %lu) group(%@ -> %@) key(%@)",
					(unsigned long)opOriginalIndex,
					(unsigned long)originalIndex,   (unsigned long)finalIndex,
					originalGroup, finalGroup, key];
		}
		else
		{
			// External style (for debugging UITableView & UICollectionView updates)
			return [NSString stringWithFormat:
				@"<YapDatabaseViewChange: Update indexPath(%lu, %lu) group(%@ -> %@) key(%@)",
					(unsigned long)originalSection, (unsigned long)originalIndex,
					originalGroup, finalGroup, key];
		}
	}
}

@end
