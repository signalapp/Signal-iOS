#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "TestObject.h"

#import <CocoaLumberjack/CocoaLumberjack.h>

#import <libkern/OSAtomic.h>

@interface TestYapDatabase : XCTestCase
@end

@implementation TestYapDatabase

- (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		unichar c = [alphabet characterAtIndex:(NSUInteger)arc4random_uniform((uint32_t)alphabetLength)];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

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

- (void)test1
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	TestObject *testObject = [TestObject generateTestObject];
	TestObjectMetadata *testMetadata = [testObject extractMetadata];
	
	NSString *key1 = @"some-key-1";
	NSString *key2 = @"some-key-2";
	NSString *key3 = @"some-key-3";
	NSString *key4 = @"some-key-4";
	NSString *key5 = @"some-key-5";
	
	__block id aObj;
	__block id aMetadata;
	__block BOOL result;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 0, @"Expected zero collection count");
		XCTAssertTrue([[transaction allCollections] count] == 0, @"Expected empty array");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected zero key count");
		
		XCTAssertNil([transaction objectForKey:@"non-existant" inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction serializedObjectForKey:@"non-existant" inCollection:nil], @"Expected nil data");
		
		XCTAssertFalse([transaction hasObjectForKey:@"non-existant" inCollection:nil], @"Expected NO object for key");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant" inCollection:nil];
		
		XCTAssertFalse(result, @"Expected NO getObject for key");
		XCTAssertNil(aObj, @"Expected object to be set to nil");
		XCTAssertNil(aMetadata, @"Expected metadata to be set to nil");
		
		XCTAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil], @"Expected nil metadata");
		
		XCTAssertNoThrow([transaction removeObjectForKey:@"non-existant" inCollection:nil], @"Expected no issues");
		
		NSArray *keys = @[@"non",@"existant",@"keys"];
		XCTAssertNoThrow([transaction removeObjectsForKeys:keys inCollection:nil], @"Expected no issues");
		
		__block NSUInteger count = 0;
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			count++;
		}];
		
		XCTAssertTrue(count == 0, @"Expceted zero keys");
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			count++;
		}];
		
		XCTAssertTrue(count == 0, @"Expceted zero keys");												
														
		// Attempt to set metadata for a key that has no associated object.
		// It should silently fail (do nothing).
		// And further queries to fetch metadata for the same key should return nil.
		
		XCTAssertNoThrow([transaction replaceMetadata:testMetadata forKey:@"non-existant" inCollection:nil],
		                 @"Expected nothing to happen");
		
		XCTAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil],
		            @"Expected nil metadata since no object");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object without metadata
		
		[transaction setObject:testObject forKey:key1 inCollection:nil];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@""] == 1, @"Expected 1 key");
		XCTAssertTrue([[transaction allKeysInCollection:@""] count] == 1, @"Expected 1 key");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction serializedObjectForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		XCTAssertTrue(result, @"Expected YES");
		XCTAssertNotNil(aObj, @"Expected non-nil object");
		XCTAssertNil(aMetadata, @"Expected nil metadata");
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			XCTAssertNil(metadata, @"Expected nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			XCTAssertNotNil(aObj, @"Expected non-nil object");
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			XCTAssertNotNil(aObj, @"Expected non-nil object");
			XCTAssertNil(metadata, @"Expected nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction serializedObjectForKey:key1 inCollection:nil], @"Expected nil data");
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		[transaction setObject:testObject forKey:key1 inCollection:nil withMetadata:testMetadata];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction serializedObjectForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		XCTAssertTrue(result, @"Expected YES");
		XCTAssertNotNil(aObj, @"Expected non-nil object");
		XCTAssertNotNil(aMetadata, @"Expected non-nil metadata");
		
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			XCTAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			XCTAssertNotNil(aObj, @"Expected non-nil object");
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			XCTAssertNotNil(aObj, @"Expected non-nil object");
			XCTAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test multiple objects
		
		[transaction setObject:testObject forKey:key1 inCollection:nil withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key2 inCollection:nil withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key3 inCollection:nil withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key4 inCollection:nil withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key5 inCollection:nil withMetadata:testMetadata];
		
		[transaction setObject:testObject forKey:key1 inCollection:@"test" withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key2 inCollection:@"test" withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key3 inCollection:@"test" withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key4 inCollection:@"test" withMetadata:testMetadata];
		[transaction setObject:testObject forKey:key5 inCollection:@"test" withMetadata:testMetadata];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Expected 5 keys");
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 5, @"Expected 5 keys");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Expected 5 keys");
		XCTAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5, @"Expected 5 keys");
		
		XCTAssertTrue([transaction numberOfKeysInAllCollections] == 10, @"Expected 10 keys");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected non-nil object");
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected YES");
		
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:nil];
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:@"test"];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 2, @"Expected 2 keys");
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 2, @"Expected 2 keys");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Expected 2 keys");
		XCTAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Expected 2 keys");
		
		XCTAssertTrue([transaction numberOfKeysInAllCollections] == 4, @"Expected 4 keys");
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"test"], @"Expected non-nil object");
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");

		XCTAssertTrue([transaction hasObjectForKey:key5 inCollection:nil], @"Expected YES");
		XCTAssertTrue([transaction hasObjectForKey:key5 inCollection:@"test"], @"Expected YES");
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		XCTAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
		
		XCTAssertNotNil([transaction metadataForKey:key5 inCollection:nil], @"Expected non-nil metadata");
		XCTAssertNotNil([transaction metadataForKey:key5 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjectsInAllCollections];
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected NO");
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		XCTAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test add objects to a particular collection
		
		[transaction setObject:testObject forKey:key1 inCollection:nil];
		[transaction setObject:testObject forKey:key2 inCollection:nil];
		[transaction setObject:testObject forKey:key3 inCollection:nil];
		[transaction setObject:testObject forKey:key4 inCollection:nil];
		[transaction setObject:testObject forKey:key5 inCollection:nil];
		
		[transaction setObject:testObject forKey:key1 inCollection:@"collection1"];
		[transaction setObject:testObject forKey:key2 inCollection:@"collection1"];
		[transaction setObject:testObject forKey:key3 inCollection:@"collection1"];
		[transaction setObject:testObject forKey:key4 inCollection:@"collection1"];
		[transaction setObject:testObject forKey:key5 inCollection:@"collection1"];
		
		[transaction setObject:testObject forKey:key1 inCollection:@"collection2"];
		[transaction setObject:testObject forKey:key2 inCollection:@"collection2"];
		[transaction setObject:testObject forKey:key3 inCollection:@"collection2"];
		[transaction setObject:testObject forKey:key4 inCollection:@"collection2"];
		[transaction setObject:testObject forKey:key5 inCollection:@"collection2"];
		
		XCTAssertTrue([transaction numberOfCollections] == 3,
					   @"Incorrect number of collections. Got=%d, Expected=3", (int)[transaction numberOfCollections]);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] ==  5, @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects from collection
		
		XCTAssertTrue([transaction numberOfCollections] == 3, @"Incorrect number of collections");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 5, @"Oops");
		
		[transaction removeAllObjectsInCollection:@"collection2"];
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2, @"Incorrect number of collections");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0, @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
	
	[connection1 flushMemoryWithFlags:YapDatabaseConnectionFlushMemoryFlags_All];
	[connection2 flushMemoryWithFlags:YapDatabaseConnectionFlushMemoryFlags_All];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2, @"Incorrect number of collections");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0, @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2, @"Incorrect number of collections");
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0, @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
}

