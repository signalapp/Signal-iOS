#import "TestYapDatabaseView.h"
#import "TestObject.h"

#import "YapDatabase.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseTransaction+Timestamp.h"

#import "YapDatabaseView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

@implementation TestYapDatabaseView

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"TestYapDatabaseView-%@.sqlite", suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)test
{
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
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
		
		return [object1 compare:object2];
	};
	
	YapDatabaseView *databaseView =
	    [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                 groupingBlockType:groupingBlockType
	                                      sortingBlock:sortingBlock
	                                  sortingBlockType:sortingBlockType];
	
	[database registerExtension:databaseView withName:@"order"];
	
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

@end
