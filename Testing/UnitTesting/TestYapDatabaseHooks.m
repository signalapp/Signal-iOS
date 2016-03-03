#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <CocoaLumberjack/CocoaLumberjack.h>

#import "YapDatabase.h"
#import "YapDatabaseHooks.h"


@interface TestYapDatabaseHooks : XCTestCase
@end

@implementation TestYapDatabaseHooks

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

- (void)test
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	XCTAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	XCTAssertNotNil(connection, @"Oops");
	
	__block NSUInteger invokeCount_willModifyRow = 0;
	__block NSUInteger invokeCount_didModifyRow  = 0;
	
	__block NSUInteger invokeCount_willRemoveRow = 0;
	__block NSUInteger invokeCount_didRemoveRow  = 0;
	
	__block NSUInteger invokeCount_willRemoveAllRows = 0;
	__block NSUInteger invokeCount_didRemoveAllRows = 0;
	
	__block YapDatabaseHooksBitMask expectedFlags;
	
	YDBHooks_WillModifyRow willModifyRow =
 	  ^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
	    YapProxyObject *proxyObject, YapProxyObject *proxyMetadata, YapDatabaseHooksBitMask flags)
	{
		invokeCount_willModifyRow++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
		XCTAssert(collection != nil, @"Bad collection");
		XCTAssert(key != nil, @"Bad key");
		XCTAssert(proxyObject != nil, @"Bad proxyObject");
		XCTAssert(proxyMetadata != nil, @"Bad proxyMetadata");
		
		XCTAssert(flags == expectedFlags, @"Bad flags");
		
		if (flags & YapDatabaseHooksInsertedRow)
		{
			XCTAssert(proxyObject.isRealObjectLoaded, @"Bad proxy");
			XCTAssert(proxyMetadata.isRealObjectLoaded, @"Bad proxy");
			
			XCTAssert(proxyObject.realObject != nil, @"Bad proxy");
			XCTAssert(proxyMetadata.realObject != nil, @"Bad proxy");
		}
		else if (flags & YapDatabaseHooksUpdatedRow)
		{
			if (flags & YapDatabaseHooksChangedObject) {
				XCTAssert(proxyObject.isRealObjectLoaded, @"Bad proxy");
			}
			
			if (flags & YapDatabaseHooksChangedMetadata) {
				XCTAssert(proxyMetadata.isRealObjectLoaded, @"Bad proxy");
			}
			
			XCTAssert(proxyObject.realObject != nil, @"Bad proxy");
			XCTAssert(proxyMetadata.realObject != nil, @"Bad proxy");
		}
	};
	
	
	YDBHooks_DidModifyRow didModifyRow =
	  ^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
	    YapProxyObject *proxyObject, YapProxyObject *proxyMetadata, YapDatabaseHooksBitMask flags)
	{
		invokeCount_didModifyRow++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
		XCTAssert(collection != nil, @"Bad collection");
		XCTAssert(key != nil, @"Bad key");
		XCTAssert(proxyObject != nil, @"Bad proxyObject");
		XCTAssert(proxyMetadata != nil, @"Bad proxyMetadata");
		
		XCTAssert(flags == expectedFlags, @"Bad flags");
		
		if (flags & YapDatabaseHooksInsertedRow)
		{
			XCTAssert(proxyObject.isRealObjectLoaded, @"Bad proxy");
			XCTAssert(proxyMetadata.isRealObjectLoaded, @"Bad proxy");
			
			XCTAssert(proxyObject.realObject != nil, @"Bad proxy");
			XCTAssert(proxyMetadata.realObject != nil, @"Bad proxy");
		}
		else if (flags & YapDatabaseHooksUpdatedRow)
		{
			if (flags & YapDatabaseHooksChangedObject) {
				XCTAssert(proxyObject.isRealObjectLoaded, @"Bad proxy");
			}
			
			if (flags & YapDatabaseHooksChangedMetadata) {
				XCTAssert(proxyMetadata.isRealObjectLoaded, @"Bad proxy");
			}
			
			XCTAssert(proxyObject.realObject != nil, @"Bad proxy");
			XCTAssert(proxyMetadata.realObject != nil, @"Bad proxy");
		}
	};
	
	YDBHooks_WillRemoveRow willRemoveRow =
	  ^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key)
	{
		invokeCount_willRemoveRow++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
		XCTAssert(collection != nil, @"Bad collection");
		XCTAssert(key != nil, @"Bad key");
		
		id object = [transaction objectForKey:key inCollection:collection];
		id metadata = [transaction metadataForKey:key inCollection:collection];
		
		XCTAssert(object != nil, @"Expected valid row");
		XCTAssert(metadata != nil, @"Expected valid row");
	};
	
	YDBHooks_DidRemoveRow didRemoveRow =
	  ^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key)
	{
		invokeCount_didRemoveRow++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
		XCTAssert(collection != nil, @"Bad collection");
		XCTAssert(key != nil, @"Bad key");
	};
	
	YDBHooks_WillRemoveAllRows willRemoveAllRows =
	  ^(YapDatabaseReadWriteTransaction *transaction)
	{
		invokeCount_willRemoveAllRows++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
	};
	
	YDBHooks_DidRemoveAllRows didRemoveAllRows =
	  ^(YapDatabaseReadWriteTransaction *transaction)
	{
		invokeCount_didRemoveAllRows++;
		
		XCTAssert(transaction != nil, @"Bad transaction");
	};
	
	YapDatabaseHooks *hooks = [[YapDatabaseHooks alloc] init];
	hooks.willModifyRow = willModifyRow;
	hooks.didModifyRow = didModifyRow;
	hooks.willRemoveRow = willRemoveRow;
	hooks.didRemoveRow = didRemoveRow;
	hooks.willRemoveAllRows = willRemoveAllRows;
	hooks.didRemoveAllRows = didRemoveAllRows;
	hooks.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObjects:@"+", @"-", nil]];
	
	BOOL result = [database registerExtension:hooks withName:@"hooks"];
	XCTAssert(result, @"Bad registration");
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Insert 5 items
		
		expectedFlags = YapDatabaseHooksInsertedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		[transaction setObject:@"0" forKey:@"0" inCollection:@"+"  withMetadata:@"0"];
		[transaction setObject:@"1" forKey:@"1" inCollection:@"+"  withMetadata:@"1"];
		[transaction setObject:@"2" forKey:@"2" inCollection:@"+"  withMetadata:@"2"];
		[transaction setObject:@"3" forKey:@"3" inCollection:@"+"  withMetadata:@"3"];
		[transaction setObject:@"4" forKey:@"4" inCollection:@"-" withMetadata:@"4"];
		// Insert row for collection not in whitelist
		[transaction setObject:@"5" forKey:@"5" inCollection:@"x" withMetadata:@"5"];
		
		// Modify 3 rows
		
		expectedFlags = YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		[transaction setObject:@"0b" forKey:@"0" inCollection:@"+" withMetadata:@"0b"];
		[transaction setObject:@"1b" forKey:@"1" inCollection:@"+" withMetadata:@"1b"];
		[transaction setObject:@"2b" forKey:@"2" inCollection:@"+" withMetadata:@"2b"];
		// Modify row for collection not in whitelist
		[transaction setObject:@"5b" forKey:@"5" inCollection:@"x" withMetadata:@"5b"];
		
		// Modify object only
		
		expectedFlags = YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject;
		
		[transaction replaceObject:@"3" forKey:@"3" inCollection:@"+"];
		// Modify object for collection not in whitelist
		[transaction setObject:@"5b" forKey:@"5" inCollection:@"x"];
		
		// Modify metadata only
		
		expectedFlags = YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedMetadata;
		
		[transaction replaceMetadata:@"4b" forKey:@"4" inCollection:@"-"];
		
		// Modify metadata for collection not in whitelist
		[transaction replaceMetadata:@"5b" forKey:@"5" inCollection:@"x"];
		
		// Remove 1 row
		
		[transaction removeObjectForKey:@"0" inCollection:nil];
		
		// Remove row in collection not in whitelist
		[transaction removeObjectForKey:@"5" inCollection:@"x"];
		
		// Remove 2 more rows
		
		[transaction removeObjectsForKeys:@[ @"1", @"2" ] inCollection:nil];
		
		// Remove 1 more row
		
		[transaction removeAllObjectsInCollection:@"+"];
		
		// Clear database
		
		[transaction removeAllObjectsInAllCollections];
	}];
	
	XCTAssert(invokeCount_willModifyRow == 10);
	XCTAssert(invokeCount_didModifyRow == 10);
	
	XCTAssert(invokeCount_willRemoveRow == 4);
	XCTAssert(invokeCount_didRemoveRow == 4);
	
	XCTAssert(invokeCount_willRemoveAllRows == 1);
	XCTAssert(invokeCount_didRemoveAllRows == 1);
}

@end
