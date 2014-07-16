#import "AppDelegate.h"
#import "AppAudioManager.h"
#import "CallLogViewController.h"
#import "CategorizingLogger.h"
#import "DialerViewController.h"
#import "DiscardingLog.h"
#import "InCallViewController.h"
#import "LeftSideMenuViewController.h"
#import "MMDrawerController.h"
#import "NotificationTracker.h"
#import "PriorityQueue.h"
#import "RecentCallManager.h"
#import "Release.h"
#import "SettingsViewController.h"
#import "TabBarParentViewController.h"
#import "Util.h"
#import <UICKeyChainStore/UICKeyChainStore.h>
#import "Environment.h"

#define kSignalVersionKey @"SignalUpdateVersionKey"

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif

@interface AppDelegate ()

@property (nonatomic, strong) MMDrawerController *drawerController;
@property (nonatomic, strong) NotificationTracker *notificationTracker;
@property (nonatomic) DDFileLogger *fileLogger;

@end

@implementation AppDelegate {
    FutureSource* futureApnIdSource;
}

#pragma mark Detect updates - perform migrations

- (void)performUpdateCheck{
    // We check if NSUserDefaults key for version exists.
    NSString *previousVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kSignalVersionKey];
    NSString *currentVersion  = [NSString stringWithFormat:@"%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
    
    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        [Environment setCurrent:[Release releaseEnvironmentWithLogging:nil]];
        [Environment resetAppData]; // We clean previous keychain entries in case their are some entries remaining.
    } else if ([currentVersion compare:previousVersion options:NSNumericSearch] == NSOrderedDescending) {
        // The application was updated
        DDLogWarn(@"Application was updated from %@ to %@", previousVersion, currentVersion);
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:kSignalVersionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark Disable cloud/iTunes syncing of call log

- (void)disableCallLogBackup{
    NSString *preferencesPath = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/Preferences"];
    NSString *userDefaultsString = [NSString stringWithFormat:@"%@/%@.plist", preferencesPath,[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"]];
    
    NSURL *userDefaultsURL = [NSURL fileURLWithPath:userDefaultsString];
    NSError *error;
    [userDefaultsURL setResourceValue: [NSNumber numberWithBool: YES]
                   forKey: NSURLIsExcludedFromBackupKey error: &error];
    
    if (error) {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:NSLocalizedString(@"WARNING", @"") message:NSLocalizedString(@"DISABLING_BACKUP_FAILED", @"") delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil, nil];
        [alert show];
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init]; //Logging to file, because it's in the Cache folder, they are not uploaded in iTunes/iCloud backups.
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling.
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 3; // Keep three days of logs.
    [DDLog addLogger:self.fileLogger];
    
    [self performUpdateCheck];
    [self disableCallLogBackup];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.notificationTracker = [NotificationTracker notificationTracker];
    
    // start register for apn id
    futureApnIdSource = [FutureSource new];
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge|UIRemoteNotificationTypeSound| UIRemoteNotificationTypeAlert)];

    CategorizingLogger* logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index) {}];
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];
    [[Environment getCurrent].phoneDirectoryManager startUntilCancelled:nil];
    [[Environment getCurrent].contactsManager doAfterEnvironmentInitSetup];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault];

    LeftSideMenuViewController *leftSideMenuViewController = [LeftSideMenuViewController new];
    leftSideMenuViewController.centerTabBarViewController.inboxFeedViewController.apnId = futureApnIdSource;
    leftSideMenuViewController.centerTabBarViewController.settingsViewController.apnId = futureApnIdSource;

    self.drawerController = [[MMDrawerController alloc] initWithCenterViewController:leftSideMenuViewController.centerTabBarViewController leftDrawerViewController:leftSideMenuViewController];
    self.window.rootViewController = _drawerController;
    [self.window makeKeyAndVisible];

    //Accept push notification when app is not open
    NSDictionary *remoteNotif = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }

    [[[Environment phoneManager] currentCallObservable] watchLatestValue:^(CallState* latestCall) {
        if (latestCall == nil){
            DDLogError(@"Latest Call is nil.");
            return;
        }
        
        InCallViewController *callViewController = [InCallViewController inCallViewControllerWithCallState:latestCall
                    andOptionallyKnownContact:[latestCall potentiallySpecifiedContact]];
        [_drawerController.centerViewController presentViewController:callViewController animated:YES completion:nil];
    } onThread:[NSThread mainThread] untilCancelled:nil];

    return YES;
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    DDLogDebug(@"Device registered for push");
    [futureApnIdSource trySetResult:deviceToken];
}
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
    DDLogError(@"Failed to register for push notifications: %@", error);
    [futureApnIdSource trySetFailure:error];
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
}

@end
