#import <SenTestingKit/SenTestingKit.h>

#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"

YapDatabaseViewSectionChange* SectionOp(NSArray*sChanges, NSUInteger index){
	
	if (index < [sChanges count])
		return (YapDatabaseViewSectionChange *)[sChanges objectAtIndex:index];
	else
		return (YapDatabaseViewSectionChange *)nil;
};

YapDatabaseViewRowChange* RowOp(NSArray *rChanges, NSUInteger index){
	
	if (index < [rChanges count])
		return (YapDatabaseViewRowChange *)[rChanges objectAtIndex:index];
	else
		return (YapDatabaseViewRowChange *)nil;
};


@interface TestViewMappingsBase : SenTestCase
@end
@implementation TestViewMappingsBase

static NSMutableArray *changes;

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


@end
#pragma mark -
#pragma mark Fixed Range Beginning

@interface TestViewMappingsFixedRangeBeginning : TestViewMappingsBase
@end

@implementation TestViewMappingsFixedRangeBeginning


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_inserting_row_inside_range_deletes_the_row_previously_at_the_end_of_the_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:2]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_insert_row_at_beginning_deletes_the_row_previously_at_the_end_of_the_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];

	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_insert_row_at_end_of_range_cause_insert_and_delete_of_row
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_insert_row_outside_of_the_range_causes_no_row_changes
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_delete_row_in_range_adds_a_new_row_at_the_end
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:2]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_delete_row_at_beginning_of_range_adds_a_new_row_at_the_end_of_the_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_deleting_row_at_end_of_range_causes_the_last_item_to_update
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_deleting_row_outside_of_range_causes_no_row_changes
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_insert_twice_at_same_position_in_range_bumps_two_rows_off_end_of_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 11, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_insert_twice_at_beginning_of_range_bumps_two_rows_off_end_of_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_insert_twice_at_end_of_range_bumps_two_rows_off_end_of_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_inserting_four_times_at_end_of_range_bumps_four_items_two_items_off_end_of_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(44) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_deleting_two_rows_in_middle_of_range_adds_two_rows_to_the_end
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_deleting_two_rows_at_beginning_of_range_adds_two_rows_to_the_end
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_deleteing_two_rows_at_end_of_range_adds_two_rows_to_the_end
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_deleting_the_same_row_four_times_pulls_rows_up_and_deletes_them
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(36) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_adding_two_rows_when_range_contents_are_empty_results_in_count_of_two_rows
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Insert multiple items into an empty view
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_adding_two_rows_when_range_is_partially_full_increases_count_by_two
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(12) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 12, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_adding_two_rows_when_range_only_has_nineteen_returns_correct_count_of_twenty
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_resetting_group_results_in_count_zero_with_corresponding_delete_changes_for_all_rows
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_resetting_group_when_group_has_more_rows_than_range_only_results_in_delete_actions_for_rows_in_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setIsDynamicSectionForAllGroups:YES];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(4) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([sectionChanges count] == 1, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_reset_group_and_add_row_results_in_delete_actions_for_original_rows_and_insert_action_for_newly_added_row
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_insert_change_before_reset_with_insert_after_doesnt_return_delete_action_for_pre_reset_insert
{
	YapDatabaseViewRangeOptions *rangeOpts =
    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Test multiple changes, forcing some change-consolidation processing
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

@end

#pragma mark -
#pragma mark Fixed Range End

@interface TestViewMappingsFixedRangeEnd : TestViewMappingsBase
@end

@implementation TestViewMappingsFixedRangeEnd

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_inserting_row_inside_range_deletes_the_row_previously_at_the_beginning_of_the_range
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Changes:
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:30]];
	
	// After
	[mappings updateWithCounts:@{ @"":@(41) }];         // indexes=[0-40], range=[21-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 9, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_insert_row_at_end_deletes_row_at_beginning_and_adds_row_at_end
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:40]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[21-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_inserting_at_beginning_of_range_inserts_row_at_the_beginning_and_deletes_the_old_row_at_the_beginning
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:21]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[21-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_inserting_row_outside_of_range_causes_no_change
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[21-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_2A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:30]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[19-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[19-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:39]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[19-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[19-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_3A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:31]];

	[mappings updateWithCounts:@{ @"":@(42) }];         // full=[0-41], range=[22-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 8, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 9, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:23]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];          // full=[0-41], range=[22-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:41]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];         // full=[0-41], range=[22-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key3" inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key4" inGroup:@"" atIndex:25]];
	
	[mappings updateWithCounts:@{ @"":@(44) }];         // full=[0-43], range=[24-43]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_4A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:30]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[18-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[18-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:38]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[18-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(36) }];         // full=[0-37], range=[18-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)test_fixedRange_end_5A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_5B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(12) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 12, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_5C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_6A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_6B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	[YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setIsDynamicSectionForAllGroups:YES];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(4) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([sectionChanges count] == 1, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_6C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_6D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Flexible Range
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingsFlexibleRange : TestViewMappingsBase
@end

@implementation TestViewMappingsFlexibleRange
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_1A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:2]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
}

