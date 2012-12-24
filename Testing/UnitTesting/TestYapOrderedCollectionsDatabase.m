#import "TestYapOrderedCollectionsDatabase.h"
#import "YapOrderedCollectionsDatabase.h"
#import "TestObject.h"

@implementation TestYapOrderedCollectionsDatabase
{
	YapOrderedCollectionsDatabase *database;
}

- (NSString *)databaseName
{
	return @"TestYapOrderedCollectionsDatabase.sqlite";
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
	database = [[YapOrderedCollectionsDatabase alloc] initWithPath:[self databasePath]];
}

- (void)tearDown
{
	database = nil;
	[[NSFileManager defaultManager] removeItemAtPath:[self databasePath] error:NULL];
	
	[super tearDown];
}

- (void)test
{
	STAssertNotNil(database, @"Oops");
	
	YapCollectionsDatabaseConnection *connection1 = [database newConnection];
	YapCollectionsDatabaseConnection *connection2 = [database newConnection];
	
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	NSString *key1 = @"some-key-1";
	NSString *key2 = @"some-key-2";
	NSString *key3 = @"some-key-3";
	NSString *key4 = @"some-key-4";
	NSString *key5 = @"some-key-5";
	
	__block id aObj;
	__block id aMetadata;
	__block BOOL result;
	
	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected zero key count");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected empty array");
		
		STAssertNil([transaction objectForKey:@"non-existant" inCollection:nil], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:@"non-existant" inCollection:nil], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:@"non-existant" inCollection:nil], @"Expected NO object for key");
		
		BOOL result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant" inCollection:nil];
		
		STAssertFalse(result, @"Expected NO getObject for key");
		STAssertNil(aObj, @"Expected object to be set to nil");
		STAssertNil(aMetadata, @"Expected metadata to be set to nil");
		
		STAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil], @"Expected nil metadata");
		
		STAssertNoThrow([transaction removeObjectForKey:@"non-existant" inCollection:nil], @"Expected no issues");
		
		NSArray *keys = @[@"non",@"existant",@"keys"];
		STAssertNoThrow([transaction removeObjectsForKeys:keys inCollection:nil], @"Expected no issues");
		
		__block NSUInteger count = 0;
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");
		
		// Attempt to set metadata for a key that has no associated object.
		// It should silently fail (do nothing).
		// And further queries to fetch metadata for the same key should return nil.
		
		STAssertNoThrow([transaction setMetadata:metadata forKey:@"non-existant" inCollection:nil],
		                @"Expected nothing to happen");
		
		STAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil],
		            @"Expected nil metadata since no object");
	}];
	
	[connection2 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test object without metadata
		
		STAssertThrows([transaction setObject:object forKey:key1 inCollection:nil], @"Expected exception");
		
		[transaction appendObject:object forKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		STAssertTrue([transaction numberOfKeysInCollection:@""] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:@""] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		STAssertNotNil([transaction objectAtIndex:0 inCollection:nil], @"Expected non-nil object");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNil(aMetadata, @"Expected nil metadata");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNil(metadata, @"Expected nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNil(metadata, @"Expected nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
	}];
	
	[connection2 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");
		
		STAssertThrows([transaction setObject:object forKey:key1 inCollection:nil withMetadata:metadata],
		                @"Expected exception");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");

		[transaction appendObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNotNil(aMetadata, @"Expected non-nil metadata");
		
		STAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		
		[transaction enumerateKeysAndMetadataOrderedInCollection:nil usingBlock:
		 ^(NSUInteger index, NSString *key, id metadata, BOOL *stop){
			
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsOrderedInCollection:nil usingBlock:
		 ^(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop){
			 
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test multiple objects
		
		[transaction appendObject:object forKey:key2 inCollection:nil withMetadata:metadata];
		[transaction appendObject:object forKey:key3 inCollection:nil withMetadata:metadata];
		[transaction appendObject:object forKey:key4 inCollection:nil withMetadata:metadata];
		[transaction appendObject:object forKey:key5 inCollection:nil withMetadata:metadata];
		
		[transaction appendObject:object forKey:key1 inCollection:@"test" withMetadata:metadata];
		[transaction appendObject:object forKey:key2 inCollection:@"test" withMetadata:metadata];
		[transaction appendObject:object forKey:key3 inCollection:@"test" withMetadata:metadata];
		[transaction appendObject:object forKey:key4 inCollection:@"test" withMetadata:metadata];
		[transaction appendObject:object forKey:key5 inCollection:@"test" withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 10, @"Expected 10 keys");
		
		NSArray *expectedOrder = @[ key1, key2, key3, key4, key5 ];
		NSArray *returnedOrder;
		
		returnedOrder = [transaction allKeysInCollection:nil];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		returnedOrder = [transaction allKeysInCollection:@"test"];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		NSArray *expectedSubOrder = @[ key2, key3, key4 ];
		NSArray *returnedSubOrder;
		
		returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3) collection:nil];
		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder], @"Incorrect sub-order");
		
		returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3) collection:@"test"];
		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder], @"Incorrect sub-order");
	}];
	
	[connection2 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:nil];
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:@"test"];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 4, @"Expected 4 keys");
		
		NSArray *expectedOrder = @[ key4, key5 ];
		NSArray *returnedOrder;
		
		returnedOrder = [transaction allKeysInCollection:nil];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		returnedOrder = [transaction allKeysInCollection:@"test"];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
	}];

	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test prepend multiple objects
		
		[transaction prependObject:object forKey:key3 inCollection:nil withMetadata:metadata];
		[transaction prependObject:object forKey:key2 inCollection:nil withMetadata:metadata];
		[transaction prependObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		
		[transaction prependObject:object forKey:key3 inCollection:@"test" withMetadata:metadata];
		[transaction prependObject:object forKey:key2 inCollection:@"test" withMetadata:metadata];
		[transaction prependObject:object forKey:key1 inCollection:@"test" withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 10, @"Expected 10 keys");
		
		NSArray *expectedOrder = @[ key1, key2, key3, key4, key5 ];
		NSArray *returnedOrder;
		
		returnedOrder = [transaction allKeysInCollection:nil];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		returnedOrder = [transaction allKeysInCollection:@"test"];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		NSArray *expectedSubOrder = @[ key2, key3, key4 ];
		NSArray *returnedSubOrder;
		
		returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3) collection:nil];
		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder], @"Incorrect sub-order");
		
		returnedSubOrder = [transaction keysInRange:NSMakeRange(1, 3) collection:@"test"];
		STAssertTrue([expectedSubOrder isEqualToArray:returnedSubOrder], @"Incorrect sub-order");
	}];

	[connection2 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove range
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Wrong number of keys");
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Wrong number of keys");
		
		[transaction removeObjectsInRange:NSMakeRange(0, 3) collection:nil];
		[transaction removeObjectsInRange:NSMakeRange(0, 3) collection:@"test"];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 4, @"Expected 4 keys");
		
		NSArray *expectedOrder = @[ key4, key5 ];
		NSArray *returnedOrder;
		
		returnedOrder = [transaction allKeysInCollection:nil];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
		
		returnedOrder = [transaction allKeysInCollection:@"test"];
		STAssertTrue([expectedOrder isEqualToArray:returnedOrder], @"Incorrect order");
	}];

	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove collection
		
		[transaction removeAllObjectsInCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Wrong number of keys");
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Wrong number of keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 2, @"Wrong number of keys");
	}];
	
	[connection2 readWithBlock:^(YapOrderedCollectionsDatabaseReadTransaction *transaction){
		
		// Test remove collection (from another connection)
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Wrong number of keys");
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Wrong number of keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 2, @"Wrong number of keys");
		
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Wrong number of keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Wrong number of keys");
	}];
	
	[connection1 readWriteWithBlock:^(YapOrderedCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove all collections
		
		[transaction removeAllObjectsInAllCollections];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 0, @"Expected 0 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 0, @"Expected 0 keys");
	}];
	
	[connection2 readWithBlock:^(YapOrderedCollectionsDatabaseReadTransaction *transaction){
		
		// Test remove all collections (from another connection)
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 0, @"Expected 0 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 0, @"Expected 0 keys");
		
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Wrong number of keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 0, @"Wrong number of keys");
	}];
}

@end
