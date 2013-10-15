#import "TestYapDatabaseView.h"

#import "YapDatabase.h"
#import "YapDatabaseView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"


@implementation TestYapDatabaseView

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

#pragma mark -

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
	groupingBlock = ^NSString *(NSString *key){
		
		if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
			return nil;
		else
			return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2 options:NSNumericSearch];
	};
	
	YapDatabaseView *databaseView =
	    [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                 groupingBlockType:groupingBlockType
	                                      sortingBlock:sortingBlock
	                                  sortingBlockType:sortingBlockType
	                                           version:0
	                                           options:options];
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	NSString *key0 = @"key0";
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";
	NSString *key3 = @"key3";
	NSString *key4 = @"key4";
	NSString *keyX = @"keyX";
	
	id object0 = @"object0"; // index 0
	id object1 = @"object1"; // index 1
	id object2 = @"object2"; // index 2
	id object3 = @"object3"; // index 3
	id object4 = @"object4"; // index 4
	id objectX = @"objectX"; // ------- excluded from group
	
	id object1B = @"object5"; // moves key1 from index1 to index4
	
	__block NSUInteger keysCount = 0;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		STAssertNotNil([transaction ext:@"order"], @"Expected non-nil view transaction");
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Expected zero group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Expected empty array");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == 0, @"Expected zero");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == 0, @"Expected zero");
		
		STAssertNil([[transaction ext:@"order"] groupForKey:key0], @"Expected nil");
		
		STAssertNil([[transaction ext:@"order"] keyAtIndex:0 inGroup:@""], @"Expected nil");
		STAssertNil([[transaction ext:@"order"] objectAtIndex:0 inGroup:@""], @"Expected nil");
		
		NSString *group = nil;
		NSUInteger index = 0;
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertFalse(result, @"Expected NO");
		STAssertNil(group, @"Expected group to be set to nil");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test inserting a single object
		
		[transaction setObject:object0 forKey:key0]; keysCount++;
		
		// Read it back
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction ext:@"order"] groupForKey:key0];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0 = [[transaction ext:@"order"] keyAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0], @"Expected match");
		
		id fetchedObject0 = [[transaction ext:@"order"] objectAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedObject0 isEqualToString:object0], @"Expected match");
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test reading data back on separate connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction ext:@"order"] groupForKey:key0];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0 = [[transaction ext:@"order"] keyAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0], @"Expected match");
		
		id fetchedObject0 = [[transaction ext:@"order"] objectAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedObject0 isEqualToString:object0], @"Expected match");
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test inserting more objects
		
		[transaction setObject:object1 forKey:key1]; keysCount++; // Included
		[transaction setObject:object2 forKey:key2]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX];              // Excluded !
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
			    @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Test a read-only transaction.
		// Test reading multiple inserted objects from a separate connection.
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test updating the metadata of our object.
		//
		// This should invoke our grouping block (to determine if the group changed).
		// However, once it determines the group hasn't changed,
		// it should abort as the sorting block only takes the object into account.
		
		[transaction setMetadata:@"some-metadata" forKey:key0];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test updating the object (in such a manner that changes its position within the view)
		//
		// key0 should move from index0 to index4
		
		NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:1 inGroup:@""];
		
		STAssertTrue([fetchedKey isEqualToString:key1], @"Oops");
		
		[transaction setObject:object1B forKey:key1];
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, key1 ]; // <-- Updated order (key1 moved to end)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Test read-only block.
		// Test reading back updated index.
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, key1 ]; // <-- Updated order (key1 moved to end)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test removing a single key
		
		[transaction removeObjectForKey:key1]; keysCount--;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, ]; // <-- Updated order (key1 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Test read-only block.
		// Test reading back updated index.
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, ]; // <-- Updated order (key1 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key2, key3 ]]; keysCount -= 2;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key4, ]; // <-- Updated order (key2 & key3 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Read the changes back on another connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key4, ]; // <-- Updated order (key2 & key3 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjects]; keysCount = 0;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
	}];

	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Read changes from other connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Add all the objects back (in random order)
		
		[transaction setObject:object2 forKey:key2]; keysCount++; // Included
		[transaction setObject:object1 forKey:key1]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX];              // Excluded !
		[transaction setObject:object0 forKey:key0]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4]; keysCount++; // Included
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ]; // <-- Updated order (key1 moved to end)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Again on connection 2
		// Remove all the keys, and then add a few back
		
		[transaction removeAllObjects]; keysCount = 0;
		
		[transaction setObject:object1 forKey:key1]; keysCount++; // Included
		[transaction setObject:object0 forKey:key0]; keysCount++; // Included
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Add all the keys back. Some are already included.
		
		[transaction setObject:object0 forKey:key0];              // Already included
		[transaction setObject:object1 forKey:key1];              // Already included
		[transaction setObject:object2 forKey:key2]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX];              // Excluded !
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		// Test enumeration
		
		__block NSUInteger correctIndex;
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		// Basic enumeration
		
		correctIndex = 0;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex++;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options: forwards
		
		correctIndex = 0;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:0
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex++;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options: backwards
		
		correctIndex = 4;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:NSEnumerationReverse
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex--;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options & range: forwards, full range
		
		correctIndex = 0;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:0
		                                           range:NSMakeRange(0, 5)
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex++;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options & range: backwards, full range
		
		correctIndex = 4;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:NSEnumerationReverse
		                                           range:NSMakeRange(0, 5)
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex--;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options & range: forwards, subset range
		
		correctIndex = 1;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:0
		                                           range:NSMakeRange(1, 3)
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex++;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
		
		// Enumerate with options & range: backwards, subset range
		
		correctIndex = 3;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                                     withOptions:NSEnumerationReverse
		                                           range:NSMakeRange(1, 3)
		                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
			
			STAssertTrue(index == correctIndex,
						 @"Index mismatch: %lu vs %lu", (unsigned long)index, (unsigned long)correctIndex);
			correctIndex--;
			
			NSString *correctKey = [keys objectAtIndex:index];
			STAssertTrue([key isEqual:correctKey],
						 @"Enumeration mismatch: (%@) vs (%@) at index %lu", key, correctKey, (unsigned long)index);
		}];
	}];
	
	connection1 = nil;
	connection2 = nil;
}

