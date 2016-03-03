#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseFilteredView.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

@interface TestYapDatabaseFilteredView : XCTestCase
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

- (void)test_badInit
{
	dispatch_block_t exceptionBlock = ^{
		
		YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
		    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
		{
			if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
				return nil;
			else
				return @"";
		}];
		
		YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		    ^(YapDatabaseReadTransaction *transaction, NSString *group,
		        NSString *collection1, NSString *key1, id obj1,
		        NSString *collection2, NSString *key2, id obj2)
		{
			__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
			__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
			
			return [number1 compare:number2];
		}];
		
		(void)[[YapDatabaseFilteredView alloc] initWithGrouping:grouping
		                                                sorting:sorting
		                                             versionTag:@"xyz"
		                                                options:nil];
	};
	
	XCTAssertThrows(exceptionBlock(), @"Should have thrown an exception");
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSString *group,
	        NSString *collection1, NSString *key1, id obj1,
	        NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	NSString *order_initialVersionTag = @"1";
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:order_initialVersionTag
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *versionTag = [[transaction ext:@"order"] versionTag];
		XCTAssert([versionTag isEqualToString:order_initialVersionTag], @"Bad versionTag");
	}];
	
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
		^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	NSString *filter_initialVersionTag = @"1";
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering
	                                               versionTag:filter_initialVersionTag];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *versionTag = [[transaction ext:@"filter"] versionTag];
		XCTAssert([versionTag isEqualToString:filter_initialVersionTag], @"Bad versionTag");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		XCTAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	connection1 = nil;
	connection2 = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_skipInitialPopulationView_persistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.skipInitialViewPopulation = YES;
    
    [self _testSkipInitialPopulationView_withPath:databasePath options:options];
}

- (void)test_skipInitialPopulationView_nonPersistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = NO;
    options.skipInitialViewPopulation = YES;
    
    [self _testSkipInitialPopulationView_withPath:databasePath options:options];
}

- (void)test_notskipInitialPopulationView_persistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.skipInitialViewPopulation = NO;
    
    [self _testSkipInitialPopulationView_withPath:databasePath options:options];
}

- (void)test_notskipInitialPopulationView_nonPersistent
{
    NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = NO;
    options.skipInitialViewPopulation = NO;
    
    [self _testSkipInitialPopulationView_withPath:databasePath options:options];
}

