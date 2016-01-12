#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseRelationship.h"
#import "TestNodes.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>


@interface TestYapDatabaseRelationship : XCTestCase
@end

@implementation TestYapDatabaseRelationship

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testProtocol_Standard
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	Node_Standard *n1 = [[Node_Standard alloc] init];
	Node_Standard *n2 = [[Node_Standard alloc] init];
	Node_Standard *n3 = [[Node_Standard alloc] init];
	
	n1.childKeys = @[ n2.key, n3.key ];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting the children
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n2.key inCollection:nil];
		[transaction removeObjectForKey:n3.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Re-add the children and edges
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Re-add the children
		
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		// Reset the parent (so it re-adds the edges)
		
		[transaction replaceObject:n1 forKey:n1.key inCollection:nil];
		
		// Check that the edges are back
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting the parent
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"child"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		
		XCTAssertNil([transaction objectForKey:n2.key inCollection:nil]);
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
	
	// Now test adding an edge and deleting it within the same transaction
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		
		[[transaction ext:@"relationship"] flush];
		
		XCTAssertNil([transaction objectForKey:n2.key inCollection:nil]);
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
	
	// Re-add everything
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
	}];
	
	// Update n1, and remove its children, which should delete n2 & n3
	
	n1.childKeys = nil;
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction objectForKey:n2.key inCollection:nil]);
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
}

- (void)testProtocol_Inverse
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	Node_Inverse *n1 = [[Node_Inverse alloc] init];
	Node_Inverse *n2 = [[Node_Inverse alloc] init];
	Node_Inverse *n3 = [[Node_Inverse alloc] init];
	
	n2.parentKey = n1.key;
	n3.parentKey = n1.key;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting 1 of the children.
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n2.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"parent"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting the parent.
	// This should also delete the second child (due to the nodeDeleteRules).
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction objectForKey:n2.key inCollection:nil]);
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
}

- (void)testProtocol_RetainCount
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	Node_RetainCount *n1 = [[Node_RetainCount alloc] init];
	Node_RetainCount *n2 = [[Node_RetainCount alloc] init];
	Node_RetainCount *n3 = [[Node_RetainCount alloc] init];
	
	// Node1 & Node2 will both retain Node3.
	//
	// Node1 -> Node3
	// Node2 -> Node3
	
	n1.retainedKey = n3.key;
	n2.retainedKey = n3.key;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting 1 of the retainers.
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" destinationKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained" sourceKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n1.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retained"
		                                                       sourceKey:n2.key
		                                                      collection:nil
		                                                  destinationKey:n3.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting the second/last retainer.
	// This should also delete n3 (as no more nodes are retaining it).
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n2.key inCollection:nil];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
}

- (void)testProtocol_InverseRetainCount
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	Node_InverseRetainCount *n1 = [[Node_InverseRetainCount alloc] init];
	Node_InverseRetainCount *n2 = [[Node_InverseRetainCount alloc] init];
	Node_InverseRetainCount *n3 = [[Node_InverseRetainCount alloc] init];
	
	// Node1 & Node2 will both retain Node3.
	// But the edges are being created in reverse.
	//
	// Node3 -> Node1
	// Node3 -> Node2
	
	n3.retainerKeys = @[ n1.key, n2.key ];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting both of the retainers.
	// This should delete n3, because no nodes are left to retain it.
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		[transaction removeObjectForKey:n2.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Reset all the nodes
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Re-add the children
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		// Check that the edges are back
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 2, @"Bad edgeCount. expected(2) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Test deleting just one of the retainers.
	// This should not delete n3, as n2 is still retaining it.
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		
		NSUInteger edgeCount;
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" sourceKey:n3.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n1.key collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(0) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer" destinationKey:n2.key collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n1.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 0, @"Bad edgeCount. expected(0) != %d", (int)edgeCount);
		
		edgeCount = [[transaction ext:@"relationship"] edgeCountWithName:@"retainer"
		                                                       sourceKey:n3.key
		                                                      collection:nil
		                                                  destinationKey:n2.key
		                                                      collection:nil];
		XCTAssertTrue(edgeCount == 1, @"Bad edgeCount. expected(1) != %d", (int)edgeCount);
	}];
	
	// Now delete the last retainer (n2).
	// This should delete n3 as there are no other nodes retaining it.
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:n2.key inCollection:nil];
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
	
	// Now test adding the edges and deleting them within the same transaction
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:n1 forKey:n1.key inCollection:nil];
		[transaction setObject:n2 forKey:n2.key inCollection:nil];
		[transaction setObject:n3 forKey:n3.key inCollection:nil];
		
		[transaction removeObjectForKey:n1.key inCollection:nil];
		[transaction removeObjectForKey:n2.key inCollection:nil];
		
		[[transaction ext:@"relationship"] flush];
		
		XCTAssertNil([transaction objectForKey:n3.key inCollection:nil]);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testManual_1
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:key1
		                                 collection:nil
		                             destinationKey:key2
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:edge];
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		[[transaction ext:@"relationship"] flush];
		
		XCTAssertNil([transaction objectForKey:key2 inCollection:nil]);
	}];
}