#pragma mark -

- (void)testMultiPage_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testMultiPage_withPath:databasePath options:options];
}

- (void)testMultiPage_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testMultiPage_withPath:databasePath options:options];
}

- (void)_testMultiPage_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
{
	//
	// These tests include enough keys to ensure that the view has to deal with multiple pages.
	// By default, there are 50 keys in a page.
	
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
	groupingBlock = ^NSString *(NSString *key){
		
		return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2 options:NSNumericSearch];
	};
	
	YapDatabaseView *databaseView =
		[[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
		                             groupingBlockType:groupingBlockType
		                                  sortingBlock:sortingBlock
		                              sortingBlockType:sortingBlockType
		                                       version:0
		                                       options:options];
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	//
	// Test adding a bunch of keys
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Add 3 pages of keys to the view
		//
		// page0 = [key0   - key49]
		// page1 = [key50  - key99]
		// page2 = [key100 - key149]
		
		for (int i = 0; i < 150; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	//
	// Test removing an entire page of keys from the middle
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Drop middle of the 3 pages
		//
		// page0 = [key0   - key49]
		// page1 = [key50  - key99]  <-- Drop
		// page2 = [key100 - key149]
		
		for (int i = 50; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction removeObjectForKey:key];
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 100; i++)
		{
			NSString *expectedKey;
			
			if (i < 50)
				expectedKey = [NSString stringWithFormat:@"key%d", i];
			else
				expectedKey = [NSString stringWithFormat:@"key%d", (i+50)];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 100; i++)
		{
			NSString *expectedKey;
			
			if (i < 50)
				expectedKey = [NSString stringWithFormat:@"key%d", i];
			else
				expectedKey = [NSString stringWithFormat:@"key%d", (i+50)];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 100; i++)
		{
			NSString *expectedKey;
			
			if (i < 50)
				expectedKey = [NSString stringWithFormat:@"key%d", i];
			else
				expectedKey = [NSString stringWithFormat:@"key%d", (i+50)];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	//
	// Test adding an entire page in the middle
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Re-add middle page
		//
		// page0 = [key0   - key49]
		// page1 = [key50  - key99]  <-- Re-add
		// page2 = [key100 - key149]
		
		for (int i = 50; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	//
	// Test removing keys from multiple pages
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Remove every 5th item
		
		for (int i = 5; i < 150; i += 5)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction removeObjectForKey:key];
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	//
	// Test removing all keys
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjects];
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		
		STAssertTrue(count == 0, @"Wrong count. Expected zero, got %lu", (unsigned long)count);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		
		STAssertTrue(count == 0, @"Wrong count. Expected zero, got %lu", (unsigned long)count);
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"order"] numberOfKeysInGroup:@""];
		
		STAssertTrue(count == 0, @"Wrong count. Expected zero, got %lu", (unsigned long)count);
	}];
	
	//
	// Test adding a bunch of keys (again)
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Add 3 pages of keys to the view
		//
		// page0 = [key0   - key49]
		// page1 = [key50  - key99]
		// page2 = [key100 - key149]
		
		for (int i = 0; i < 150; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	//
	// Test removing keys from multiple pages (this time as a single instruction)
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Remove every 5th item
		
		NSMutableArray *keysToRemove = [NSMutableArray array];
		
		for (int i = 5; i < 150; i += 5)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[keysToRemove addObject:key];
		}
		
		[transaction removeObjectsForKeys:keysToRemove];
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	[[database newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			if ((i % 5) == 0){
				continue;
			}
			else
			{
				NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
				
				int index = i - (i / 5);
				
				NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
				
				STAssertTrue([expectedKey isEqualToString:fetchedKey],
				             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			}
		}
	}];
	
	//
	// Clear the database, and add a bunch of keys (again)
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjects];
		
		// Add 2 pages of keys to the view
		//
		// page0 = [key0   - key49]
		// page1 = [key100 - key149]
		
		for (int i = 0; i < 50; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
		
		for (int i = 100; i < 150; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Add [key50 - key59]
		//
		// Should originally add to page1, and then get moved to page0
		
		for (int i = 50; i < 60; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
		
		// Remove [key40 - key49]
		//
		// This should make room for [key50 - key59] to move from page1 to page0
		
		for (int i = 40; i < 50; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction removeObjectForKey:key];
		}
		
		// This test is designed to hit the codePath:
		//
		// YapDatabaseViewTransaction:
		// - splitOversizedPage
		// - "Move objects from beginning of page to end of previous page"
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger index = 0;
		
		for (int i = 0; i < 40; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
		
		for (int i = 50; i < 60; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
		
		for (int i = 100; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
	}];
	
	//
	// Clear the database, and add a bunch of keys (again)
	//
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjects];
		
		// Add 2 pages of keys to the view
		//
		// page0 = [key50  - key99]
		// page1 = [key100 - key149]
		
		for (int i = 50; i < 150; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Add [key0 - key9]
		//
		// Should add to page0
		
		for (int i = 0; i < 10; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
		
		// Remove [key100 - key109]
		//
		// This should make room for [key90 - key99] to move from page0 to page1
		
		for (int i = 100; i < 110; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction removeObjectForKey:key];
		}
		
		// This test is designed to hit the codePath:
		//
		// YapDatabaseViewTransaction:
		// - splitOversizedPage
		// - "Move objects from end of page to beginning of next page"
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger index = 0;
		
		for (int i = 0; i < 10; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
		
		for (int i = 50; i < 100; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
		
		for (int i = 110; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:index inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
						 @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
			
			index++;
		}
	}];
}

#pragma mark -

- (void)testViewPopulation_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testViewPopulation_withPath:databasePath options:options];
}

