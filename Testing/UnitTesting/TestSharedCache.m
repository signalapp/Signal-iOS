#import "TestSharedCache.h"
#import "YapSharedCache.h"


@implementation TestSharedCache
{
	YapSharedCache *sharedCache;
}

- (void)setUp
{
	NSLog(@"TestYapDatabase: setUp");
	
	[super setUp];
	
	sharedCache = [[YapSharedCache alloc] init];
}

- (void)tearDown
{
	NSLog(@"TestSharedCache: tearDown");
	
	sharedCache = nil;
	
	[super tearDown];
}

- (void)test1
{
	STAssertNotNil(sharedCache, @"Setup problem");
	
	YapSharedCacheConnection *connection1 = [sharedCache newConnection];
	YapSharedCacheConnection *connection2 = [sharedCache newConnection];
	
	NSTimeInterval timestamp = [[NSProcessInfo processInfo] systemUptime];
	
	NSString *value1 = @"value1";
	NSString *value2 = @"value2";
	
	[connection1 startReadTransaction:timestamp];
	[connection2 startReadTransaction:timestamp];
	
	// Put separate objects in each cache.
	// Make sure we can read them back.
	// Then try reading across cache boundaries.
	// That is, use cache1 to read a value stored by cache2.
	// And vice-versa.
	
	[connection1 setObject:value1 forKey:@"key1"];
	[connection2 setObject:value2 forKey:@"key2"];
	
	// Simple test
	
	id obj1 = [connection1 objectForKey:@"key1"];
	id obj2 = [connection2 objectForKey:@"key2"];
	
	STAssertTrue(obj1 == value1, @"Expected value1, got: %@", obj1);
	STAssertTrue(obj2 == value2, @"Expected value2, got: %@", obj2);
	
	// Now read across cache boundaries
	
	STAssertTrue([connection1 objectForKey:@"key2"] == value2, @"Oops");
	STAssertTrue([connection2 objectForKey:@"key1"] == value1, @"Oops");
	
	[connection1 endTransaction];
	[connection2 endTransaction];
}

- (void)test2
{
	STAssertNotNil(sharedCache, @"Setup problem");
	
	YapSharedCacheConnection *connection1 = [sharedCache newConnection];
	YapSharedCacheConnection *connection2 = [sharedCache newConnection];
	
	// Now test having caches on different snapshots.
	//
	// Imagine 2 database connections, each having started a transaction at a different time.
	// - Connection 1 sees an atomic snapshot of the database at time 1.
	// - Connection 2 sees an atomic snapshot of the database at time 2.
	//
	// Thus each connection should be able to read and write from the cache
	// in a manner which should be entirely separate.
	//
	// Afterwards, connection 1 is run again, this time with an atomic snapshot of the database at time 2.
	// It should now see all the changes made by connection 2.
	
	NSTimeInterval timestamp1 = 1.0;
	NSTimeInterval timestamp2 = timestamp1 + 1.0;
	
	NSMutableSet *changedKeys = [NSMutableSet set];
	
	int (^changesetBlock)(id) = ^(id key){
		
		if ([changedKeys containsObject:key])
			return 1;
		else
			return 0;
	};
	
	[connection1 startReadTransaction:timestamp1];
	[connection2 startReadWriteTransaction:timestamp2 changesetBlock:changesetBlock];
	
	id oldValue = @"old-value";
	id newValue = @"new-value";
	
	[connection1 setObject:oldValue forKey:@"test2"]; // Connection 1 stores value from older snapshot
	
	[connection2 setObject:newValue forKey:@"test2"]; // Connection 2 stores value from newer snapshot
	[changedKeys addObject:@"test2"];
	
	id value1 = [connection1 objectForKey:@"test2"]; // Connection 1 should see older value
	id value2 = [connection2 objectForKey:@"test2"]; // Connection 2 should see newer value
	
	STAssertTrue(value1 == oldValue, @"Expected old-value, got %@", value1);
	STAssertTrue(value2 == newValue, @"Expected new-value, got %@", value2);
	
	[connection1 endTransaction];
	[connection2 endTransaction];
	
	[sharedCache notePendingChangesetBlock:changesetBlock writeTimestamp:timestamp2];
	[connection1 noteCommittedChangesetBlock:changesetBlock writeTimestamp:timestamp2];
	[sharedCache noteCommittedChangesetBlock:changesetBlock writeTimestamp:timestamp2];
	
	// Now try 
	
	[connection1 startReadTransaction:timestamp2];
	
	value1 = [connection1 objectForKey:@"test2"]; // Connection 1 should now see newer value
	
	STAssertTrue(value1 == newValue, @"Expected new-value, got %@", value1);
	
	[connection1 endTransaction];
}

