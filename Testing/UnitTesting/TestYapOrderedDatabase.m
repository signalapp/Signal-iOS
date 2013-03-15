#import "TestYapOrderedDatabase.h"
#import "YapOrderedDatabase.h"
#import "YapDatabaseTransaction+Timestamp.h"
#import "TestObject.h"


@implementation TestYapOrderedDatabase
{
	YapOrderedDatabase *database;
}

- (NSString *)databaseName
{
	return @"TestYapOrderedDatabase.sqlite";
}

- (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	return [baseDir stringByAppendingPathComponent:[self databaseName]];
}

- (void)setUp
{
	[super setUp];
	
	[[NSFileManager defaultManager] removeItemAtPath:[self databasePath] error:NULL];
	database = [[YapOrderedDatabase alloc] initWithPath:[self databasePath]];
}

- (void)tearDown
{
	database = nil;
	[[NSFileManager defaultManager] removeItemAtPath:[self databasePath] error:NULL];
	
	[super tearDown];
}

//- (void)test
//{
//	STAssertNotNil(database, @"Oops");
//	
//	YapOrderedDatabaseConnection *connection1 = [database newConnection];
//	YapOrderedDatabaseConnection *connection2 = [database newConnection];
//	
//	TestObject *object = [TestObject generateTestObject];
//	TestObjectMetadata *metadata = [object extractMetadata];
//	
//	NSString *key1 = @"some-key-1";
//	NSString *key2 = @"some-key-2";
//	NSString *key3 = @"some-key-3";
//	NSString *key4 = @"some-key-4";
//	NSString *key5 = @"some-key-5";
//	
//	__block id aObj;
//	__block id aMetadata;
//	__block BOOL result;
//	
//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		STAssertTrue([transaction numberOfKeys] == 0, @"Expected zero key count");
//		STAssertTrue([[transaction allKeys] count] == 0, @"Expected empty array");
//		
//		STAssertNil([transaction objectForKey:@"non-existant-key"], @"Expected nil object");
//		STAssertNil([transaction primitiveDataForKey:@"non-existant-key"], @"Expected nil data");
//		
//		STAssertFalse([transaction hasObjectForKey:@"non-existant-key"], @"Expected NO object for key");
//		
//		BOOL result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant-key"];
//		
//		STAssertFalse(result, @"Expected NO getObject for key");
//		STAssertNil(aObj, @"Expected object to be set to nil");
//		STAssertNil(aMetadata, @"Expected metadata to be set to nil");
//		
//		STAssertNil([transaction metadataForKey:@"non-existant-key"], @"Expected nil metadata");
//		
//		STAssertNoThrow([transaction removeObjectForKey:@"non-existant-key"], @"Expected no issues");
//		
//		NSArray *keys = @[@"non",@"existant",@"keys"];
//		STAssertNoThrow([transaction removeObjectsForKeys:keys], @"Expected no issues");
//		
//		__block NSUInteger count = 0;
//		
//		[transaction enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
//			count++;
//		}];
//		
//		STAssertTrue(count == 0, @"Expceted zero keys");
//		
//		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
//			count++;
//		}];
//		
//		STAssertTrue(count == 0, @"Expceted zero keys");
//		
//		// Attempt to set metadata for a key that has no associated object.
//		// It should silently fail (do nothing).
//		// And further queries to fetch metadata for the same key should return nil.
//		
//		STAssertNoThrow([transaction setMetadata:metadata forKey:@"non-existant-key"], @"Expected nothing to happen");
//		
//		STAssertNil([transaction metadataForKey:@"non-existant-key"], @"Expected nil metadata since no object");
//	}];
//
//	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test object without metadata
//		
//		STAssertThrows([transaction setObject:object forKey:key1], @"Expected exception");
//		
//		[transaction appendObject:object forKey:key1];
//		
//		STAssertTrue([transaction numberOfKeys] == 1, @"Expected 1 key");
//		STAssertTrue([[transaction allKeys] count] == 1, @"Expected 1 key");
//		
//		STAssertNotNil([transaction objectForKey:key1], @"Expected non-nil object");
//		STAssertNotNil([transaction primitiveDataForKey:key1], @"Expected non-nil data");
//		
//		STAssertNotNil([transaction objectAtIndex:0], @"Expected non-nil object");
//		
//		STAssertTrue([transaction hasObjectForKey:key1], @"Expected YES");
//		
//		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1];
//		
//		STAssertTrue(result, @"Expected YES");
//		STAssertNotNil(aObj, @"Expected non-nil object");
//		STAssertNil(aMetadata, @"Expected nil metadata");
//		
//		STAssertNil([transaction metadataForKey:key1], @"Expected nil metadata");
//		
//		[transaction enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
//			
//			STAssertNil(metadata, @"Expected nil metadata");
//		}];
//		
//		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
//			
//			STAssertNotNil(aObj, @"Expected non-nil object");
//			STAssertNil(metadata, @"Expected nil metadata");
//		}];
//	}];
//	
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
//
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
//
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
//
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
//
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
//
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
//
//	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction <YapOrderedReadWriteTransaction> *transaction){
//		
//		// Test remove all objects
//		
//		[transaction removeAllObjects];
//		
//		STAssertTrue([transaction numberOfKeys] == 0, @"Expected 0 keys");
//		STAssertTrue([[transaction allKeys] count] == 0, @"Expected 0 keys");
//	}];
//	
//	connection1 = nil;
//	connection2 = nil;
//}

