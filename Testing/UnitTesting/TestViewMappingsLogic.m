#import <XCTest/XCTest.h>

#import "YapDatabaseViewChangePrivate.h"
#import "YapDatabaseViewMappingsPrivate.h"
#import "YapCollectionKey.h"

#define YCK(collection, key) YapCollectionKeyCreate(collection, key)

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

@interface TestViewMappingsBase : XCTestCase
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

- (void)test_fixedRange_beginning_1A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_1B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];

	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_1C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_1D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_2A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_2B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_2C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_fixedRange_beginning_2D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_3A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 11, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_3B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_3C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_3D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(44) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_4A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_4B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_4C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

- (void)test_fixedRange_beginning_4D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(36) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_5A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Insert multiple items into an empty view
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_beginning_5B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(12) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 12, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_beginning_5C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 18, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_6A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_beginning_6B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setIsDynamicSectionForAllGroups:YES];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([sectionChanges count] == 1, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_beginning_6C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_fixedRange_beginning_6D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
      [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Test multiple changes, forcing some change-consolidation processing
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Clear
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_7A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_beginning_7B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_beginning_7C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:50 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range Beginning: Clear + UpdateWithTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_beginning_8A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_beginning_8B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_beginning_8C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:50 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
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

- (void)test_fixedRange_end_1A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Changes:
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 9, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_1B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:40]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_1C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:21]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_1D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_2A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[19-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[19-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:39]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[19-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_2D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[19-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_3A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:31]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[22-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 8, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 9, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:23]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[22-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:41]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[22-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

- (void)test_fixedRange_end_3D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:25]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(44) } forceUpdateRangeOptions:NO]; // full=[0-43], range=[24-43]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_4A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[18-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[18-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:38]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[18-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_4D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(36) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[18-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (void)test_fixedRange_end_5A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_5B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(12) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 12, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_fixedRange_end_5C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_6A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_6B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setIsDynamicSectionForAllGroups:YES];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all items via removeAllObjectsInAllCollections
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([sectionChanges count] == 1, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_fixedRange_end_6C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_fixedRange_end_6D
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Clear
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_7A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixexRange_end_7B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_end_7C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:50 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 4, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fixed Range End: Clear + UpdateWithTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_fixedRange_end_8A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixexRange_end_8B
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_fixedRange_end_8C
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:50 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 4, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

@end

#pragma mark -
#pragma mark Fixed Range: Multiple Groups

@interface TestViewMappingsFixedRangeMulti : TestViewMappingsBase
@end

@implementation TestViewMappingsFixedRangeMulti

/**
 * Addressing issue #89
 * https://github.com/yaptv/YapDatabase/issues/89
 * 
 * Infinite loop when using ranges on multiple groups.
**/
- (void)test_fixedRange_multi_1A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A",@"B"] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@"A"];
	[mappings setRangeOptions:rangeOpts forGroup:@"B"];
	
	[mappings updateWithCounts:@{ @"A":@(40), @"B":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"A", @"key") inGroup:@"A" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"B", @"key") inGroup:@"B" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"A":@(41), @"B":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@"A"] == 20, @"");
	XCTAssertTrue([mappings numberOfItemsInGroup:@"B"] == 20, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @""); // A
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 1, @""); // B
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, // A
	              @"Expected 0, got %lu", (unsigned long)(RowOp(rowChanges, 2).originalSection));
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 1, // B
	              @"Expected 1, got %lu", (unsigned long)(RowOp(rowChanges, 3).originalSection));
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 19, @"");
}