- (void)testViewPopulation_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testViewPopulation_withPath:databasePath options:options];
}

- (void)_testViewPopulation_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
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
	groupingBlock = ^NSString *(NSString *key){
		
		return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2 options:NSNumericSearch];
	};
	
	YapDatabaseView *databaseView =
		[[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
		                             groupingBlockType:groupingBlockType
		                                  sortingBlock:sortingBlock
		                              sortingBlockType:sortingBlockType
		                                       version:0
		                                       options:options];
	
	// Without registering the view,
	// add a bunch of keys to the database.
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			NSString *obj = [NSString stringWithFormat:@"object%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	// And NOW register the view
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	// Make sure both connections can see the view now
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (int i = 0; i < 150; i++)
		{
			NSString *expectedKey = [NSString stringWithFormat:@"key%d", i];
			
			NSString *fetchedKey = [[transaction ext:@"order"] keyAtIndex:i inGroup:@""];
			
			STAssertTrue([expectedKey isEqualToString:fetchedKey],
			             @"Key mismatch: expected(%@) fetched(%@)", expectedKey, fetchedKey);
		}
	}];
}

#pragma mark -

- (void)testMutationDuringEnumerationProtection_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testMutationDuringEnumerationProtection_withPath:databasePath options:options];
}

- (void)testMutationDuringEnumerationProtection_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testMutationDuringEnumerationProtection_withPath:databasePath options:options];
}

