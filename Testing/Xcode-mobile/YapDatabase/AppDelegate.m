#import "AppDelegate.h"
#import "ViewController.h"

#import "YapDatabase.h"
#import "YapDatabaseView.h"

#import "DDLog.h"
#import "DDTTYLogger.h"
#import "YapDatabaseLogging.h"


@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *databaseConnection;
}

- (BOOL)application:(UIApplication __unused *)application didFinishLaunchingWithOptions:(NSDictionary __unused *)launchOptions
{
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	[[DDTTYLogger sharedInstance] setColorsEnabled:YES];
	
#if YapDatabaseLoggingTechnique == YapDatabaseLoggingTechnique_Lumberjack
	[[DDTTYLogger sharedInstance] setForegroundColor:[UIColor grayColor]
	                                 backgroundColor:nil
	                                         forFlag:YDB_LOG_FLAG_TRACE
	                                         context:YDBLogContext];
#endif
	
	double delayInSeconds = 2.0;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
	//	[self debug];
	//	[self debugOnTheFlyViews];
	});
	
	// Normal UI stuff
	
	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
		self.viewController = [[ViewController alloc] initWithNibName:@"ViewController_iPhone" bundle:nil];
	} else {
		self.viewController = [[ViewController alloc] initWithNibName:@"ViewController_iPad" bundle:nil];
	}
	self.window.rootViewController = self.viewController;
	[self.window makeKeyAndVisible];
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"database-%@.sqlite", suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
	NSLog(@"YapDatabaseModified: %@", notification);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		uint32_t randomIndex = arc4random_uniform((uint32_t)alphabetLength);
		unichar c = [alphabet characterAtIndex:(NSUInteger)randomIndex];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

static const NSUInteger COUNT = 2500;
static const NSUInteger STR_LENGTH = 2000;

- (void)asyncFillDatabase:(YapDatabaseConnection *)connection after:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
	
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 0; i < COUNT; i++)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				[transaction setObject:[self randomLetters:STR_LENGTH] forKey:key inCollection:nil];
			}
		}];
	});
}

- (void)asyncFillOddIndexes:(YapDatabaseConnection *)connection after:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 1; i < COUNT; i += 2)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				[transaction setObject:[self randomLetters:STR_LENGTH] forKey:key inCollection:nil];
			}
		}];
	});
}

- (void)asyncFillEvenIndexes:(YapDatabaseConnection *)connection after:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 0; i < COUNT; i += 2)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				[transaction setObject:[self randomLetters:STR_LENGTH] forKey:key inCollection:nil];
			}
		}];
	});
}

- (void)asyncDeleteOddIndexes:(YapDatabaseConnection *)connection after:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 1; i < COUNT; i+=2)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				[transaction removeObjectForKey:key inCollection:nil];
			}
		}];
	});
}

- (void)asyncDeleteEvenIndexes:(YapDatabaseConnection *)connection after:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 0; i < COUNT; i+=2)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				[transaction removeObjectForKey:key inCollection:nil];
			}
		}];
	});
}

- (void)asyncVacuumAfter:(const NSTimeInterval)delayInSeconds
{
	dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
	
		[[database newConnection] asyncVacuumWithCompletionBlock:NULL];
	});
}

