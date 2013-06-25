#import "TestViewOperationLogic.h"
#import "YapDatabaseViewOperation.h"

/**
 * A database view needs to report a changeset in the YapDatabaseModifiedNotification.
 * The changeset needs to properly indicate any keys that were inserted, deleted, or moved.
 * 
 * If a key is inserted or moved, then the changeset needs to report the original index of the key,
 * as it existed at the start of the readwrite transaction.
 * 
 * If a key is deleted or moved, then the changeset needs to report the final index of the key,
 * as it exists at the end of the readwrite transaction.
 * 
 * This sounds simple enough in principle.
 * But when the transaction may consist of multiple modifications to multiple keys,
 * the complexities of the problem begin to add up...
 * 
 * For the test cases below, we will use "ascii art" to diagram the order of changes that occurred.
 * 
 * The views record each operation that modifies the view as the modifications occur:
 *
 * - If a item is inserted, then the insertion index is recorded at the time of the insert.
 * - If a key is deleted, then the deletion index is recorded at the time of the delete.
 * - If a key is moved, then the operation is recorded as 2 separate operations. A delete and then an insert.
 * 
 * The the recording of the modifications is quite simple.
 * After the transaction is complete, we need to perform post-processing on the operation log in order to:
 *
 * - deduce the original index value and final index value of modifications
 * - consolidate multiple changes to the same key
 * 
 * Notes:
 * 
 * - a MOVE is written as    : (originalIndex -> finalIndex)
 * - a DELETE is written as  : (originalIndex -> ~)           because a delete has no final index
 * - an INSERT is written as : (            ~ -> finalIndex)  because an insert has no original index
**/
@implementation TestViewOperationLogic

static NSMutableArray *operations;

static YapDatabaseViewOperation* (^Op)(NSUInteger) = ^(NSUInteger index){
	
	return (YapDatabaseViewOperation *)[operations objectAtIndex:index];
};

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		operations = [NSMutableArray array];
	}
}

- (void)tearDown
{
	[operations removeAllObjects];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1A
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | tiger
	// 1 | tiger | tiger | cat
	// 2 | bear  | cat   | dog
	// 3 | cat   | dog   | 
	// 4 | dog   |       | 
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion" inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Delete: 0 (lion)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 0, @"");
}

- (void)test1B
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | dog
	// 3 | cat   | dog   |
	// 4 | dog   |       |
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"cat"  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: (2 -> ~) (bear)
	// Delete: (3 -> ~) (cat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 3, @"");
}

- (void)test1C
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | cat
	// 3 | cat   | dog   |
	// 4 | dog   |       |
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"dog"  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: (2 -> ~) (bear)
	// Delete: (4 -> ~) (dog)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 4, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Insert, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test2A
{
	//     orig    insrt   insrt
	//
	// 0 | lion  | lion  | goat
	// 1 | tiger | tiger | lion
	// 2 | bear  | zebra | tiger
	// 3 | cat   | bear  | zebra
	// 4 | dog   | cat   | bear
	// 5 |       | dog   | cat
	// 6 |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: (~ -> 3) (zebra)
	// Insert: (~ -> 0) (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 3, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 0, @"");
}

- (void)test2B
{
	//     orig    insrt   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | goat
	// 3 | cat   | bear  | zebra
	// 4 | dog   | cat   | bear
	// 5 |       | dog   | cat
	// 6 |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: (~ -> 3) (zebra)
	// Insert: (~ -> 2) (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 3, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 2, @"");
}

- (void)test2C
{
	//     orig    insrt   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | zebra
	// 3 | cat   | bear  | bear
	// 4 | dog   | cat   | cat
	// 5 |       | dog   | dog
	// 6 |       |       | goat
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:6]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: (~ -> 2) (zebra)
	// Insert: (~ -> 6) (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 6, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test3A
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | zebra
	// 1 | tiger | tiger | lion
	// 2 | bear  | cat   | tiger
	// 3 | cat   | dog   | cat
	// 4 | dog   |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 0 (zebra)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 0, @"");
}

- (void)test3B
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | zebra
	// 3 | cat   | dog   | cat
	// 4 | dog   |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 2 (zebra)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 2, @"");
}

- (void)test3C
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | cat
	// 3 | cat   | dog   | dog
	// 4 | dog   |       | zebra
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:4]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 4 (zebra)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 4, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Insert, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test4A
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | tiger
	// 1 | tiger | tiger | zebra
	// 2 | bear  | zebra | bear
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   | 
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion"  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 0 (lion)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 1, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 0, @"");
}

- (void)test4B
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | zebra
	// 2 | bear  | zebra | bear
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 1 (tiger)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 1, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 1, @"");
}

- (void)test4C
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | zebra
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 2 (zebra)
	// Delete: 2 (bear)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 2, @"");
}

