#import <XCTest/XCTest.h>

#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"
#import "YapCollectionKey.h"

#define YCK(collection, key) YapCollectionKeyCreate(collection, key)

@interface TestViewChangeLogic : XCTestCase
@end

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
 * For the test cases below, we will use "ascii art" to diagram the order of changes that occurred in the view.
 * 
 * The views record each change that modifies the view as the modifications occur:
 *
 * - If a item is inserted, then the insertion index is recorded at the time of the insert.
 * - If a key is deleted, then the deletion index is recorded at the time of the delete.
 * - If a key is moved, then the change is recorded as 2 separate operations. A delete and then an insert.
 * 
 * The recording of the modifications is quite simple.
 * After the transaction is complete, we need to perform post-processing on the changes log in order to:
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
@implementation TestViewChangeLogic

static NSMutableArray *changes;

static YapDatabaseViewSectionChange* (^SectionOp)(NSArray*, NSUInteger) = ^(NSArray *sChanges, NSUInteger index){
	
	if (index < [sChanges count])
		return (YapDatabaseViewSectionChange *)[sChanges objectAtIndex:index];
	else
		return (YapDatabaseViewSectionChange *)nil;
};

static YapDatabaseViewRowChange* (^RowOp)(NSArray*, NSUInteger) = ^(NSArray *rChanges, NSUInteger index){
	
	if (index < [rChanges count])
		return (YapDatabaseViewRowChange *)[rChanges objectAtIndex:index];
	else
		return (YapDatabaseViewRowChange *)nil;
};

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		changes = [NSMutableArray array];
	}
}

- (void)tearDown
{
	[changes removeAllObjects];
	[super tearDown];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Row: Delete, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_1A
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | tiger
	// 1 | tiger | tiger | cat
	// 2 | bear  | cat   | dog
	// 3 | cat   | dog   | 
	// 4 | dog   |       | 
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: (2 -> ~) (bear)
	// Delete: (0 -> ~) (lion)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == NSNotFound, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == NSNotFound, @"");
}

- (void)test_row_1B
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | dog
	// 3 | cat   | dog   |
	// 4 | dog   |       |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"cat")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: (2 -> ~) (bear)
	// Delete: (3 -> ~) (cat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 3, @"");
}

- (void)test_row_1C
{
	//     orig    delte   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | cat
	// 3 | cat   | dog   |
	// 4 | dog   |       |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"dog")  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: (2 -> ~) (bear)
	// Delete: (4 -> ~) (dog)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 4, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Insert, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_2A
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
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: (~ -> 3) (zebra)
	// Insert: (~ -> 0) (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 0, @"");
}

- (void)test_row_2B
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
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: (~ -> 3) (zebra)
	// Insert: (~ -> 2) (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 2, @"");
}

- (void)test_row_2C
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
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:6]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: (~ -> 2) (zebra)
	// Insert: (~ -> 6) (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 6, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Delete, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_3A
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | zebra
	// 1 | tiger | tiger | lion
	// 2 | bear  | cat   | tiger
	// 3 | cat   | dog   | cat
	// 4 | dog   |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 0 (zebra)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 0, @"");
}

- (void)test_row_3B
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | zebra
	// 3 | cat   | dog   | cat
	// 4 | dog   |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 2 (zebra)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 2, @"");
}

- (void)test_row_3C
{
	//     orig    delte   insrt
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | cat   | cat
	// 3 | cat   | dog   | dog
	// 4 | dog   |       | zebra
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:4]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 4 (zebra)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 4, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Insert, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_4A
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | tiger
	// 1 | tiger | tiger | zebra
	// 2 | bear  | zebra | bear
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   | 
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 0 (lion)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 0, @"");
}

- (void)test_row_4B
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | zebra
	// 2 | bear  | zebra | bear
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 1 (tiger)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 1, @"");
}

- (void)test_row_4C
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | zebra
	// 3 | cat   | bear  | cat
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 2 (zebra)
	// Delete: 2 (bear)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 2, @"");
}

