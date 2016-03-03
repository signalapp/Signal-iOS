#import <XCTest/XCTest.h>
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <libkern/OSAtomic.h>

#import "TestObject.h"
#import "YapDatabase.h"

#import "YapProxyObject.h"
#import "YapProxyObjectPrivate.h"


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
	
	XCTAssertNotNil(database);
	
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
		
		XCTAssertTrue([transaction numberOfCollections] == 0);
		XCTAssertTrue([[transaction allCollections] count] == 0);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 0);
		
		XCTAssertNil([transaction objectForKey:@"non-existant" inCollection:nil]);
		XCTAssertNil([transaction serializedObjectForKey:@"non-existant" inCollection:nil]);
		
		XCTAssertFalse([transaction hasObjectForKey:@"non-existant" inCollection:nil]);
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant" inCollection:nil];
		
		XCTAssertFalse(result, @"Expected NO getObject for key");
		XCTAssertNil(aObj, @"Expected object to be set to nil");
		XCTAssertNil(aMetadata, @"Expected metadata to be set to nil");
		
		XCTAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil]);
		
		XCTAssertNoThrow([transaction removeObjectForKey:@"non-existant" inCollection:nil]);
		
		NSArray *keys = @[@"non",@"existant",@"keys"];
		XCTAssertNoThrow([transaction removeObjectsForKeys:keys inCollection:nil]);
		
		__block NSUInteger count = 0;
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			count++;
		}];
		
		XCTAssertTrue(count == 0);
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			count++;
		}];
		
		XCTAssertTrue(count == 0);
														
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
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 1);
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 1);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@""] == 1);
		XCTAssertTrue([[transaction allKeysInCollection:@""] count] == 1);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction serializedObjectForKey:key1 inCollection:nil]);
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil]);
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		XCTAssertTrue(result);
		XCTAssertNotNil(aObj);
		XCTAssertNil(aMetadata);
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil]);
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			XCTAssertNil(metadata);
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			XCTAssertNotNil(aObj);
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			XCTAssertNotNil(aObj);
			XCTAssertNil(metadata);
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 0);
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 0);
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNil([transaction serializedObjectForKey:key1 inCollection:nil]);
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil]);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		[transaction setObject:testObject forKey:key1 inCollection:nil withMetadata:testMetadata];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 1);
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 1);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction serializedObjectForKey:key1 inCollection:nil]);
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil]);
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		XCTAssertTrue(result);
		XCTAssertNotNil(aObj);
		XCTAssertNotNil(aMetadata);
		
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:nil]);
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			XCTAssertNotNil(metadata);
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			XCTAssertNotNil(aObj);
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			XCTAssertNotNil(aObj);
			XCTAssertNotNil(metadata);
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
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 5);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5);
		XCTAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5);
		
		XCTAssertTrue([transaction numberOfKeysInAllCollections] == 10);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"test"]);
		
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:nil]);
		XCTAssertTrue([transaction hasObjectForKey:key1 inCollection:@"test"]);
		
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction metadataForKey:key1 inCollection:@"test"]);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:nil];
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:@"test"];
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 2);
		XCTAssertTrue([[transaction allKeysInCollection:nil] count] == 2);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2);
		XCTAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2);
		
		XCTAssertTrue([transaction numberOfKeysInAllCollections] == 4);
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"test"]);
		
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"test"]);
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil]);
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:@"test"]);

		XCTAssertTrue([transaction hasObjectForKey:key5 inCollection:nil]);
		XCTAssertTrue([transaction hasObjectForKey:key5 inCollection:@"test"]);
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil]);
		XCTAssertNil([transaction metadataForKey:key1 inCollection:@"test"]);
		
		XCTAssertNotNil([transaction metadataForKey:key5 inCollection:nil]);
		XCTAssertNotNil([transaction metadataForKey:key5 inCollection:@"test"]);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjectsInAllCollections];
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:nil],);
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"test"]);
		
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:nil]);
		XCTAssertFalse([transaction hasObjectForKey:key1 inCollection:@"test"]);
		
		XCTAssertNil([transaction metadataForKey:key1 inCollection:nil]);
		XCTAssertNil([transaction metadataForKey:key1 inCollection:@"test"]);
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
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] ==  5);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil]);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"]);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection2"]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection2"]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection2"]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection2"]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection2"]);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects from collection
		
		XCTAssertTrue([transaction numberOfCollections] == 3);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 5);
		
		[transaction removeAllObjectsInCollection:@"collection2"];
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil]);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"]);
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"]);
	}];
	
	[connection1 flushMemoryWithFlags:YapDatabaseConnectionFlushMemoryFlags_All];
	[connection2 flushMemoryWithFlags:YapDatabaseConnectionFlushMemoryFlags_All];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil]);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"]);
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"]);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertTrue([transaction numberOfCollections] == 2);
		
		XCTAssertTrue([transaction numberOfKeysInCollection:nil] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5);
		XCTAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:nil]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:nil]);
		
		XCTAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"]);
		XCTAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"]);
		
		XCTAssertNil([transaction objectForKey:key1 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key2 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key3 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key4 inCollection:@"collection2"]);
		XCTAssertNil([transaction objectForKey:key5 inCollection:@"collection2"]);
	}];
}

