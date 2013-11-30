#import "ViewController.h"
#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"


@implementation ViewController

@synthesize yapDatabaseBenchmarksButton;
@synthesize cacheBenchmarksButton;

- (IBAction)runYapDatabaseBenchmarks
{
	yapDatabaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapDatabase runTestsWithCompletion:^{
			
			yapDatabaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

- (IBAction)runCacheBenchmarks
{
	yapDatabaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapCache runTestsWithCompletion:^{
			
			yapDatabaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

@end
