#import "AppDelegate.h"
#import "ViewController.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import "YapDatabase.h"
#import "YapDatabaseView.h"

#import "TestObject.h"

@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *databaseConnection;
	YapDatabaseView *databaseView;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	dispatch_async(dispatch_get_main_queue(), ^(void){
		
	//	[BenchmarkYapCache startTests];
	//	[BenchmarkYapDatabase startTests];
		
		[self testView];
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

- (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = @"test.sqlite";
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)testView
{
	NSString *databasePath = [self databasePath];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:nil];
	
	database = [[YapDatabase alloc] initWithPath:databasePath];
	databaseConnection = [database newConnection];
	
	YapDatabaseViewFilterWithBothBlock filterBlock;
	YapDatabaseViewSortWithBothBlock sortBlock;
	
	filterBlock = ^BOOL (NSString *key, id object, id metadata, NSUInteger *outSection){
		
		return YES;
	};
	
	sortBlock = ^NSComparisonResult (NSString *key1, id obj1, id meta1, NSString *key2, id obj2, id meta2){
		
		TestObject *object1 = (TestObject *)obj1;
		TestObject *object2 = (TestObject *)obj2;
		
		return [object1.string1 compare:object2.string1];
	};
	
	databaseView = [[YapDatabaseView alloc] initWithFilterBlock:filterBlock
	                                                 filterType:YapDatabaseViewBlockTypeWithBoth
	                                                  sortBlock:sortBlock
	                                                   sortType:YapDatabaseViewBlockTypeWithBoth];
	
	[database registerView:databaseView withName:@"view"];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSError *error = nil;
		if ([transaction createOrOpenView:@"view"])
		{
			NSLog(@"Created view !");
		}
		else
		{
			NSLog(@"Error creating view: %@", error);
		}
	}];
}

@end
