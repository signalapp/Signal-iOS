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
	YapDatabaseViewGroupingWithBothBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithBoth;
	groupingBlock = ^NSString *(NSString *key, id object, id metadata){
		
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
	
	[database registerView:databaseView withName:@"order"];
	
	NSString *key0 = @"key0";
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";
	NSString *key3 = @"key3";
	NSString *key4 = @"key4";
	NSString *keyX = @"keyX";
	
	id object0 = @"object0";
	id object1 = @"object1";
	id object2 = @"object2";
	id object3 = @"object3";
	id object4 = @"object4";
	id objectX = @"objectX";
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertNil([transaction view:@"non-existent-view"], @"Expected nil view");
		STAssertNotNil([transaction view:@"order"], @"Expected non-nil view transaction");
		
		STAssertTrue([[transaction view:@"order"] numberOfGroups] == 0, @"Expected zero group count");
		STAssertTrue([[[transaction view:@"order"] allGroups] count] == 0, @"Expected empty array");
		
		STAssertTrue([[transaction view:@"order"] numberOfKeysInGroup:@""] == 0, @"Expected zero");
		STAssertTrue([[transaction view:@"order"] numberOfKeysInAllGroups] == 0, @"Expected zero");
		
		STAssertNil([[transaction view:@"order"] groupForKey:key0], @"Expected nil");
		
		STAssertNil([[transaction view:@"order"] keyAtIndex:0 inGroup:@""], @"Expected nil");
		STAssertNil([[transaction view:@"order"] objectAtIndex:0 inGroup:@""], @"Expected nil");
		
		NSString *group = nil;
		NSUInteger index = 0;
		
		BOOL result = [[transaction view:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertFalse(result, @"Expected NO");
		STAssertNil(group, @"Expected group to be set to nil");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test inserting a single object
		
		[transaction setObject:object0 forKey:key0];
		
		// Read it back
		
		STAssertTrue([[transaction view:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction view:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction view:@"order"] numberOfKeysInGroup:@""] == 1, @"Wrong count");
		STAssertTrue([[transaction view:@"order"] numberOfKeysInAllGroups] == 1, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction view:@"order"] groupForKey:key0];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0 = [[transaction view:@"order"] keyAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0], @"Expected match");
		
		id fetchedObject0 = [[transaction view:@"order"] objectAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedObject0 isEqualToString:object0], @"Expected match");
		
		BOOL result = [[transaction view:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test reading data back on separate connection
		
		STAssertTrue([[transaction view:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction view:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction view:@"order"] numberOfKeysInGroup:@""] == 1, @"Wrong count");
		STAssertTrue([[transaction view:@"order"] numberOfKeysInAllGroups] == 1, @"Wrong count");
		
		NSString *group = nil;
		NSUInteger index = NSNotFound;
		
		group = [[transaction view:@"order"] groupForKey:key0];
		
		STAssertTrue([group isEqualToString:@""], @"Wrong group");
		
		id fetchedKey0 = [[transaction view:@"order"] keyAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedKey0 isEqualToString:key0], @"Expected match");
		
		id fetchedObject0 = [[transaction view:@"order"] objectAtIndex:0 inGroup:@""];
		
		STAssertTrue([fetchedObject0 isEqualToString:object0], @"Expected match");
		
		BOOL result = [[transaction view:@"order"] getGroup:&group index:&index forKey:key0];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(group, @"Expected group to be set");
		STAssertTrue(index == 0, @"Expected index to be set to zero");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test inserting more objects
		
		NSUInteger count = 1;
		
		[transaction setObject:object1 forKey:key1]; count++; // Included
		[transaction setObject:object2 forKey:key2]; count++; // Included
		[transaction setObject:object3 forKey:key3]; count++; // Included
		[transaction setObject:object4 forKey:key4]; count++; // Included
		[transaction setObject:objectX forKey:keyX];          // Excluded !
		
		STAssertTrue([[transaction view:@"order"] numberOfGroups] == 1, @"Wrong group count");
		STAssertTrue([[[transaction view:@"order"] allGroups] count] == 1, @"Wrong array count");
		
		STAssertTrue([[transaction view:@"order"] numberOfKeysInGroup:@""] == count, @"Wrong count");
		STAssertTrue([[transaction view:@"order"] numberOfKeysInAllGroups] == count, @"Wrong count");
		
		NSArray *keys = @[ key0, key1, key2, key3, key4 ];
		
		NSUInteger index = 0;
		for (NSString *key in keys)
		{
			NSString *fetchedKey = [[transaction view:@"order"] keyAtIndex:index inGroup:@""];;
			
			STAssertTrue([fetchedKey isEqualToString:key],
			    @"Non-matching keys(%@ vs %@) at index %d", fetchedKey, key, index);
			
			index++;
		}
		
		for (NSString *key in keys)
		{
			NSString *fetchedGroup = [[transaction view:@"order"] groupForKey:key];
			
			STAssertTrue([fetchedGroup isEqualToString:@""], @"Wrong group(%@) for key(%@)", fetchedGroup, key);
		}
	}];
	
//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test remove object
//		
//		[transaction removeObjectForKey:key1];
//		
//		STAssertTrue([transaction numberOfKeys] == 0, @"Expected 0 keys");
//		STAssertTrue([[transaction allKeys] count] == 0, @"Expected 0 keys");
//		
//		STAssertNil([transaction objectForKey:key1], @"Expected nil object");
//		STAssertNil([transaction primitiveDataForKey:key1], @"Expected nil data");
//		
//		STAssertFalse([transaction hasObjectForKey:key1], @"Expected NO");
//	}];