- (void)testManual_2
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:key1
		                                 collection:nil
		                             destinationKey:key2
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:edge];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:key1
		                                 collection:nil
		                             destinationKey:key2
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:edge];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test removing an edge
		
		[[transaction ext:@"relationship"] removeEdgeWithName:@"child"
		                                            sourceKey:key1
		                                           collection:nil
		                                       destinationKey:key2
		                                           collection:nil
		                                       withProcessing:YDB_SourceNodeDeleted];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 0);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// The edge's nodeDeleteRules (YDB_DeleteDestinationIfSourceDeleted),
		// plus the processing rules (YDB_SourceNodeDeleted),
		// should have resulted in the destination node being deleted.
		
		id obj1 = [transaction objectForKey:key1 inCollection:nil];
		XCTAssertNotNil(obj1, @"Relationship incorrectly deleted sourceNode");
		
		id obj2 = [transaction objectForKey:key2 inCollection:nil];
		XCTAssertNil(obj2, @"Relationship extension didn't properly delete destinationNode");
		
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test removing an edge that doesn't exist in the database.
		// Make sure it doesn't do anything funky.
		
		[[transaction ext:@"relationship"] removeEdgeWithName:@"child"
		                                            sourceKey:key1
		                                           collection:nil
		                                       destinationKey:key2
		                                           collection:nil
		                                       withProcessing:YDB_SourceNodeDeleted];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 0);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		id obj1 = [transaction objectForKey:key1 inCollection:nil];
		XCTAssertNotNil(obj1, @"Relationship incorrectly deleted sourceNode");
		
		id obj2 = [transaction objectForKey:key2 inCollection:nil];
		XCTAssertNil(obj2, @"Relationship extension didn't properly delete destinationNode");
		
	}];
}

- (void)testManual_3
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";

	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test creating an edge in a separate transaction from when the nodes are created
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:key1
		                                 collection:nil
		                             destinationKey:key2
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:edge];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test deleting an edge without any processing rules
		
		[[transaction ext:@"relationship"] removeEdgeWithName:@"child"
		                                            sourceKey:key1
		                                           collection:nil
		                                       destinationKey:key2
		                                           collection:nil
		                                       withProcessing:YDB_EdgeDeleted];
		
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 0);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// The processing rules (YDB_EdgeDeleted),
		// should * NOT * have resulted in the destination node being deleted.
		
		id obj1 = [transaction objectForKey:key1 inCollection:nil];
		XCTAssertNotNil(obj1, @"Relationship incorrectly deleted sourceNode");
		
		id obj2 = [transaction objectForKey:key2 inCollection:nil];
		XCTAssertNotNil(obj2, @"Relationship incorrectly deleted destinationNode");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Re-create the edge (with different nodeDeleteRules)
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:key1
		                                 collection:nil
		                             destinationKey:key2
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
		
		[[transaction ext:@"relationship"] addEdge:edge];
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test deleting an edge
		
		[[transaction ext:@"relationship"] removeEdgeWithName:@"child"
		                                            sourceKey:key1
		                                           collection:nil
		                                       destinationKey:key2
		                                           collection:nil
		                                       withProcessing:YDB_DestinationNodeDeleted];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child"];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" sourceKey:key1 collection:nil];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"child" destinationKey:key2 collection:nil];
		XCTAssertTrue(count == 0);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// The edge's nodeDeleteRules (YDB_DeleteSourceIfDestinationDeleted),
		// plus the processing rules (YDB_DestinationNodeDeleted),
		// should have resulted in the source node being deleted.
		
		id obj1 = [transaction objectForKey:key1 inCollection:nil];
		XCTAssertNil(obj1, @"Relationship extension should have deleted sourceNode");
		
		id obj2 = [transaction objectForKey:key2 inCollection:nil];
		XCTAssertNotNil(obj2, @"Relationship extension improperly deleted destinationNode");
		
	}];
}

