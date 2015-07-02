#import "AppDelegate.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import <YapDatabase/YapDatabase.h>

@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *connection;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	
}

@synthesize databaseBenchmarksButton = databaseBenchmarksButton;
@synthesize cacheBenchmarksButton = cacheBenchmarksButton;

- (IBAction)runDatabaseBenchmarks:(id)sender
{
	databaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapDatabase runTestsWithCompletion:^{
			
			databaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

- (IBAction)runCacheBenchmarks:(id)sender
{
	databaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapCache runTestsWithCompletion:^{
			
			databaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
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

- (void)debug
{
	NSString *databaseFilePath = [self databaseFilePath];
	NSLog(@"databaseFilePath: %@", databaseFilePath);
	
	[[NSFileManager defaultManager] removeItemAtPath:databaseFilePath error:NULL];
	
	database = [[YapDatabase alloc] initWithPath:databaseFilePath];
}

@end
