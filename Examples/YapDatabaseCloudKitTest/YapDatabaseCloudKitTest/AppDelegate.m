#import "AppDelegate.h"
#import "DatabaseManager.h"

#import "MyTodo.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

#import <CloudKit/CloudKit.h>

#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif


@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	DDLogVerbose(@"application:didFinishLaunchingWithOptions: %@", launchOptions);
	
	// Configure logging
	
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	
	// Register for push notifications
	
	UIUserNotificationSettings *notificationSettings =
	  [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];

	[application registerUserNotificationSettings:notificationSettings];
	
	// Start database
	
	[DatabaseManager initialize];
	
	// Start test
	
	dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC));
	dispatch_after(delay, dispatch_get_main_queue(), ^{
		
		[self startTest];
	});
	
	return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	
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

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)info
{
	DDLogVerbose(@"Push received with alert body: %@", info[@"aps"][@"alert"]);
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier
                                                      forRemoteNotification:(NSDictionary *)userInfo
                                                          completionHandler:(void (^)())completionHandler
{
	DDLogVerbose(@"application:handleActionWithIdentifier:forRemoteNotification:completionHandler:");
	
	completionHandler();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Test
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)startTest
{
	MyTodo *todo = [[MyTodo alloc] init];
	todo.title = @"Mow the lawn";
	
	YapDatabaseConnection *databaseConnection = [MyDatabaseManager.database newConnection];
	[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:todo forKey:todo.uuid inCollection:Collection_Todos];
	}];
}

@end