- (void)test2
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
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
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil]);
		XCTAssertNil([transaction metadataForKey:key inCollection:nil]);
	}];
	
	dispatch_semaphore_signal(semaphore1);
	dispatch_semaphore_wait(semaphore2, DISPATCH_TIME_FOREVER);
	
	// This transaction will execute after the read-write transaction has started, but before it has committed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil]);
		XCTAssertNil([transaction metadataForKey:key inCollection:nil]);
	}];
	
	dispatch_semaphore_wait(semaphore3, DISPATCH_TIME_FOREVER);
	
	// This transaction should start after the read-write transaction has completed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNotNil([transaction objectForKey:key inCollection:nil]);
		XCTAssertNotNil([transaction metadataForKey:key inCollection:nil]);
	}];
}

- (void)test3
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
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
		
		XCTAssertNil([transaction objectForKey:key inCollection:nil]);
		XCTAssertNil([transaction metadataForKey:key inCollection:nil]);
	}];
	
	[NSThread sleepForTimeInterval:0.2]; // Zz
	
	// This transaction should start after the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertNotNil([transaction objectForKey:key inCollection:nil]);
		XCTAssertNotNil([transaction metadataForKey:key inCollection:nil]);
	}];
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
	
	XCTAssertNotNil(database);
	
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
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysInCollection:nil usingBlock:^(NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateKeysInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateMetadataForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateObjectsForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateRowsForKeys:inCollection:unorderedUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateKeysAndMetadataInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateKeysAndObjectsInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateRowsInCollection:usingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
		
		// enumerateRowsInAllCollectionsUsingBlock:
		
		XCTAssertThrows(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			}]);
		
		XCTAssertNoThrow(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			}]);
	}];
}