- (void)_testMutationDuringEnumerationProtection_withPath:(NSString *)databasePath
                                                  options:(YapDatabaseViewOptions *)options
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
	groupingBlock = ^NSString *(NSString *key){
		
		if ([key hasPrefix:@"key"])
			return @"default-group";
		else
			return @"different-group";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2 options:NSNumericSearch];
	};
	
	YapDatabaseView *databaseView =
		[[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
		                             groupingBlockType:groupingBlockType
		                                  sortingBlock:sortingBlock
		                              sortingBlockType:sortingBlockType
		                                       version:0
		                                       options:options];
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	// Add a bunch of keys to the database.
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key-%d", i];
			NSString *obj = [NSString stringWithFormat:@"obj-%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// enumerateKeysInGroup:usingBlock:
		
		__block int i = 200;
		__block int j = 0;
		__block int k = 0;
		
		dispatch_block_t exceptionBlock1A = ^{
		
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
												  usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t exceptionBlock1B = ^{
		
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
												  usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t noExceptionBlock1A = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock1B = ^{
		
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
												  usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock1C = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"diff-obj-%d", k]
				                forKey:[NSString stringWithFormat:@"diff-key-%d", k]];
				k++;
				// No stop; Shouldn't affect default-group.
			}];
		};
		
		STAssertThrows(exceptionBlock1A(), @"Should throw exception");
		STAssertThrows(exceptionBlock1B(), @"Should throw exception");
		STAssertNoThrow(noExceptionBlock1A(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock1B(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock1C(), @"Should NOT throw exception. Mutating different group.");
		
		// enumerateKeysInGroup:withOptions:usingBlock:
		
		dispatch_block_t exceptionBlock2A = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:NSEnumerationReverse
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t exceptionBlock2B = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:NSEnumerationReverse
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t noExceptionBlock2A = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:NSEnumerationReverse
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock2B = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:NSEnumerationReverse
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock2C = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:NSEnumerationReverse
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"diff-obj-%d", k]
				                forKey:[NSString stringWithFormat:@"diff-key-%d", k]];
				k++;
				// No stop; Shouldn't affect default-group.
			}];
		};
		
		STAssertThrows(exceptionBlock2A(), @"Should throw exception");
		STAssertThrows(exceptionBlock2B(), @"Should throw exception");
		STAssertNoThrow(noExceptionBlock2A(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock2B(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock2C(), @"Should NOT throw exception. Mutating different group.");
		
		// enumerateKeysInGroup:withOptions:range:usingBlock:
		
		dispatch_block_t exceptionBlock3A = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:0
			                                           range:NSMakeRange(0, 10)
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t exceptionBlock3B = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:0
			                                           range:NSMakeRange(0, 10)
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				// Missing stop; Will cause exception.
			}];
		};
		dispatch_block_t noExceptionBlock3A = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:0
			                                           range:NSMakeRange(0, 10)
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"obj-%d", i]
				                forKey:[NSString stringWithFormat:@"key-%d", i]];
				i++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock3B = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:0
			                                           range:NSMakeRange(0, 10)
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeObjectForKey:[NSString stringWithFormat:@"key-%d", j]];
				j++;
				*stop = YES;
			}];
		};
		dispatch_block_t noExceptionBlock3C = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                     withOptions:0
			                                           range:NSMakeRange(0, 10)
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction setObject:[NSString stringWithFormat:@"diff-obj-%d", k]
				                forKey:[NSString stringWithFormat:@"diff-key-%d", k]];
				k++;
				// No stop; Shouldn't affect default-group.
			}];
		};
		
		STAssertThrows(exceptionBlock3A(), @"Should throw exception");
		STAssertThrows(exceptionBlock3B(), @"Should throw exception");
		STAssertNoThrow(noExceptionBlock3A(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock3B(), @"Should NOT throw exception. Proper use of stop.");
		STAssertNoThrow(noExceptionBlock3C(), @"Should NOT throw exception. Mutating different group.");
	}];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test removeAll
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key-%d", i];
			NSString *obj = [NSString stringWithFormat:@"obj-%d", i];
			
			[transaction setObject:obj forKey:key];
		}
		
		dispatch_block_t exceptionBlock1 = ^{
		
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
												  usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeAllObjects];
				// Missing stop; Will cause exception.
			}];
		};
		
		STAssertThrows(exceptionBlock1(), @"Should throw exception");
		
		for (int i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key-%d", i];
			NSString *obj = [NSString stringWithFormat:@"obj-%d", i];
			
			[transaction setObject:obj forKey:key];
		}
		
		dispatch_block_t noExceptionBlock1 = ^{
			
			[[transaction ext:@"order"] enumerateKeysInGroup:@"default-group"
			                                      usingBlock:^(NSString *key, NSUInteger index, BOOL *stop) {
				
				[transaction removeAllObjects];
				*stop = YES;
			}];
		};
		
		STAssertNoThrow(noExceptionBlock1(), @"Should NOT throw exception. Proper use of stop.");
	}];
}