//- (void)test3
//{
//	STAssertNotNil(cache1, @"Setup problem");
//	STAssertNotNil(cache2, @"Setup problem");
//	
//	NSTimeInterval timestamp = [[NSProcessInfo processInfo] systemUptime];
//	
//	// Simple test.
//	// Make sure multiple connections (on the same snapshot) can both write values to the database,
//	// without causing any issues or duplicating objects within the cache.
//	
//	[cache1 startReadTransaction:timestamp];
//	[cache2 startReadTransaction:timestamp];
//	
//	STAssertNil([cache1 objectForKey:@"key"], @"Should be nil");
//	STAssertNil([cache2 objectForKey:@"key"], @"Should be nil");
//	
//	[cache1 setObject:@"value" forKey:@"key"];
//	[cache2 setObject:@"value" forKey:@"key"];
//	
//	id value1 = [cache1 objectForKey:@"key"];
//	id value2 = [cache2 objectForKey:@"key"];
//	
//	STAssertTrue([value1 isEqual:@"value"], @"Oops");
//	STAssertTrue([value2 isEqual:@"value"], @"Oops");
//}

//- (void)test4
//{
//	STAssertNotNil(cache1, @"Setup problem");
//	STAssertNotNil(cache2, @"Setup problem");
//	STAssertNotNil(cache3, @"Setup problem");
//	
//	NSTimeInterval timestamp1 = 1.0;
//	NSTimeInterval timestamp2 = 2.0;
//	NSTimeInterval timestamp3 = 3.0;
//	
//	[cache1 startReadTransaction:timestamp1];
//	[cache2 startReadTransaction:timestamp1];
//	[cache3 startReadWriteTransaction:timestamp2];
//	
//	[cache1 setObject:@"old-value" forKey:@"key"];
//	
//	[cache3 setObject:@"new-value" forKey:@"key"];
//	
//	id value1 = [cache1 objectForKey:@"key"];
//	id value2 = [cache2 objectForKey:@"key"];
//	id value3 = [cache3 objectForKey:@"key"];
//	
//	STAssertEqualObjects(value1, @"old-value", @"Bad value: %@", value1);
//	STAssertEqualObjects(value2, @"old-value", @"Bad value: %@", value2);
//	STAssertEqualObjects(value3, @"new-value", @"Bad value: %@", value3);
//	
//	[cache2 endReadTransaction];
//	
//	[cache3 commitReadWriteTransaction];
//	[cache3 endReadWriteTransaction];
//	
//	[cache2 startReadTransaction:timestamp2];
//	[cache3 startReadWriteTransaction:timestamp3];
//	
//	[cache3 setObject:@"new-new-value" forKey:@"key"];
//	
//	value1 = [cache1 objectForKey:@"key"]; // Reading on timestamp1
//	value2 = [cache2 objectForKey:@"key"]; // Reading on timestamp2
//	value3 = [cache3 objectForKey:@"key"]; // Reading on timestamp3
//	
//	STAssertEqualObjects(value1, @"old-value", @"Bad value: %@", value1);
//	STAssertEqualObjects(value2, @"new-value", @"Bad value: %@", value2);
//	STAssertEqualObjects(value3, @"new-new-value", @"Bad value: %@", value3);
//	
//	[cache1 endReadTransaction];
//	
//	[cache3 commitReadWriteTransaction];
//	[cache3 endReadWriteTransaction];
//	
//	[cache2 endReadTransaction];
//}

@end
