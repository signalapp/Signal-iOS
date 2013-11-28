#import <SenTestingKit/SenTestingKit.h>

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabaseView.h"
#import "YapCollectionsDatabaseFilteredView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

@interface TestYapCollectionsDatabaseFilteredView : SenTestCase
@end

@implementation TestYapCollectionsDatabaseFilteredView

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
/*
- (void)test_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _test_withPath:databasePath options:options];
}

- (void)test_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _test_withPath:databasePath options:options];
}

- (void)_test_withPath:(NSString *)databasePath options:(YapCollectionsDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapCollectionsDatabase *database = [[YapCollectionsDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapCollectionsDatabaseConnection *connection1 = [database newConnection];
	YapCollectionsDatabaseConnection *connection2 = [database newConnection];
	
	YapCollectionsDatabaseViewBlockType groupingBlockType;
	YapCollectionsDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapCollectionsDatabaseViewBlockType sortingBlockType;
	YapCollectionsDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapCollectionsDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapCollectionsDatabaseView *view =
	  [[YapCollectionsDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                          groupingBlockType:groupingBlockType
	                                               sortingBlock:sortingBlock
	                                           sortingBlockType:sortingBlockType
	                                                    version:0
	                                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapCollectionsDatabaseViewBlockType filteringBlockType;
	YapCollectionsDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapCollectionsDatabaseFilteredView *filteredView =
	  [[YapCollectionsDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                      filteringBlock:filteringBlock
	                                                  filteringBlockType:filteringBlockType];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
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
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}
*/
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
- (void)testScratch_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testScratch_withPath:databasePath options:options];
}

- (void)testScratch_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testScratch_withPath:databasePath options:options];
}

- (void)_testScratch_withPath:(NSString *)databasePath options:(YapCollectionsDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapCollectionsDatabase *database = [[YapCollectionsDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapCollectionsDatabaseConnection *connection1 = [database newConnection];
	YapCollectionsDatabaseConnection *connection2 = [database newConnection];
	
	YapCollectionsDatabaseViewBlockType groupingBlockType;
	YapCollectionsDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapCollectionsDatabaseViewBlockType sortingBlockType;
	YapCollectionsDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapCollectionsDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapCollectionsDatabaseView *view =
	  [[YapCollectionsDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                          groupingBlockType:groupingBlockType
	                                               sortingBlock:sortingBlock
	                                           sortingBlockType:sortingBlockType
	                                                    version:0
	                                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
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
	
	YapCollectionsDatabaseViewBlockType filteringBlockType;
	YapCollectionsDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapCollectionsDatabaseFilteredView *filteredView =
	  [[YapCollectionsDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                      filteringBlock:filteringBlock
	                                                  filteringBlockType:filteringBlockType];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
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
*/
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testRepopulate_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testRepopulate_withPath:databasePath options:options];
}

- (void)testRepopulate_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapCollectionsDatabaseViewOptions *options = [[YapCollectionsDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testRepopulate_withPath:databasePath options:options];
}

- (void)_testRepopulate_withPath:(NSString *)databasePath options:(YapCollectionsDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapCollectionsDatabase *database = [[YapCollectionsDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapCollectionsDatabaseConnection *connection1 = [database newConnection];
	YapCollectionsDatabaseConnection *connection2 = [database newConnection];
	
	YapCollectionsDatabaseViewBlockType groupingBlockType;
	YapCollectionsDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapCollectionsDatabaseViewBlockType sortingBlockType;
	YapCollectionsDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapCollectionsDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key){
		
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2){
		
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapCollectionsDatabaseView *view =
	  [[YapCollectionsDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                          groupingBlockType:groupingBlockType
	                                               sortingBlock:sortingBlock
	                                           sortingBlockType:sortingBlockType
	                                                    version:0
	                                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	STAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapCollectionsDatabaseViewBlockType filteringBlockType;
	YapCollectionsDatabaseViewFilteringBlock filteringBlock;
	
	filteringBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object){
		
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	};
	
	YapCollectionsDatabaseFilteredView *filteredView =
	  [[YapCollectionsDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                      filteringBlock:filteringBlock
	                                                  filteringBlockType:filteringBlockType
	                                                                 tag:@"even"];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	STAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
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
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	//
	// Now update the filterBlock
	//
	
	filteringBlockType = YapCollectionsDatabaseViewBlockTypeWithObject;
	filteringBlock = ^BOOL (NSString *group, NSString *collection, NSString *key, id object){
		
		int num = [(NSNumber *)object intValue];
		
		if ((num % 2 == 0) || (num % 5 == 0))
			return YES; // even OR divisable by 5
		else
			return NO;  // odd
	};
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter"] setFilteringBlock:filteringBlock
		                            filteringBlockType:filteringBlockType
		                                           tag:@"even+5"];
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfKeysInGroup:@""];
		
		STAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		STAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}

@end
