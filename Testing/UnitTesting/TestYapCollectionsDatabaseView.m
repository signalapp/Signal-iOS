#import "TestYapCollectionsDatabaseView.h"

#import "YapCollectionsDatabase.h"
#import "YapCollectionsDatabasePrivate.h"
#import "YapCollectionsDatabaseTransaction+Timestamp.h"

#import "YapCollectionsDatabaseView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"


@implementation TestYapCollectionsDatabaseView

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"TestYapDatabaseView-%@.sqlite", suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)test
{
	[DDLog removeAllLoggers];
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
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
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2];
	};
	
	YapCollectionsDatabaseView *databaseView =
	    [[YapCollectionsDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                            groupingBlockType:groupingBlockType
	                                                 sortingBlock:sortingBlock
	                                             sortingBlockType:sortingBlockType];
	
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
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		STAssertNil([transaction ext:@"non-existent-view"], @"Expected nil");
		STAssertNotNil([transaction ext:@"order"], @"Expected non-nil view transaction");
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Expected zero group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Expected empty array");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == 0, @"Expected zero");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == 0, @"Expected zero");
		
		STAssertNil([[transaction ext:@"order"] groupForKey:key0 inCollection:nil], @"Expected nil");
		
		NSString *group = nil;
		NSUInteger index = 0;
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0 inCollection:nil];
		
		STAssertFalse(result, @"Expected NO");
		STAssertNil(group, @"Expected group to be set to nil");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test inserting a single object
		
		[transaction setObject:object0 forKey:key0 inCollection:nil]; keysCount++;
		
		// Read it back
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction ext:@"order"] groupForKey:key0 inCollection:nil];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0;
		id fetchedCollection0;
		
		[[transaction ext:@"order"] getKey:&fetchedKey0 collection:&fetchedCollection0 atIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0], @"Expected match");
		STAssertTrue([fetchedCollection0 isEqualToString:@""], @"Expected match");
		
		id fetchedObject0 = [[transaction ext:@"order"] objectAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedObject0 isEqualToString:object0], @"Expected match");
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0 inCollection:nil];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set");
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test reading data back on separate connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction ext:@"order"] groupForKey:key0 inCollection:nil];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0;
		id fetchedCollection0;
		
		[[transaction ext:@"order"] getKey:&fetchedKey0 collection:&fetchedCollection0 atIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0],
		             @"Expected match: fetched(%@) vs expected(%@)", fetchedKey0, key0);
		
		STAssertTrue([fetchedCollection0 isEqualToString:@""],
		             @"Expected match: fetched(%@) expected(%@)", fetchedCollection0, @"");
		
		id fetchedObject0 = [[transaction ext:@"order"] objectAtIndex:0 inGroup:@""];
	
		STAssertTrue([fetchedObject0 isEqualToString:object0],
		             @"Expected match: fetchedObject0(%@) vs object0(%@)", fetchedObject0, object0);
		
		BOOL result = [[transaction ext:@"order"] getGroup:&group index:&index forKey:key0 inCollection:nil];
	
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test inserting more objects
		
		[transaction setObject:object1 forKey:key1 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object2 forKey:key2 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4 inCollection:nil]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX inCollection:nil];              // Excluded !
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedCollection;
			NSString *fetchedKey;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
			             @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result = [[transaction ext:@"order"] getGroup:&fetchedGroup
			                                             index:&fetchedIndex
			                                            forKey:key
			                                      inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
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
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test updating the metadata of our object.
		//
		// This should invoke our grouping block (to determine if the group changed).
		// However, once it determines the group hasn't changed,
		// it should abort as the sorting block only takes the object into account.
		
		[transaction setMetadata:@"some-metadata" forKey:key0 inCollection:nil];
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test updating the object (in such a manner that changes its position within the view)
		//
		// key0 should move from index0 to index4
		
		NSString *fetchedKey;
		NSString *fetchedCollection;
		
		[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:1 inGroup:@""];
		
		STAssertTrue([fetchedKey isEqualToString:key1], @"Oops");
		STAssertTrue([fetchedCollection isEqualToString:@""], @"Oops");
		
		[transaction setObject:object1B forKey:key1 inCollection:nil];
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, key1 ]; // <-- Updated order (key1 moved to end)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
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
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test removing a single key
		
		[transaction removeObjectForKey:key1 inCollection:nil]; keysCount--;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key2, key3, key4, ]; // <-- Updated order (key1 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
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
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];

	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key2, key3 ] inCollection:nil]; keysCount -= 2;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key4, ]; // <-- Updated order (key2 & key3 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Read the changes back on another connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key4, ]; // <-- Updated order (key2 & key3 removed)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];

	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjectsInAllCollections]; keysCount = 0;
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
	}];

	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		// Read changes from other connection
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 0, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 0, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Add all the objects back (in random order)
		
		[transaction setObject:object2 forKey:key2 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object1 forKey:key1 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3 inCollection:nil]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX inCollection:nil];              // Excluded !
		[transaction setObject:object0 forKey:key0 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4 inCollection:nil]; keysCount++; // Included
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ]; // <-- Updated order (key1 moved to end)
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Again on connection 2
		// Remove all the keys, and then add a few back
		
		[transaction removeAllObjectsInCollection:nil]; keysCount = 0;
		
		[transaction setObject:object1 forKey:key1 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object0 forKey:key0 inCollection:nil]; keysCount++; // Included
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Add all the keys back. Some are already included.
		
		[transaction setObject:object0 forKey:key0 inCollection:nil];              // Already included
		[transaction setObject:object1 forKey:key1 inCollection:nil];              // Already included
		[transaction setObject:object2 forKey:key2 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object3 forKey:key3 inCollection:nil]; keysCount++; // Included
		[transaction setObject:object4 forKey:key4 inCollection:nil]; keysCount++; // Included
		[transaction setObject:objectX forKey:keyX inCollection:nil];              // Excluded !
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection1 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		// Read the changes
		
		STAssertTrue([[transaction ext:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction ext:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInGroup:@""] == keysCount, @"Wrong count");
		STAssertTrue([[transaction ext:@"order"] numberOfKeysInAllGroups] == keysCount, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey;
			NSString *fetchedCollection;
			
			[[transaction ext:@"order"] getKey:&fetchedKey collection:&fetchedCollection atIndex:index inGroup:@""];
			
			STAssertTrue([fetchedKey isEqualToString:key],
						 @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			STAssertTrue([fetchedCollection isEqualToString:@""],
						 @"Non-matching collections(%@ vs %@) at index %d", fetchedCollection, @"", index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction ext:@"order"] groupForKey:key inCollection:nil];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
		
		index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = nil;
			NSUInteger fetchedIndex = NSNotFound;
			
			BOOL result =
			    [[transaction ext:@"order"] getGroup:&fetchedGroup index:&fetchedIndex forKey:key inCollection:nil];
			
			STAssertTrue(result, @"Wrong result for key(%@) at index(%d)", key, index);
			
			STAssertTrue([fetchedGroup isEqualToString:@""],
			             @"Wrong group(%@) for key(%@) at index(%d)", fetchedGroup, key, index);
			
			STAssertTrue(fetchedIndex == index,
			             @"Wrong index(%d) for key(%@) at index(%d)", fetchedIndex, key, index);
			
			index++;
		}
	}];
	
	[connection2 readWithBlock:^(YapCollectionsDatabaseReadTransaction *transaction){
		
		// Test enumeration
		
		__block NSUInteger correctIndex;
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		// Basic enumeration
		
		correctIndex = 0;
		[[transaction ext:@"order"] enumerateKeysInGroup:@""
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
		                              usingBlock:^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop) {
			
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
