#import "AppDelegate.h"
#import "ViewController.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "TestObject.h"

#import "DDLog.h"
#import "DDTTYLogger.h"
#import "YapDatabaseLogging.h"


@implementation AppDelegate
{
	YapDatabase *database;
	YapDatabaseConnection *databaseConnection;
	YapDatabaseView *databaseView;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	[[DDTTYLogger sharedInstance] setColorsEnabled:YES];
	[[DDTTYLogger sharedInstance] setForegroundColor:[UIColor darkGrayColor]
	                                 backgroundColor:nil
	                                         forFlag:YDB_LOG_FLAG_TRACE
	                                         context:YDBLogContext];
	
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
		
		NSString *object1 = (NSString *)obj1;
		NSString *object2 = (NSString *)obj2;
		
		return [object1 compare:object2];
	};
	
	databaseView = [[YapDatabaseView alloc] initWithGroupingBlock:groupingBlock
	                                            groupingBlockType:YapDatabaseViewBlockTypeWithBoth
	                                                 sortingBlock:sortingBlock
	                                             sortingBlockType:YapDatabaseViewBlockTypeWithObject];
	
	[database registerView:databaseView withName:@"test"];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		(void)[transaction view:@"test"];
	}];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSLog(@"setObject:forKey: 1");
		[transaction setObject:@"object1" forKey:@"key1"];
		
		NSLog(@"setObject:forKey: 2");
		[transaction setObject:@"object2" forKey:@"key2"];
		
		NSLog(@"setObject:forKey: 3");
		[transaction setObject:@"object3" forKey:@"key3"];
	}];
	
	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		NSLog(@"setObject:forKey: 1");
		[transaction setObject:@"Z-object1" forKey:@"key1"];
	}];
	
//	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
//		
//		NSLog(@"removeObjectForKey: 2");
//		[transaction removeObjectForKey:@"key2"];
//	}];
	
//	[databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
//		
//		NSLog(@"removeAllObjects");
//		[transaction removeAllObjects];
//	}];
}

@end