- (void)debug
{
	NSLog(@"Starting debug...");
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	NSLog(@"databasePath: %@", databasePath);
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:nil];
	
	database = [[YapDatabase alloc] initWithPath:databasePath];
	databaseConnection = [database newConnection];
	
	// Fill up the database with stuff
	
	dispatch_time_t when;
	
	NSTimeInterval after = 0.5;
	
	[self asyncFillDatabase:databaseConnection after:after];      after += 1.5;
	
	[self asyncDeleteEvenIndexes:databaseConnection after:after]; after += 1.5;
	[self asyncFillEvenIndexes:databaseConnection after:after];   after += 1.5;
	
	[self asyncDeleteOddIndexes:databaseConnection after:after];  after += 1.5;
	[self asyncFillOddIndexes:databaseConnection after:after];    after += 1.5;
	
	[self asyncFillEvenIndexes:databaseConnection after:after];   after += 1.5;
	[self asyncFillOddIndexes:databaseConnection after:after];    after += 1.5;
	
	[self asyncDeleteEvenIndexes:databaseConnection after:after]; after += 1.5;
	[self asyncFillEvenIndexes:databaseConnection after:after];   after += 1.5;
	
	[self asyncDeleteOddIndexes:databaseConnection after:after];  after += 1.5;
	[self asyncFillOddIndexes:databaseConnection after:after];    after += 1.5;
	
	[self asyncFillEvenIndexes:databaseConnection after:after];   after += 1.5;
	[self asyncFillOddIndexes:databaseConnection after:after];    after += 1.5;
	
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			NSLog(@"Preparing to sleep read transaction...");
			[NSThread sleepForTimeInterval:0.25];
			
			NSLog(@"Fetching items...");
			
			for (unsigned int i = 0; i < COUNT; i++)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				(void)[transaction objectForKey:key inCollection:nil];
			}
			
			NSLog(@"Preparing to sleep read transaction...");
			[NSThread sleepForTimeInterval:2.0];
			
			NSLog(@"Fetching more items...");
			
			for (unsigned int i = 0; i < COUNT; i++)
			{
				NSString *key = [NSString stringWithFormat:@"%d", i];
				
				(void)[transaction objectForKey:key inCollection:nil];
			}
			
			NSLog(@"Read transaction complete");
		}];
	});
	
	[self asyncVacuumAfter:after];
	
	after += 4.0;
	
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after * NSEC_PER_SEC));
	dispatch_after(when, dispatch_get_main_queue(), ^{
		
		[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			[transaction setObject:@"quack" forKey:@"quack" inCollection:@"animals"];
		}];
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark On-The-Fly Extensions Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)debugOnTheFlyViews
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
//	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	database = [[YapDatabase alloc] initWithPath:databasePath];
	databaseConnection = [database newConnection];
	
	[self printDatabaseCount];
	
	[self registerMainView];
	[self printMainViewCount];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSUInteger count = 5;
		NSLog(@"Adding %lu items...", (unsigned long)count);
		
		for (NSUInteger i = 0; i < count; i++)
		{
			NSString *key = [[NSUUID UUID] UUIDString];
			NSString *obj = [[NSUUID UUID] UUIDString];
			
			[transaction setObject:obj forKey:key inCollection:nil];
		}
	}];
	
	[self printDatabaseCount];
	[self printMainViewCount];
	
	[self registerOnTheFlyView];
	
	[self printOnTheFlyViewCount];
}

- (void)registerMainView
{
	NSLog(@"Registering mainView....");

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(NSString __unused *collection, NSString __unused *key, id __unused object){
		
		return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(NSString __unused *group, NSString __unused *collection1, NSString __unused *key1, id obj1,
	                       NSString __unused *collection2, NSString __unused *key2, id obj2){
		
		return [obj1 compare:obj2];
	}];

	YapDatabaseView *databaseView =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting];
	
	if ([database registerExtension:databaseView withName:@"main"])
		NSLog(@"Registered mainView");
	else
		NSLog(@"ERROR registering mainView !");
}

- (void)registerOnTheFlyView
{
	NSLog(@"Registering onTheFlyView....");

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(NSString __unused *collection, NSString __unused *key, id __unused object){
		
		return @"";
	}];

	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(NSString __unused *group, NSString __unused *collection, NSString __unused *key1, id obj1,
	                       NSString __unused *collection2, NSString __unused *key2, id obj2){
		
		return [obj1 compare:obj2];
	}];

	YapDatabaseView *databaseView =
	  [[YapDatabaseView alloc] initWithGrouping:grouping
	                                    sorting:sorting];
	
	if ([database registerExtension:databaseView withName:@"on-the-fly"])
		NSLog(@"Registered onTheFlyView");
	else
		NSLog(@"ERROR registering onTheFlyView !");
}

- (void)printDatabaseCount
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [transaction numberOfKeysInCollection:nil];
		
		NSLog(@"database.count = %lu", (unsigned long)count);
	}];
}

- (void)printMainViewCount
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"main"] numberOfItemsInGroup:@""];
		
		NSLog(@"mainView.count = %lu", (unsigned long)count);
	}];
}

- (void)printOnTheFlyViewCount
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"on-the-fly"] numberOfItemsInGroup:@""];
		
		NSLog(@"onTheFlyView.count = %lu", (unsigned long)count);
	}];
}

@end
