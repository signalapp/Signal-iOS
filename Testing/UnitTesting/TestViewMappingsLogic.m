#import "TestViewMappingsLogic.h"
#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"


@implementation TestViewMappingsLogic

static NSMutableArray *changes;
static YapDatabaseViewMappings *mappings;
static YapDatabaseViewMappings *originalMappings;

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
		mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	}
}

- (void)tearDown
{
	[changes removeAllObjects];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Hard Range: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1A
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test1B
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test1C
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test1D
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Hard Range: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test2A
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test2B
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test2C
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	STAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	STAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test2D
{
	[mappings updateWithCounts:@{ @"":@(40) }];
	originalMappings = [mappings copy];
	
	[mappings setRange:NSMakeRange(0, 20) hard:YES pinnedTo:YapDatabaseViewBeginning forGroup:@""];
	
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
	
	STAssertTrue([rowChanges count] == 0, @"");
}

@end