- (void)test_fixedRange_multi_2A
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@"A",@"B"] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@"A"];
	[mappings setRangeOptions:rangeOpts forGroup:@"B"];
	
	[mappings updateWithCounts:@{ @"A":@(40), @"B":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Changes:
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"A", @"key") inGroup:@"A" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(@"B", @"key") inGroup:@"B" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"A":@(41), @"B":@(41) } forceUpdateRangeOptions:NO]; // indexes=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@"A"] == 20, @"");
	XCTAssertTrue([mappings numberOfItemsInGroup:@"B"] == 20, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @""); // A
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 9, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 1, @""); // B
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 9, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, // A
	              @"Expected 0, got %lu", (unsigned long)(RowOp(rowChanges, 2).originalSection));
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 1, // B
	              @"Expected 1, got %lu", (unsigned long)(RowOp(rowChanges, 3).originalSection));
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
}

@end

#pragma mark -
#pragma mark Flexible Range

@interface TestViewMappingsFlexibleRange : TestViewMappingsBase
@end

@implementation TestViewMappingsFlexibleRange

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Insert
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_1A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
}

- (void)test_flexibleRange_1B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_1C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (still inside)
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
}

- (void)test_flexibleRange_1D_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just outside)
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

- (void)test_flexibleRange_1A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[20-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
}

- (void)test_flexibleRange_1B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:40]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[20-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
}

- (void)test_flexibleRange_1C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just inside)
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:21]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[20-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
}

- (void)test_flexibleRange_1D_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert item at the end of the range (just outside)
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(41) } forceUpdateRangeOptions:NO]; // full=[0-40], range=[21-40]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Delete
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_2A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
}

- (void)test_flexibleRange_2B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_flexibleRange_2C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
}

- (void)test_flexibleRange_2D_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

- (void)test_flexibleRange_2A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:22]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[20-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
}

- (void)test_flexibleRange_2B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item in the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:39]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[20-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
}

- (void)test_flexibleRange_2C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-38], range=[20-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_flexibleRange_2D_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete item outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(39) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[19-38]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Insert, Insert, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_3A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 11, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 10, @"");
}

- (void)test_flexibleRange_3B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
}

- (void)test_flexibleRange_3C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 18, @"");
}

- (void)test_flexibleRange_3D_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(44) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
}

- (void)test_flexibleRange_3A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Insert multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:31]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[20-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 11, @"");
}

- (void)test_flexibleRange_3B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:41]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[20-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 21, @"");
}

- (void)test_flexibleRange_3C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:21]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(42) } forceUpdateRangeOptions:NO]; // full=[0-41], range=[20-41]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_3D_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert multiple items at the end of the range, some of them end out outside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:23]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(44) } forceUpdateRangeOptions:NO]; // full=[0-43], range=[22-43]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 22, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Delete, Delete, ...
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_4A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
}

- (void)test_flexibleRange_4B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

- (void)test_flexibleRange_4C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
}

- (void)test_flexibleRange_4D_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items at the end of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(36) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_flexibleRange_4A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:30]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[20-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
}

- (void)test_flexibleRange_4B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:38]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[20-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
}

- (void)test_flexibleRange_4C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(38) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[20-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

- (void)test_flexibleRange_4D_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(40) } forceUpdateRangeOptions:NO]; // full=[0-39], range=[20-39]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Delete multiple items at the beginning of the range, and some outside the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key4") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(36) } forceUpdateRangeOptions:NO]; // full=[0-37], range=[16-37]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 18, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Move
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_5A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item within range (19 -> 0)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_5B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item within range (18 -> 1)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
}

- (void)test_flexibleRange_5C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item outside range (0 -> 24)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:24]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_flexibleRange_5D_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item into range (24 -> 0)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_5A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Move item within range (0 -> 19)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:19]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
}

- (void)test_flexibleRange_5B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	// Move item within range (1 -> 18)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 18, @"");
}

- (void)test_flexibleRange_5C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item outside range (24 -> 0)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 19, @"");
}

- (void)test_flexibleRange_5D_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Move item into range (0 -> 24)
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:24]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(25) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 21, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Changing Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_6A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Insert multiple items to an empty view
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_6B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Insert multiple items into a small view
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(12) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 11, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_6C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Insert multiple items into a view to grow the length
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_flexibleRange_6A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
}

- (void)test_flexibleRange_6B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:11]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(12) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 11, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
}

