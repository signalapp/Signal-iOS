#import "AppDelegate.h"
#import "ViewController.h"

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseView.h>

#import <CocoaLumberjack/CocoaLumberjack.h>
#import "YapDatabaseLogging.h"


static int ddLogLevel = DDLogLevelWarning;
#pragma unused(ddLogLevel)


@implementation AppDelegate

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
	
	double delayInSeconds;
	dispatch_time_t popTime;
	
	delayInSeconds = 2.0;
	popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
	//	[self confirmCheckpointUnderstanding];
	//	[self testPragmaPageSize];
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

- (NSURL *)appSupportFolderURL
{
    static NSURL *appSupportFolderURL = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        NSError *error = nil;
        NSURL *url = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:YES
                                                               error:&error];
        if (!error)
		{
		#if !TARGET_OS_IPHONE
		
			url = [url URLByAppendingPathComponent:@"YapDatabaseTesting"];
			
		#endif
			
			[[NSFileManager defaultManager] createDirectoryAtURL:url
			                         withIntermediateDirectories:YES
			                                          attributes:nil
			                                               error:&error];
		}
		
		appSupportFolderURL = url;
	});
	
	return appSupportFolderURL;
}

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"database-%@.sqlite", suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Testing Checkpoint Algorithm
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)confirmCheckpointUnderstanding
{
	NSLog(@"%@", NSStringFromSelector(_cmd));
	
	// Goal:
	//
	// - observe the behavior of the WAL file size
	// - ensure it shrinks, according to our understanding of the sqlite documentation
	//
	// Instructions:
	//
	// - enable VERBOSE logging in YapDatabase.m
	// - enable YDB_PRINT_WAL_SIZE in YapDatabase.m
	//
	// This will result in the logging system printing out the file size of the WAL,
	// along with checkpoint operation information.
	
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	NSLog(@"databasePath: %@", databasePath);
	
	NSString *databaseWalPath = [databasePath stringByAppendingString:@"-wal"];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:databaseWalPath error:nil];
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), bgQueue, ^{
		
		YapDatabaseConnection *databaseConnection1 = [database newConnection];
		YapDatabaseConnection *databaseConnection2 = [database newConnection];
		YapDatabaseConnection *databaseConnection3 = [database newConnection];
		
		// Put databaseConnection1 on commit #0
		[databaseConnection1 beginLongLivedReadTransaction];
		
		// Write commit #1 to the WAL
		[databaseConnection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			for (unsigned int i = 0; i < 200; i++)
			{
				NSString *str = [self randomLetters:200];
				
				[transaction setObject:str forKey:str inCollection:str];
			}
		}];
		
		// Put databaseConnection3 on commit #1 for a little bit
		[databaseConnection3 beginLongLivedReadTransaction];
		[databaseConnection3 asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			[NSThread sleepForTimeInterval:5.0];
			
		} completionBlock:^{
			
			NSLog(@"[databaseConnection3 endLongLivedReadTransaction]");
			[databaseConnection3 endLongLivedReadTransaction];
		}];
		
		// End the read-only transaction on databaseConnection1.
		// This will result in a checkpoint operation, which should checkpoint commit #1
		[databaseConnection1 endLongLivedReadTransaction];
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), bgQueue, ^{
			
			NSLog(@"========== Post checkpoint read-write transaction ==========");
			
			// This write should reset the WAL.
			// So the size should drop from ~334 KB down to ~66 KB.
			
			[databaseConnection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				for (unsigned int i = 0; i < 10; i++)
				{
					NSString *str = [self randomLetters:10];
					
					[transaction setObject:str forKey:str inCollection:str];
				}
			}];
		});
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Test PRAGMA page_size
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)testPragmaPageSize
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
	options.pragmaPageSize = 8192;
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath
	serializer:NULL
												 deserializer:NULL
													  options:options];
	
	NSLog(@"database.sqliteVersion = %@", database.sqliteVersion);
	NSLog(@"database.sqlitePageSize = %ld", (long)[[database newConnection] pragmaPageSize]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Test VACUUM
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static const NSUInteger COUNT = 2500;
static const NSUInteger STR_LENGTH = 2000;

- (void)asyncFillDatabase:(YapDatabaseConnection *)connection afterDelay:(const NSTimeInterval)delayInSeconds
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

- (void)asyncFillOddIndexes:(YapDatabaseConnection *)connection afterDelay:(const NSTimeInterval)delayInSeconds
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

- (void)asyncFillEvenIndexes:(YapDatabaseConnection *)connection afterDelay:(const NSTimeInterval)delayInSeconds
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

- (void)asyncDeleteOddIndexes:(YapDatabaseConnection *)connection afterDelay:(const NSTimeInterval)delayInSeconds
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

- (void)asyncDeleteEvenIndexes:(YapDatabaseConnection *)connection afterDelay:(const NSTimeInterval)delayInSeconds
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

- (void)asyncVacuumDatabase:(YapDatabase *)database afterDelay:(const NSTimeInterval)delayInSeconds
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
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	YapDatabaseConnection *databaseConnection = [database newConnection];
	
	// Fill up the database with stuff
	
	dispatch_time_t when;
	
	NSTimeInterval delay = 0.5;
	
	[self asyncFillDatabase:databaseConnection afterDelay:delay];      delay += 1.5;
	
	[self asyncDeleteEvenIndexes:databaseConnection afterDelay:delay]; delay += 1.5;
	[self asyncFillEvenIndexes:databaseConnection afterDelay:delay];   delay += 1.5;
	
	[self asyncDeleteOddIndexes:databaseConnection afterDelay:delay];  delay += 1.5;
	[self asyncFillOddIndexes:databaseConnection afterDelay:delay];    delay += 1.5;
	
	[self asyncFillEvenIndexes:databaseConnection afterDelay:delay];   delay += 1.5;
	[self asyncFillOddIndexes:databaseConnection afterDelay:delay];    delay += 1.5;
	
	[self asyncDeleteEvenIndexes:databaseConnection afterDelay:delay]; delay += 1.5;
	[self asyncFillEvenIndexes:databaseConnection afterDelay:delay];   delay += 1.5;
	
	[self asyncDeleteOddIndexes:databaseConnection afterDelay:delay];  delay += 1.5;
	[self asyncFillOddIndexes:databaseConnection afterDelay:delay];    delay += 1.5;
	
	[self asyncFillEvenIndexes:databaseConnection afterDelay:delay];   delay += 1.5;
	[self asyncFillOddIndexes:databaseConnection afterDelay:delay];    delay += 1.5;
	
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
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
	
	[self asyncVacuumDatabase:database afterDelay:delay];
	
	delay += 4.0;
	
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
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
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	YapDatabaseConnection *databaseConnection = [database newConnection];
	
	[self printDatabaseCount:databaseConnection];
	
	[self registerMainView:database];
	[self printMainViewCount:databaseConnection];
	
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
	
	[self printDatabaseCount:databaseConnection];
	[self printMainViewCount:databaseConnection];
	
	[self registerOnTheFlyView:database];
	
	[self printOnTheFlyViewCount:databaseConnection];
}

