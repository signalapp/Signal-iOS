#import "AppDelegate.h"
#import "ViewController.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "TestObject.h"

#import "DDLog.h"
#import "DDTTYLogger.h"


@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *databaseConnection;
	YapDatabaseView *databaseView;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
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
	
	YapDatabaseViewGroupingWithBothBlock groupingBlock;
	YapDatabaseViewSortingWithObjectBlock sortingBlock;
	
	groupingBlock = ^(NSString *key, id object, id metadata){
		
		return @"";
	};
	
	sortingBlock = ^(NSString *group, NSString *key1, id obj1, NSString *key2, id obj2){
		
		TestObject *object1 = (TestObject *)obj1;
		TestObject *object2 = (TestObject *)obj2;
		
		return [object1.string1 compare:object2.string1];
	};
	
	databaseView = [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                            groupingBlockType:YapDatabaseViewBlockTypeWithBoth
	                                                 sortingBlock:sortingBlock
	                                             sortingBlockType:YapDatabaseViewBlockTypeWithObject];
	
	[database registerView:databaseView withName:@"view"];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSLog(@"setObject:forKey: 1");
		[transaction setObject:@"objectA" forKey:@"key1"];
		
//		NSLog(@"setObject:forKey: 2");
//		[transaction setObject:@"objectA" forKey:@"key2"];
		
//		NSLog(@"setObject:forKey: 3");
//		[transaction setObject:@"objectA" forKey:@"key2"];
		
//		NSLog(@"setObject:forKey: 1");
//		[transaction setObject:@"objectB" forKey:@"key1"];
		
//		NSLog(@"removeObjectForKey: 2");
//		[transaction removeObjectForKey:@"key2"];
		
//		NSLog(@"removeAllObjects");
//		[transaction removeAllObjects];
	}];
}

@end