- (void)test_flexibleRange_6C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 19, @"");
	
	// Delete multiple items inside the range
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 20, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 19, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Reset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_7A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_flexibleRange_7B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view, then add one
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_7C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_7A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
}

- (void)test_flexibleRange_7B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view, then add one
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_7C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(2) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(1) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 1, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Max & Min Length
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_8A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:8 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.maxLength = 10;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(8) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 8, @"");
	
	// Inset enough items to exceed max length
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(11) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	XCTAssertTrue([rowChanges count] == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 7, @"");
}

- (void)test_flexibleRange_8B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 5;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(8) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 4, @"");
}

- (void)test_flexibleRange_8C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:1 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 5;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 1, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(17) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	XCTAssertTrue([[mappings rangeOptionsForGroup:@""] length] == 5, @"");
	XCTAssertTrue([[mappings rangeOptionsForGroup:@""] offset] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 4, @"");
}

- (void)test_flexibleRange_8A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:8 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.maxLength = 10;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(8) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 8, @"");
	
	// Delete all from the view (with other operations beforehand), and then add one
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(11) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 10, @"");
	
	XCTAssertTrue([rowChanges count] == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 7, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 8, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 9, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
}

- (void)test_flexibleRange_8B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 5;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(10) } forceUpdateRangeOptions:NO]; // full=[0-9], range=[4-9]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:8]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(8) } forceUpdateRangeOptions:NO]; // full=[0-7], range=[3-7]
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
}

- (void)test_flexibleRange_8C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:6 offset:1 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 5;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO]; // full=[0-19], range=[13-18]
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 6, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 13, @"");
	
	// Delete enough items to drop below min length
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:16]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(17) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 5, @"");
	
	XCTAssertTrue([[mappings rangeOptionsForGroup:@""] length] == 5, @"");
	XCTAssertTrue([[mappings rangeOptionsForGroup:@""] offset] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Clear
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_9A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_9B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_9C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:50 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_9A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_9B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_9C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:50 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 4, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: Clear + UpdateWithTransaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_10A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_10B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_10C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:50 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_10A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewSectionChange resetGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_10B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:2 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 2, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 2, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key2") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key3") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_10C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:50 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(54) } forceUpdateRangeOptions:NO];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 50, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 4, @"");
	
	// Delete all items
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"49") inGroup:@"" atIndex:49]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"48") inGroup:@"" atIndex:48]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"47") inGroup:@"" atIndex:47]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"46") inGroup:@"" atIndex:46]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"45") inGroup:@"" atIndex:45]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"44") inGroup:@"" atIndex:44]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"43") inGroup:@"" atIndex:43]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"42") inGroup:@"" atIndex:42]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"41") inGroup:@"" atIndex:41]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"40") inGroup:@"" atIndex:40]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"39") inGroup:@"" atIndex:39]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"38") inGroup:@"" atIndex:38]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"37") inGroup:@"" atIndex:37]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"36") inGroup:@"" atIndex:36]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"35") inGroup:@"" atIndex:35]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"34") inGroup:@"" atIndex:34]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"33") inGroup:@"" atIndex:33]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"32") inGroup:@"" atIndex:32]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"31") inGroup:@"" atIndex:31]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"30") inGroup:@"" atIndex:30]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"29") inGroup:@"" atIndex:29]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"28") inGroup:@"" atIndex:28]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"27") inGroup:@"" atIndex:27]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"26") inGroup:@"" atIndex:26]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"25") inGroup:@"" atIndex:25]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"24") inGroup:@"" atIndex:24]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"23") inGroup:@"" atIndex:23]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"22") inGroup:@"" atIndex:22]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"21") inGroup:@"" atIndex:21]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"20") inGroup:@"" atIndex:20]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"19") inGroup:@"" atIndex:19]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"18") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"17") inGroup:@"" atIndex:17]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"16") inGroup:@"" atIndex:16]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"15") inGroup:@"" atIndex:15]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"14") inGroup:@"" atIndex:14]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"13") inGroup:@"" atIndex:13]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"12") inGroup:@"" atIndex:12]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"11") inGroup:@"" atIndex:11]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"10") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"9") inGroup:@"" atIndex:9]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"8") inGroup:@"" atIndex:8]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"7") inGroup:@"" atIndex:7]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"6") inGroup:@"" atIndex:6]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"5") inGroup:@"" atIndex:5]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"4") inGroup:@"" atIndex:4]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"3") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"2") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"1") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil,  @"0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"53") inGroup:@"" atIndex:3]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"52") inGroup:@"" atIndex:2]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"51") inGroup:@"" atIndex:1]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"50") inGroup:@"" atIndex:0]];
	
	[changes addObject:[YapDatabaseViewSectionChange deleteGroup:@""]];
	
	// Simulate updateWithTransaction,
	// rather than getSectionChanges:rowChanges:::
	
	[mappings updateWithCounts:@{ @"":@(0) } forceUpdateRangeOptions:YES];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Flexible Range: GrowOptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_flexibleRange_11A_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 2, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_11B_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 2, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_11C_beginning
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewBeginning];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 0, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 2, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_11A_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 1, @"");
	
	// Delete item at the beginning of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:1]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_11B_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 1, @"");
	
	// Delete item at the end of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:3]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
}

