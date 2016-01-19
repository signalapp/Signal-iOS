#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseSecondaryIndex.h"

#import "TestObject.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

@interface TestYapDatabaseSecondaryIndex : XCTestCase

@end

@implementation TestYapDatabaseSecondaryIndex

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


- (void)test
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:@"someDate" withType:YapDatabaseSecondaryIndexTypeReal];
	[setup addColumn:@"someInt" withType:YapDatabaseSecondaryIndexTypeInteger];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
		
		// If we're storing other types of objects in our database,
		// then we should check the object before presuming we can cast it.
		if ([object isKindOfClass:[TestObject class]])
		{
			__unsafe_unretained TestObject *testObject = (TestObject *)object;
			
			if (testObject.someDate)
				[dict setObject:testObject.someDate forKey:@"someDate"];
			
			[dict setObject:@(testObject.someInt) forKey:@"someInt"];
		}
	}];
	
	YapDatabaseSecondaryIndex *secondaryIndex =
	  [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
	
	[database registerExtension:secondaryIndex withName:@"idx"];
	
	//
	// Test populating the database
	//
	
	NSDate *startDate = [NSDate date];
	int startInt = 0;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 20; i++)
		{
			NSDate *someDate = [startDate dateByAddingTimeInterval:i];
			int someInt = startInt + i;
			
			TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
			
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:object forKey:key inCollection:nil];
		}
	}];
	
	//
	// Test basic queries
	//
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 5"];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(5)];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
		                         [startDate dateByAddingTimeInterval:5],           @(4)];
		
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt IN (?)",
																															@[@(2), @(4), @(5.5), @(9)]];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
																							usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
																								
			count++;
		}];
		
		XCTAssertTrue(count == 3, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	//
	// Test updating the database
	//
	
	startDate = [NSDate dateWithTimeIntervalSinceNow:4];
	startInt = 100;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 20; i++)
		{
			NSDate *someDate = [startDate dateByAddingTimeInterval:i];
			int someInt = startInt + i;
			
			TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
			
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:object forKey:key inCollection:nil];
		}
	}];
	
	//
	// Re-check basic queries
	//
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 105"];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(105)];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 105"];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(105)];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
				 [startDate dateByAddingTimeInterval:5],           @(104)];
		
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query
		                                          usingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		XCTAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		XCTAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
				 [startDate dateByAddingTimeInterval:5],           @(104)];
		
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		XCTAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
	}];
}

/**
 * https://github.com/yaptv/YapDatabase/issues/104
**/
- (void)testIssue104
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:@"str" withType:YapDatabaseSecondaryIndexTypeText];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
		
		// If we're storing other types of objects in our database,
		// then we should check the object before presuming we can cast it.
		if ([object isKindOfClass:[NSString class]])
		{
			__unsafe_unretained NSString *str = (NSString *)object;
			
			if ([str hasPrefix:@"like "]) {
				[dict setObject:str forKey:@"str"];
			}
		}
	}];
	
	YapDatabaseSecondaryIndex *secondaryIndex =
	  [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
	
	[database registerExtension:secondaryIndex withName:@"idx"];
	
	//
	// Test initial population
	//
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"like whatever" forKey:@"1" inCollection:nil];
		[transaction setObject:@"as if"         forKey:@"2" inCollection:nil];
		
		
		__block NSUInteger count = 0;
		
		YapDatabaseQuery *query = [YapDatabaseQuery queryMatchingAll];
		[[transaction ext:@"idx"] enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			count++;
			
			XCTAssert([object isEqual:@"like whatever"], @"like whatever, guess the code sucks");
		}];
		
		XCTAssertTrue(count == 1, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	//
	// Test update
	//
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"whatever"   forKey:@"1" inCollection:nil];
		[transaction setObject:@"like as if" forKey:@"2" inCollection:nil];
		
		__block NSUInteger count = 0;
		
		YapDatabaseQuery *query = [YapDatabaseQuery queryMatchingAll];
		[[transaction ext:@"idx"] enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			count++;
			
			XCTAssert([object isEqual:@"like as if"], @"like as if, the code was going to work");
		}];
		
		XCTAssertTrue(count == 1, @"Incorrect count: %lu", (unsigned long)count);
	}];
}