- (void)test_row_4D
{
	//     orig    insrt   delte
	//
	// 0 | lion  | lion  | lion
	// 1 | tiger | tiger | tiger
	// 2 | bear  | zebra | zebra
	// 3 | cat   | bear  | bear
	// 4 | dog   | cat   | dog
	// 5 |       | dog   |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"cat")   inGroup:@"" atIndex:4]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 2 (zebra)
	// Delete: 3 (cat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 3, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Insert, Delete, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_5A
{
	//     orig    insrt   delte   delte
	//
	// 0 | lion  | lion  | tiger | zebra
	// 1 | tiger | tiger | zebra | bear
	// 2 | bear  | zebra | bear  | cat
	// 3 | cat   | bear  | cat   | dog
	// 4 | dog   | cat   | dog   |
	// 5 |       | dog   |       |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 2).originalIndex == 1, @"");
}

- (void)test_row_5B
{
	//     orig    insrt   delte   delte
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | zebra | zebra
	// 2 | bear  | zebra | bear  | cat
	// 3 | cat   | bear  | cat   | dog
	// 4 | dog   | cat   | dog   |
	// 5 |       | dog   |       |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 1 (zebra)
	// Delete: 1 (tiger)
	// Delete: 2 (bear)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 2).originalIndex == 2, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Delete, Insert, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_6A
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | zebra | goat
	// 1 | tiger | tiger | lion  | zebra
	// 2 | bear  | cat   | tiger | lion
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 0 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 0, @"");
}

- (void)test_row_6B
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | zebra | zebra
	// 1 | tiger | tiger | lion  | goat
	// 2 | bear  | cat   | tiger | lion
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 0 (zebra)
	// Insert: 1 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 1, @"");
}

- (void)test_row_6C
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | goat
	// 1 | tiger | tiger | zebra | lion
	// 2 | bear  | cat   | tiger | zebra
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 2 (zebra)
	// Insert: 0 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 0, @"");
}

- (void)test_row_6D
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | zebra | zebra
	// 2 | bear  | cat   | tiger | goat
	// 3 | cat   | dog   | cat   | tiger
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 2 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 2, @"");
}

- (void)test_row_6E
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | tiger | goat
	// 2 | bear  | cat   | zebra | tiger
	// 3 | cat   | dog   | cat   | zebra
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 3 (zebra)
	// Insert: 1 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 1, @"");
}

- (void)test_row_6F
{
	//     orig    delte   insrt   insrt
	//
	// 0 | lion  | lion  | lion  | lion
	// 1 | tiger | tiger | tiger | tiger
	// 2 | bear  | cat   | zebra | goat
	// 3 | cat   | dog   | cat   | zebra
	// 4 | dog   |       | dog   | cat
	// 5 |       |       |       | dog
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 3 (zebra)
	// Insert: 2 (goat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 2, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Insert, Delete ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_7A
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | tiger | zebra | zebra | zebra |
	// 1 | tiger | tiger | zebra | bear  | cat   | dog   |
	// 2 | bear  | zebra | bear  | cat   | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"cat")   inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	// Delete: 2 (bear)
	// Delete: 3 (cat)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 2).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 3).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 4).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 4).originalIndex == 3, @"");
}

- (void)test_row_7B
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | lion  | zebra | zebra | zebra |
	// 1 | tiger | tiger | zebra | bear  | bear  | dog   |
	// 2 | bear  | zebra | bear  | cat   | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"cat")   inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:1]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 1 (tiger)
	// Delete: 0 (lion)
	// Delete: 3 (cat)
	// Delete: 2 (bear)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 3).originalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 4).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 4).originalIndex == 2, @"");
}

