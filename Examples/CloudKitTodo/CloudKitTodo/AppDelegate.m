#import "AppDelegate.h"
#import "DatabaseManager.h"
#import "CloudKitManager.h"

#import "MyTodo.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

#import <CloudKit/CloudKit.h>
#import <Reachability/Reachability.h>

#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
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

- (void)applicationWillResignActive:(UIApplication *)application
{
	DDLogVerbose(@"applicationWillResignActive:");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	DDLogVerbose(@"applicationDidEnterBackground:");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	DDLogVerbose(@"applicationWillEnterForeground:");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	DDLogVerbose(@"applicationDidBecomeActive:");
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
