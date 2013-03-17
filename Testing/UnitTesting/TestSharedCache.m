#import "TestSharedCache.h"
#import "YapSharedCache.h"


@implementation TestSharedCache
{
	YapSharedCache *sharedCache;
}

- (void)setUp
{
	[super setUp];
	
	sharedCache = [[YapSharedCache alloc] init];
}

- (void)tearDown
{
	sharedCache = nil;
	
	[super tearDown];
}

- (void)test1
{
	STAssertNotNil(sharedCache, @"Setup problem");
	
	YapSharedCacheConnection *connection1 = [sharedCache newConnection];
	YapSharedCacheConnection *connection2 = [sharedCache newConnection];
	
	uint64_t snapshot = 1;
	
	NSString *value1 = @"value1";
	NSString *value2 = @"value2";
	
	[connection1 startReadTransaction:snapshot];
	[connection2 startReadTransaction:snapshot];
	
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
	
	uint64_t snapshot1 = 1;
	uint64_t snapshot2 = snapshot1 + 1;
	
	NSMutableSet *changedKeys = [NSMutableSet set];
	
	int (^changesetBlock)(id) = ^(id key){
		
		if ([changedKeys containsObject:key])
			return 1;
		else
			return 0;
	};
	
	[connection1 startReadTransaction:snapshot1];
	[connection2 startReadWriteTransaction:snapshot2 withChangesetBlock:changesetBlock];
	
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
	
	[sharedCache notePendingChangesetBlock:changesetBlock snapshot:snapshot2];
	[connection1 noteCommittedChangesetBlock:changesetBlock snapshot:snapshot2];
	[sharedCache noteCommittedChangesetBlock:changesetBlock snapshot:snapshot2];
	
	// Now try 
	
	[connection1 startReadTransaction:snapshot2];
	
	value1 = [connection1 objectForKey:@"test2"]; // Connection 1 should now see newer value
	
	STAssertTrue(value1 == newValue, @"Expected new-value, got %@", value1);
	
	[connection1 endTransaction];
}

- (void)test3
{
	STAssertNotNil(sharedCache, @"Setup problem");

	YapSharedCacheConnection *connection1 = [sharedCache newConnection];
	YapSharedCacheConnection *connection2 = [sharedCache newConnection];
	
	uint64_t snapshot = 1;
	
	// Simple test.
	// Make sure multiple connections (on the same snapshot) can both write values to the database,
	// without causing any issues or duplicating objects within the cache.
	
	[connection1 startReadTransaction:snapshot];
	[connection2 startReadTransaction:snapshot];
	
	STAssertNil([connection1 objectForKey:@"key"], @"Should be nil");
	STAssertNil([connection2 objectForKey:@"key"], @"Should be nil");
	
	[connection1 setObject:@"value" forKey:@"key"];
	[connection2 setObject:@"value" forKey:@"key"];
	
	id value1 = [connection1 objectForKey:@"key"];
	id value2 = [connection2 objectForKey:@"key"];
	
	STAssertTrue([value1 isEqual:@"value"], @"Oops");
	STAssertTrue([value2 isEqual:@"value"], @"Oops");
}

- (void)test4
{
	STAssertNotNil(sharedCache, @"Setup problem");

	YapSharedCacheConnection *connection1 = [sharedCache newConnection];
	YapSharedCacheConnection *connection2 = [sharedCache newConnection];
	YapSharedCacheConnection *connection3 = [sharedCache newConnection];
	
	NSMutableSet *snapshot2_changedKeys = [NSMutableSet set];
	int (^snapshot2_changesetBlock)(id key) = ^(id key){
		
		if ([snapshot2_changedKeys containsObject:key])
			return 1;
		else
			return 0;
	};
	
	uint64_t snapshot1 = 1;
	uint64_t snapshot2 = 2;
	uint64_t snapshot3 = 3;
	
	[connection1 startReadTransaction:snapshot1];
	[connection2 startReadTransaction:snapshot1];
	[connection3 startReadWriteTransaction:snapshot2 withChangesetBlock:snapshot2_changesetBlock];
	
	[connection1 setObject:@"old-value" forKey:@"key"];
	
	[connection3 setObject:@"new-value" forKey:@"key"];
	[snapshot2_changedKeys addObject:@"key"];
	
	id value1 = [connection1 objectForKey:@"key"];
	id value2 = [connection2 objectForKey:@"key"];
	id value3 = [connection3 objectForKey:@"key"];
	
	STAssertEqualObjects(value1, @"old-value", @"Bad value: %@", value1);
	STAssertEqualObjects(value2, @"old-value", @"Bad value: %@", value2);
	STAssertEqualObjects(value3, @"new-value", @"Bad value: %@", value3);
	
	[connection2 endTransaction];
	[connection3 endTransaction];
	
	[sharedCache notePendingChangesetBlock:snapshot2_changesetBlock snapshot:snapshot2];
	[connection2 noteCommittedChangesetBlock:snapshot2_changesetBlock snapshot:snapshot2];
	
	NSMutableSet *snapshot3_changedKeys = [NSMutableSet set];
	int (^snapshot3_changesetBlock)(id key) = ^(id key){
		
		if ([snapshot3_changedKeys containsObject:key])
			return 1;
		else
			return 0;
	};
	
	[connection2 startReadTransaction:snapshot2];
	[connection3 startReadWriteTransaction:snapshot3 withChangesetBlock:snapshot3_changesetBlock];
	
	[connection3 setObject:@"new-new-value" forKey:@"key"];
	[snapshot3_changedKeys addObject:@"key"];
	
	value1 = [connection1 objectForKey:@"key"]; // Reading on snapshot1
	value2 = [connection2 objectForKey:@"key"]; // Reading on snapshot2
	value3 = [connection3 objectForKey:@"key"]; // Reading on snapshot3
	
	STAssertEqualObjects(value1, @"old-value", @"Bad value: %@", value1);
	STAssertEqualObjects(value2, @"new-value", @"Bad value: %@", value2);
	STAssertEqualObjects(value3, @"new-new-value", @"Bad value: %@", value3);
	
	[connection1 endTransaction];
	
	[connection2 noteCommittedChangesetBlock:snapshot2_changesetBlock snapshot:snapshot2];
	[sharedCache noteCommittedChangesetBlock:snapshot2_changesetBlock snapshot:snapshot2];
	
	[connection2 endTransaction];
	[connection3 endTransaction];
	
	[sharedCache notePendingChangesetBlock:snapshot3_changesetBlock snapshot:snapshot3];
	[connection1 noteCommittedChangesetBlock:snapshot3_changesetBlock snapshot:snapshot3];
	[connection2 noteCommittedChangesetBlock:snapshot3_changesetBlock snapshot:snapshot3];
	[sharedCache noteCommittedChangesetBlock:snapshot3_changesetBlock snapshot:snapshot3];
}

@end