#pragma mark -

- (void)testDropView_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testDropView_withPath:databasePath options:options];
}

- (void)testDropView_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testDropView_withPath:databasePath options:options];
}

- (void)_testDropView_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
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
	groupingBlock = ^NSString *(NSString *key){
		
		return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2 options:NSNumericSearch];
	};
	
	YapDatabaseView *databaseView =
		[[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
		                             groupingBlockType:groupingBlockType
		                                  sortingBlock:sortingBlock
		                              sortingBlockType:sortingBlockType
		                                       version:0
		                                       options:options];
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	// Add a bunch of keys to the database & to the view
	
	NSUInteger count = 100;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < count; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key-%d", i];
			NSString *obj = [NSString stringWithFormat:@"obj-%d", i];
			
			[transaction setObject:obj forKey:key];
		}
	}];
	
	// Make sure the view is populated
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == count, @"View count is wrong");
	}];
	
	// Now drop the view
	
	[database unregisterExtension:@"order"];
	
	// Now make sure it's gone
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertNil([transaction ext:@"order"], @"Expected nil extension");
	}];
}

#pragma mark -

- (void)testFind_persistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = YES;
	
	[self _testFind_withPath:databasePath options:options];
}

- (void)testFind_nonPersistent
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
	options.isPersistent = NO;
	
	[self _testFind_withPath:databasePath options:options];
}