- (void)_testSkipInitialPopulationView_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
    [[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
    YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
    
    XCTAssertNotNil(database, @"Oops");
    
    YapDatabaseConnection *connection1 = [database newConnection];
    YapDatabaseConnection *connection2 = [database newConnection];
    
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
		^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
    
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
    
    NSString *order_initialVersionTag = @"1";
    
    YapDatabaseView *view =
    [[YapDatabaseView alloc] initWithGrouping:grouping
                                      sorting:sorting
                                   versionTag:order_initialVersionTag
                                      options:options];
    
    BOOL registerResult1 = [database registerExtension:view withName:@"order"];
    XCTAssertTrue(registerResult1, @"Failure registering view extension");
    
    [connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        
        NSString *versionTag = [[transaction ext:@"order"] versionTag];
        XCTAssert([versionTag isEqualToString:order_initialVersionTag], @"Bad versionTag");
    }];
    
    YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
		^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
    
    NSString *filter_initialVersionTag = @"1";
    
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering
	                                               versionTag:filter_initialVersionTag
	                                                  options:options];
    
    // Without registering the view,
    // add a bunch of keys to the database.
    
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        
        for (int i = 0; i < 100; i++)
        {
            NSString *key = [NSString stringWithFormat:@"key%d", i];
            
            [transaction setObject:@(i) forKey:key inCollection:nil];
        }
    }];
    
    BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
    XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");
    
    [connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        
        NSUInteger orderCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
        if (options.skipInitialViewPopulation) {
            XCTAssertTrue(orderCount == 0, @"Bad count in view. Expected 0, got %d", (int)orderCount);
        } else {
            XCTAssertTrue(orderCount == 50, @"Bad count in view. Expected 0, got %d", (int)orderCount);
        }
    }];
    
    [connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        
        NSUInteger orderCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
        if (options.skipInitialViewPopulation) {
            XCTAssertTrue(orderCount == 0, @"Bad count in view. Expected 0, got %d", (int)orderCount);
        } else {
            XCTAssertTrue(orderCount == 50, @"Bad count in view. Expected 0, got %d", (int)orderCount);
        }
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		XCTAssertNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
	}];
	
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		XCTAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering
	                                               versionTag:@"even"];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected view extension");
		XCTAssertNotNil([transaction ext:@"filter"], @"Expected filteredView extension");
		
		[transaction setObject:[NSNull null] forKey:@"keyX" inCollection:nil];
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:@(i) forKey:key inCollection:nil];
		}
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == 50, @"Bad count in filter. Expected 50, got %d", (int)filterCount);
	}];
	
	//
	// Now update the filterBlock
	//
	
	filtering = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		int num = [(NSNumber *)object intValue];
		
		if ((num % 2 == 0) || (num % 5 == 0))
			return YES; // even OR divisable by 5
		else
			return NO;  // odd
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter"] setFiltering:filtering
		                               versionTag:@"even+5"];
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		NSUInteger orderCount = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		NSUInteger filterCount = [[transaction ext:@"filter"] numberOfItemsInGroup:@""];
		
		XCTAssertTrue(orderCount == 100, @"Bad count in view. Expected 100, got %d", (int)orderCount);
		XCTAssertTrue(filterCount == (50 + 10), @"Bad count in filter. Expected 60, got %d", (int)filterCount);
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering];
	
	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");
	
	// Make sure the extensions are visible
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter"], @"Expected YapDatabaseFilteredViewTransaction");
	}];
	
	// Now unregister the view, and make sure it automatically unregisters the filteredView too.
	
	[database unregisterExtensionWithName:@"order"];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction ext:@"order"], @"Expected nil");
		XCTAssertNil([transaction ext:@"filter"], @"Expected nil");
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewFiltering *filtering1 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	YapDatabaseFilteredView *filteredView1 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering1];
	
	BOOL registerResult2 = [database registerExtension:filteredView1 withName:@"filter1"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView1 extension");
	
	YapDatabaseViewFiltering *filtering2 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 100)
			return YES; // even && within range
		else
			return NO;  // odd || out of range
	}];
	
	YapDatabaseFilteredView *filteredView2 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"filter1"
	                                                filtering:filtering2];
	
	BOOL registerResult3 = [database registerExtension:filteredView2 withName:@"filter2"];
	XCTAssertTrue(registerResult3, @"Failure registering filteredView2 extension");
	
	// Make sure the extensions are visible
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter1"], @"Expected YapDatabaseFilteredViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter2"], @"Expected YapDatabaseFilteredViewTransaction");
	}];
	
	// Now unregister the view, and make sure it automatically unregisters both filteredViews too.
	
	[database unregisterExtensionWithName:@"order"];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction ext:@"order"], @"Expected nil");
		XCTAssertNil([transaction ext:@"filter1"], @"Expected nil");
		XCTAssertNil([transaction ext:@"filter2"], @"Expected nil");
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
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewFiltering *filtering1 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];
	
	YapDatabaseFilteredView *filteredView1 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering1
	                                               versionTag:@"1"];
	
	BOOL registerResult2 = [database registerExtension:filteredView1 withName:@"filter1"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView1 extension");
	
	YapDatabaseViewFiltering *filtering2 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 100)
			return YES; // within range
		else
			return NO;  // out of range
	}];
	
	YapDatabaseFilteredView *filteredView2 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"filter1"
	                                                filtering:filtering2
	                                               versionTag:@"1"];
	
	BOOL registerResult3 = [database registerExtension:filteredView2 withName:@"filter2"];
	XCTAssertTrue(registerResult3, @"Failure registering filteredView2 extension");
	
	// Make sure the extensions are visible
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter1"], @"Expected YapDatabaseFilteredViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter2"], @"Expected YapDatabaseFilteredViewTransaction");
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
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
	}];
	
	// Now update the filteringBlock, and make sure the dependent filteredView is also updated properly
	
	filtering1 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return YES; // odd <<---- changed
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter1"] setFiltering:filtering1 versionTag:@"2"];
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
	}];
	
	// Now update the filteringBlock (again), and make sure the dependent filteredView is also updated properly
	
	filtering1 = [YapDatabaseViewFiltering withObjectBlock:
		^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return NO;  // even <<---- changed
		else
			return YES; // odd
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"filter1"] setFiltering:filtering1 versionTag:@"3"];
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
	}];

}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testDoubleDependencyPlusChangeGroupingBlock_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testDoubleDependencyPlusChangeGroupingBlock_withPath:databasePath options:options];
}