- (void)testManual_4
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *edgeName      = @"story->topic";
	NSString *srcKey        = @"storyID";
	NSString *srcCollection = @"stories";
	NSString *dstKey        = @"topicID";
	NSString *dstCollection = @"topics";
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test creating an edge where the source doesn't exist yet
		
		YapDatabaseRelationshipEdge *edge =
		  [YapDatabaseRelationshipEdge edgeWithName:edgeName
		                                  sourceKey:srcKey
		                                 collection:srcCollection
		                             destinationKey:dstKey
		                                 collection:dstCollection
		                            nodeDeleteRules:0];
		
		[[transaction ext:@"relationship"] addEdge:edge];
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                                   sourceKey:srcKey
		                                                  collection:srcCollection];
		XCTAssertTrue(count == 1, @"Expected=1, Found=%lu", (unsigned long)count);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                              destinationKey:dstKey
		                                                  collection:dstCollection];
		XCTAssertTrue(count == 1, @"Expected=1, Found=%lu", (unsigned long)count);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                                   sourceKey:srcKey
		                                                  collection:srcCollection
		                                              destinationKey:dstKey
		                                                  collection:dstCollection];
		XCTAssertTrue(count == 1, @"Expected=1, Found=%lu", (unsigned long)count);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Test adding a bad edge (forgetting to add source || destination)
		
		NSUInteger count;
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName];
		XCTAssertTrue(count == 0);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                                   sourceKey:srcKey
		                                                  collection:srcCollection];
		XCTAssertTrue(count == 0, @"Expected=1, Found=%lu", (unsigned long)count);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                              destinationKey:dstKey
		                                                  collection:dstCollection];
		XCTAssertTrue(count == 0, @"Expected=1, Found=%lu", (unsigned long)count);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:edgeName
		                                                   sourceKey:srcKey
		                                                  collection:srcCollection
		                                              destinationKey:dstKey
		                                                  collection:dstCollection];
		XCTAssertTrue(count == 0, @"Expected=1, Found=%lu", (unsigned long)count);
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

- (NSURL *)randomFileURL
{
	NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory
	                                                        inDomain:NSUserDomainMask
	                                               appropriateForURL:nil
	                                                          create:YES
	                                                           error:NULL];
	
	NSString *fileName = [self randomLetters:16];
	NSURL *fileURL = [baseURL URLByAppendingPathComponent:fileName isDirectory:NO];
	
	// Create the temp file
	[[NSFileManager defaultManager] createFileAtPath:[fileURL path] contents:nil attributes:nil];
	
	return fileURL;
}

- (void)testEncryption1_manual
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationshipOptions *options = [[YapDatabaseRelationshipOptions alloc] init];
	options.fileURLSerializer = ^NSData* (YapDatabaseRelationshipEdge *edge){
		
		NSString *dstFilePath = [edge.destinationFileURL path];
		return [dstFilePath dataUsingEncoding:NSUTF8StringEncoding];
	};
	options.fileURLDeserializer = ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *dstBlob){
		
		NSString *dstFilePath = [[NSString alloc] initWithBytes:dstBlob.bytes
		                                                 length:dstBlob.length
		                                               encoding:NSUTF8StringEncoding];
		return [NSURL fileURLWithPath:dstFilePath];
	};
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1" options:options];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *key1 = @"key1";
	NSURL *fileURL1 = [self randomFileURL];
	
	NSString *key2 = @"key2";
	NSURL *fileURL2 = [self randomFileURL];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
		
		YapDatabaseRelationshipEdge *manualEdge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"random"
		                                  sourceKey:key1
		                                 collection:nil
		                         destinationFileURL:fileURL1
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:manualEdge];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// Test creating an edge in a separate transaction from when the nodes are created
		
		YapDatabaseRelationshipEdge *manualEdge =
		  [YapDatabaseRelationshipEdge edgeWithName:@"random"
		                                  sourceKey:key2
		                                 collection:nil
		                         destinationFileURL:fileURL2
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationship"] addEdge:manualEdge];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFileURL
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1      // <- Mismatch
		                                               collection:nil
		                                       destinationFileURL:fileURL2 // <- Mismatch
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0); // Zero because of mismatch
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjectsInAllCollections];
	}];
	
	// Make sure the file still exists (was NOT deleted)
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists1 = [[NSFileManager defaultManager] fileExistsAtPath:[fileURL1 path]];
	XCTAssertTrue(!exists1);
	
	BOOL exists2 = [[NSFileManager defaultManager] fileExistsAtPath:[fileURL2 path]];
	XCTAssertTrue(!exists2);
}