- (void)test_flexibleRange_11C_end
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:3 offset:0 from:YapDatabaseViewEnd];
	rangeOpts.minLength = 3;
	rangeOpts.growOptions = YapDatabaseViewGrowOnBothSides;
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	XCTAssertTrue([mappings indexForRow:0 inGroup:@""] == 1, @"");
	
	// Delete item in the middle of the range
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
								  rowChanges:&rowChanges
						withOriginalMappings:originalMappings
							   finalMappings:mappings
								 fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([mappings numberOfItemsInGroup:@""] == 3, @"");
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	
	YapDatabaseViewRangePosition rangePosition = [mappings rangePositionForGroup:@""];
	
	XCTAssertTrue(rangePosition.length == 3, @"");
	XCTAssertTrue(rangePosition.offsetFromBeginning == 0, @"");
	XCTAssertTrue(rangePosition.offsetFromEnd == 0, @"");
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
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete an item.
	// Make sure there is a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:17]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 17, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 18, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 17, @"");
}

- (void)test_dependencies_2
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete multiple items right next to each other.
	// Make sure there is only one dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:18]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:18]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(18) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 18, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
}

- (void)test_dependencies_3
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete an item.
	// Update the dependency change, and check for proper changes flags.
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:10]];
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10 withChanges:flags]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 3, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	flags = YapDatabaseViewChangedObject | YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
	
	flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 12, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).changes == flags, @"");
}

- (void)test_dependencies_4
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert an item in the middle.
	// Check for proper dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:10]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 10, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 10, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 11, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
}

- (void)test_dependencies_5
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the very end.
	// There shouldn't be any dependency related changes.
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
}

- (void)test_dependencies_6
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:1 forGroup:@""]; // +1 dependency
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the very end.
	// Make sure there is a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:20]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 20, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 19, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 19, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
}

- (void)test_dependencies_7
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:1 forGroup:@""]; // +1 dependency
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Insert item at the very beginning.
	// There shouldn't be a dependency change.
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(21) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
}

- (void)test_dependencies_8
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(20) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Try hard to mess up the algorithm...
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:10]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key1") inGroup:@"" atIndex:14]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(19) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 4, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 10, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 11, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 14, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 12, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 10, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).changes == flags, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 16, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 15, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).changes == flags, @"");
}

- (void)test_dependencies_9
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Try hard to mess up the algorithm...
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
}

