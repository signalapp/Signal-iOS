#import "YapDatabaseViewOperation.h"


@implementation YapDatabaseViewOperation

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->type = YapDatabaseViewOperationInsert;
	op->key = key;
	op->group = group;
	op->original = op->opOriginal = NSUIntegerMax; // invalid in insert type
	op->final = op->opFinal = index;
	
	return op;
}

+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index
{
	YapDatabaseViewOperation *op = [[YapDatabaseViewOperation alloc] init];
	op->type = YapDatabaseViewOperationDelete;
	op->key = key;
	op->group = group;
	op->original = op->opOriginal = index;
	op->final = op->opFinal = NSUIntegerMax; // invalid in delete type
	
	return op;
}

+ (void)postProcessAndConsolidateOperations:(NSMutableArray *)operations
{
	NSUInteger count = [operations count];
	NSUInteger i;
	NSUInteger j;
	
//	NSLog(@"OPERATIONS (initial): %@", operations);
	
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
				    laterOperation->original >= operation->opOriginal)
				{
					laterOperation->original += 1;
				}
			}
		}
		else if (operation->type == YapDatabaseViewOperationInsert)
		{
			// An INSERT operation may affect the ORIGINAL index value of operations that occurred AFTER it,
			//   IF the later operation occurs at a greater or equal index value. ( -1 )
			
			for (j = i; j < count; j++)
			{
				YapDatabaseViewOperation *laterOperation = [operations objectAtIndex:j];
				
				if (laterOperation->type == YapDatabaseViewOperationDelete &&
				    laterOperation->original >= operation->opFinal)
				{
					laterOperation->original -= 1;
				}
			}
		}
	}
	
//	NSLog(@"OPERATIONS (middle): %@", operations);
	
	// Next we enumerate the items FORWARDS,
	// and update the FINAL values.
	
	for (i = 1; i < count; i++)
	{
		YapDatabaseViewOperation *operation = [operations objectAtIndex:i];
		
		if (operation->type == YapDatabaseViewOperationDelete)
		{
			// A DELETE operation may affect the FINAL index value of operations that occurred BEFORE it,
			//  IF the earlier operation occurs at a greater index value. ( -1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewOperation *earlierOperation = [operations objectAtIndex:(j-1)];
				
				if (earlierOperation->type == YapDatabaseViewOperationInsert)
				{
					if (earlierOperation->final == operation->opOriginal)
					{
						NSLog(@"SKIP 1 --------------------------------------------------------");
					//	earlierOperation->final -= 1;
					}
					else if (earlierOperation->final > operation->opOriginal)
					{
						earlierOperation->final -= 1;
					}
				}
			}
		}
		else if (operation->type == YapDatabaseViewOperationInsert)
		{
			// An INSERT operation may affect the FINAL index value of operations that occurred BEFORE it,
			//   IF the earlier operation occurs at a greater index value ( +1 )
			
			for (j = i; j > 0; j--)
			{
				YapDatabaseViewOperation *earlierOperation = [operations objectAtIndex:(j-1)];
				
				if (earlierOperation->type == YapDatabaseViewOperationInsert)
				{
					if (earlierOperation->final == operation->opFinal)
					{
						NSLog(@"INCLUDE 2 --------------------------------------------------------");
						earlierOperation->final += 1;
					}
					else if (earlierOperation->final > operation->opFinal)
					{
						earlierOperation->final += 1;
					}
				}
			}
		}
	}
	
//	NSLog(@"OPERATIONS (final): %@", operations);
}

- (NSString *)description
{
	if (type == YapDatabaseViewOperationDelete)
		return [NSString stringWithFormat:@"<YapDatabaseViewOperation: Delete pre(%lu -> ~) post(%lu -> ~) key(%@)",
		           (unsigned long)opOriginal, (unsigned long)original, key];
	
	if (type == YapDatabaseViewOperationInsert)
		return [NSString stringWithFormat:@"<YapDatabaseViewOperation: Insert pre(~ -> %lu) post(~ -> %lu) key(%@)",
		           (unsigned long)opFinal, (unsigned long)final, key];
	
	return [NSString stringWithFormat:@"<YapDatabaseViewOperation: Move pre(%lu -> %lu) post(%lu -> %lu) key(%@)",
	           (unsigned long)opOriginal, (unsigned long)opFinal,
	           (unsigned long)original,   (unsigned long)final, key];
}

@end