- (void)test_row_7C
{
	//     orig    insrt   delte   delte   delte   delte
	//
	// 0 | lion  | lion  | lion  | lion  | tiger | zebra |
	// 1 | tiger | tiger | tiger | tiger | zebra | dog   |
	// 2 | bear  | zebra | zebra | zebra | dog   |       |
	// 3 | cat   | bear  | cat   | dog   |       |       |
	// 4 | dog   | cat   | dog   |       |       |       |
	// 5 |       | dog   |       |       |       |       |
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"cat")   inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"tiger") inGroup:@"" atIndex:0]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Insert: 0 (zebra)
	// Delete: 2 (bear)
	// Delete: 3 (cat)
	// Delete: 0 (lion)
	// Delete: 1 (tiger)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 1).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 2).originalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(changes, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 3).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(changes, 4).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 4).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Delete, Insert ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_8A
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
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"bear")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zebra") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"goat")  inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"fish")  inGroup:@"" atIndex:3]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Delete: 2 (bear)
	// Insert: 1 (zebra)
	// Insert: 2 (goat)
	// Insert: 3 (fish)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(changes, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 2).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(changes, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(changes, 3).finalIndex == 3, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Row: Move
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_row_9A
{
	//     orig    delte   insrt
	//
	// 0 | lion  | tiger | tiger |
	// 1 | tiger | bear  | bear  |
	// 2 | bear  |       | lion  |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion")  inGroup:@"" atIndex:2]];
	
	// Process
	
	[YapDatabaseViewChange processRowChanges:changes withOriginalMappings:nil finalMappings:nil];
	[YapDatabaseViewChange consolidateRowChanges:changes];
	
	// Expecting:
	// Move: 0 -> 2 (lion)
	
	XCTAssertTrue(RowOp(changes, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(changes, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(changes, 0).finalIndex == 2, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Section: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_1A
{
	//           orig    insrt
	//
	// A[0, 0] | (nil) | lion
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	// Section Insert: 0 (A)
	//     Row Insert: 0 (lion)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
}

- (void)test_section_1B
{
	//           orig    insrt
	//
	// A[0, 0] | (nil) | lion
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = NO; // <-- static sections
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	// Section Insert: none (allowsEmptySections)
	//     Row Insert: 0 (lion)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_2A
{
	//           orig    delte
	//
	// A[0, 0] | lion  | (nil)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	// Section Delete: 0 (A)
	//     Row Delete: 0 (lion)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
}

- (void)test_section_2B
{
	//           orig    delte
	//
	// A[0, 0] | lion  | (nil)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = NO; // <-- static sections
	
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	// Section Delete: none (allowsEmptySections)
	//     Row Insert: 0 (lion)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Insert +
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_3A
{
	//           orig   insrt  insrt
	//
	// A[0, 0] | elm  | elm  | elm  |
	// A[0, 1] |      |      |+oak  |
	// --------|      |------|------|
	// B[1, 0] |      |+lion | lion |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(2), @"B" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 1 (B)
	//
	// 0) Row Insert: [1, 0] (lion)
	// 1) Row Insert: [0, 1] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 1, @"");
}

- (void)test_section_3B
{
	//           orig   insrt  insrt
	//
	// A[X, 0] |      |+lion | lion |
	// --------|      |------|------|
	// B[X, 0] | elm  | elm  | elm  |
	// B[X, 1] |      |      |+oak  |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"B" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(2) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 0 (A)
	//
	// 0) Row Insert: [0, 0] (lion)
	// 1) Row Insert: [1, 1] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 1, @"");
}

- (void)test_section_3C
{
	//           orig   insrt  updte
	//
	// A[0, 0] | elm  | elm  |~elm  |
	// --------|      |------|------|
	// B[1, 0] |      |+lion | lion |
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:
	  [YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"elm")  inGroup:@"A" atIndex:0 withChanges:flags]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 1 (B)
	//
	// 0) Row Insert: [1, 0] (lion)
	// 1) Row Update: [0, 0] (elm)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

- (void)test_section_3D
{
	//           orig   insrt  updte
	//
	// A[X, 0] |      |+lion | lion |
	// --------|      |------|------|
	// B[X, 0] | elm  | elm  |~elm  |
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:
	  [YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"A" atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"elm")  inGroup:@"B" atIndex:0 withChanges:flags]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 0 (A)
	//
	// 0) Row Insert: [0, 0] (lion)
	// 1) Row Move  : [0, 0] -> [1, 0] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Delete +
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_4A
{
	//           orig   insrt  insrt
	//
	// A[0, 0] | elm  | elm  | elm  |
	// A[0, 1] |      |      |+oak  |
	// --------|------|      |      |
	// B[1, 0] | lion-|      |      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"B"]];
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(2), @"B" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (B)
	//
	// 0) Row Delete: [1, 0] (lion)
	// 1) Row Insert: [0, 1] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 1, @"");
}

- (void)test_section_4B
{
	//           orig   insrt  insrt
	//
	// A[X, 0] | elm- |      |      |
	// --------|------|      |      |
	// B[1, 0] | lion | lion | lion |
	// B[X, 1] |      |      |+bear |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"bear") inGroup:@"B" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(2) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 0 (A)
	//
	// 0) Row Delete: [0, 0] (elm)
	// 1) Row Insert: [0, 1] (bear)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 1, @"");
}

- (void)test_section_4C
{
	//           orig   delte  updte
	//
	// A[0, 0] | elm  | elm  |~elm  |
	// --------|------|      |      |
	// B[1, 0] | lion-|      |      |
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"B"]];
	
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0 withChanges:flags]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (B)
	//
	// 0) Row Delete: [1, 0] (lion)
	// 1) Row Update: [0, 0] (elm)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

- (void)test_section_4D
{
	//           orig   delte  updte
	//
	// A[X, 0] | elm -|      |      |
	// --------|------|      |      |
	// B[X, 0] | lion | lion |~lion |
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0 withChanges:flags]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 0 (A)
	//
	// 0) Row Delete: [0, 0] (elm)
	// 1) Row Move  : [1, 0] -> [0, 0] (lion)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Insert, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_5A
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  |      |
	// --------|------|------|      |
	// B[X, 0] | lion | lion | lion |
	// --------|      |------|------|
	// C[X, 0] |      | john | john |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"C"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 1 (C)
	// 1) Section Delete: 0 (A)
	//
	// 0) Row Insert: [1, 0] (john)
	// 1) Row Delete: [0, 0] (elm)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

- (void)test_section_5B
{
	//           orig   insrt  delte
	//
	// A[X, 0] |      | elm  | elm  |
	// --------|      |------|------|
	// B[X, 0] | lion | lion | lion |
	// --------|----- |------|      |
	// C[X, 0] | john | john |      |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(0), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 0 (A)
	// 1) Section Delete: 1 (C)
	//
	// 0) Row Insert: [0, 0] (elm)
	// 1) Row Delete: [1, 0] (john)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

- (void)test_section_5C
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  | elm  |
	// --------|------|------|------|
	// B[X, 0] |      |+lion | lion |
	// --------|      |------|      |
	// C[X, 0] | john | john-|      |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0), @"C" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 1 (B)
	// 1) Section Delete: 1 (C)
	//
	// 0) Row Insert: [1, 0] (lion)
	// 1) Row Delete: [1, 0] (john)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Insert, Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_6A
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  | elm  |
	// --------|------|------|------|
	// B[X, 0] |      |+lion | lion |
	// --------|      |------|------|
	// C[X, 0] |      |      |+john |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"C"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0), @"C" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 1 (B)
	// 1) Section Insert: 2 (C)
	//
	// 0) Row Insert: [1, 0] (lion)
	// 1) Row Insert: [2, 0] (john)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 2, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 2, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

- (void)test_section_6B
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  | elm  |
	// --------|------|------|------|
	// B[X, 0] |      |      |+lion |
	// --------|      |      |------|
	// C[X, 0] |      |+john | john |
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"C"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0), @"C" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 2 (C)
	// 1) Section Insert: 1 (B)
	//
	// 0) Row Insert: [2, 0] (john)
	// 1) Row Insert: [1, 0] (lion)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 2, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 2, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Delete, Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_7A
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  | elm  |
	// --------|------|------|------|
	// B[X, 0] | lion-|      |      |
	// --------|------|      |      |
	// C[X, 0] | john | john-|      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"B"]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0), @"C" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (B)
	// 1) Section Delete: 2 (C)
	//
	// 0) Row Delete: [1, 0] (lion)
	// 1) Row Delete: [2, 0] (john)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 2, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 2, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

- (void)test_section_7B
{
	//           orig   insrt  delte
	//
	// A[X, 0] | elm  | elm  | elm  |
	// --------|------|------|------|
	// B[X, 0] | lion | lion-|      |
	// --------|------|      |      |
	// C[X, 0] | john-|      |      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"lion") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"B"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1), @"C" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0), @"C" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 2 (C)
	// 1) Section Delete: 1 (B)
	//
	// 0) Row Delete: [2, 0] (john)
	// 1) Row Delete: [1, 0] (lion)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 2, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 2, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Move
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_8A
{
	//           orig   move
	//
	// A[X, 0] | elm  | elm  |
	// --------|------|------|
	// B[X, 0] |      |+john |
	// --------|      |      |
	// =======================
	// C[X, 0] | john-|      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"john") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"john") inGroup:@"B" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(0) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B" : @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (B)
	//
	// 0) Row Insert: [1, 0] (john)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
}

- (void)test_section_8B
{
	//           orig   move
	//
	// A[0, 0] | elm  | elm  |
	// A[0, 1] |      |+oak  |
	// --------|------|------|
	// B[1, 0] | oak -|      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"oak") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"B"]];
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(2), @"B": @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (B)
	//
	// 0) Row Move: [1, 0] -> [0, 1] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 1, @"");
}

- (void)test_section_8C
{
	//           orig   move
	//
	// A[0, 0] | elm  | elm  |
	// --------|------|------|
	// B[X, 0] |      |+oak  |
	// --------|------|------|
	// C[X, 0] | oak -|      |
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"oak") inGroup:@"C" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"C"]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"B"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"B" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B", @"C"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1), @"B": @(0), @"C" : @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B": @(1), @"C" : @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 1 (C)
	// 1) Section Insert: 1 (B)
	//
	// 0) Row Move: [1, 0] -> [1, 0] (oak)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 1, @"");
	
	XCTAssertTrue(SectionOp(sChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 1).index == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Update & Move
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_9A
{
	//           orig   updte  move
	//
	// A[0, 0] | elm  | elm  | elm  |
	// A[0, 0] |      |      |+oak  |
	// ==============================
	// B[X, 0] | oak  |~oak -|      |
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"oak") inGroup:@"B" atIndex:0 withChanges:flags]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"oak") inGroup:@"B" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:1]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	//
	// 0) Row Insert: [null] -> [0, 1] (oak)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Drop & Add Again
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_10A
{
	//           orig   delte  insrt
	//
	// A[0, 0] | elm -|      |+oak |
	// --------|------|------|-----|
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"elm") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete: [0, 0] -> [null] (elm)
	// 1) Row Insert: [null] -> [0, 0] (oak)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Add & Drop Again
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_11A
{
	//           orig   insrt  delte
	//
	// A[0, 0] |      |+oak -|     |
	// --------|------|------|-----|
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"oak") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// Nothing
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue([rChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Section: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_section_12A
{
	//           orig   reset
	//
	// A[0, 0] | elm  |      |
	// A[0, 1] | oak  |      |
	// --------|------|------|
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 0 (A)
	//
	// 0) Row Delete: [0, 1] (oak)
	// 1) Row Delete: [0, 1] (elm)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

- (void)test_section_12B
{
	//           orig   reset
	//
	// A[0, 0] | elm  |      |
	// A[0, 1] | oak  |      |
	// --------|------|------|
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@"A"]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = NO; // <-- static sections
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete: [0, 1] (oak)
	// 1) Row Delete: [0, 1] (elm)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
}

- (void)test_section_12C
{
	//           orig   reset  insrt
	//
	// A[0, 0] | elm  |      | pine |
	// A[0, 1] | oak  |      |      |
	// --------|------|------|------|
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@"A"]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"pine") inGroup:@"A" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Delete: 0 (A)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 2).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Blogged Bugs
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Blog Bug 1:
 * http://deusty.blogspot.com/2010/02/hideous-bug-in-nsfetchedresultscontroll.html
**/
- (void)testBlogBug1
{
	//           orig     move     move
	//
	// A[X, 0] |        | austin | austin |
	// --------|--------|--------|--------|
	// B[X, 0] | austin | ben    | ben    |
	// B[X, 1] | ben    | robbie | quack  |
	// B[X, 2] | robbie | zach   | robbie |
	// B[X, 3] | zach   |        |        |
	// --------|--------|--------|--------|
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"austin") inGroup:@"B" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"A"]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"austin") inGroup:@"A" atIndex:0]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A", @"B"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(0), @"B": @(4) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(1), @"B": @(3) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Section Insert: 0 (A)
	//
	// 0) Row Move: [0, 0] -> [0, 0] (austin)
	
	XCTAssertTrue(SectionOp(sChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sChanges, 0).index == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
}

