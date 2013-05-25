#import "AppDelegate.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	dispatch_async(dispatch_get_main_queue(), ^(void){
		
	//	[BenchmarkYapCache startTests];
		[BenchmarkYapDatabase startTests];
	});
}

@end