- (void)testDoubleDependencyPlusChangeGroupingBlock_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testDoubleDependencyPlusChangeGroupingBlock_withPath:databasePath options:options];
}

- (void)_testDoubleDependencyPlusChangeGroupingBlock_withPath:(NSString *)databasePath
                                                      options:(YapDatabaseViewOptions *)options
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return @""; // even
		else
			return nil; // odd
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	}];
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:options];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	YapDatabaseViewFiltering *filtering1 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 100)
			return YES; // within range
		else
			return NO;  // out of range
	}];
	
	YapDatabaseFilteredView *filteredView1 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering1
	                                               versionTag:@"1"];
	
	BOOL registerResult2 = [database registerExtension:filteredView1 withName:@"filter1"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView1 extension");
	
	YapDatabaseViewFiltering *filtering2 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] < 50)
			return YES; // within range
		else
			return NO;  // out of range
	}];
	
	YapDatabaseFilteredView *filteredView2 =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"filter1"
	                                                filtering:filtering2
	                                               versionTag:@"1"];
	
	BOOL registerResult3 = [database registerExtension:filteredView2 withName:@"filter2"];
	XCTAssertTrue(registerResult3, @"Failure registering filteredView2 extension");
	
	// Make sure the extensions are visible
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNotNil([transaction ext:@"order"], @"Expected YapDatabaseViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter1"], @"Expected YapDatabaseFilteredViewTransaction");
		XCTAssertNotNil([transaction ext:@"filter2"], @"Expected YapDatabaseFilteredViewTransaction");
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
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 25, @"");
		
	//	[[transaction ext:@"filter1"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter1: key: %@", key);
	//	}];
	//
	//	[[transaction ext:@"filter2"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter2: key: %@", key);
	//	}];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 25, @"");
	}];
	
//	NSLog(@"===========================================================================================");
	
	// Now update the groupingBlock, and make sure the dependent filteredView's are also updated properly
	
	grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return @""; // even
		else
			return @""; // odd <<----- changed
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"order"] setGrouping:grouping
		                                sorting:sorting
		                             versionTag:@"2"];
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
		
	//	[[transaction ext:@"filter1"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter1: key: %@", key);
	//	}];
	//
	//	[[transaction ext:@"filter2"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter2: key: %@", key);
	//	}];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 200, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
	}];
	
