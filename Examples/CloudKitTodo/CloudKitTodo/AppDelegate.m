#import "AppDelegate.h"
#import "DatabaseManager.h"
#import "CloudKitManager.h"

#import "MyTodo.h"

#import "YapDatabaseLogging.h"

#import <CocoaLumberjack/CocoaLumberjack.h>
#import <CocoaLumberjack/DDTTYLogger.h>

#import <CloudKit/CloudKit.h>
#import <Reachability/Reachability.h>

#if DEBUG
  static const NSUInteger ddLogLevel = DDLogLevelAll;
#else
  static const NSUInteger ddLogLevel = DDLogLevelAll;
#endif

AppDelegate *MyAppDelegate;


@implementation AppDelegate

@synthesize reachability = reachability;

- (id)init
{
	if ((self = [super init]))
	{
		// Store global reference
		MyAppDelegate = self;
		
		// Configure logging
		[DDLog addLogger:[DDTTYLogger sharedInstance]];
		
		[[DDTTYLogger sharedInstance] setColorsEnabled:YES];
		
	#if TARGET_OS_IPHONE
		UIColor *redColor    = [UIColor redColor];
		UIColor *orangeColor = [UIColor orangeColor];
		UIColor *grayColor   = [UIColor grayColor];
	#else
		NSColor *redColor    = [NSColor redColor];
		NSColor *orangeColor = [NSColor orangeColor];
		NSColor *grayColor   = [NSColor grayColor];
	#endif
		
		[[DDTTYLogger sharedInstance] setForegroundColor:redColor
		                                 backgroundColor:nil
		                                         forFlag:YDB_LOG_FLAG_ERROR   // errors
		                                         context:YDBLogContext];      // from YapDatabase
	
		[[DDTTYLogger sharedInstance] setForegroundColor:orangeColor
		                                 backgroundColor:nil
		                                         forFlag:YDB_LOG_FLAG_WARN    // warnings
		                                         context:YDBLogContext];      // from YapDatabase
		
		[[DDTTYLogger sharedInstance] setForegroundColor:grayColor
		                                 backgroundColor:nil
		                                         forFlag:YDB_LOG_FLAG_TRACE   // trace (method invocations)
		                                         context:YDBLogContext];      // from YapDatabase
	}
	return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	DDLogVerbose(@"application:didFinishLaunchingWithOptions: %@", launchOptions);
	
	// Start database & cloudKit (in that order)
	
	[DatabaseManager initialize];
	[CloudKitManager initialize];
	
	// Register for push notifications
	
	UIUserNotificationSettings *notificationSettings =
	  [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];

	[application registerUserNotificationSettings:notificationSettings];
	
	// Start reachability
 
	reachability = [Reachability reachabilityForInternetConnection];
	[reachability startNotifier];
	
	return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	DDLogVerbose(@"applicationWillEnterForeground:");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	DDLogVerbose(@"applicationDidBecomeActive:");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	DDLogVerbose(@"applicationWillResignActive:");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	DDLogVerbose(@"applicationDidEnterBackground:");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	DDLogVerbose(@"applicationWillTerminate:");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Push (iOS 8)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
	DDLogVerbose(@"application:didRegisterUserNotificationSettings: %@", notificationSettings);
	
	[application registerForRemoteNotifications];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
	DDLogVerbose(@"Registered for Push notifications with token: %@", deviceToken);
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
	DDLogVerbose(@"Push subscription failed: %@", error);
}

- (void)application:(UIApplication *)application
       didReceiveRemoteNotification:(NSDictionary *)userInfo
             fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
	DDLogVerbose(@"Push received: %@", userInfo);
	
	__block UIBackgroundFetchResult combinedFetchResult = UIBackgroundFetchResultNoData;
	
	[[CloudKitManager sharedInstance] fetchRecordChangesWithCompletionHandler:
	    ^(UIBackgroundFetchResult fetchResult, BOOL moreComing)
	{
		if (fetchResult == UIBackgroundFetchResultNewData) {
			combinedFetchResult = UIBackgroundFetchResultNewData;
		}
		else if (fetchResult == UIBackgroundFetchResultFailed && combinedFetchResult == UIBackgroundFetchResultNoData) {
			combinedFetchResult = UIBackgroundFetchResultFailed;
		}
		
		if (!moreComing) {
			completionHandler(combinedFetchResult);
		}
	}];
}

@end