- (void)testEncryption1_protocol
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationshipOptions *options = [[YapDatabaseRelationshipOptions alloc] init];
	options.fileURLSerializer = ^NSData* (YapDatabaseRelationshipEdge *edge){
		
		NSString *dstFilePath = [edge.destinationFileURL path];
		return [dstFilePath dataUsingEncoding:NSUTF8StringEncoding];
	};
	options.fileURLDeserializer = ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *dstBlob){
		
		NSString *dstFilePath = [[NSString alloc] initWithBytes:dstBlob.bytes
		                                                 length:dstBlob.length
		                                               encoding:NSUTF8StringEncoding];
		return [NSURL fileURLWithPath:dstFilePath];
	};
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1" options:options];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	Node_Standard_FileURL *node1 = [[Node_Standard_FileURL alloc] init];
	node1.fileURL = [self randomFileURL];
	NSString *key1 = node1.key;
	NSURL *fileURL1 = node1.fileURL;
	
	Node_Standard_FileURL *node2 = [[Node_Standard_FileURL alloc] init];
	node2.fileURL = [self randomFileURL];
	NSString *key2 = node2.key;
	NSURL *fileURL2 = node2.fileURL;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:node1 forKey:key1 inCollection:nil];
		[transaction setObject:node2 forKey:key2 inCollection:nil];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random" destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1      // <- Mismatch
		                                               collection:nil
		                                       destinationFileURL:fileURL2 // <- Mismatch
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0); // Zero because of mismatch
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:fileURL1];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:fileURL2];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:fileURL1
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:fileURL2
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"random"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"random"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjectsInAllCollections];
	}];
	
	// Make sure the file still exists (was NOT deleted)
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists1 = [[NSFileManager defaultManager] fileExistsAtPath:[fileURL1 path]];
	XCTAssertTrue(!exists1);
	
	BOOL exists2 = [[NSFileManager defaultManager] fileExistsAtPath:[fileURL2 path]];
	XCTAssertTrue(!exists2);
}

- (void)testEncryption2_manual
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationshipOptions *options = [[YapDatabaseRelationshipOptions alloc] init];
	options.fileURLSerializer = ^NSData* (YapDatabaseRelationshipEdge *edge){
		
		NSString *dstFilePath = [edge.destinationFileURL path];
		return [dstFilePath dataUsingEncoding:NSUTF8StringEncoding];
	};
	options.fileURLDeserializer = ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *dstBlob){
		
		NSString *dstFilePath = [[NSString alloc] initWithBytes:dstBlob.bytes
		                                                 length:dstBlob.length
		                                               encoding:NSUTF8StringEncoding];
		return [NSURL fileURLWithPath:dstFilePath];
	};
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1" options:options];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSString *key1 = @"key1";
	NSString *key2 = @"key2";
	
	NSURL *sharedFileURL = [self randomFileURL];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:key1 forKey:key1 inCollection:nil];
		[transaction setObject:key2 forKey:key2 inCollection:nil];
		
		YapDatabaseRelationshipEdge *manualEdge1 =
		  [YapDatabaseRelationshipEdge edgeWithName:@"shared"
		                                  sourceKey:key1
		                                 collection:nil
		                         destinationFileURL:sharedFileURL
		                            nodeDeleteRules:YDB_DeleteDestinationIfAllSourcesDeleted];
		
		YapDatabaseRelationshipEdge *manualEdge2 =
		  [YapDatabaseRelationshipEdge edgeWithName:@"shared"
		                                  sourceKey:key2
		                                 collection:nil
		                         destinationFileURL:sharedFileURL
		                            nodeDeleteRules:YDB_DeleteDestinationIfAllSourcesDeleted];
		
		[[transaction ext:@"relationship"] addEdge:manualEdge1];
		[[transaction ext:@"relationship"] addEdge:manualEdge2];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:key2 inCollection:nil];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
	}];
	
	// Make sure the file still exists (was NOT deleted)
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists1 = [[NSFileManager defaultManager] fileExistsAtPath:[sharedFileURL path]];
	XCTAssertTrue(exists1);
	
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:key1 inCollection:nil];
	}];
	
	// Make sure the file was deleted
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists2 = [[NSFileManager defaultManager] fileExistsAtPath:[sharedFileURL path]];
	XCTAssertTrue(!exists2);
}