- (void)testPermittedTransactions
{
#if YapDatabaseEnforcePermittedTransactions
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	// Ensure enumeration protects against mutation
	
	YapDatabaseConnection *connection = [database newConnection];
	
	// IMPORTANT NOTE:
	//
	// Within YapDatabaseConnection, the permittedTransaction is tested BEFORE the dispatch_async.
	// So we can safely test exception throwing when invoking async transactions.
	
	{// IMPLICIT YDB_AnyTransaction;
		
		XCTAssertNoThrow([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertNoThrow([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnyReadTransaction;
		
		XCTAssertNoThrow([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertThrows([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertThrows([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnyReadWriteTransaction;
		
		XCTAssertThrows([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertThrows([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertNoThrow([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnySyncTransaction;
		
		XCTAssertNoThrow([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertThrows([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertNoThrow([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertThrows([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnyAsyncTransaction;
		
		XCTAssertThrows([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertThrows([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnyTransaction | YDB_MainThreadOnly;
		
		XCTAssertNoThrow([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		
		XCTAssertNoThrow([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
		XCTAssertNoThrow([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
	}
	
	{ connection.permittedTransactions = YDB_AnyTransaction | YDB_MainThreadOnly;
		
		dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			
			XCTAssertThrows([connection readWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
			XCTAssertThrows([connection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
			
			XCTAssertThrows([connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
			XCTAssertThrows([connection asyncReadWriteWithBlock:^(YapDatabaseReadTransaction *transaction){}]);
			
			dispatch_semaphore_signal(semaphore);
		});
		
		dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	}
#endif
}

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
		
		XCTAssertNotNil(database);
		
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
		
		XCTAssertNotNil(backupDatabase);
		
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
	
	XCTAssertNotNil(database);
	
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
		
		XCTAssertNotNil(backupDatabase);
		
		[[backupDatabase newConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			NSUInteger num = [transaction numberOfKeysInCollection:nil];
			
			XCTAssertTrue(num == count, @"num(%lu) != count(%lu)", (unsigned long)num, (unsigned long)count);
		}];
		
		dispatch_semaphore_signal(semaphore);
	}];
		
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	XCTAssertTrue(progress.fractionCompleted >= 1.0, @"progress: %@", progress);
}

- (void)testVFS_standard
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[self _testVFS_withPath:databasePath options:nil];
}

- (void)testVFS_memoryMappedIO
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	// When using Memory Mapped IO, sqlite uses xFetch instead of xRead.
	// Since this is a different code path, it's worthwhile to have different test cases.
	
	YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
	options.pragmaMMapSize = (1024 * 1024 * 1); // in bytes
	
	[self _testVFS_withPath:databasePath options:options];
}

- (void)_testVFS_withPath:(NSString *)databasePath options:(YapDatabaseOptions *)options
{
	// Yap uses a vfs shim in order to send a notification which is useful
	// in detecting when sqlite has acquired its snapshot.
	//
	// This allows read-only transactions to skip the sqlite machinery in certain circustances.
	// Which is helpful, as a read-only transaction may only require the cache.
	//
	// However, this requires us to watch out for a particular edge case:
	//
	// - a read-write transaction that occurs AFTER a read-only transaction has started
	// - the read-write transaction is ready to commit BEFORE the read-only transaction has
	//   acquired its sql-level snapshot
	//
	// In this case, we have to make the read-write transaction wait until the read-only transaction has
	// acquired its sql-level snapshot. And we use a custom vfs shim in order to notify the read-only
	// transaction of when the sql-level snapshot has been taken.
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath options:options];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	dispatch_queue_t queue1 = dispatch_queue_create("completion_connection1", DISPATCH_QUEUE_SERIAL);
	dispatch_queue_t queue2 = dispatch_queue_create("completion_connection2", DISPATCH_QUEUE_SERIAL);
	
	dispatch_semaphore_t semaphore1 = dispatch_semaphore_create(0);
	dispatch_semaphore_t semaphore2 = dispatch_semaphore_create(0);
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
		// Force connection1 to acquire 'wal_file' instance.
	}];
	
	[connection1 asyncReadWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
		
//		NSLog(@"connection1: sleeping...");
		[NSThread sleepForTimeInterval:4.0];
//		NSLog(@"connection1: Done sleeping !");
		
		NSUInteger numberOfCollections = [transaction numberOfCollections];
//		NSLog(@"connection1: numberOfCollections = %lu", (unsigned long)numberOfCollections);
		
		XCTAssert(numberOfCollections == 0);
		
	} completionQueue:queue1 completionBlock:^{
		
		dispatch_semaphore_signal(semaphore1);
	}];
	
	// Make sure connection1's read-only transaction starts BEFORE connection2's read-write transaction
	[NSThread sleepForTimeInterval:1.0];
	
//	NSLog(@"Starting readWrite transaction on connection2...");
	[connection2 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
		
//		NSLog(@"connection2: modifying database...");
		
		[transaction setObject:@"object" forKey:@"key" inCollection:@"collection"];
		
		NSUInteger numberOfCollections = [transaction numberOfCollections];
//		NSLog(@"connection2: numberOfCollections = %lu", (unsigned long)numberOfCollections);
		
		XCTAssert(numberOfCollections == 1);
		
	} completionQueue:queue2 completionBlock:^{
		
		dispatch_semaphore_signal(semaphore2);
	}];
	
	dispatch_semaphore_wait(semaphore1, DISPATCH_TIME_FOREVER);
	dispatch_semaphore_wait(semaphore2, DISPATCH_TIME_FOREVER);
}

- (void)testDeadlockDetection
{
#ifndef NS_BLOCK_ASSERTIONS
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertThrows([connection1 readWithBlock:^(YapDatabaseReadTransaction *ignore){}]);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		XCTAssertThrows([connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *ignore){}]);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertThrows([connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *ignore){}]);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		XCTAssertThrows([connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *ignore){}]);
	}];

#endif
}

- (void)testDoubleEnumeration
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection = [database newConnection];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"New York Yankees" forKey:@"nyy" inCollection:@"teams"];
		[transaction setObject:@"Boston Red Sox"   forKey:@"brs" inCollection:@"teams"];
		
		[transaction setObject:@"Mickey Mantle" forKey:@"1" inCollection:@"nyy"];
		[transaction setObject:@"Derek Jeter"   forKey:@"2" inCollection:@"nyy"];
		
		[transaction setObject:@"Ted Williams" forKey:@"1" inCollection:@"brs"];
		[transaction setObject:@"David Ortiz"  forKey:@"2" inCollection:@"brs"];
	}];
	
	__block NSUInteger count = 0;
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[transaction enumerateKeysInCollection:@"teams" usingBlock:^(NSString *teamName, BOOL *stop) {
			
			[transaction enumerateKeysInCollection:teamName usingBlock:^(NSString *player, BOOL *_stop) {
				
				count++;
			}];
		}];
	}];
	
	XCTAssert(count == 4);
}

@end