- (void)test_dependencies_10
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOptions =
	  [YapDatabaseViewRangeOptions flexibleRangeWithLength:50 offset:0 from:YapDatabaseViewEnd];
	rangeOptions.maxLength = 150;
	[mappings setRangeOptions:rangeOptions forGroup:@""];
	
	[mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Try hard to mess up the algorithm...
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:0]];
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key0") inGroup:@"" atIndex:2]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 2, @"");
	
	int flags = YapDatabaseViewChangedDependency;
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeUpdate, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).changes == flags, @"");
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
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete an item.
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key5") inGroup:@"" atIndex:5]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
}

- (void)test_reverse_2
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	YapDatabaseViewMappings *originalMappings = [mappings copy];
	
	// Delete an item.
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key5") inGroup:@"" atIndex:0]];
	
	// Fetch changeset
	
	NSArray *rowChanges = nil;
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	[YapDatabaseViewChange getSectionChanges:NULL
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:mappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 4, @"");
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
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings updateWithCounts:@{ @"":@(3) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_2
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(4) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_3
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	    [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_4
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_5
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_6
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_7
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 0, @"Expected 0, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_8
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_9
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:0 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(5) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
}

- (void)test_getter_10
{
	YapDatabaseViewMappings *mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"view"];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:4 offset:1 from:YapDatabaseViewEnd];
	[mappings setRangeOptions:rangeOpts forGroup:@""];
	
	[mappings setIsReversed:YES forGroup:@""];
	
	[mappings updateWithCounts:@{ @"":@(6) } forceUpdateRangeOptions:NO];
	
	// Verify: UI -> View
	
	NSUInteger index;
	
	index = [mappings indexForRow:0 inSection:0];
	XCTAssertTrue(index == 4, @"Expected 4, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:1 inSection:0];
	XCTAssertTrue(index == 3, @"Expected 3, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:2 inSection:0];
	XCTAssertTrue(index == 2, @"Expected 2, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:3 inSection:0];
	XCTAssertTrue(index == 1, @"Expected 1, got %lu", (unsigned long)index);
	
	index = [mappings indexForRow:4 inSection:0];
	XCTAssertTrue(index == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)index);
	
	// Verify: View -> UI
	
	NSUInteger row;
	
	row = [mappings rowForIndex:0 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:1 inGroup:@""];
	XCTAssertTrue(row == 3, @"Expected 3, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:2 inGroup:@""];
	XCTAssertTrue(row == 2, @"Expected 2, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:3 inGroup:@""];
	XCTAssertTrue(row == 1, @"Expected 1, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:4 inGroup:@""];
	XCTAssertTrue(row == 0, @"Expected 0, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:5 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
	
	row = [mappings rowForIndex:6 inGroup:@""];
	XCTAssertTrue(row == NSNotFound, @"Expected NSNotFound, got %lu", (unsigned long)row);
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
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete single item:
	//
	// - [group0, section=0, row=0]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group0], @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_1B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete single item:
	//
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group0], @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group0], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_1C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to collapse (auto consolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group1], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:group0], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:group1], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_2A
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Insert single item:
	//
	// - [group0, section=0, row=0]
	//
	// This should cause all the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_2B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Insert single item:
	//
	// - [group1, section=1, row=1]
	//
	// This should cause the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_2C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:5 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Insert multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// This should cause all the groups to UNcollapse (auto UNconsolidate)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 3, @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 0).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 0).group isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 1).index == 0, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 1).group isEqualToString:group0], @"");
	
	XCTAssertTrue(SectionOp(sectionChanges, 2).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(SectionOp(sectionChanges, 2).index == 1, @"");
	XCTAssertTrue([SectionOp(sectionChanges, 2).group isEqualToString:group1], @"");
	
	XCTAssertTrue([rowChanges count] == 5, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 2).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 2).finalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 2).finalGroup isEqualToString:group0], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 3).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).originalIndex == 1, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 3).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 3).finalGroup isEqualToString:group1], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 4).type == YapDatabaseViewChangeMove, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).originalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).originalGroup isEqualToString:consolidatedGroupName], @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalSection == 1, @"");
	XCTAssertTrue(RowOp(rowChanges, 4).finalIndex == 2, @"");
	XCTAssertTrue([RowOp(rowChanges, 4).finalGroup isEqualToString:group1], @"");
}