- (void)test_flexibleRange_beginning_1B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_1C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (still inside)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
}

- (void)test_flexibleRange_beginning_1D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just outside)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

- (void)test_flexibleRange_end_1A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:30]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[20-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
}

- (void)test_flexibleRange_end_1B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:40]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[20-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
}

- (void)test_flexibleRange_end_1C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just inside)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:21]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[20-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
}

- (void)test_flexibleRange_end_1D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just outside)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(41) }];         // full=[0-40], range=[21-40]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_2A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:2]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
}

- (void)test_flexibleRange_beginning_2B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_2C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
}

- (void)test_flexibleRange_beginning_2D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

- (void)test_flexibleRange_end_2A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:22]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[20-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
}

- (void)test_flexibleRange_end_2B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:39]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[20-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
}

- (void)test_flexibleRange_end_2C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];         // full=[0-38], range=[20-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_flexibleRange_end_2D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(39) }];        // full=[0-39], range=[19-38]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_3A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 11, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 10, @"");
}

- (void)test_flexibleRange_beginning_3B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_3C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
}

- (void)test_flexibleRange_beginning_3D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key3" inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key4" inGroup:@"" atIndex:19]];
	
	[mappings updateWithCounts:@{ @"":@(44) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_flexibleRange_end_3A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:31]];

	[mappings updateWithCounts:@{ @"":@(42) }];         // full=[0-41], range=[20-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 11, @"");
}

- (void)test_flexibleRange_end_3B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:41]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];          // full=[0-41], range=[20-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 21, @"");
}

- (void)test_flexibleRange_end_3C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:21]];
	
	[mappings updateWithCounts:@{ @"":@(42) }];         // full=[0-41], range=[20-41]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_end_3D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key3" inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key4" inGroup:@"" atIndex:23]];
	
	[mappings updateWithCounts:@{ @"":@(44) }];         // full=[0-43], range=[22-43]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_4A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
}

- (void)test_flexibleRange_beginning_4B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

- (void)test_flexibleRange_beginning_4C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
}

- (void)test_flexibleRange_beginning_4D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the end of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(36) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_flexibleRange_end_4A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:30]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[20-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
}

- (void)test_flexibleRange_end_4B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:38]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[20-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
}

- (void)test_flexibleRange_end_4C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(38) }];         // full=[0-37], range=[20-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

- (void)test_flexibleRange_end_4D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(36) }];         // full=[0-37], range=[16-37]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_5A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Insert multiple items to an empty view
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_beginning_5B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Insert multiple items into a small view
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(12) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 11, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_5C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Insert multiple items into a view to grow the length
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_end_5A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_end_5B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:11]];
	
	[mappings updateWithCounts:@{ @"":@(12) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 11, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
}

- (void)test_flexibleRange_end_5C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_6A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_6B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view, then add one
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_beginning_6C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_end_6A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	[mappings updateWithCounts:@{ @"":@(0) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_flexibleRange_end_6B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view, then add one
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_end_6C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(2) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(1) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Max & Min Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_7A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:8 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.maxLength = 10;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(8) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 8, @"");
	
	// Inset enough items to exceed max length
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(11) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	STAssertTrue([rowChanges count] == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 7, @"");
}

- (void)test_flexibleRange_beginning_7B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 5;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(8) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 4, @"");
}