//	NSLog(@"===========================================================================================");
	
	// Now update the groupingBlock (again), and make sure the dependent filteredView's are also updated properly
	
	grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;
		
		if ([number intValue] % 2 == 0)
			return nil; // even <<----- changed
		else
			return @""; // odd
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"order"] setGrouping:grouping
		                                sorting:sorting
		                             versionTag:@"3"];
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 25, @"");
		
	//	[[transaction ext:@"filter1"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter1: key: %@", key);
	//	}];
	//
	//	[[transaction ext:@"filter2"] enumerateKeysInGroup:@""
	//	                                usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"filter2: key: %@", key);
	//	}];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 100, @"");
		
		count = [[transaction ext:@"filter1"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 50, @"");
		
		count = [[transaction ext:@"filter2"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 25, @"");
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

	XCTAssertNotNil(database, @"Oops");

	YapDatabaseConnection *connection1 = [database newConnection];
    YapDatabaseConnection *connection2 = [database newConnection];
    YapDatabaseConnection *connection3 = [database newConnection];

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	}];

	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
		    NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
		__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;

		return [number1 compare:number2];
	}];

	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"0"
	                                    options:options];

	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");

	YapDatabaseViewFiltering *filtering1 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
		__unsafe_unretained NSNumber *number = (NSNumber *)object;

		if ([number intValue] % 2 == 0)
			return YES; // even
		else
			return NO;  // odd
	}];

	YapDatabaseFilteredView *filteredView =
	  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"order"
	                                                filtering:filtering1
	                                               versionTag:@"0"];

	BOOL registerResult2 = [database registerExtension:filteredView withName:@"filter"];
	XCTAssertTrue(registerResult2, @"Failure registering filteredView extension");


    YapDatabaseViewMappings *mappings =
    [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:@"filter"];

    [connection1 beginLongLivedReadTransaction];
    [connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [mappings updateWithTransaction:transaction];
    }];

	__block int notificationCount = 0;
	id observer =
	  [[NSNotificationCenter defaultCenter] addObserverForName:YapDatabaseModifiedNotification
	                                                    object:database
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
		
		[[transaction extension:@"filter"] setFiltering:filtering1 versionTag:@"1"];
	}];
	
	notificationCount = 0;
	
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }
	
    XCTAssertEqual(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);
	
	// --- Try setting an empty filter
	
	YapDatabaseViewFiltering *filtering2 = [YapDatabaseViewFiltering withObjectBlock:
	    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group, NSString *collection, NSString *key, id object)
	{
        return NO;
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFiltering:filtering2
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

    XCTAssertEqual(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);

    // --- Try setting a regular filter

    [connection3 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFiltering:filtering1 versionTag:@"3"];
	}];

	notificationCount = 0;
	
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }

    XCTAssertEqual(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);

    // --- Try setting an empty filter

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction extension:@"filter"] setFiltering:filtering2
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

    XCTAssertEqual(notificationCount, 1, @"Expected notification (%d notifications)", notificationCount);
    
    // ---
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    
    [database unregisterExtensionWithName:@"order"];
	// The @"filter" extension will get automatically unregistered with order (b/c of dependency)
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * https://github.com/yapstudios/YapDatabase/issues/186
**/

- (void)testIssue186_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testIssue186_withPath:databasePath options:options];
}

- (void)testIssue186_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testIssue186_withPath:databasePath options:options];
}