//	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test object with metadata
//		
//		STAssertThrows([transaction setObject:object forKey:key1 withMetadata:metadata], @"Expected exception");
//		
//		[transaction appendObject:object forKey:key1 withMetadata:metadata];
//		
//		STAssertTrue([transaction numberOfKeys] == 1, @"Expected 1 key");
//		STAssertTrue([[transaction allKeys] count] == 1, @"Expected 1 key");
//		
//		STAssertNotNil([transaction objectForKey:key1], @"Expected non-nil object");
//		STAssertNotNil([transaction primitiveDataForKey:key1], @"Expected non-nil data");
//		
//		STAssertTrue([transaction hasObjectForKey:key1], @"Expected YES");
//		
//		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1];
//		
//		STAssertTrue(result, @"Expected YES");
//		STAssertNotNil(aObj, @"Expected non-nil object");
//		STAssertNotNil(aMetadata, @"Expected non-nil metadata");
//		
//		STAssertNotNil([transaction metadataForKey:key1], @"Expected non-nil metadata");
//		
//		[transaction enumerateKeysAndMetadataOrderedUsingBlock:
//		 ^(NSUInteger index, NSString *key, id metadata, BOOL *stop){
//			
//			STAssertNotNil(metadata, @"Expected non-nil metadata");
//		}];
//		
//		[transaction enumerateKeysAndObjectsOrderedUsingBlock:
//		 ^(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop){
//			 
//			STAssertNotNil(aObj, @"Expected non-nil object");
//			STAssertNotNil(metadata, @"Expected non-nil metadata");
//		}];
//	}];

//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test multiple objects
//		
//		STAssertTrue([transaction numberOfKeys] == 1, @"Expected 1 key");
//		STAssertTrue([[transaction allKeys] count] == 1, @"Expected 1 key");
//		
//		[transaction appendObject:object forKey:key2 withMetadata:metadata];
//		[transaction appendObject:object forKey:key3 withMetadata:metadata];
//		[transaction appendObject:object forKey:key4 withMetadata:metadata];
//		[transaction appendObject:object forKey:key5 withMetadata:metadata];
//		
//		STAssertTrue([transaction numberOfKeys] == 5, @"Expected 5 keys");
//		STAssertTrue([[transaction allKeys] count] == 5, @"Expected 5 keys");
//		
//		NSArray *expectedOrder = @[ key1, key2, key3, key4, key5 ];
//		NSArray *returnedOrder = [transaction allKeys];
//		
//		STAssertTrue([expectedOrder isEqualToArray:returnedOrder],
//		             @"Incorrect order:\n expected: %@\n returned: %@", expectedOrder, returnedOrder);
//		
//		NSArray *expectedSubOrder = @[ key2, key3, key4 ];
//		NSArray *returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3)];
//		
//		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder], @"Incorrect sub-order");
//	}];

//	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test remove multiple objects
//		
//		[transaction removeObjectsForKeys:@[ key1, key2, key3 ]];
//		
//		STAssertTrue([transaction numberOfKeys] == 2, @"Expected 2 keys");
//		STAssertTrue([[transaction allKeys] count] == 2, @"Expected 2 keys");
//		
//		NSArray *expectedOrder = @[ key4, key5 ];
//		NSArray *returnedOrder = [transaction allKeys];
//		
//		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
//	}];

//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test prepend multiple objects
//		
//		[transaction prependObject:object forKey:key3 withMetadata:metadata];
//		[transaction prependObject:object forKey:key2 withMetadata:metadata];
//		[transaction prependObject:object forKey:key1 withMetadata:metadata];
//		
//		STAssertTrue([transaction numberOfKeys] == 5, @"Expected 5 keys");
//		STAssertTrue([[transaction allKeys] count] == 5, @"Expected 5 keys");
//		
//		NSArray *expectedOrder = @[ key1, key2, key3, key4, key5 ];
//		NSArray *returnedOrder = [transaction allKeys];
//		
//		STAssertTrue([expectedOrder isEqualToArray:returnedOrder],
//		             @"Incorrect order: expected(%@) returned(%@)", expectedOrder, returnedOrder);
//		
//		NSArray *expectedSubOrder = @[ key2, key3, key4 ];
//		NSArray *returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3)];
//		
//		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder],
//		             @"Incorrect sub-order: expected(%@) returned(%@)", expectedSubOrder, returnedSubOrder);
//	}];

//	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test remove range
//		
//		[transaction removeObjectsInRange:NSMakeRange(0, 3)];
//		
//		STAssertTrue([transaction numberOfKeys] == 2, @"Expected 2 keys");
//		STAssertTrue([[transaction allKeys] count] == 2, @"Expected 2 keys");
//		
//		NSArray *expectedOrder = @[ key4, key5 ];
//		NSArray *returnedOrder = [transaction allKeys];
//		
//		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
//	}];

//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test remove all objects
//		
//		[transaction removeAllObjects];
//		
//		STAssertTrue([transaction numberOfKeys] == 0, @"Expected 0 keys");
//		STAssertTrue([[transaction allKeys] count] == 0, @"Expected 0 keys");
//	}];
	
	connection1 = nil;
	connection2 = nil;
}

@end