- (void)test_flexibleRange_beginning_7C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:1 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 5;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(20) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	STAssertTrue([mappings indexForRow:0 inGroup:@""] == 1, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:1]];
	
	[mappings updateWithCounts:@{ @"":@(17) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	STAssertTrue([[mappings rangeOptionsForGroup:@""] length] == 5, @"");
	STAssertTrue([[mappings rangeOptionsForGroup:@""] offset] == 0, @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 4, @"");
}

- (void)test_flexibleRange_end_7A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:8 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.maxLength = 10;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(8) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 8, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key2" inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(11) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	STAssertTrue([rowChanges count] == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 7, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 8, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 9, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
}

- (void)test_flexibleRange_end_7B
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 5;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(10) }];         // full=[0-9], range=[4-9]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:8]];
	
	[mappings updateWithCounts:@{ @"":@(8) }];         // full=[0-7], range=[3-7]
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_end_7C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:1 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 5;
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(20) }];           // full=[0-19], range=[13-18]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	STAssertTrue([mappings indexForRow:0 inGroup:@""] == 13, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:16]];
	
	[mappings updateWithCounts:@{ @"":@(17) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	STAssertTrue([[mappings rangeOptionsForGroup:@""] length] == 5, @"");
	STAssertTrue([[mappings rangeOptionsForGroup:@""] offset] == 0, @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 0, @"");
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Dependencies
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingsDependencies : TestViewMappingsBase
@end

@implementation TestViewMappingsDependencies

- (void)test_dependencies_1
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Delete an item.
	// Make sure there is a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:17]];
	
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 17, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 17, @"");
}

- (void)test_dependencies_2
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Delete multiple items right next to each other.
	// Make sure there is only one dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(18) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_dependencies_3
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Delete an item.
	// Update the dependency change, and check for proper changes flags.
	
	int flags = YapDatabaseViewChangedObject;
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange updateKey:@"key1" changes:flags inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 3, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	flags = YapDatabaseViewChangedObject | YapDatabaseViewChangedDependency;
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	STAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
	
	flags = YapDatabaseViewChangedDependency;
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 12, @"");
	STAssertTrue(RowOp(rowChanges, 2).changes == flags, @"");
}

- (void)test_dependencies_4
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Insert an item in the middle.
	// Check for proper dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:10]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 10, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 11, @"");
	STAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
}

- (void)test_dependencies_5
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Insert item at the very end.
	// There shouldn't be any dependency related changes.
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
}

- (void)test_dependencies_6
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:1 forGroup:@""]; // +1 dependency
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Insert item at the very end.
	// Make sure there is a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:20]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
	STAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
}

- (void)test_dependencies_7
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:1 forGroup:@""]; // +1 dependency
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Insert item at the very beginning.
	// There shouldn't be a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key0" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(21) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_dependencies_8
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) }];
	originalMappings = [mappings copy];
	
	// Try hard to mess up the algorithm...
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key0" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"key1" inGroup:@"" atIndex:14]];
	
	[mappings updateWithCounts:@{ @"":@(19) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 4, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 14, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 12, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 10, @"");
	STAssertTrue(RowOp(rowChanges, 2).changes == flags, @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeUpdate, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 16, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 15, @"");
	STAssertTrue(RowOp(rowChanges, 3).changes == flags, @"");
}

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Reverse
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingsReverse : TestViewMappingsBase
@end

@implementation TestViewMappingsReverse

- (void)test_reverse_1
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) }];
	originalMappings = [mappings copy];
	
	// Delete an item.
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key5" inGroup:@"" atIndex:5]];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_reverse_2
{
	YapDatabaseViewMappings *mappings, *originalMappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	originalMappings = [mappings copy];
	
	// Delete an item.
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key5" inGroup:@"" atIndex:0]];
	
	[mappings updateWithCounts:@{ @"":@(4) }];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 4, @"");
}
@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingsGetters : TestViewMappingsBase
@end

@implementation TestViewMappingsGetters

- (void)test_getter_1
{
	YapDatabaseViewMappings *mappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(3) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_2
{
	YapDatabaseViewMappings *mappings;
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_3
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_4
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_5
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_6
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_7
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_8
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_9
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_10
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) }];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	STAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	STAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	STAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	STAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	STAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	STAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	STAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	STAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	STAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	STAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Auto Consolidate Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingsAutoConsolidatingGroups : TestViewMappingsBase
@end

