#import <SenTestingKit/SenTestingKit.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseFilteredView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

@interface TestYapDatabaseFilteredView : SenTestCase
@end

@implementation TestYapDatabaseFilteredView

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"%@-%@.sqlite", THIS_FILE, suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)setUp
{
    [super setUp];
	[DDLog removeAllLoggers];
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
}

- (void)tearDown
{
    [DDLog flushLog];
	[super tearDown];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _test_withPath:databasePath options:options];
}

- (void)test_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _test_withPath:databasePath options:options];
}

- (void)_test_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewBlockType filteringBlockType;
	YapDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock
	                                       filteringBlockType:filteringBlockType];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		
		STAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		STAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testScratch_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testScratch_withPath:databasePath options:options];
}

- (void)testScratch_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testScratch_withPath:databasePath options:options];
}

- (void)_testScratch_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		STAssertNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
	}];
	
	YapDatabaseViewBlockType filteringBlockType;
	YapDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock
	                                       filteringBlockType:filteringBlockType];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		STAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}
 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testRepopulate_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testRepopulate_withPath:databasePath options:options];
}

- (void)testRepopulate_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testRepopulate_withPath:databasePath options:options];
}

- (void)_testRepopulate_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key){
		
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2){
		
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewBlockType filteringBlockType;
	YapDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object){
		
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock
	                                       filteringBlockType:filteringBlockType
	                                               versionTag:@"even"];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		
		STAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		STAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	//
	// Now update the filterBlock
	//
	
	filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object){
		
		int num = [(NSNumber *)object intValue];
		
		if ((num % 2 == 0) || (num % 5 == 0))
			return YES; // even OR divisable by 5
		else
			return NO;  // odd
	};
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter"] setFilteringBlock:filteringBlock
		                            filteringBlockType:filteringBlockType
		                                    versionTag:@"even+5"];
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testUnregistration_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testUnregistration_withPath:databasePath options:options];
}

- (void)testUnregistration_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testUnregistration_withPath:databasePath options:options];
}

- (void)_testUnregistration_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewBlockType filteringBlockType;
	YapDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock
	                                       filteringBlockType:filteringBlockType];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	// Make sure the extensions are visible
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		STAssertNotNil([transaction ext:@"filter"], @"Expected YapDatabaseFilteredViewTransaction");
	}];
	
	// Now unregister the view, and make sure it automatically unregisters the filteredView too.
	
	[database unregisterExtension:@"order"];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNil([transaction ext:@"order"], @"Expected nil");
		STAssertNil([transaction ext:@"filter"], @"Expected nil");
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testDoubleUnregistration_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testDoubleUnregistration_withPath:databasePath options:options];
}

- (void)testDoubleUnregistration_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testDoubleUnregistration_withPath:databasePath options:options];
}

- (void)_testDoubleUnregistration_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewBlockType filteringBlockType1;
	YapDatabaseViewFilteringBlock filteringBlock1;
	
	filteringBlockType1 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock1 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView1 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock1
	                                       filteringBlockType:filteringBlockType1];
	
	BOOL registerResult2 = [database registerExtension:filteredView1 withName:@"filter1"];
	STAssertTrue(registerResult2, @"Failure registering filteredView1 extension");
	
	YapDatabaseViewBlockType filteringBlockType2;
	YapDatabaseViewFilteringBlock filteringBlock2;
	
	filteringBlockType2 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock2 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 100)
			return YES; // even && within range
		else
			return NO;  // odd || out of range
	};
	
	YapDatabaseFilteredView *filteredView2 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"filter1"
	                                           filteringBlock:filteringBlock2
	                                       filteringBlockType:filteringBlockType2];
	
	BOOL registerResult3 = [database registerExtension:filteredView2 withName:@"filter2"];
	STAssertTrue(registerResult3, @"Failure registering filteredView2 extension");
	
	// Make sure the extensions are visible
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		STAssertNotNil([transaction ext:@"filter1"], @"Expected YapDatabaseFilteredViewTransaction");
		STAssertNotNil([transaction ext:@"filter2"], @"Expected YapDatabaseFilteredViewTransaction");
	}];
	
	// Now unregister the view, and make sure it automatically unregisters the filteredView too.
	
	[database unregisterExtension:@"order"];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNil([transaction ext:@"order"], @"Expected nil");
		STAssertNil([transaction ext:@"filter1"], @"Expected nil");
		STAssertNil([transaction ext:@"filter2"], @"Expected nil");
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testDoubleDependencyPlusChangeFilterBlock_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testDoubleDependencyPlusChangeFilterBlock_withPath:databasePath options:options];
}

- (void)testDoubleDependencyPlusChangeFilterBlock_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testDoubleDependencyPlusChangeFilterBlock_withPath:databasePath options:options];
}