- (void)registerMainView:(YapDatabase *)database
{
	NSLog(@"Registering mainView....");

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction __unused *transaction,
	                NSString __unused *collection, NSString __unused *key, id __unused object)
	{
		return @"";
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction __unused *transaction, NSString __unused *group,
	      NSString __unused *collection1, NSString __unused *key1, id obj1,
	      NSString __unused *collection2, NSString __unused *key2, id obj2)
	{
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

- (void)registerOnTheFlyView:(YapDatabase *)database
{
	NSLog(@"Registering onTheFlyView....");

	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction __unused *transaction,
	                NSString __unused *collection, NSString __unused *key, id __unused object)
	{
		return @"";
	}];

	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction __unused *transaction, NSString __unused *group,
	      NSString __unused *collection, NSString __unused *key1, id obj1,
	      NSString __unused *collection2, NSString __unused *key2, id obj2)
	{
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

- (void)printDatabaseCount:(YapDatabaseConnection *)databaseConnection
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [transaction numberOfKeysInCollection:nil];
		
		NSLog(@"database.count = %lu", (unsigned long)count);
	}];
}

- (void)printMainViewCount:(YapDatabaseConnection *)databaseConnection
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"main"] numberOfItemsInGroup:@""];
		
		NSLog(@"mainView.count = %lu", (unsigned long)count);
	}];
}

- (void)printOnTheFlyViewCount:(YapDatabaseConnection *)databaseConnection
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		NSUInteger count = [[transaction ext:@"on-the-fly"] numberOfItemsInGroup:@""];
		
		NSLog(@"onTheFlyView.count = %lu", (unsigned long)count);
	}];
}

@end