/**
 * Blog Bug 2:
 * http://deusty.blogspot.com/2010/02/more-bugs-in-nsfetchedresultscontroller.html
**/
- (void)testBlogBug2
{
	//           orig     move     move
	//
	// A[X, 0] | austin |+AAA    | AAA    |
	// B[X, 1] | ben    | austin | austin |
	// B[X, 2] | robbie | ben    | ben    |
	// B[X, 3] | zach   | robbie |+quack  |
	// B[X, 4] |        | zach  -| robbie |
	// --------|--------|--------|--------|
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"AAA") inGroup:@"A" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"zach/quack") inGroup:@"A" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"zach/quack") inGroup:@"A" atIndex:3]];
	
	// Process
	
	NSArray *sChanges;
	NSArray *rChanges;
	
	YapDatabaseViewMappings *mappings;
	YapDatabaseViewMappings *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"A": @(4) } forceUpdateRangeOptions:NO];
	originalMappings = [mappings copy];
	[mappings updateWithCounts:@{ @"A": @(5) } forceUpdateRangeOptions:NO];
	
	[YapDatabaseViewChange getSectionChanges:&sChanges
	                              rowChanges:&rChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Insert: [null] -> [0, 0] (AAA)
	// 0) Row Move  : [0, 3] -> [0, 3] (zach/quack)
	
	XCTAssertTrue([sChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).originalIndex == 3, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rChanges, 1).finalIndex == 3, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Issue Bugs
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Issue #125:
 * https://github.com/yapstudios/YapDatabase/issues/125
**/
- (void)testIssue125_1
{
	// I noticed this:
	//
	// - setup view mapping on group A, which contains 2 rows, 1 section
	// - in the same read write transaction:
	//   - add 1 item to A
	//   - mode all items from A to B
	// - end the read write transaction
	//
	// [UITableView endUpdates] crashes with the following exception:
	// attempt to delete and reload the same index path (<NSIndexPath: 0xc000000000008016> {length = 2, path = 0 - 1})
	//
	// notifications =
	// <__NSArrayM 0x170454f10>(
	//  NSConcreteNotification 0x174454d90 {
	//    name = YapDatabaseModifiedNotification;
	//    object = <YapDatabase: 0x1741e7100>;
	//    userInfo = {
	//      connection = "<YapDatabaseConnection: 0x15c56c0d0>";
	//      extensions = {
	//        chatview = {
	//          changes = (
	//            "<YapDatabaseViewRowChange: Insert pre(~ -> 2) post(~ -> 2)   group(A) collectionKey(Chats, k3)>",
	//            "<YapDatabaseViewRowChange: Delete pre(0 -> ~) post(0 -> ~)   group(A) collectionKey(Chats, k1)>",
	//            "<YapDatabaseViewRowChange: Insert pre(~ -> 18) post(~ -> 18) group(B) collectionKey(Chats, k1)>",
	//            "<YapDatabaseViewRowChange: Delete pre(0 -> ~) post(0 -> ~)   group(A) collectionKey(Chats, k2)>",
	//            "<YapDatabaseViewRowChange: Insert pre(~ -> 19) post(~ -> 19) group(B) collectionKey(Chats, k2)>",
	//            "<YapDatabaseViewRowChange: Delete pre(0 -> ~) post(0 -> ~)   group(A) collectionKey(Chats, k3)>",
	//            "<YapDatabaseViewRowChange: Insert pre(~ -> 20) post(~ -> 20) group(B) collectionKey(Chats, k3)>",
	//            "<YapDatabaseViewSectionChange: Delete group(A)" );
	//          };
	//        };
	//      metadataChanges = "<YapSet: 0x17443b5e0>";
	//      objectChanges = "<YapSet: 0x174620f60>";
	//      snapshot = 21;
	//    }
	//  }
	// )
	//
	// rowChanges =
	// <__NSArrayM 0x174457370>(
	//   <YapDatabaseViewRowChange: Delete indexPath(0, 0) newIndexPath(nil) group(A) collectionKey(Chats, k1)>,
	//   <YapDatabaseViewRowChange: Delete indexPath(0, 1) newIndexPath(nil) group(A) collectionKey(Chats, k2)>,
	//   <YapDatabaseViewRowChange: Update indexPath(0, 1) group(B) collectionKey((null))
	// )
	
	// Note: I made the following swaps: (-RH)
	//
	// group "A" <- "2618|6766"
	// group "B" <- "2618|4212|6766"
	//
	// key "k0" <- "PRIVMSG261867662618014144983664eeac15ae345b99db2b063be34cfa006fd7d551f5805a296e5f9fc72ff6efcad"
	// key "k1" <- "JOIN26186766421201414498369"
	// key "k2" <- "JOIN26186766421201414498411"
	
	
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:2]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k0") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k0") inGroup:@"B" atIndex:18]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k1") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k1") inGroup:@"B" atIndex:19]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"B" atIndex:20]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sectionChanges;
	NSArray *rowChanges;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete : [0, 0] -> [-] (k0)
	// 1) Row Delete : [0, 1] -> [-] (k1)
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

