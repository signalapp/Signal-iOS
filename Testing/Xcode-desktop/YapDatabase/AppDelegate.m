#import "AppDelegate.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import "YapDatabase.h"

@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *primaryConnection;
	YapDatabaseConnection *secondaryConnection;
	YapDatabaseConnection *writerConnection;
	
	NSUInteger count;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	dispatch_async(dispatch_get_main_queue(), ^(void){
		
	//	[BenchmarkYapCache startTests];
		[BenchmarkYapDatabase startTests];
		
	//	[self testWalSize];
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark WAL Size Test
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)databaseFilePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (appName == nil) {
		appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	}
	
	NSString *appSupportDir = [basePath stringByAppendingPathComponent:appName];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (![fileManager fileExistsAtPath:appSupportDir])
	{
		[fileManager createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];
	}
	
	NSString *fileName = @"test.sqlite";
	return [appSupportDir stringByAppendingPathComponent:fileName];
}

- (void)testWalSize
{
	NSString *databaseFilePath = [self databaseFilePath];
	NSLog(@"databaseFilePath: %@", databaseFilePath);
	
	[[NSFileManager defaultManager] removeItemAtPath:databaseFilePath error:NULL];
	
	database = [[YapDatabase alloc] initWithPath:databaseFilePath];
	
	primaryConnection = [database newConnection];
	secondaryConnection = [database newConnection];
	writerConnection = [database newConnection];
	
	[primaryConnection beginLongLivedReadTransaction];
	[secondaryConnection beginLongLivedReadTransaction];
	
	[NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(readwrite:) userInfo:nil repeats:YES];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(yapDatabaseModified:)
	                                             name:YapDatabaseModifiedNotification
	                                           object:database];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
	double delayInSeconds;
	dispatch_time_t popTime;
	
	delayInSeconds = 1.0;
	popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		NSLog(@"Syncing primary connection...");
		[primaryConnection beginLongLivedReadTransaction];
	});
	
	delayInSeconds = 6.0;
	popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		NSLog(@"Syncing secondary connection...");
		[secondaryConnection beginLongLivedReadTransaction];
	});
}

- (void)readwrite:(NSTimer *)timer
{
	[writerConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (NSUInteger i = 0; i < 100; i++)
		{
			NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)count];
			[transaction setObject:@"a string object that's kinda big" forKey:key];
			
			count++;
		}
		
		NSLog(@"Writing more objects to the database. Count = %lu", (unsigned long)count);
	}];
}

@end