@implementation TestViewMappingsAutoConsolidatingGroups

- (void)test_autoConsolidateGroups_1A
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete single item:
	//
	// - [group0, section=0, row=0]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section0,row0" inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group0], @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_1B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete single item:
	//
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(2) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group0], @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group0], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_1C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section0,row0" inGroup:group0 atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(2) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group0], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_2A
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(3) }];
	
	// Insert single item:
	//
	// - [group0, section=0, row=0]
	//
	// This should cause all the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section0,row0" inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_2B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(2) }];
	
	// Insert single item:
	//
	// - [group1, section=1, row=1]
	//
	// This should cause the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_2C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(2) }];
	
	// Insert multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section0,row0" inGroup:group0 atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 3, @"");
	
	STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	STAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	STAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	STAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	STAssertTrue([rowChanges count] == 5, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group0], @"");
	
	STAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
	STAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	STAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	STAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	STAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	STAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_3A
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete single item:
	//
	// - [group0, section=0, row=0]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section0,row0" inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete single item:
	//
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(2) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Delete multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section0,row0" inGroup:group0 atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(2) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3D
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(3) }];
	
	// Insert single item:
	//
	// - [group0, section=0, row=0]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section0,row0" inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3E
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(2) }];
	
	// Insert single item:
	//
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 1, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3F
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(2) }];
	
	// Insert multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section0,row0" inGroup:group0 atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertKey:@"section1,row1" inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) }];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	STAssertTrue([sectionChanges count] == 0, @"");
	
	STAssertTrue([rowChanges count] == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	STAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 3, @"");
	STAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
}
@end

@interface TestViewMappingDynamicGroupAddition : TestViewMappingsBase
@end

@implementation TestViewMappingDynamicGroupAddition

-(void)test_adding_group_should_cause_result_in_section_insert_change{
    YapDatabaseViewMappings *originalMapping, *finalMapping;
    originalMapping = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g){
                                                                                            return YES;
                                                                                        }
                                                                                       sortBlock:^NSComparisonResult(NSString *l, NSString *r){
                                                                                           return [l compare:r];
                                                                                       }
                                                                                            view:@"view"];
    
    
    [originalMapping updateWithCounts:@{@"group1":@(5),
                                @"group2":@(3)}];
    
    finalMapping = [originalMapping copy];
    [finalMapping updateWithCounts:@{@"group1":@(5),
                                     @"group2":@(3),
                                     @"group3":@(2)}];
    

	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"group3"]];
    
    NSArray *sectionChanges = nil, *rowChanges = nil;
    [YapDatabaseViewChange getSectionChanges:&sectionChanges
                                  rowChanges:&rowChanges
                        withOriginalMappings:originalMapping
                               finalMappings:finalMapping
                                 fromChanges:changes];
    
    STAssertTrue(sectionChanges.count == 1, nil);
    STAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeInsert, nil);
    STAssertTrue(SectionOp(sectionChanges, 0).index == 2, nil);
}

-(void)test_adding_empty_group_when_dynamic_section_for_all_groups_is_set_should_not_result_in_section_insert_change{
    YapDatabaseViewMappings *originalMapping, *finalMapping;
    originalMapping = [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g){
        return YES;
    }
                                                                      sortBlock:^NSComparisonResult(NSString *l, NSString *r){
                                                                          return [l compare:r];
                                                                      }
                                                                           view:@"view"];
    originalMapping.isDynamicSectionForAllGroups = YES;
    
    
    [originalMapping updateWithCounts:@{@"group1":@(5),
                                        @"group2":@(3)}];
    
    finalMapping = [originalMapping copy];
    [finalMapping updateWithCounts:@{@"group1":@(5),
                                     @"group2":@(3),
                                     @"group3":@(0)}];
    
    
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"group3"]];
    
    NSArray *sectionChanges = nil, *rowChanges = nil;
    [YapDatabaseViewChange getSectionChanges:&sectionChanges
                                  rowChanges:&rowChanges
                        withOriginalMappings:originalMapping
                               finalMappings:finalMapping
                                 fromChanges:changes];
    
    
    STAssertTrue(sectionChanges.count == 0, nil);
}


@end