- (void)testCategory
{
	STAssertNotNil(database, @"Oops");
	
	YapOrderedDatabaseConnection *connection1 = [database newConnection];
	YapOrderedDatabaseConnection *connection2 = [database newConnection];
	
	TestObject *object = [TestObject generateTestObject];
	
	NSDate *metadata1 = [NSDate dateWithTimeIntervalSinceNow:-1];
	NSDate *metadata2 = [NSDate dateWithTimeIntervalSinceNow:-2];
	NSDate *metadata3 = [NSDate dateWithTimeIntervalSinceNow:-3];
	NSDate *metadata4 = [NSDate dateWithTimeIntervalSinceNow:-4];
	NSDate *metadata5 = [NSDate dateWithTimeIntervalSinceNow:-5];
	
	NSString *key1 = @"some-key-1";
	NSString *key2 = @"some-key-2";
	NSString *key3 = @"some-key-3";
	NSString *key4 = @"some-key-4";
	NSString *key5 = @"some-key-5";
	
	[connection1 readWriteWithBlock:^(YapOrderedDatabaseReadWriteTransaction *transaction){
		
		[transaction appendObject:object forKey:key1 withMetadata:metadata1];
		[transaction appendObject:object forKey:key2 withMetadata:metadata2];
		[transaction appendObject:object forKey:key3 withMetadata:metadata3];
		[transaction appendObject:object forKey:key4 withMetadata:metadata4];
		[transaction appendObject:object forKey:key5 withMetadata:metadata5];
	}];
	
	[connection2 readWriteWithBlock:^(YapOrderedDatabaseReadWriteTransaction *transaction){
		
		NSArray *keys = nil;
		
		keys = [transaction removeObjectsLaterThanOrEqualTo:metadata1];
		STAssertTrue([keys count] == 1, @"Removed keys: %@", keys);
		
		keys = [transaction removeObjectsEarlierThanOrEqualTo:metadata5];
		STAssertTrue([keys count] == 1, @"Removed keys: %@", keys);
	}];
	
	[connection1 readWriteWithBlock:^(YapOrderedDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfKeys] == 3, @"Oops");
		STAssertTrue([[transaction allKeys] count] == 3, @"Oops");
		
		NSArray *keys = nil;
		
		keys = [transaction removeObjectsLaterThan:metadata3];
		STAssertTrue([keys count] == 1, @"Removed keys: %@", keys);
		
		keys = [transaction removeObjectsEarlierThan:metadata3];
		STAssertTrue([keys count] == 1, @"Removed keys: %@", keys);
	}];
	
	[connection2 readWriteWithBlock:^(YapOrderedDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfKeys] == 1, @"Oops");
		STAssertTrue([[transaction allKeys] count] == 1, @"Oops");
		
		NSArray *keys = [transaction removeObjectsFrom:metadata5 to:metadata1];
		STAssertTrue([keys count] == 1, @"Oops");
	}];
	
	[connection1 readWithBlock:^(YapOrderedDatabaseReadTransaction *transaction){
		
		STAssertTrue([transaction numberOfKeys] == 0, @"Oops");
		STAssertTrue([[transaction allKeys] count] == 0, @"Oops");
	}];
	
	connection1 = nil;
	connection2 = nil;
}

@end
