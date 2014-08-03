#import "AppDelegate.h"
#import "AppAudioManager.h"
#import "CallLogViewController.h"
#import "CategorizingLogger.h"
#import "DialerViewController.h"
#import "DiscardingLog.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "LeftSideMenuViewController.h"
#import "MMDrawerController.h"
#import "NotificationTracker.h"
#import "PushManager.h"
#import "PriorityQueue.h"
#import "RecentCallManager.h"
#import "Release.h"
#import "SettingsViewController.h"
#import "TabBarParentViewController.h"
#import "Util.h"
#import "VersionMigrations.h"

#define kSignalVersionKey @"SignalUpdateVersionKey"

#define URL_SCHEME_CALL_HOST @"call"
#define URL_SCHEME_TEXT_HOST @"text"
#define URL_SCHEME_CHALLENGECODE_HOST @"vcode"

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif

@interface AppDelegate ()

@property (nonatomic, strong) MMDrawerController *drawerController;
@property (nonatomic, strong) NotificationTracker *notificationTracker;
@property (nonatomic) DDFileLogger *fileLogger;

@end

@implementation AppDelegate

#pragma mark Detect updates - perform migrations

- (void)performUpdateCheck{
    // We check if NSUserDefaults key for version exists.
    NSString *previousVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kSignalVersionKey];
    NSString *currentVersion  = [NSString stringWithFormat:@"%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
    
    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        [Environment resetAppData]; // We clean previous keychain entries in case their are some entries remaining.
    } else if ([currentVersion compare:previousVersion options:NSNumericSearch] == NSOrderedDescending){
        // Application was updated, let's see if we have a migration scheme for it.
        if ([previousVersion isEqualToString:@"1.0.2"]) {
            // Migrate from custom preferences to NSUserDefaults
            [VersionMigrations migrationFrom1Dot0Dot2toLarger];
        }
        
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:kSignalVersionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


/**
 *  Protects the preference and logs file with disk encryption and prevents them to leak to iCloud.
 */

- (void)protectPreferenceFiles{
    NSMutableArray *pathsToExclude = [NSMutableArray array];
    
    [pathsToExclude addObject:[[[NSHomeDirectory() stringByAppendingString:@"/Library/Preferences/"] stringByAppendingString:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingString:@".plist"]];
    
    NSError *error;
    
    NSString *logPath    = [NSHomeDirectory() stringByAppendingString:@"/Library/Caches/Logs/"];
    NSArray  *logsFiles  = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logPath error:&error];
    
    for (NSUInteger i = 0; i < [logsFiles count]; i++) {
        [pathsToExclude addObject:[logPath stringByAppendingString:[logsFiles objectAtIndex:i]]];
    }
    
    for (NSUInteger i = 0; i < [pathsToExclude count]; i++) {
        [[NSURL fileURLWithPath:[pathsToExclude objectAtIndex:i]] setResourceValue: [NSNumber numberWithBool: YES]
                                                                            forKey: NSURLIsExcludedFromBackupKey error: &error];
    }
    
    if (error) {
        DDLogError(@"Error while removing log files from backup: %@", error.description);
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:NSLocalizedString(@"WARNING", @"") message:NSLocalizedString(@"DISABLING_BACKUP_FAILED", @"") delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil, nil];
        [alert show];
        
        return;
    }
    
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init]; //Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling.
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3; // Keep three days of logs.
    [DDLog addLogger:self.fileLogger];
    
    [self performUpdateCheck];
    [self protectPreferenceFiles];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.notificationTracker = [NotificationTracker notificationTracker];
    
    CategorizingLogger* logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index) {}];
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];
    [[Environment getCurrent].phoneDirectoryManager startUntilCancelled:nil];
    [[Environment getCurrent].contactsManager doAfterEnvironmentInitSetup];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];
    
    LeftSideMenuViewController *leftSideMenuViewController = [LeftSideMenuViewController new];
    
    self.drawerController = [[MMDrawerController alloc] initWithCenterViewController:leftSideMenuViewController.centerTabBarViewController leftDrawerViewController:leftSideMenuViewController];
    self.window.rootViewController = _drawerController;
    [self.window makeKeyAndVisible];
    
    //Accept push notification when app is not open
    NSDictionary *remoteNotif = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }
    
    [[[Environment phoneManager] currentCallObservable] watchLatestValue:^(CallState* latestCall) {
        if (latestCall == nil){
            return;
        }
        
        InCallViewController *callViewController = [InCallViewController inCallViewControllerWithCallState:latestCall
                                                                                 andOptionallyKnownContact:[latestCall potentiallySpecifiedContact]];
        [_drawerController.centerViewController presentViewController:callViewController animated:YES completion:nil];
    } onThread:[NSThread mainThread] untilCancelled:nil];
    
    
    return YES;
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    [[PushManager sharedManager] registerForPushWithToken:deviceToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
    [[PushManager sharedManager]verifyPushActivated];
    DDLogError(@"Failed to register for push notifications: %@", error);
}

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    ResponderSessionDescriptor* call;
    @try {
        call = [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:userInfo];
        DDLogDebug(@"Received remote notification. Parsed session descriptor: %@.", call);
    } @catch (OperationFailed* ex) {
        DDLogError(@"Error parsing remote notification. Error: %@.", ex);
        return;
    }
    
    [[Environment phoneManager] incomingCallWithSession:call];
}

-(void) application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    if([self.notificationTracker shouldProcessNotification:userInfo]){
        [self application:application didReceiveRemoteNotification:userInfo];
    } else{
        DDLogDebug(@"Push already processed. Skipping.");
    }
    completionHandler(UIBackgroundFetchResultNewData);
}

-(void) applicationDidBecomeActive:(UIApplication *)application {
    [[AppAudioManager sharedInstance] awake];
    application.applicationIconBadgeNumber = 0;
    
    if ([Environment isRegistered]) {
        [[PushManager sharedManager] verifyPushActivated];
        [[AppAudioManager sharedInstance] requestRequiredPermissionsIfNeeded];
    }
}

-(BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url{
    
    if ([Environment isRegistered]) {
        __block BOOL inCall;
        [[[Environment phoneManager] currentCallObservable] watchLatestValue:^(CallState* latestCall) {
            if (latestCall == nil){
                inCall=NO;
                return;
            }
        } onThread:[NSThread mainThread] untilCancelled:nil];
        if (inCall) {
            return NO;
        }
        
        if ([[url host] isEqualToString:URL_SCHEME_CALL_HOST]) {
        }
        if ([[url host] isEqualToString:URL_SCHEME_TEXT_HOST]) {
            //Not supported yet
            return NO;
        }
    }else{
        if ([[url host] isEqualToString:URL_SCHEME_CHALLENGECODE_HOST]) {
        }
    }
    return NO;
}

@end
