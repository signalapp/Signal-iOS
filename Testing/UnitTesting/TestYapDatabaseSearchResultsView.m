#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseSearchResultsView.h"
#import "YapCollectionKey.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>


@interface TestYapDatabaseSearchResultsView : XCTestCase
@end

@implementation TestYapDatabaseSearchResultsView

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
#pragma mark Bad Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test_badInit
{
	dispatch_block_t exceptionBlock = ^{
		
		YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
		    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
		{
			if ([key isEqualToString:@"keyX"]) // Exclude keyX from view
				return nil;
			else
				return @"";
		}];
		
		YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
		    ^(YapDatabaseReadTransaction *transaction, NSString *group,
		        NSString *collection1, NSString *key1, id obj1,
		        NSString *collection2, NSString *key2, id obj2)
		{
			__unsafe_unretained NSNumber *number1 = (NSNumber *)obj1;
			__unsafe_unretained NSNumber *number2 = (NSNumber *)obj2;
			
			return [number1 compare:number2];
		}];
		
		(void)[[YapDatabaseSearchResultsView alloc] initWithGrouping:grouping
		                                                     sorting:sorting
		                                                  versionTag:@"xyz"
		                                                     options:nil];
	};
	
	XCTAssertThrows(exceptionBlock(), @"Should have thrown an exception");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark With ParentView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1_parentView_memory_withoutSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = NO;
	
	[self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)test1_parentView_memory_withSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseFullTextSearchSnippetOptions *snippetOptions = [[YapDatabaseFullTextSearchSnippetOptions alloc] init];
	snippetOptions.numberOfTokens = 5;
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = NO;
	searchViewOptions.snippetOptions = snippetOptions;
	
	[self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)test1_parentView_persistent_withoutSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = YES;
	
	[self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)test1_parentView_persistent_withSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseFullTextSearchSnippetOptions *snippetOptions = [[YapDatabaseFullTextSearchSnippetOptions alloc] init];
	snippetOptions.numberOfTokens = 5;
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = YES;
	searchViewOptions.snippetOptions = snippetOptions;
	
	[self _test1_parentView_withPath:databasePath options:searchViewOptions];
}

- (void)_test1_parentView_withPath:(NSString *)databasePath
                           options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	// Setup ParentView
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSString *group,
	        NSString *collection1, NSString *key1, id obj1,
	        NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSString *str1 = (NSString *)obj1;
		__unsafe_unretained NSString *str2 = (NSString *)obj2;
		
		return [str1 compare:str2 options:NSLiteralSearch];
	}];
	
	YapDatabaseViewOptions *viewOptions = [[YapDatabaseViewOptions alloc] init];
	viewOptions.isPersistent = NO;
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting
	                                 versionTag:@"1"
	                                    options:viewOptions];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	// Setup FTS
	
	YapDatabaseFullTextSearchHandler *handler = [YapDatabaseFullTextSearchHandler withObjectBlock:
	    ^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
		
		[dict setObject:object forKey:@"content"];
	}];
	
	YapDatabaseFullTextSearch *fts =
	  [[YapDatabaseFullTextSearch alloc] initWithColumnNames:@[@"content"]
	                                                 handler:handler
	                                              versionTag:@"1"];
	
	BOOL registerResult2 = [database registerExtension:fts withName:@"fts"];
	XCTAssertTrue(registerResult2, @"Failure registering fts extension");
	
	// Setup SearchResultsView
	
	YapDatabaseSearchResultsView *searchResultsView =
	  [[YapDatabaseSearchResultsView alloc] initWithFullTextSearchName:@"fts"
	                                                    parentViewName:@"order"
	                                                        versionTag:@"1"
	                                                      options:searchViewOptions];
	
	BOOL registerResult3 = [database registerExtension:searchResultsView withName:@"searchResults"];
	XCTAssertTrue(registerResult3, @"Failure registering searchResults extension");
	
	[self _testWithDatabase:database options:searchViewOptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark With Blocks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)test1_blocks_memory_withoutSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = NO;
	
	[self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)test1_blocks_memory_withSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseFullTextSearchSnippetOptions *snippetOptions = [[YapDatabaseFullTextSearchSnippetOptions alloc] init];
	snippetOptions.numberOfTokens = 5;
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = NO;
	searchViewOptions.snippetOptions = snippetOptions;
	
	[self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)test1_blocks_persistent_withoutSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = YES;
	
	[self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)test1_blocks_persistent_withSnippets
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseFullTextSearchSnippetOptions *snippetOptions = [[YapDatabaseFullTextSearchSnippetOptions alloc] init];
	snippetOptions.numberOfTokens = 5;
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = YES;
	searchViewOptions.snippetOptions = snippetOptions;
	
	[self _test1_blocks_withPath:databasePath options:searchViewOptions];
}