- (void)test4D
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | zebra
	// 3 | cat   | bear  | bear
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"cat"   inGroup:@"" atIndex:4]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 2 (zebra)
	// Delete: 3 (cat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 3, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Insert, Delete, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test5A
{
	//     orig    insrt   delte   delte
	//
	// 0 | lion  | lion  | tiger | zebra
	// 1 | tiger | tiger | zebra | bear
	// 2 | bear  | zebra | bear  | cat
	// 3 | cat   | bear  | cat   | dog
	// 4 | dog   | cat   | dog   |
	// 5 |       | dog   |       |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion"  inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 0, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 0, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(2).originalIndex == 1, @"");
}

- (void)test5B
{
	//     orig    insrt   delte   delte
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | zebra | zebra
	// 2 | bear  | zebra | bear  | cat
	// 3 | cat   | bear  | cat   | dog
	// 4 | dog   | cat   | dog   |
	// 5 |       | dog   |       |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 1 (tiger)
	// Delete: 2 (bear)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 1, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 1, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(2).originalIndex == 2, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete, Insert, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test6A
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | zebra | goat
	// 1 | tiger | tiger | lion  | zebra
	// 2 | bear  | cat   | tiger | lion
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 0 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 1, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 0, @"");
}

- (void)test6B
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | zebra | zebra
	// 1 | tiger | tiger | lion  | goat
	// 2 | bear  | cat   | tiger | lion
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 0 (zebra)
	// Insert: 1 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 0, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 1, @"");
}

- (void)test6C
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | goat
	// 1 | tiger | tiger | zebra | lion
	// 2 | bear  | cat   | tiger | zebra
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 2 (zebra)
	// Insert: 0 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 2, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 0, @"");
}

- (void)test6D
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | zebra | zebra
	// 2 | bear  | cat   | tiger | goat
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 2 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 1, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 2, @"");
}

- (void)test6E
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | tiger | goat
	// 2 | bear  | cat   | zebra | tiger
	// 3 | cat   | dog   | cat   | zebra
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 3 (zebra)
	// Insert: 1 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 3, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 1, @"");
}

- (void)test6F
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | tiger | tiger
	// 2 | bear  | cat   | zebra | goat
	// 3 | cat   | dog   | cat   | zebra
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 3 (zebra)
	// Insert: 2 (goat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 3, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 2, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Insert, Delete ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test7A
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | tiger | zebra | zebra | zebra |
	// 1 | tiger | tiger | zebra | bear  | cat   | dog   |
	// 2 | bear  | zebra | bear  | cat   | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion"  inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"cat"   inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	// Delete: 2 (bear)
	// Delete: 3 (cat)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 0, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 0, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(2).originalIndex == 1, @"");
	
	STAssertTrue(Op(3).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(3).originalIndex == 2, @"");
	
	STAssertTrue(Op(4).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(4).originalIndex == 3, @"");
}

- (void)test7B
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | lion  | zebra | zebra | zebra |
	// 1 | tiger | tiger | zebra | bear  | bear  | dog   |
	// 2 | bear  | zebra | bear  | cat   | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion"  inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"cat"   inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 1 (tiger)
	// Delete: 0 (lion)
	// Delete: 3 (cat)
	// Delete: 2 (bear)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 0, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 1, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(2).originalIndex == 0, @"");
	
	STAssertTrue(Op(3).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(3).originalIndex == 3, @"");
	
	STAssertTrue(Op(4).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(4).originalIndex == 2, @"");
}

- (void)test7C
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | lion  | lion  | tiger | zebra |
	// 1 | tiger | tiger | tiger | tiger | zebra | dog   |
	// 2 | bear  | zebra | zebra | zebra | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:3]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"cat"   inGroup:@"" atIndex:3]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"lion"  inGroup:@"" atIndex:0]];
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"tiger" inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 2 (bear)
	// Delete: 3 (cat)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(0).finalIndex == 0, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(1).originalIndex == 2, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(2).originalIndex == 3, @"");
	
	STAssertTrue(Op(3).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(3).originalIndex == 0, @"");
	
	STAssertTrue(Op(4).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(4).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete, Insert ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test8A
{
	//     orig    delte   insrt   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | zebra | zebra | zebra
	// 2 | bear  | cat   | tiger | goat  | goat
	// 3 | cat   | dog   | cat   | tiger | fish
	// 4 | dog   |       | dog   | cat   | tiger
	// 5 |       |       |       | dog   | cat
	// 6 |       |       |       |       | dog
	
	[operations addObject:[YapDatabaseViewOperation deleteKey:@"bear"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"zebra" inGroup:@"" atIndex:1]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"goat"  inGroup:@"" atIndex:2]];
	[operations addObject:[YapDatabaseViewOperation insertKey:@"fish"  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewOperation processAndConsolidateOperations:operations];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 2 (goat)
	// Insert: 3 (fish)
	
	STAssertTrue(Op(0).type == YapDatabaseViewOperationDelete, @"");
	STAssertTrue(Op(0).originalIndex == 2, @"");
	
	STAssertTrue(Op(1).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(1).finalIndex == 1, @"");
	
	STAssertTrue(Op(2).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(2).finalIndex == 2, @"");
	
	STAssertTrue(Op(3).type == YapDatabaseViewOperationInsert, @"");
	STAssertTrue(Op(3).finalIndex == 3, @"");
}

@end