- (void)_testFind_withPath:(NSString *)databasePath options:(YapDatabaseViewOptions *)options
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
	groupingBlock = ^NSString *(NSString *key){
		
		return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		NSNumber *number1 = (NSNumber *)obj1;
		NSNumber *number2 = (NSNumber *)obj2;
		
		return [number1 compare:number2];
	};
	
	YapDatabaseView *databaseView =
		[[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
		                             groupingBlockType:groupingBlockType
		                                  sortingBlock:sortingBlock
		                              sortingBlockType:sortingBlockType
		                                       version:0
		                                       options:options];
	
	BOOL registerResult = [database registerExtension:databaseView withName:@"order"];
	
	STAssertTrue(registerResult, @"Failure registering extension");
	
	// Add a bunch of values to the database & to the view
	
	NSUInteger count = 100;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < count; i++)
		{
			NSString *key = [NSString stringWithFormat:@"key-%d", i];
			NSNumber *num = [NSNumber numberWithInt:i];
			
			[transaction setObject:num forKey:key];
		}
	}];
	
	// Make sure the view is populated
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == count, @"View count is wrong");
	}];
	
	// Now test finding different ranges
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		int min = 0;
		int max = 5;
		
		YapDatabaseViewBlockType blockType = YapDatabaseViewBlockTypeWithObject;
		YapDatabaseViewFindWithObjectBlock block = ^(NSString *key, id object){
			
			int value = [(NSNumber *)object intValue];
			
			if (value < min)
				return NSOrderedAscending;
			if (value >= max)
				return NSOrderedDescending;
			
			return NSOrderedSame;
		};
		
		NSRange range = [[transaction ext:@"order"] findRangeInGroup:@"" usingBlock:block blockType:blockType];
		
		NSUInteger location = (max > min) ? min : NSNotFound;
		NSUInteger length = (max > min) ? (max - min) : 0;
		
		STAssertTrue(range.location == location, @"Bad range location: %d", (int)range.location);
		STAssertTrue(range.length == length, @"Bad range length: %d", (int)range.length);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		int min = 11;
		int max = 54;
		
		YapDatabaseViewBlockType blockType = YapDatabaseViewBlockTypeWithObject;
		YapDatabaseViewFindWithObjectBlock block = ^(NSString *key, id object){
			
			int value = [(NSNumber *)object intValue];
			
			if (value < min)
				return NSOrderedAscending;
			if (value >= max)
				return NSOrderedDescending;
			
			return NSOrderedSame;
		};
		
		NSRange range = [[transaction ext:@"order"] findRangeInGroup:@"" usingBlock:block blockType:blockType];
		
		NSUInteger location = (max > min) ? min : NSNotFound;
		NSUInteger length = (max > min) ? (max - min) : 0;
		
		STAssertTrue(range.location == location, @"Bad range location: %d", (int)range.location);
		STAssertTrue(range.length == length, @"Bad range length: %d", (int)range.length);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		int min = 50;
		int max = 100;
		
		YapDatabaseViewBlockType blockType = YapDatabaseViewBlockTypeWithObject;
		YapDatabaseViewFindWithObjectBlock block = ^(NSString *key, id object){
			
			int value = [(NSNumber *)object intValue];
			
			if (value < min)
				return NSOrderedAscending;
			if (value >= max)
				return NSOrderedDescending;
			
			return NSOrderedSame;
		};
		
		NSRange range = [[transaction ext:@"order"] findRangeInGroup:@"" usingBlock:block blockType:blockType];
		
		NSUInteger location = (max > min) ? min : NSNotFound;
		NSUInteger length = (max > min) ? (max - min) : 0;
		
		STAssertTrue(range.location == location, @"Bad range location: %d", (int)range.location);
		STAssertTrue(range.length == length, @"Bad range length: %d", (int)range.length);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		int min = 40;
		int max = 40;
		
		YapDatabaseViewBlockType blockType = YapDatabaseViewBlockTypeWithObject;
		YapDatabaseViewFindWithObjectBlock block = ^(NSString *key, id object){
			
			int value = [(NSNumber *)object intValue];
			
			if (value < min)
				return NSOrderedAscending;
			if (value >= max)
				return NSOrderedDescending;
			
			return NSOrderedSame;
		};
		
		NSRange range = [[transaction ext:@"order"] findRangeInGroup:@"" usingBlock:block blockType:blockType];
		
		NSUInteger location = (max > min) ? min : NSNotFound;
		NSUInteger length = (max > min) ? (max - min) : 0;
		
		STAssertTrue(range.location == location, @"Bad range location: %d", (int)range.location);
		STAssertTrue(range.length == length, @"Bad range length: %d", (int)range.length);
	}];
}

@end