- (void)_testIssue186_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	BOOL registerResult;
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	{ // Create "view-object"
	
		YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
		    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
		{
			return @"";
		}];
		
		YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		    ^(YapDatabaseReadTransaction *transaction, NSString *group,
		        NSString *collection1, NSString *key1, id obj1,
		        NSString *collection2, NSString *key2, id obj2)
		{
			NSParameterAssert(obj1 != nil);
			NSParameterAssert(obj2 != nil);
			
			__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
			__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
			
			return [number1 compare:number2];
		}];

		YapDatabaseView *view =
		  [[YapDatabaseView alloc] initWithGrouping:grouping
		                                    sorting:sorting
		                                 versionTag:@"0"
		                                    options:options];
		
		registerResult = [database registerExtension:view withName:@"view-object"];
		XCTAssertTrue(registerResult, @"Failure registering view extension");
	}
	
	{ // Create "view-metadata"
	
		YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
		    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
		{
			return @"";
		}];
		
		YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withMetadataBlock:
		    ^(YapDatabaseReadTransaction *transaction, NSString *group,
		        NSString *collection1, NSString *key1, id obj1,
		        NSString *collection2, NSString *key2, id obj2)
		{
			NSParameterAssert(obj1 != nil);
			NSParameterAssert(obj2 != nil);
			
			__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
			__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;

			return [number1 compare:number2];
		}];

		YapDatabaseView *view =
		  [[YapDatabaseView alloc] initWithGrouping:grouping
		                                    sorting:sorting
		                                 versionTag:@"0"
		                                    options:options];
		
		registerResult = [database registerExtension:view withName:@"view-metadata"];
		XCTAssertTrue(registerResult, @"Failure registering view extension");
	}
		
	{ // Create "filter-object-even"
	
		YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withObjectBlock:
		    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group,
		             NSString *collection, NSString *key, id object)
		{
			NSParameterAssert(object != nil);
			
			__unsafe_unretained NSNumber *number = (NSNumber *)object;

			if ([number intValue] % 2 == 0)
				return YES; // even
			else
				return NO;  // odd
		}];
	
		YapDatabaseFilteredView *filteredView =
		  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"view-object"
		                                                filtering:filtering
		                                               versionTag:@"0"];

		registerResult = [database registerExtension:filteredView withName:@"filter-object-even"];
		XCTAssertTrue(registerResult, @"Failure registering filteredView extension");
	}
	
	{ // Create "filter-metadata-odd"
	
		YapDatabaseViewFiltering *oddFiltering = [YapDatabaseViewFiltering withMetadataBlock:
		    ^BOOL (YapDatabaseReadTransaction *transaction, NSString *group,
		             NSString *collection, NSString *key, id metadata)
		{
			NSParameterAssert(metadata != nil);
			
			__unsafe_unretained NSNumber *number = (NSNumber *)metadata;

			if ([number intValue] % 2 == 0)
				return NO; // even
			else
				return YES;  // odd
		}];
	
		YapDatabaseFilteredView *oddFilteredView =
		  [[YapDatabaseFilteredView alloc] initWithParentViewName:@"view-metadata"
		                                                filtering:oddFiltering
		                                               versionTag:@"0"];

		registerResult = [database registerExtension:oddFilteredView withName:@"filter-metadata-odd"];
		XCTAssertTrue(registerResult, @"Failure registering filteredView extension");
	}
	
	// Add a couple items
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@(0) forKey:@"even-even" inCollection:nil withMetadata:@(0)];
		[transaction setObject:@(0) forKey:@"even-odd"  inCollection:nil withMetadata:@(1)];
		[transaction setObject:@(1) forKey:@"odd-even"  inCollection:nil withMetadata:@(0)];
		[transaction setObject:@(1) forKey:@"odd-odd"   inCollection:nil withMetadata:@(1)];
		
		NSUInteger count;
		
		count = [[transaction ext:@"filter-object-even"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
		
		count = [[transaction ext:@"filter-metadata-odd"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"filter-object-even"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
		
		count = [[transaction ext:@"filter-metadata-odd"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction replaceObject:@(2) forKey:@"even-even" inCollection:nil];
		[transaction replaceObject:@(2) forKey:@"even-odd"  inCollection:nil];
		[transaction replaceObject:@(3) forKey:@"odd-even"  inCollection:nil];
		[transaction replaceObject:@(3) forKey:@"odd-odd"   inCollection:nil];
		
		[transaction replaceMetadata:@(2) forKey:@"even-even" inCollection:nil];
		[transaction replaceMetadata:@(3) forKey:@"even-odd"  inCollection:nil];
		[transaction replaceMetadata:@(2) forKey:@"odd-even"  inCollection:nil];
		[transaction replaceMetadata:@(3) forKey:@"odd-odd"   inCollection:nil];
		
		NSUInteger count;
		
		count = [[transaction ext:@"filter-object-even"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
		
		count = [[transaction ext:@"filter-metadata-odd"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"filter-object-even"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
		
		count = [[transaction ext:@"filter-metadata-odd"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 2, @"");
	}];
}

@end
