#import "TestYapCollectionsDatabase.h"
#import "YapCollectionsDatabase.h"
#import "TestObject.h"


@implementation TestYapCollectionsDatabase
{
	YapCollectionsDatabase *database;
}

- (NSString *)databaseName
{
	return @"TestYapCollectionsDatabase.sqlite";
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
	database = [[YapCollectionsDatabase alloc] initWithPath:[self databasePath]];
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
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfCollections] == 0, @"Expected zero collection count");
		STAssertTrue([[transaction allCollections] count] == 0, @"Expected empty array");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected zero key count");
		
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
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test object without metadata
		
		[transaction setObject:object forKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		STAssertTrue([transaction numberOfKeysInCollection:@""] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:@""] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected non-nil data");
		
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
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		[transaction setObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		
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
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test multiple objects
		
		[transaction setObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key2 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key3 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key4 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key5 inCollection:nil withMetadata:metadata];
		
		[transaction setObject:object forKey:key1 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key2 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key3 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key4 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key5 inCollection:@"test" withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 10, @"Expected 10 keys");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected non-nil object");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected YES");
		
		STAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:nil];
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:@"test"];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 4, @"Expected 4 keys");
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"test"], @"Expected non-nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");

		STAssertTrue([transaction hasObjectForKey:key5 inCollection:nil], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key5 inCollection:@"test"], @"Expected YES");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
		
		STAssertNotNil([transaction metadataForKey:key5 inCollection:nil], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key5 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjectsInAllCollections];
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected NO");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test add objects to a particular collection
		
		[transaction setObject:object forKey:key1 inCollection:nil];
		[transaction setObject:object forKey:key2 inCollection:nil];
		[transaction setObject:object forKey:key3 inCollection:nil];
		[transaction setObject:object forKey:key4 inCollection:nil];
		[transaction setObject:object forKey:key5 inCollection:nil];
		
		[transaction setObject:object forKey:key1 inCollection:@"collection1"];
		[transaction setObject:object forKey:key2 inCollection:@"collection1"];
		[transaction setObject:object forKey:key3 inCollection:@"collection1"];
		[transaction setObject:object forKey:key4 inCollection:@"collection1"];
		[transaction setObject:object forKey:key5 inCollection:@"collection1"];
		
		[transaction setObject:object forKey:key1 inCollection:@"collection2"];
		[transaction setObject:object forKey:key2 inCollection:@"collection2"];
		[transaction setObject:object forKey:key3 inCollection:@"collection2"];
		[transaction setObject:object forKey:key4 inCollection:@"collection2"];
		[transaction setObject:object forKey:key5 inCollection:@"collection2"];
		
		STAssertTrue([transaction numberOfCollections] == 3,
					   @"Incorrect number of collections. Got=%d, Expected=3", [transaction numberOfCollections]);
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] ==  5, @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
	
	[connection1 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects from collection
		
		STAssertTrue([transaction numberOfCollections] == 3, @"Incorrect number of collections");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 5, @"Oops");
		
		[transaction removeAllObjectsInCollection:@"collection2"];
	}];
	
	[connection2 readWriteWithBlock:^(YapCollectionsDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfCollections] == 2, @"Incorrect number of collections");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0, @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		STAssertNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
}

@end
