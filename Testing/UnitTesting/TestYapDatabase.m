#import "TestYapDatabase.h"
#import "TestObject.h"

#import "YapDatabase.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseTransaction+Timestamp.h"

#import <libkern/OSAtomic.h>


@implementation TestYapDatabase
{
	YapDatabase *database;
}

- (NSString *)databaseName
{
	return @"TestYapDatabase.sqlite";
}

- (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	return [baseDir stringByAppendingPathComponent:[self databaseName]];
}

- (void)setUp
{
	NSLog(@"TestYapDatabase: setUp");
	
	[super setUp];
	
	[[NSFileManager defaultManager] removeItemAtPath:[self databasePath] error:NULL];
	
	database = [[YapDatabase alloc] initWithPath:[self databasePath]];
}

- (void)tearDown
{
	NSLog(@"TestYapDatabase: tearDown");
	
#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
	[database syncCheckpoint];
#endif
	
	database = nil;
	[[NSFileManager defaultManager] removeItemAtPath:[self databasePath] error:NULL];
	
	[super tearDown];
}

- (void)test1
{
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
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
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test empty database
		
		STAssertTrue([transaction numberOfKeys] == 0, @"Expected zero key count");
		STAssertTrue([[transaction allKeys] count] == 0, @"Expected empty array");
		
		STAssertNil([transaction objectForKey:@"non-existant-key"], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:@"non-existant-key"], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:@"non-existant-key"], @"Expected NO object for key");
		
		BOOL result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant-key"];
		
		STAssertFalse(result, @"Expected NO getObject for key");
		STAssertNil(aObj, @"Expected object to be set to nil");
		STAssertNil(aMetadata, @"Expected metadata to be set to nil");
		
		STAssertNil([transaction metadataForKey:@"non-existant-key"], @"Expected nil metadata");
		
		STAssertNoThrow([transaction removeObjectForKey:@"non-existant-key"], @"Expected no issues");
		
		NSArray *keys = @[@"non",@"existant",@"keys"];
		STAssertNoThrow([transaction removeObjectsForKeys:keys], @"Expected no issues");
		
		__block NSUInteger count = 0;
		
		[transaction enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");
		
		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");
		
		// Attempt to set metadata for a key that has no associated object.
		// It should silently fail (do nothing).
		// And further queries to fetch metadata for the same key should return nil.
		
		STAssertNoThrow([transaction setMetadata:metadata forKey:@"non-existant-key"], @"Expected nothing to happen");
		
		STAssertNil([transaction metadataForKey:@"non-existant-key"], @"Expected nil metadata since no object");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object without metadata
		
		[transaction setObject:object forKey:key1];
		
		STAssertTrue([transaction numberOfKeys] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeys] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1], @"Expected non-nil data");
		
		STAssertTrue([transaction hasObjectForKey:key1], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNil(aMetadata, @"Expected nil metadata");
		
		STAssertNil([transaction metadataForKey:key1], @"Expected nil metadata");
		
		[transaction enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNil(metadata, @"Expected nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNil(metadata, @"Expected nil metadata");
		}];
	}];

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1];
		
		STAssertTrue([transaction numberOfKeys] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeys] count] == 0, @"Expected 0 keys");
		
		STAssertNil([transaction objectForKey:key1], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:key1], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:key1], @"Expected NO");
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		[transaction setObject:object forKey:key1 withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeys] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeys] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1], @"Expected non-nil data");
		
		STAssertTrue([transaction hasObjectForKey:key1], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNotNil(aMetadata, @"Expected non-nil metadata");
		
		STAssertNotNil([transaction metadataForKey:key1], @"Expected non-nil metadata");
		
		[transaction enumerateKeysAndMetadataUsingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
	}];

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test multiple objects
		
		[transaction setObject:object forKey:key2 withMetadata:metadata];
		[transaction setObject:object forKey:key3 withMetadata:metadata];
		[transaction setObject:object forKey:key4 withMetadata:metadata];
		[transaction setObject:object forKey:key5 withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeys] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeys] count] == 5, @"Expected 5 keys");
		
		STAssertNotNil([transaction objectForKey:key1], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key2], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key3], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key4], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key5], @"Expected non-nil object");
		
		STAssertTrue([transaction hasObjectForKey:key1], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key2], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key3], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key4], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key5], @"Expected YES");
		
		STAssertNotNil([transaction metadataForKey:key1], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key2], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key3], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key4], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key5], @"Expected non-nil metadata");
	}];

	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ]];
		
		STAssertTrue([transaction numberOfKeys] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeys] count] == 2, @"Expected 2 keys");
		
		STAssertNil([transaction objectForKey:key1], @"Expected nil object");
		STAssertNil([transaction objectForKey:key2], @"Expected nil object");
		STAssertNil([transaction objectForKey:key3], @"Expected nil object");
		STAssertNotNil([transaction objectForKey:key4], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key5], @"Expected non-nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key2], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key3], @"Expected NO");
		STAssertTrue([transaction hasObjectForKey:key4], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key5], @"Expected YES");
		
		STAssertNil([transaction metadataForKey:key1], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key2], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key3], @"Expected nil metadata");
		STAssertNotNil([transaction metadataForKey:key4], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key5], @"Expected non-nil metadata");
	}];

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjects];
		
		STAssertNil([transaction objectForKey:key1], @"Expected nil object");
		STAssertNil([transaction objectForKey:key2], @"Expected nil object");
		STAssertNil([transaction objectForKey:key3], @"Expected nil object");
		STAssertNil([transaction objectForKey:key4], @"Expected nil object");
		STAssertNil([transaction objectForKey:key5], @"Expected nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key2], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key3], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key4], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key5], @"Expected NO");
		
		STAssertNil([transaction metadataForKey:key1], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key2], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key3], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key4], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key5], @"Expected nil metadata");
	}];
	
	connection1 = nil;
	connection2 = nil;
}