- (void)testAggregateQuery
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:@"department" withType:YapDatabaseSecondaryIndexTypeText];
	[setup addColumn:@"title" withType:YapDatabaseSecondaryIndexTypeText];
	[setup addColumn:@"salary" withType:YapDatabaseSecondaryIndexTypeReal];
	
	YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSMutableDictionary *dict, NSString *collection, NSString *key, id object)
	{
		// If we're storing other types of objects in our database,
		// then we should check the object before presuming we can cast it.
			
		__unsafe_unretained NSDictionary *employee = (NSDictionary *)object;
		
		dict[@"department"] = employee[@"department"];
		dict[@"title"]      = employee[@"title"];
		dict[@"salary"]     = employee[@"salary"];
	}];
	
	YapDatabaseSecondaryIndex *secondaryIndex =
	  [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
	
	[database registerExtension:secondaryIndex withName:@"idx"];
	
	//
	// Add some sample rows
	//
	
	NSDictionary *employee1 = @{ @"department":@"brass", @"title":@"CEO",      @"salary":@(100000)};
	NSDictionary *employee2 = @{ @"department":@"sys",   @"title":@"manager",  @"salary":@(50000)};
	NSDictionary *employee3 = @{ @"department":@"sys",   @"title":@"sysadmin", @"salary":@(40000)};
	NSDictionary *employee4 = @{ @"department":@"dev",   @"title":@"manager",  @"salary":@(50000)};
	NSDictionary *employee5 = @{ @"department":@"dev",   @"title":@"manager",  @"salary":@(50000)};
	NSDictionary *employee6 = @{ @"department":@"dev",   @"title":@"engineer", @"salary":@(75000)};
	NSDictionary *employee7 = @{ @"department":@"dev",   @"title":@"engineer", @"salary":@(75000)};
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:employee1 forKey:@"1" inCollection:@"employees"];
		[transaction setObject:employee2 forKey:@"2" inCollection:@"employees"];
		[transaction setObject:employee3 forKey:@"3" inCollection:@"employees"];
		[transaction setObject:employee4 forKey:@"4" inCollection:@"employees"];
		[transaction setObject:employee5 forKey:@"5" inCollection:@"employees"];
		[transaction setObject:employee6 forKey:@"6" inCollection:@"employees"];
		[transaction setObject:employee7 forKey:@"7" inCollection:@"employees"];
		
		__block NSUInteger count = 0;
		
		YapDatabaseQuery *query = [YapDatabaseQuery queryMatchingAll];
		[[transaction ext:@"idx"] enumerateKeysAndObjectsMatchingQuery:query usingBlock:
		    ^(NSString *collection, NSString *key, id object, BOOL *stop)
		{
			count++;
		}];
		
		XCTAssertTrue(count == 7, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	//
	// Perform some aggregate queries
	//
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Figure out how much money we're wasting on management
		
		YapDatabaseQuery *query1 = [YapDatabaseQuery queryWithAggregateFunction:@"SUM(salary)"
		                                                                 format:@"WHERE title = ?", @"manager"];
		NSNumber *wasted = [[transaction ext:@"idx"] performAggregateQuery:query1];
	//	NSLog(@"wasted: %@", wasted);
		
		XCTAssert([wasted isKindOfClass:[NSNumber class]], @"Oops");
		XCTAssert([wasted isEqualToNumber:@(150000)], @"Oops");
		
		// Figure out how much the dev department is costing us
		
		YapDatabaseQuery *query2 = [YapDatabaseQuery queryWithAggregateFunction:@"SUM(salary)"
		                                                                 format:@"WHERE department = ?", @"dev"];
		NSNumber *devCost = [[transaction ext:@"idx"] performAggregateQuery:query2];
	//	NSLog(@"devCost: %@", devCost);
		
		XCTAssert([devCost isKindOfClass:[NSNumber class]], @"Oops");
		XCTAssert([devCost isEqualToNumber:@(250000)], @"Oops");
	}];
}

@end