- (void)test_autoConsolidateGroups_3A
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete single item:
	//
	// - [group0, section=0, row=0]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3B
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete single item:
	//
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3C
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Delete multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(1), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).originalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeDelete, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).originalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3D
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Insert single item:
	//
	// - [group0, section=0, row=0]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3E
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(2), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Insert single item:
	//
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 1, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_autoConsolidateGroups_3F
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	NSString *group0 = @"g0";
	NSString *group1 = @"g1";
	NSString *consolidatedGroupName = @"auto";
	
	originalMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[group0, group1] view:@"view"];
	[originalMappings setAutoConsolidateGroupsThreshold:20 withName:consolidatedGroupName];
	
	[originalMappings updateWithCounts:@{ group0:@(1), group1:@(2) } forceUpdateRangeOptions:NO];
	
	// Insert multiple items:
	//
	// - [group0, section=0, row=0]
	// - [group1, section=1, row=1]
	//
	// Groups remain collapsed (auto consolidated)
	
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section0,row0") inGroup:group0 atIndex:0]];
	[changes addObject:
	  [YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"section1,row1") inGroup:group1 atIndex:1]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ group0:@(2), group1:@(3) } forceUpdateRangeOptions:NO];
	
	// Fetch changeset
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	// Verify
	
	XCTAssertTrue([sectionChanges count] == 0, @"");
	
	XCTAssertTrue([rowChanges count] == 2, @"");
	
	XCTAssertTrue(RowOp(rowChanges, 0).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 0).finalIndex == 0, @"");
	XCTAssertTrue([RowOp(rowChanges, 0).finalGroup isEqualToString:consolidatedGroupName], @"");
	
	XCTAssertTrue(RowOp(rowChanges, 1).type == YapDatabaseViewChangeInsert, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalSection == 0, @"");
	XCTAssertTrue(RowOp(rowChanges, 1).finalIndex == 3, @"");
	XCTAssertTrue([RowOp(rowChanges, 1).finalGroup isEqualToString:consolidatedGroupName], @"");
}

- (void)test_setting_autoconsolidation_group_name_to_existing_group_should_result_in_nil_groupname_and_zero_threshold
{
	YapDatabaseViewMappings *mapping =
	  [[YapDatabaseViewMappings alloc] initWithGroups:@[@"group1", @"group2"] view:@"view"];
    
    [mapping setAutoConsolidateGroupsThreshold:100 withName:@"group1"];

    XCTAssertNil([mapping consolidatedGroupName]);
    XCTAssertTrue([mapping autoConsolidateGroupsThreshold] == 0);
}
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Dynamic Groups
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface TestViewMappingDynamicGroupAddition : TestViewMappingsBase
@end

@implementation TestViewMappingDynamicGroupAddition

- (void)test_adding_group_should_cause_result_in_section_insert_change
{
	YapDatabaseViewMappings *originalMappings, *finalMappings;
	
    originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		  
		  return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
	  
	  } view:@"view"];
    
    [originalMappings updateWithCounts:@{ @"group1":@(5),
		                                  @"group2":@(3) } forceUpdateRangeOptions:NO];
    
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"group3"]];
	
	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ @"group1":@(5),
	                                   @"group2":@(3),
	                                   @"group3":@(2) } forceUpdateRangeOptions:NO];
    
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
    
    XCTAssertTrue(sectionChanges.count == 1);
    XCTAssertTrue(SectionOp(sectionChanges, 0).type == YapDatabaseViewChangeInsert);
    XCTAssertTrue(SectionOp(sectionChanges, 0).index == 2);
}

