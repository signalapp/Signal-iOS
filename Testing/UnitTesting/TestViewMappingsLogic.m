#import "TestViewMappingsLogic.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"


@implementation TestViewMappingsLogic

static NSMutableArray *changes;

static YapDatabaseViewSectionChange* (^SectionOp)(NSArray*, NSUInteger) = ^(NSArray *sChanges, NSUInteger index){
	
	return (YapDatabaseViewSectionChange *)[sChanges objectAtIndex:index];
};

static YapDatabaseViewRowChange* (^RowOp)(NSArray*, NSUInteger) = ^(NSArray *rChanges, NSUInteger index){
	
	return (YapDatabaseViewRowChange *)[rChanges objectAtIndex:index];
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
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Fixed Range: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_1A
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

- (void)test_fixedRange_beginning_1B
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

- (void)test_fixedRange_beginning_1C
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

- (void)test_fixedRange_beginning_1D
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

- (void)test_fixedRange_end_1A
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

- (void)test_fixedRange_end_1B
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

- (void)test_fixedRange_end_1C
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

- (void)test_fixedRange_end_1D
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
#pragma mark Fixed Range: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_2A
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

- (void)test_fixedRange_beginning_2B
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

- (void)test_fixedRange_beginning_2C
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

- (void)test_fixedRange_beginning_2D
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
#pragma mark Fixed Range: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_3A
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

- (void)test_fixedRange_beginning_3B
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

- (void)test_fixedRange_beginning_3C
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

- (void)test_fixedRange_beginning_3D
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
#pragma mark Fixed Range: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_4A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
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

- (void)test_fixedRange_beginning_4B
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

- (void)test_fixedRange_beginning_4C
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

- (void)test_fixedRange_beginning_4D
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
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

- (void)test_fixedRange_end_4A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	[mappings updateWithCounts:@{ @"":@(40) }];         // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
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
	[mappings updateWithCounts:@{ @"":@(40) }]; // full=[0-39], range=[20-39]
	
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the beginning of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key1" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key2" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key3" inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteKey:@"key4" inGroup:@"" atIndex:18]];
	
	[mappings updateWithCounts:@{ @"":@(36) }]; // full=[0-37], range=[18-37]
	
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
#pragma mark Fixed Range: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_5A
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
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

- (void)test_fixedRange_beginning_5B
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

- (void)test_fixedRange_beginning_5C
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
#pragma mark Fixed Range: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_6A
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

- (void)test_fixedRange_beginning_6B
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

- (void)test_fixedRange_beginning_6C
{
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	
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

- (void)test_fixedRange_end_6A
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
#pragma mark -
#pragma mark Flexible Range: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_beginning_5A
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

- (void)test_flexibleRange_beginning_5B
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

- (void)test_flexibleRange_beginning_5C
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

- (void)test_flexibleRange_beginning_5D
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

- (void)test_flexibleRange_end_5A
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

- (void)test_flexibleRange_end_5B
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

- (void)test_flexibleRange_end_5C
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

- (void)test_flexibleRange_end_5D
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

@end