- (void)_testDoubleDependencyPlusChangeFilterBlock_withPath:(NSString *)databasePath
                                                    options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewBlockType filteringBlockType1;
	YapDatabaseViewFilteringBlock filteringBlock1;
	
	filteringBlockType1 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock1 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapDatabaseFilteredView *filteredView1 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock1
	                                       filteringBlockType:filteringBlockType1
	                                               versionTag:@"1"];
	
	BOOL registerResult2 = [database registerExtension:filteredView1 withName:@"filter1"];
	STAssertTrue(registerResult2, @"Failure registering filteredView1 extension");
	
	YapDatabaseViewBlockType filteringBlockType2;
	YapDatabaseViewFilteringBlock filteringBlock2;
	
	filteringBlockType2 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock2 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 100)
			return YES; // within range
		else
			return NO;  // out of range
	};
	
	YapDatabaseFilteredView *filteredView2 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"filter1"
	                                           filteringBlock:filteringBlock2
	                                       filteringBlockType:filteringBlockType2
	                                               versionTag:@"1"];
	
	BOOL registerResult3 = [database registerExtension:filteredView2 withName:@"filter2"];
	STAssertTrue(registerResult3, @"Failure registering filteredView2 extension");
	
	// Make sure the extensions are visible
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		STAssertNotNil([transaction ext:@"filter1"], @"Expected YapDatabaseFilteredViewTransaction");
		STAssertNotNil([transaction ext:@"filter2"], @"Expected YapDatabaseFilteredViewTransaction");
	}];
	
	// Now add a bunch of numbers to the views
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 200; i++)
		{
			NSString *key = [NSString stringWithFormat:@"%d", i];
			NSNumber *number = @(i);
			
			[transaction setObject:number forKey:key inCollection:nil];
		}
	}];
	
	// Make sure the views are working correctly
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 50, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 50, @"");
	}];
	
	filteringBlock1 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return YES; // OR odd <<----
	};
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter1"] setFilteringBlock:filteringBlock1
									 filteringBlockType:filteringBlockType1
											 versionTag:@"2"];
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter2"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 100, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter2"] numberOfKeysInGroup:@""];
		STAssertTrue(count == 100, @"");
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testEmptyFilterMappings_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];

	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;

	[self _testEmptyFilterMappings_withPath:databasePath options:options];
}

- (void)testEmptyFilterMappings_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];

	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;

	[self _testEmptyFilterMappings_withPath:databasePath options:options];
}

- (void)_testEmptyFilterMappings_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];

	STAssertNotNil(database, @"Oops");

	YapDatabaseConnection *connection1 = [database newConnection];
    YapDatabaseConnection *connection2 = [database newConnection];
    YapDatabaseConnection *connection3 = [database newConnection];

	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;

	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;

	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};

	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
                     NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;

		return [number1 compare:number2];
	};

	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"0"
	                                         options:options];

	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");

	YapDatabaseViewBlockType filteringBlockType1;
	YapDatabaseViewFilteringBlock filteringBlock1;

	filteringBlockType1 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock1 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;

		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};

	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                           filteringBlock:filteringBlock1
	                                       filteringBlockType:filteringBlockType1
	                                               versionTag:@"0"];

	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");


    YapDatabaseViewMappings *mappings =
    [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"filter"];

    [connection1 beginLongLivedReadTransaction];
    [connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [mappings updateWithTransaction:transaction];
    }];

	__block int notificationCount = 0;
	id observer =
	  [[NSNotificationCenter defaultCenter] addObserverForName:YapDatabaseModifiedNotification
	                                                    object:nil
	                                                     queue:[NSOperationQueue mainQueue]
	                                                usingBlock:^(NSNotification *note)
	{
		notificationCount++;
	}];

	NSTimeInterval timeout = 1.0;   // Number of seconds before giving up
	NSTimeInterval idle = 0.01;     // Number of seconds to pause within loop
	BOOL timedOut = NO;
	NSDate *timeoutDate = nil;
	
	// --- Flush NSNotification queue. There are pending notifications from the extension registrations.
	
	timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }
	
	// --- Try setting a regular filter
	
	[connection3 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFilteringBlock:filteringBlock1
		                                  filteringBlockType:filteringBlockType1
		                                          versionTag:@"1"];
	}];
	
	notificationCount = 0;
	
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }
	
    STAssertEquals(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);
	
	// --- Try setting an empty filter
	
	YapDatabaseViewBlockType filteringBlockType2;
	YapDatabaseViewFilteringBlock filteringBlock2;

	filteringBlockType2 = YapDatabaseViewBlockTypeWithObject;
	filteringBlock2 = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
        return NO;
	};

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFilteringBlock:filteringBlock2
		                                  filteringBlockType:filteringBlockType2
		                                          versionTag:@"2"];
	}];

	notificationCount = 0;
	
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }

    STAssertEquals(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);

    // --- Try setting a regular filter

    [connection3 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFilteringBlock:filteringBlock1
		                                  filteringBlockType:filteringBlockType1
		                                          versionTag:@"3"];
	}];

	notificationCount = 0;
	
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }

    STAssertEquals(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);

    // --- Try setting an empty filter

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFilteringBlock:filteringBlock2
		                                  filteringBlockType:filteringBlockType2
		                                          versionTag:@"emptytag"];
	}];
	
	notificationCount = 0;

    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }

    STAssertEquals(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);
    
    // ---
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    [database unregisterExtension:@"order"];
//	[database unregisterExtension:@"filter"]; // <- will get automatically unregistered with order (b/c of dependency)
}

@end