- (void)test_adding_empty_group_when_dynamic_section_for_all_groups_is_set_should_not_result_in_section_insert_change
{
    YapDatabaseViewMappings *originalMappings, *finalMappings;
	
	originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		  
	      return YES;
	  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];

	  } view:@"view"];
	
    originalMappings.isDynamicSectionForAllGroups = YES;
    
	[originalMappings updateWithCounts:@{ @"group1":@(5),
	                                      @"group2":@(3) } forceUpdateRangeOptions:NO];

	finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ @"group1":@(5),
	                                   @"group2":@(3),
	                                   @"group3":@(0) } forceUpdateRangeOptions:NO];
	
    
	[changes addObject:[YapDatabaseViewSectionChange insertGroup:@"group3"]];
    
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	XCTAssertTrue(sectionChanges.count == 0);
}

- (void)test_range_options_transfer_when_new_group_is_added
{
	YapDatabaseViewMappings *mappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		  
		  return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
	
	
	mappings.isDynamicSectionForAllGroups = YES;
	
	[mappings updateWithCounts:@{ @"group1":@(30),
	                              @"group2":@(3) } forceUpdateRangeOptions:NO];
	
	YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
	[mappings setRangeOptions:rangeOpts forGroup:@"group1"];
	
	[mappings updateWithCounts:@{ @"group1":@(30),
	                              @"group2":@(3) ,
	                              @"group3":@(1) } forceUpdateRangeOptions:NO];
    
    
    XCTAssertNotNil([mappings rangeOptionsForGroup:@"group1"]);
    XCTAssertTrue([mappings numberOfItemsInGroup:@"group1"] == 20);
    XCTAssertTrue([mappings numberOfItemsInGroup:@"group3"] == 1);
}

- (void)test_range_options_can_be_set_before_update_with_transaction
{
	YapDatabaseViewMappings *mappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		  
		  return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
	
	
    YapDatabaseViewRangeOptions *rangeOpts =
	  [YapDatabaseViewRangeOptions fixedRangeWithLength:10 offset:0 from:YapDatabaseViewBeginning];
    [mappings setRangeOptions:rangeOpts forGroup:@"group2"];
    
	[mappings updateWithCounts:@{ @"group1":@(30),
	                              @"group2":@(15) } forceUpdateRangeOptions:NO];

	XCTAssertNotNil([mappings rangeOptionsForGroup:@"group2"]);
	XCTAssertTrue([mappings numberOfItemsInGroup:@"group2"] == 10);
}

- (void)test_isReversed_can_be_set_before_update_with_transaction
{
	YapDatabaseViewMappings *mappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t) {
		  
		  return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
	
	
	[mappings setIsReversed:YES forGroup:@"group1"];

	[mappings updateWithCounts:@{ @"group1":@(30),
	                              @"group2":@(15) } forceUpdateRangeOptions:NO];
    
	XCTAssertTrue([mappings isReversedForGroup:@"group1"]);
	XCTAssertTrue([mappings indexForRow:29 inGroup:@"group1"] == 0 );
}

- (void)test_dependencies_can_be_set_before_update_with_transaction
{
	YapDatabaseViewMappings *originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		  
		  return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
    
    [originalMappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@"group1"];
	
	[originalMappings updateWithCounts:@{ @"group1":@(30),
	                                      @"group2":@(15) } forceUpdateRangeOptions:NO];
    
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
	
	[changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"") inGroup:@"group1" atIndex:3 withChanges:flags]];
	
	YapDatabaseViewMappings *finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{ @"group1":@(30),
	                                   @"group2":@(15) } forceUpdateRangeOptions:NO];
    
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
    [YapDatabaseViewChange getSectionChanges:&sectionChanges
                                  rowChanges:&rowChanges
                        withOriginalMappings:originalMappings
                               finalMappings:finalMappings
                                 fromChanges:changes];
    
	NSSet *expectedSet = [NSSet setWithObject:@(-1)];
	
    XCTAssertTrue([[originalMappings cellDrawingDependencyOffsetsForGroup:@"group1"] isEqualToSet:expectedSet]);
    XCTAssertTrue(rowChanges.count == 2);
    XCTAssertTrue(RowOp(rowChanges, 0).changes == YapDatabaseViewChangedObject);
    XCTAssertTrue(RowOp(rowChanges, 0).originalIndex == 3);
    XCTAssertTrue(RowOp(rowChanges, 1).changes == YapDatabaseViewChangedDependency);
    XCTAssertTrue(RowOp(rowChanges, 1).originalIndex == 4);
}

