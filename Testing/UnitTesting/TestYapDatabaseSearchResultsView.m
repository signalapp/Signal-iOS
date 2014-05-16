#import <XCTest/XCTest.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseSearchResultsView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"


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
	
	YapDatabaseViewBlockType groupingBlockType;
	YapDatabaseViewGroupingWithKeyBlock groupingBlock;
	
	YapDatabaseViewBlockType sortingBlockType;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlockType = YapDatabaseViewBlockTypeWithKey;
	groupingBlock = ^NSString *(NSString *collection, NSString *key)
	{
		return @"";
	};
	
	sortingBlockType = YapDatabaseViewBlockTypeWithObject;
	sortingBlock = ^(NSString *group, NSString *collection1, NSString *key1, id obj1,
	                                  NSString *collection2, NSString *key2, id obj2)
	{
		__unsafe_unretained NSString *str1 = (NSString *)obj1;
		__unsafe_unretained NSString *str2 = (NSString *)obj2;
		
		return [str1 compare:str2 options:NSLiteralSearch];
	};
	
	YapDatabaseViewOptions *viewOptions = [[YapDatabaseViewOptions alloc] init];
	viewOptions.isPersistent = NO;
	
	YapDatabaseView *view =
	  [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                               groupingBlockType:groupingBlockType
	                                    sortingBlock:sortingBlock
	                                sortingBlockType:sortingBlockType
	                                      versionTag:@"1"
	                                         options:viewOptions];
	
	BOOL registerResult1 = [database registerExtension:view withName:@"order"];
	XCTAssertTrue(registerResult1, @"Failure registering view extension");
	
	// Setup FTS
	
	YapDatabaseFullTextSearchBlockType blockType = YapDatabaseFullTextSearchBlockTypeWithObject;
	YapDatabaseFullTextSearchWithObjectBlock block =
	^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object){
		
		[dict setObject:object forKey:@"content"];
	};
	
	YapDatabaseFullTextSearch *fts =
	  [[YapDatabaseFullTextSearch alloc] initWithColumnNames:@[@"content"]
	                                                   block:block
	                                               blockType:blockType
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
	
	// Add a bunch of values to the database
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	connection1.name = @"connection1";
	connection2.name = @"connection2";
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSArray *phrases = @[
		  @"The duck quacks at midnight",
		  @"You take the red pill, you stay in Wonderland, and I show you how deep the rabbit hole goes.",
		  @"I am a fire gasoline. Come pour yourself all over me.",
		  @"I am enjoying my coffee.",
		  @"Are you gonna stay the night?",
		  @"What it is hoe? What's up?",
		  @"If Jimmy cracks corn and no one cares, then why does he keep doing it?"
		];
		
		NSUInteger i = 0;
		for (NSString *phrase in phrases)
		{
			NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)i];
			
			[transaction setObject:phrase forKey:key inCollection:nil];
			i++;
		}
		
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
		
		NSUInteger count = 0;
		
		count = [[transaction ext:@"order"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 7, @"Bad count: %lu", (unsigned long)count);
		
		count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 0, @"Bad count: %lu", (unsigned long)count);
	}];

	NSString *query = @"the";
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"searchResults"] performSearchFor:query];
		
		[[transaction ext:@"searchResults"] enumerateKeysAndObjectsInGroup:@""
		                    usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop)
		{
		//	NSLog(@"Search view: %lu : %@", (unsigned long)index, object);
			
			if (searchViewOptions.snippetOptions)
			{
				NSString *snippet = [[transaction ext:@"searchResults"] snippetForKey:key inCollection:collection];
		//		NSLog(@"    snippet: %lu : %@", (unsigned long)index, snippet);
				
				XCTAssertNotNil(snippet, @"Expected a snippet");
			}
		}];
		
		NSUInteger count = 0;
		
		count = [[transaction ext:@"searchResults"] numberOfItemsInGroup:@""];
		XCTAssertTrue(count == 3, @"Bad count: %lu", (unsigned long)count);
	}];

	[connection1 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
	}];
	
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSString *connectionQuery = [[transaction ext:@"searchResults"] query];
		XCTAssertTrue([connectionQuery isEqualToString:query], @"Oops");
	}];
}

@end
