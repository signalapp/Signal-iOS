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
	[super tearDown];
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

- (void)test_fixedRange_beginning_4D
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Dependencies
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Reverse
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