- (void)test2
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	/// Test concurrent connections.
	///
	/// Ensure that a read-only transaction can continue while a read-write transaction starts.
	/// Ensure that a read-only transaction can start while a read-write transaction is in progress.
	/// Ensure that a read-only transaction picks up the changes after a read-write transaction.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	NSString *key = @"some-key";
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	dispatch_semaphore_t semaphore1 = dispatch_semaphore_create(0);
	dispatch_semaphore_t semaphore2 = dispatch_semaphore_create(0);
	dispatch_semaphore_t semaphore3 = dispatch_semaphore_create(0);
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		dispatch_semaphore_wait(semaphore1, DISPATCH_TIME_FOREVER);
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
			
			dispatch_semaphore_signal(semaphore2);
			[NSThread sleepForTimeInterval:0.4]; // Zzzzzzzzzzzzzzzzzzzzzzzzzz
		}];
		
		dispatch_semaphore_signal(semaphore3);
	});
	
	// This transaction will execute before the read-write transaction starts
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	dispatch_semaphore_signal(semaphore1);
	dispatch_semaphore_wait(semaphore2, DISPATCH_TIME_FOREVER);
	
	// This transaction will execute after the read-write transaction has started, but before it has committed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	dispatch_semaphore_wait(semaphore3, DISPATCH_TIME_FOREVER);
	
	// This transaction should start after the read-write transaction has completed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNotNil([transaction objectForKey:key inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction metadataForKey:key inCollection:nil], @"Expected non-nil metadata");
	}];
}