- (void)testMetadataTimestamp
{
	NSString *databaseName = @"TestYapDatabase2.sqlite";
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databasePath = [baseDir stringByAppendingPathComponent:databaseName];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	YapDatabase *database2 = [[YapDatabase alloc] initWithPath:databasePath
											  objectSerializer:NULL
											objectDeserializer:NULL
											metadataSerializer:[YapDatabase timestampSerializer]
										  metadataDeserializer:[YapDatabase timestampDeserializer]];
	
	YapDatabaseConnection *connection = [database2 newConnection];
	connection.objectCacheEnabled = NO;
	connection.metadataCacheEnabled = NO;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		NSString *key = @"key";
		id object = [NSNull null];
		NSDate *date = [NSDate date];
		
		[transaction setObject:object forKey:key withTimestamp:date];
		
		NSDate *aDate = [transaction timestampForKey:key];
		
		STAssertTrue([date isEqual:aDate], @"Oops");
	}];
}

/*
- (void)test2
{
	STAssertNotNil(database, @"Oops");
	
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
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		[NSThread sleepForTimeInterval:0.2]; // Zz
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			[transaction setObject:object forKey:key withMetadata:metadata];
			
			[NSThread sleepForTimeInterval:5.0]; // Zzzzzzzzzzzzzzzzzzzzzzzzzz
		}];
		
	});
	
	// This transaction should start before the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNil([transaction objectForKey:key], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:1.0]; // Zzzzzz
	
	// This transaction should start during the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNil([transaction objectForKey:key], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:5.0]; // Zzzzzzzzzzzzzzzzzzzzzzzzzz
	
	// This transaction should start after the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNotNil([transaction objectForKey:key], @"Expected non-nil object");
		STAssertNotNil([transaction metadataForKey:key], @"Expected non-nil metadata");
	}];
}
*/
/*
- (void)test3
{
	STAssertNotNil(database, @"Oops");
	
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
			
			[transaction setObject:object forKey:key withMetadata:metadata];
		}];
		
	});
	
	// This transaction should before the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNil([transaction objectForKey:key], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key], @"Expected nil metadata");
		
		[NSThread sleepForTimeInterval:2.0]; // Zzzzzzzzzzz
	}];
	
	[NSThread sleepForTimeInterval:0.2]; // Zz
	
	// This transaction should start after the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNotNil([transaction objectForKey:key], @"Expected non-nil object");
		STAssertNotNil([transaction metadataForKey:key], @"Expected non-nil metadata");
	}];
}
*/
/*
- (void)test4
{
	STAssertNotNil(database, @"Oops");
	
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
				
				[transaction setObject:object forKey:key withMetadata:metadata];
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
			
			(void)[transaction objectForKey:@"some-key-0"];
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		NSLog(@"Read operation: %.6f", elapsed);
		
		STAssertTrue(elapsed < 0.05, @"Read-Write transaction maybe blocking read-only transaction?");
	}
}
*/
/*
- (void)test5
{
	STAssertNotNil(database, @"Oops");
	
	/// Test race condition.
	/// 
	/// Need to modify YapDatabaseConnection:
	//  - add [NSThread sleepForTimeInterval:1.0] after read-write commit.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	__block int32_t doneWritingFlag = 0;
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		[NSThread sleepForTimeInterval:0.2];
		
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			int i;
			for (i = 0; i < 10; i++)
			{
				NSString *key = [NSString stringWithFormat:@"some-key-%d", i];
				TestObject *object = [TestObject generateTestObject];
				TestObjectMetadata *metadata = [object extractMetadata];
				
				[transaction setObject:object forKey:key withMetadata:metadata];
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
			
			(void)[transaction objectForKey:@"some-key-0"];
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		NSLog(@"Read operation: %.6f", elapsed);
		
		[NSThread sleepForTimeInterval:0.2];
	}
	
	for (int i = 0; i < 5; i++)
	{
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
			
			(void)[transaction objectForKey:@"some-key-0"];
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		NSLog(@"Read operation: %.6f", elapsed);
		
		[NSThread sleepForTimeInterval:0.2];
	}
	
	[database syncCheckpoint];
}
*/
@end