/**
 * Issue #125:
 * https://github.com/yapstudios/YapDatabase/issues/125
**/
- (void)testIssue125_2
{
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:2]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k0") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k0") inGroup:@"B" atIndex:18]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k1") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k1") inGroup:@"B" atIndex:19]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"B" atIndex:20]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sectionChanges;
	NSArray *rowChanges;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@"A"];
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete : [0, 0] -> [-] (k1)
	// 1) Row Delete : [0, 1] -> [-] (k2)
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

/**
 * Issue #125:
 * https://github.com/yapstudios/YapDatabase/issues/125
**/
- (void)testIssue125_3
{
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k3") inGroup:@"A" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:2]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k0") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k0") inGroup:@"B" atIndex:18]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k1") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k1") inGroup:@"B" atIndex:19]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"B" atIndex:20]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k3") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k3") inGroup:@"B" atIndex:21]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sectionChanges;
	NSArray *rowChanges;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@"A"];
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete : [0, 0] -> [-] (k1)
	// 1) Row Delete : [0, 1] -> [-] (k2)
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

/**
 * Issue #125:
 * https://github.com/yapstudios/YapDatabase/issues/125
**/
- (void)testIssue125_4
{
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k0") inGroup:@"A" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k3") inGroup:@"A" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:1]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k1") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k1") inGroup:@"B" atIndex:18]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k2") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k2") inGroup:@"B" atIndex:19]];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(@"Chats", @"k3") inGroup:@"A" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"Chats", @"k3") inGroup:@"B" atIndex:20]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@"A"]];
	
	// Process
	
	NSArray *sectionChanges;
	NSArray *rowChanges;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A"] view:@""];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@"A"];
	
	[mappings updateWithCounts:@{ @"A": @(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	[mappings updateWithCounts:@{ @"A": @(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Expecting:
	//
	// 0) Row Delete : [0, 0] -> [-] (k1)
	// 1) Row Delete : [0, 1] -> [-] (k2)
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

@end