- (void)_test1_blocks_withPath:(NSString *)databasePath
                       options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	XCTAssertNotNil(database, @"Oops");
	
	// Setup FTS
	
	YapDatabaseFullTextSearchHandler *handler = [YapDatabaseFullTextSearchHandler withObjectBlock:
	    ^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
		
		[dict setObject:object forKey:@"content"];
	}];
	
	YapDatabaseFullTextSearch *fts =
	  [[YapDatabaseFullTextSearch alloc] initWithColumnNames:@[@"content"]
	                                                 handler:handler
	                                              versionTag:@"1"];
	
	BOOL registerResult1 = [database registerExtension:fts withName:@"fts"];
	XCTAssertTrue(registerResult1, @"Failure registering fts extension");
	
	// Setup SearchResultsView
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
		return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSString *group,
	        NSString *collection1, NSString *key1, id obj1,
	        NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSString *str1 = (NSString *)obj1;
		__unsafe_unretained NSString *str2 = (NSString *)obj2;
		
		return [str1 compare:str2 options:NSLiteralSearch];
	}];
	
	YapDatabaseSearchResultsView *searchResultsView =
	  [[YapDatabaseSearchResultsView alloc] initWithFullTextSearchName:@"fts"
	                                                          grouping:grouping
	                                                           sorting:sorting
	                                                        versionTag:@"1"
	                                                           options:searchViewOptions];
	
	BOOL registerResult2 = [database registerExtension:searchResultsView withName:@"searchResults"];
	XCTAssertTrue(registerResult2, @"Failure registering searchResults extension");
	
	[self _testWithDatabase:database options:searchViewOptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Test Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_testWithDatabase:(YapDatabase *)database options:(YapDatabaseSearchResultsViewOptions *)searchViewOptions
{
	// Add a bunch of values to the database
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	connection1.name = @"connection1";
	connection2.name = @"connection2";
	
	NSDictionary *originalPhrases = @{
	  @"0": @"The duck quacks at midnight",
	  @"1": @"You take the red pill, you stay in Wonderland, and I show you how deep the rabbit hole goes.",
	  @"2": @"I am a fire gasoline. Come pour yourself all over me.",
	  @"3": @"I am enjoying my coffee.",
	  @"4": @"Are you gonna stay the night?",
	  @"5": @"What it is hoe? What's up?",
	  @"6": @"If Jimmy cracks corn and no one cares, then why does he keep doing it?"
	};
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[originalPhrases enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *phrase, BOOL *stop) {
			
			[transaction setObject:phrase forKey:key inCollection:nil];
		}];
		
	//	[[transaction ext:@"order"] enumerateKeysAndObjectsInGroup:@""
	//	                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"Normal view: %lu : %@", (unsigned long)index, object);
	//	}];
		
	//	[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
	//	                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
	//	}];
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 0, @"Bad count: %lu", (unsigned long)count);
	}];

	NSString *query = nil;
	NSUInteger expectedQueryResults = 0;
	
	NSMutableDictionary *snippets = [NSMutableDictionary dictionary];
	
	// Perform a query on an existing data set.
	
	query = @"the";
	expectedQueryResults = 3;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"searchResults"] performSearchFor:query];
		
		[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
		                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
		//	NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
			
			if (searchViewOptions.snippetOptions)
			{
				NSString *snippet = [[transaction ext:@"searchResults"] snippetForKey:key inCollection:collection];
			//	NSLog(@"    snippet: %lu : %@", (unsigned long)index, snippet);
				
				XCTAssertNotNil(snippet, @"Expected a snippet");
				
				YapCollectionKey *ck = YapCollectionKeyCreate(collection, key);
				snippets[ck] = snippet;
			}
		}];
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];

	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];
	
	// Perform another query, and make sure the snippets change
	
	query = @"the you";
	expectedQueryResults = 2;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"searchResults"] performSearchFor:query];
		
		[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
		                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
		//	NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
			
			if (searchViewOptions.snippetOptions)
			{
				NSString *snippet = [[transaction ext:@"searchResults"] snippetForKey:key inCollection:collection];
			//	NSLog(@"    snippet: %lu : %@", (unsigned long)index, snippet);
				
				XCTAssertNotNil(snippet, @"Expected a snippet");
				
				YapCollectionKey *ck = YapCollectionKeyCreate(collection, key);
				NSString *prevSnippet = snippets[ck];
				
				XCTAssertTrue(![snippet isEqualToString:prevSnippet], @"Expected a diff snippet vs last time");
				snippets[ck] = snippet;
			}
		}];
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];
	
	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
	}];
	
	// Add some items to the database that match the query,
	// and make sure they show up in the search results.
	
	NSDictionary *morePhrases = @{
	  @"7": @"The more you know...",
	  @"8": @"All I wanna do is take you downtown baby.",
	};
	
//	query = @"the you";
	expectedQueryResults = 3;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[morePhrases enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *phrase, BOOL *stop) {
			
			[transaction setObject:phrase forKey:key inCollection:nil];
		}];
		
	//	[[transaction ext:@"order"] enumerateKeysAndObjectsInGroup:@""
	//	                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"Normal view: %lu : %@", (unsigned long)index, object);
	//	}];
		
	//	[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
	//	                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
	//	{
	//		NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
	//	}];
		
		NSUInteger count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == expectedQueryResults, @"Bad count: %lu", (unsigned long)count);
		
		[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
		                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
		//	NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
			
			if (searchViewOptions.snippetOptions)
			{
				NSString *snippet = [[transaction ext:@"searchResults"] snippetForKey:key inCollection:collection];
			//	NSLog(@"    snippet: %lu : %@", (unsigned long)index, snippet);
				
				XCTAssertNotNil(snippet, @"Expected a snippet");
				
			//	YapCollectionKey *ck = YapCollectionKeyCreate(collection, key);
			//	snippets[ck] = snippet;
			}
		}];
	}];
}

@end
