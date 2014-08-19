#import "AppDelegate.h"
#import "AppAudioManager.h"
#import "CallLogViewController.h"
#import "CategorizingLogger.h"
#import "DebugLogger.h"
#import "DialerViewController.h"
#import "DiscardingLog.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "LeftSideMenuViewController.h"
#import "MMDrawerController.h"
#import "PreferencesUtil.h"
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

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif

@interface AppDelegate ()

@property (nonatomic, retain) UIWindow            *blankWindow;
@property (nonatomic, strong) MMDrawerController  *drawerController;
@property (nonatomic, strong) NotificationTracker *notificationTracker;

@end

@implementation AppDelegate

#pragma mark Detect updates - perform migrations

- (void)performUpdateCheck{
    // We check if NSUserDefaults key for version exists.
    NSString *previousVersion = [[Environment preferences] lastRanVersion];
    NSString *currentVersion  = [[Environment preferences] setAndGetCurrentVersion];
    
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
}

/**
 *  Protects the preference and logs file with disk encryption and prevents them to leak to iCloud.
 */

- (void)protectPreferenceFiles{
    
    NSMutableArray *pathsToExclude = [NSMutableArray array];
    NSString *preferencesPath =[NSHomeDirectory() stringByAppendingString:@"/Library/Preferences/"];
    
    NSError *error;
    
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:preferencesPath error:&error];
    
    [pathsToExclude addObject:[[preferencesPath stringByAppendingString:[[NSBundle mainBundle] bundleIdentifier]] stringByAppendingString:@".plist"]];
    
    NSString *logPath    = [NSHomeDirectory() stringByAppendingString:@"/Library/Caches/Logs/"];
    NSArray  *logsFiles  = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logPath error:&error];
    
    attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:logPath error:&error];
    
    for (NSUInteger i = 0; i < logsFiles.count; i++) {
        [pathsToExclude addObject:[logPath stringByAppendingString:logsFiles[i]]];
    }
    
    for (NSUInteger i = 0; i < pathsToExclude.count; i++) {
        [[NSURL fileURLWithPath:pathsToExclude[i]] setResourceValue:@YES
                                                             forKey:NSURLIsExcludedFromBackupKey
                                                              error:&error];
    }
    
    if (error) {
        DDLogError(@"Error while removing log files from backup: %@", error.description);
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:NSLocalizedString(@"WARNING", @"") message:NSLocalizedString(@"DISABLING_BACKUP_FAILED", @"") delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil, nil];
        [alert show];
        return;
    }
    
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    BOOL loggingIsEnabled;

#ifdef DEBUG
    loggingIsEnabled = TRUE;
    [DebugLogger.sharedInstance enableTTYLogging];
    
#elif RELEASE
    loggingIsEnabled = [[Environment preferences] loggingIsEnabled];
#endif

    if (loggingIsEnabled) {
        [DebugLogger.sharedInstance enableFileLogging];
    }
    
    [self performUpdateCheck];
    [self protectPreferenceFiles];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    [self prepareScreenshotProtection];
    
    self.notificationTracker = [NotificationTracker notificationTracker];
    
    CategorizingLogger* logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index) {}];
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];
    [[Environment getCurrent].phoneDirectoryManager startUntilCancelled:nil];
    [[Environment getCurrent].contactsManager doAfterEnvironmentInitSetup];
    [UIApplication.sharedApplication setStatusBarStyle:UIStatusBarStyleDefault];
    
    LeftSideMenuViewController *leftSideMenuViewController = [LeftSideMenuViewController new];
    
    self.drawerController = [[MMDrawerController alloc] initWithCenterViewController:leftSideMenuViewController.centerTabBarViewController leftDrawerViewController:leftSideMenuViewController];
    self.window.rootViewController = _drawerController;
    [self.window makeKeyAndVisible];
    
    //Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
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
    [PushManager.sharedManager registerForPushWithToken:deviceToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
    [PushManager.sharedManager verifyPushActivated];
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
    
    if (!call) {
        DDLogError(@"Decryption of session descriptor failed");
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
    [AppAudioManager.sharedInstance awake];
    
    // Hacky way to clear notification center after processed push
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];
    
    [self removeScreenProtection];
    
    if (Environment.isRegistered) {
        [PushManager.sharedManager verifyPushActivated];
        [AppAudioManager.sharedInstance requestRequiredPermissionsIfNeeded];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application{
    [self protectScreen];
}

- (void)prepareScreenshotProtection{
    self.blankWindow = ({
        UIWindow *window = [[UIWindow alloc] initWithFrame:self.window.bounds];
        window.hidden = YES;
        window.opaque = YES;
        window.userInteractionEnabled = NO;
        window.windowLevel = CGFLOAT_MAX;
        window;
    });
}

- (void)protectScreen{
    if ([[Environment preferences] screenSecurityIsEnabled]) {
        self.blankWindow.rootViewController = [[UIViewController alloc] init];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.blankWindow.bounds];
        if (self.blankWindow.bounds.size.height == 568) {
            imageView.image = [UIImage imageNamed:@"Default-568h"];
        } else {
            imageView.image = [UIImage imageNamed:@"Default"];
        }
        imageView.opaque = YES;
        [self.blankWindow.rootViewController.view addSubview:imageView];
        self.blankWindow.hidden = NO;
    }
}

- (void)removeScreenProtection{
    if ([[Environment preferences] screenSecurityIsEnabled]) {
        self.blankWindow.rootViewController = nil;
        self.blankWindow.hidden = YES;
    }
}

@end