- (void)testEncryption2_protocol
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	YapDatabaseRelationshipOptions *options = [[YapDatabaseRelationshipOptions alloc] init];
	options.fileURLSerializer = ^NSData* (YapDatabaseRelationshipEdge *edge){
		
		NSString *dstFilePath = [edge.destinationFileURL path];
		return [dstFilePath dataUsingEncoding:NSUTF8StringEncoding];
	};
	options.fileURLDeserializer = ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *dstBlob){
		
		NSString *dstFilePath = [[NSString alloc] initWithBytes:dstBlob.bytes
		                                                 length:dstBlob.length
		                                               encoding:NSUTF8StringEncoding];
		return [NSURL fileURLWithPath:dstFilePath];
	};
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] initWithVersionTag:@"1" options:options];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	NSURL *sharedFileURL = [self randomFileURL];
	
	Node_RetainCount_FileURL *node1 = [[Node_RetainCount_FileURL alloc] init];
	node1.fileURL = sharedFileURL;
	NSString *key1 = node1.key;
	
	Node_RetainCount_FileURL *node2 = [[Node_RetainCount_FileURL alloc] init];
	node2.fileURL = sharedFileURL;
	NSString *key2 = node2.key;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:node1 forKey:key1 inCollection:nil];
		[transaction setObject:node2 forKey:key2 inCollection:nil];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 2);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 2);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:key2 inCollection:nil];
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
	}];
	
	// Make sure the file still exists (was NOT deleted)
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists1 = [[NSFileManager defaultManager] fileExistsAtPath:[sharedFileURL path]];
	XCTAssertTrue(exists1);
	
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count;
		
		// Query: name
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared" destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		// Query: name & src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src & dstFilePath
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil
		                                          destinationFileURL:sharedFileURL];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                       destinationFileURL:sharedFileURL
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: name & src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:@"shared"
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"shared"
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
		
		// Query: src
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key1
		                                                  collection:nil];
		XCTAssertTrue(count == 1);
		
		count = [[transaction ext:@"relationship"] edgeCountWithName:nil
		                                                   sourceKey:key2
		                                                  collection:nil];
		XCTAssertTrue(count == 0);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key1
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 1);
		
		count = 0;
		[[transaction ext:@"relationship"] enumerateEdgesWithName:nil
		                                                sourceKey:key2
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			count++;
		}];
		XCTAssertTrue(count == 0);
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeObjectForKey:key1 inCollection:nil];
	}];
	
	// Make sure the file was deleted
	
	[NSThread sleepForTimeInterval:1.0];
	
	BOOL exists2 = [[NSFileManager defaultManager] fileExistsAtPath:[sharedFileURL path]];
	XCTAssertTrue(!exists2);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testDoubleEnumeration
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database);
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] init];
	
	BOOL registered = [database registerExtension:relationship withName:@"relationship"];
	
	XCTAssertTrue(registered, @"Error registering extension");
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"Baseball" forKey:@"baseball" inCollection:@"sports"];
		
		[transaction setObject:@"New York Yankees" forKey:@"yankees" inCollection:@"teams"];
		[transaction setObject:@"Boston Red Sox"   forKey:@"redsox" inCollection:@"teams"];
		
		[transaction setObject:@"Mickey Mantle" forKey:@"1" inCollection:@"yankees"];
		[transaction setObject:@"Derek Jeter"   forKey:@"2" inCollection:@"yankees"];
		
		[transaction setObject:@"Ted Williams" forKey:@"1" inCollection:@"redsox"];
		[transaction setObject:@"David Ortiz"  forKey:@"2" inCollection:@"redsox"];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"teams"
		                                  sourceKey:@"baseball"
		                                 collection:@"sports"
		                             destinationKey:@"yankees"
		                                 collection:@"teams"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"teams"
		                                  sourceKey:@"baseball"
		                                 collection:@"sports"
		                             destinationKey:@"redsox"
		                                 collection:@"teams"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"players"
		                                  sourceKey:@"yankees"
		                                 collection:@"teams"
		                             destinationKey:@"1"
		                                 collection:@"yankees"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"players"
		                                  sourceKey:@"yankees"
		                                 collection:@"teams"
		                             destinationKey:@"2"
		                                 collection:@"yankees"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"players"
		                                  sourceKey:@"redsox"
		                                 collection:@"teams"
		                             destinationKey:@"1"
		                                 collection:@"redsox"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
		
		[[transaction ext:@"relationship"] addEdge:
		  [YapDatabaseRelationshipEdge edgeWithName:@"players"
		                                  sourceKey:@"redsox"
		                                 collection:@"teams"
		                             destinationKey:@"2"
		                                 collection:@"redsox"
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted]];
	}];
	
	__block NSUInteger count = 0;
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"teams"
		                                                sourceKey:@"baseball"
		                                               collection:@"sports"
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			[[transaction ext:@"relationship"] enumerateEdgesWithName:@"players"
			                                                sourceKey:edge.destinationKey
			                                               collection:edge.destinationCollection
			                                               usingBlock:^(YapDatabaseRelationshipEdge *_edge, BOOL *_stop)
			{
				count++;
			}];
		}];
	}];
	
	XCTAssert(count == 4);
}

@end
