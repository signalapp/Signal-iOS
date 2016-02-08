#import "AppDelegate.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseFilteredView.h>


@implementation AppDelegate

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
#pragma mark Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)appName
{
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (appName == nil) {
		appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	}
	if (appName == nil) {
		appName = @"YapDatabaseTesting";
	}
	
	return appName;
}

- (NSString *)appSupportDir
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *appSupportDir = [basePath stringByAppendingPathComponent:[self appName]];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (![fileManager fileExistsAtPath:appSupportDir])
	{
		[fileManager createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];
	}
	
	return appSupportDir;
}

- (NSString *)databaseFilePath
{
	NSString *fileName = @"test.sqlite";
	return [[self appSupportDir] stringByAppendingPathComponent:fileName];
}

@end