- (void)test3
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	/// Test concurrent connections.
	///
	/// Ensure that a read-only transaction properly unblocks a blocked read-write transaction.
	/// Need to turn on logging to check this.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	NSString *key = @"some-key";
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		[NSThread sleepForTimeInterval:0.2]; // Zz
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
		}];
		
	});
	
	// This transaction should before the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		[NSThread sleepForTimeInterval:1.0]; // Zzzzzzzzzzz
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		XCTAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:0.2]; // Zz
	
	// This transaction should start after the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNotNil([transaction objectForKey:key inCollection:nil], @"Expected non-nil object");
		XCTAssertNotNil([transaction metadataForKey:key inCollection:nil], @"Expected non-nil metadata");
	}];
}

- (void)test4
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	/// Ensure large write doesn't block concurrent read operations on other connections.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	__block int32_t doneWritingFlag = 0;
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			int i;
			for (i = 0; i < 100; i++)
			{
				NSString *key = [NSString stringWithFormat:@"some-key-%d", i];
				TestObject *object = [TestObject generateTestObject];
				TestObjectMetadata *metadata = [object extractMetadata];
				
				[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
			}
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		NSLog(@"Write operation: %.6f", elapsed);
		
		OSAtomicAdd32(1, &doneWritingFlag);
	});
	
	while (OSAtomicAdd32(0, &doneWritingFlag) == 0)
	{
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
			
			(void)[transaction objectForKey:@"some-key-0" inCollection:nil];
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		
		XCTAssertTrue(elapsed < 0.05, @"Read-Only transaction taking too long...");
	}
}

- (void)testPropertyListSerializerDeserializer
{
	YapDatabaseSerializer propertyListSerializer = [YapDatabase propertyListSerializer];
	YapDatabaseDeserializer propertyListDeserializer = [YapDatabase propertyListDeserializer];
	
	NSDictionary *originalDict = @{ @"date":[NSDate date], @"string":@"string" };
	
	NSData *data = propertyListSerializer(@"collection", @"key", originalDict);
	
	NSDictionary *deserializedDictionary = propertyListDeserializer(@"collection", @"key", data);
	
	XCTAssertTrue([originalDict isEqualToDictionary:deserializedDictionary], @"PropertyList serialization broken");
}

- (void)testTimestampSerializerDeserializer
{
	YapDatabaseSerializer timestampSerializer = [YapDatabase timestampSerializer];
	YapDatabaseDeserializer timestampDeserializer = [YapDatabase timestampDeserializer];
	
	NSDate *originalDate = [NSDate date];
	
	NSData *data = timestampSerializer(@"collection", @"key", originalDate);
	
	NSDate *deserializedDate = timestampDeserializer(@"collection", @"key", data);
	
	XCTAssertTrue([originalDate isEqual:deserializedDate], @"Timestamp serialization broken");
}

