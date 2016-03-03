#import "AppDelegate.h"
#import "Person.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

// Per-file log level for CocoaLumbejack (logging framework)
#if DEBUG
  static const int ddLogLevel = DDLogLevelVerbose;
#else
  static const int ddLogLevel = DDLogLevelWarn;
#endif

AppDelegate *TheAppDelegate;

@implementation AppDelegate

@synthesize database = database;

- (id)init
{
    if ((self = [super init]))
	{
		TheAppDelegate = self;
    }
	return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	// Configure the logging framework.
	//
	// We're using CocoaLumberjack, which is a professional logging framework.
	// If you've never heard of it, you can find a ton of information from its project page:
	// https://github.com/CocoaLumberjack/CocoaLumberjack
	//
	// YapDatabase has a fully configurable logging stack built in.
	// You can configure it to use CocoaLumberjack, or NSLog, or just disable it.
	//
	// For these examples, we're going to be using CocoaLumberjack. 'Cause it's awesome.
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	// Setup the database, and all extensions
	[self setupDatabase];
	
	// Fill the database with our sample names (if needed)
	[self asyncPopulateDatabaseIfNeeded];
	
    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
	
	NSString *databaseName = @"database.sqlite";
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)setupDatabase
{
	NSString *databasePath = [self databasePath];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	// Create the database.
	// We do this using the default settings.
	// If you want to get fancy, you can do things like customize the serialization/deserialization routines.
	
	DDLogVerbose(@"Creating database instance...");
	database = [[YapDatabase alloc] initWithPath:databasePath];
	
	// Create the main view.
	// This is a database extension that will sort our objects in the manner in which we want them.
	//
	// For more information on views, see the wiki article:
	// https://github.com/yaptv/YapDatabase/wiki/Views
	
	DDLogVerbose(@"Creating view...");

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withKeyBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key)
	{
        // The grouping block is used to:
        // - filter items that we don't want in the view
        // - place items into specific groups (which can be used as sections in a tableView, for example)
        //
        // In this example, we're only storing one kind of object into the database: Person objects.
        // And we want to display them all in the same section.

        return @"all";
    }];

	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^NSComparisonResult(YapDatabaseReadTransaction *transaction, NSString *group,
	                        NSString *collection1, NSString *key1, id object1,
	                        NSString *collection2, NSString *key2, id object2)
	{
		// The sorting block is used to sort items within their group/section.

        __unsafe_unretained Person *person1 = (Person *)object1;
        __unsafe_unretained Person *person2 = (Person *)object2;

        return [person1.name compare:person2.name options:NSLiteralSearch];
    }];

	YapDatabaseView *view = [[YapDatabaseView alloc] initWithGrouping:grouping
                                                              sorting:sorting
                                                           versionTag:@"1"
                                                              options:nil];
	
	if (![database registerExtension:view withName:@"order"])
	{
		DDLogError(@"Unable to register extension: order");
	}
	
	// Create the Full Text Search (FTS) index.
	// This is a database extension that allows us to perform extremely fast text based searches.
	//
	// The FTS extension is built atop the FTS module within sqlite (which was originally written by Google).
	//
	// For more information on views, see the wiki article:
	// https://github.com/yaptv/YapDatabase/wiki/Full-Text-Search
	
	DDLogVerbose(@"Creating fts...");

    YapDatabaseFullTextSearchHandler *handler = [YapDatabaseFullTextSearchHandler withObjectBlock:^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object) {
        __unsafe_unretained Person *person = (Person *)object;
        dict[@"name"] = person.name;
    }];

	YapDatabaseFullTextSearch *fts = [[YapDatabaseFullTextSearch alloc] initWithColumnNames:@[ @"name" ] handler:handler versionTag:@"1"];

	
	if (![database registerExtension:fts withName:@"fts"])
	{
		DDLogError(@"Unable to register extension: fts");
	}
	
	// Create the search view.
	// This extension allows you to use an existing FTS extension, perform searches on it,
	// and then pipe the search results into a regular view.
	//
	// There are a couple ways we can set this up:
	// - Use the FTS module to search an existing view
	// - Just use the FTS module, and provide a groupingBlock/sortingBlock to order the results
	//
	// In our case, we want to use the FTS module in order to search the main view.
	// So we're going to setup the search view accordingly.
	
	YapDatabaseSearchResultsViewOptions *searchViewOptions = [[YapDatabaseSearchResultsViewOptions alloc] init];
	searchViewOptions.isPersistent = NO;
	
	YapDatabaseSearchResultsView *searchResultsView = [[YapDatabaseSearchResultsView alloc] initWithFullTextSearchName:@"fts"
	                                                    parentViewName:@"order"
	                                                        versionTag:@"1"
	                                                      options:searchViewOptions];
	
	if (![database registerExtension:searchResultsView withName:@"searchResults"])
	{
		DDLogError(@"Unable to register extension: searchResults");
	}
}

- (void)asyncPopulateDatabaseIfNeeded
{
	[[database newConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSUInteger count = [transaction numberOfKeysInAllCollections];
		if (count > 0)
		{
			// Looks like the database is already populated.
			return; // from block
		}
		
		DDLogVerbose(@"Loading sample names from JSON file...");
		
		NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"names" ofType:@"json"];
		
		NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:jsonPath];
		[inputStream open];
		
		NSArray *people = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:nil];
		
		DDLogVerbose(@"Adding sample items to database...");
		
		// Bump the objectCacheLimit for a little performance boost.
		// https://github.com/yaptv/YapDatabase/wiki/Performance-Pro
		NSUInteger originalObjectCacheLimit = transaction.connection.objectCacheLimit;
		transaction.connection.objectCacheLimit = [people count];
		
		[people enumerateObjectsUsingBlock:^(NSDictionary *info, NSUInteger idx, BOOL *stop) {
            
			NSString *name = info[@"name"];
			NSString *uuid = info[@"udid"];
			
			Person *person = [[Person alloc] initWithName:name uuid:uuid];
			
			[transaction setObject:person forKey:person.uuid inCollection:@"people"];
		}];
		
		transaction.connection.objectCacheLimit = originalObjectCacheLimit;
		
		DDLogVerbose(@"Committing transaction...");
	}];
}

@end