- (void)test_row_insert_in_removed_group_get_filtered_out
{
	YapDatabaseViewMappings *originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		
		  return YES;
		
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
	
	
    [originalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3),
	    @"group3":@(2) } forceUpdateRangeOptions:NO];
	
	[changes addObject:[YapDatabaseViewRowChange insertCollectionKey:YCK(nil, @"key") inGroup:@"group3" atIndex:2]];
	
	YapDatabaseViewMappings *finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3) } forceUpdateRangeOptions:NO];
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	XCTAssertTrue([rowChanges count] == 0);
}

- (void)test_row_update_in_removed_group_get_filtered_out
{
	YapDatabaseViewMappings *originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t) {
		
	      return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t) {
		  
		  return [l compare:r];
	  
	  } view:@"view"];
	
	
	[originalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3),
	    @"group3":@(2) } forceUpdateRangeOptions:NO];
	
	YapDatabaseViewChangesBitMask flags = YapDatabaseViewChangedObject;
    [changes addObject:
	  [YapDatabaseViewRowChange updateCollectionKey:YCK(nil, @"key") inGroup:@"group3" atIndex:0 withChanges:flags]];
	
	YapDatabaseViewMappings *finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3) } forceUpdateRangeOptions:NO];
	
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	XCTAssertTrue([rowChanges count] == 0);
}

- (void)test_row_delete_in_removed_group_does_not_get_filtered_out
{
	YapDatabaseViewMappings *originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		
	      return YES;
		  
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
	  
	  } view:@"view"];
	
	[originalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3),
	    @"group3":@(2) } forceUpdateRangeOptions:NO];
	
	[changes addObject:[YapDatabaseViewRowChange deleteCollectionKey:YCK(nil, @"key") inGroup:@"group3" atIndex:0]];
	
	YapDatabaseViewMappings *finalMappings = [originalMappings copy];
	[finalMappings updateWithCounts:@{
	    @"group1":@(5),
	    @"group2":@(3) } forceUpdateRangeOptions:NO];
    
	NSArray *sectionChanges = nil;
	NSArray *rowChanges = nil;
	
	[YapDatabaseViewChange getSectionChanges:&sectionChanges
	                              rowChanges:&rowChanges
	                    withOriginalMappings:originalMappings
	                           finalMappings:finalMappings
	                             fromChanges:changes];
	
	XCTAssertTrue([rowChanges count] == 1);
}

- (void)test_consolidation_threshhold_and_group_name_get_cleared_on_update_transaction_if_name_is_in_new_groups
{
	YapDatabaseViewMappings *originalMappings =
	  [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL(NSString *g, YapDatabaseReadTransaction *t){
		
	      return YES;
	
	  } sortBlock:^NSComparisonResult(NSString *l, NSString *r, YapDatabaseReadTransaction *t){
		  
		  return [l compare:r];
		  
	  } view:@"view"];
	
	
	[originalMappings setAutoConsolidateGroupsThreshold:100 withName:@"super-omega-group"];
	
	XCTAssertEqualObjects([originalMappings consolidatedGroupName], @"super-omega-group");
	XCTAssertTrue([originalMappings autoConsolidateGroupsThreshold] == 100);
	
	[originalMappings updateWithCounts:@{
	    @"group1":@(30),
	    @"group2":@(15),
	    @"super-omega-group":@(10) } forceUpdateRangeOptions:NO];
	
	XCTAssertNil([originalMappings consolidatedGroupName]);
	XCTAssertTrue([originalMappings autoConsolidateGroupsThreshold] == 0);
}

@end