- (void)testMutationDuringEnumerationProtection
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	// Ensure enumeration protects against mutation
	
	YapDatabaseConnection *connection = [database newConnection];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"object" forKey:@"key1" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key2" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key3" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key4" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
	}];
	
	NSArray *keys = @[@"key1", @"key2", @"key3"];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// enumerateKeysInCollection:
		
		XCTAssertThrows(
			[transaction enumerateKeysInCollection:nil usingBlock:^(NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysInCollection:nil usingBlock:^(NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		
		// enumerateKeysInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateMetadataForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateObjectsForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndMetadataInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndObjectsInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		XCTAssertNoThrow(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
	}];
}

#if DEBUG
- (void)testPermittedTransactions
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	// Ensure enumeration protects against mutation
	
	YapDatabaseConnection *connection = [database newConnection];
	
	{// IMPLICIT YDB_AnyTransaction;
		
		XCTAssertNoThrow(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnyReadTransaction;
		
		XCTAssertNoThrow(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnyReadWriteTransaction;
		
		XCTAssertThrows(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnySyncTransaction;
		
		XCTAssertNoThrow(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnyAsyncTransaction;
		
		XCTAssertThrows(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertThrows(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnyTransaction | YDB_MainThreadOnly;
		
		XCTAssertNoThrow(
			[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
		XCTAssertNoThrow(
			[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
			@"Should throw exception"
		);
	}
	
	{ connection.permittedTransactions = YDB_AnyTransaction | YDB_MainThreadOnly;
		
		dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			
			XCTAssertThrows(
				[connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}],
				@"Should throw exception"
			);
			XCTAssertThrows(
				[connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}],
				@"Should throw exception"
			);
			XCTAssertThrows(
				[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
				@"Should throw exception"
			);
			XCTAssertThrows(
				[connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}],
				@"Should throw exception"
			);
			
			dispatch_semaphore_signal(semaphore);
		});
		
		dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	}
}
#endif

- (void)testBackup_synchronous
{
	NSUInteger count = 10000;
	
	NSString *databaseBackupName = [NSString stringWithFormat:@"%@.backup", NSStringFromSelector(_cmd)];
	NSString *databaseBackupPath = [self databasePath:databaseBackupName];
	
	[[NSFileManager defaultManager] removeItemAtPath:databaseBackupPath error:NULL];
	
	{
		NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
		
		[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
		YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
		
		XCTAssertNotNil(database, @"Oops");
		
		YapDatabaseConnection *connection = [database newConnection];
		
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (int i = 0; i < count; i++)
			{
				NSString *str = [self randomLetters:100];
				
				[transaction setObject:str forKey:str inCollection:nil];
			}
		}];
		
		NSError *error = [connection backupToPath:databaseBackupPath];
		
		XCTAssertNil(error, @"Error: %@", error);
	}
	
	{
		YapDatabase *backupDatabase = [[YapDatabase alloc] initWithPath:databaseBackupPath];
		
		XCTAssertNotNil(backupDatabase, @"Oops");
		
		[[backupDatabase newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			NSUInteger num = [transaction numberOfKeysInCollection:nil];
			
			XCTAssertTrue(num == count, @"num(%lu) != count(%lu)", (unsigned long)num, (unsigned long)count);
		}];
	}
}

- (void)testBackup_asynchronous
{
	NSUInteger count = 10000;
	
	NSString *databaseBackupName = [NSString stringWithFormat:@"%@.backup", NSStringFromSelector(_cmd)];
	NSString *databaseBackupPath = [self databasePath:databaseBackupName];
	
	[[NSFileManager defaultManager] removeItemAtPath:databaseBackupPath error:NULL];
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < count; i++)
		{
			NSString *str = [self randomLetters:100];
			
			[transaction setObject:str forKey:str inCollection:nil];
		}
	}];
	
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	
	__block NSProgress *progress = nil;
	progress = [connection asyncBackupToPath:databaseBackupPath
	                         completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
	                         completionBlock:^(NSError *error)
	{
		
		XCTAssertNil(error, @"Error: %@", error);
		
		YapDatabase *backupDatabase = [[YapDatabase alloc] initWithPath:databaseBackupPath];
		
		XCTAssertNotNil(backupDatabase, @"Oops");
		
		[[backupDatabase newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			NSUInteger num = [transaction numberOfKeysInCollection:nil];
			
			XCTAssertTrue(num == count, @"num(%lu) != count(%lu)", (unsigned long)num, (unsigned long)count);
		}];
		
		dispatch_semaphore_signal(semaphore);
	}];
		
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	XCTAssertTrue(progress.fractionCompleted >= 1.0, @"progress: %@", progress);
}

@end
