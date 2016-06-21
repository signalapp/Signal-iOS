#import "AppDelegate.h"
#import "Person.h"
#import "ViewController.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

// Per-file log level for CocoaLumbejack (logging framework)
#if DEBUG
  static const int ddLogLevel = DDLogLevelVerbose;
#else
  static const int ddLogLevel = DDLogLevelWarn;
#endif

NSString *ManualView_RegisteredName = @"order";
NSString *ManualView_GroupName      = @"";

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
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (ViewController *)viewController
{
	UIViewController *rootViewController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
	
	if ([rootViewController isKindOfClass:[ViewController class]])
		return (ViewController *)rootViewController;
	else
		return nil;
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
	
	// Delete the previous database on next launch (force create new database)
//	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	// Create the database.
	// We do this using the default settings.
	// If you want to get fancy, you can do things like customize the serialization/deserialization routines.
	
	DDLogVerbose(@"Creating database instance...");
	database = [[YapDatabase alloc] initWithPath:databasePath];
	
	// Create the manual view.
	// This is a database extension that will store the order of our objects, according to how the user sorts them.
	//
	// For more information on views, see the wiki article:
	// https://github.com/yaptv/YapDatabase/wiki/Views
	
	DDLogVerbose(@"Creating view...");

	YapDatabaseManualView *view = [[YapDatabaseManualView alloc] init];
	
	if (![database registerExtension:view withName:ManualView_RegisteredName])
	{
		DDLogError(@"Unable to register extension: order");
	}
}

- (void)asyncPopulateDatabaseIfNeeded
{
	YapDatabaseConnection *databaseConnection = [database newConnection];
	
	// Note:
	//
	// This code could be written to be more efficient.
	// But that's not the goal here. The goal is simplicity & readability (skimability even).
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ @autoreleasepool {
		
		__block NSUInteger count = 0;
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			count = [transaction numberOfKeysInAllCollections];
		}];
		
		if (count == 0)
		{
			// Need to populate the database with the list of sample names
			
			DDLogVerbose(@"Loading sample names from JSON file...");
			
			NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"names" ofType:@"json"];
			
			NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:jsonPath];
			[inputStream open];
			
			NSArray *people = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:nil];
			
			[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				DDLogVerbose(@"Adding sample items to database...");
				
				[people enumerateObjectsUsingBlock:^(NSDictionary *info, NSUInteger idx, BOOL *stop) {
					
					NSString *name = info[@"name"];
					NSString *uuid = info[@"udid"];
					
					Person *person = [[Person alloc] initWithName:name uuid:uuid];
					
					[transaction setObject:person forKey:person.uuid inCollection:@"people"];
				}];
				
				DDLogVerbose(@"Committing transaction...");
			}];
		}
		
		// Figure out what keys are in the database, and which are already in our manual view.
		// We're going to pass this information to the ViewController.
		
		__block NSMutableSet<NSString *> *allKeys = nil;
		__block NSMutableSet<NSString *> *viewKeys = nil;
		
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			NSUInteger count;
			
			// Populate 'allKeys'
			
			count = [transaction numberOfKeysInCollection:@"people"];
			allKeys = [NSMutableSet setWithCapacity:count];
			
			[transaction enumerateKeysInCollection:@"people" usingBlock:^(NSString *key, BOOL *stop) {
				
				[allKeys addObject:key];
			}];
			
			// Populate 'viewKeys'
			
			count = [[transaction ext:ManualView_RegisteredName] numberOfItemsInGroup:ManualView_GroupName];
			viewKeys = [NSMutableSet setWithCapacity:count];
			
			[[transaction ext:ManualView_RegisteredName] enumerateKeysInGroup:ManualView_GroupName usingBlock:
				^(NSString *collection, NSString *key, NSUInteger index, BOOL *stop)
			{
				[viewKeys addObject:key];
			}];
		}];
		
		// Calculate the remainingKeys (that can be added to the manualView)
		
		NSArray<NSString *> *remainingKeys = nil;
		
		[allKeys minusSet:viewKeys];
		remainingKeys = [allKeys allObjects];
		
		
		dispatch_async(dispatch_get_main_queue(), ^{
			
			[[self viewController] setRemainingKeys:remainingKeys];
		});
	}});
}

@end
