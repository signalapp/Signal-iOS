#import "ViewController.h"
#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"
#import "BenchmarkYapCollectionsDatabase.h"


@implementation ViewController

@synthesize yapDatabaseBenchmarksButton;
@synthesize yapCollectionsDatabaseBenchmarksButton;
@synthesize cacheBenchmarksButton;

- (IBAction)runYapDatabaseBenchmarks
{
	yapDatabaseBenchmarksButton.enabled = NO;
	yapCollectionsDatabaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapDatabase runTestsWithCompletion:^{
			
			yapDatabaseBenchmarksButton.enabled = YES;
			yapCollectionsDatabaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

- (IBAction)runYapCollectionsDatabaseBenchmarks
{
	yapDatabaseBenchmarksButton.enabled = NO;
	yapCollectionsDatabaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapCollectionsDatabase runTestsWithCompletion:^{
			
			yapDatabaseBenchmarksButton.enabled = YES;
			yapCollectionsDatabaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

- (IBAction)runCacheBenchmarks
{
	yapDatabaseBenchmarksButton.enabled = NO;
	yapCollectionsDatabaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapCache runTestsWithCompletion:^{
			
			yapDatabaseBenchmarksButton.enabled = YES;
			yapCollectionsDatabaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

@end
