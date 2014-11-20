#import "AppDelegate.h"
#import "AppAudioManager.h"
#import "CategorizingLogger.h"
#import "DebugLogger.h"
#import "DialerViewController.h"
#import "DiscardingLog.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "PreferencesUtil.h"
#import "NotificationTracker.h"
#import "PushManager.h"
#import "PriorityQueue.h"
#import "RecentCallManager.h"
#import "Release.h"
#import "TSAccountManager.h"
#import "Util.h"
#import "VersionMigrations.h"

#import "InitialViewController.h"


#import <PastelogKit/Pastelog.h>

#define kSignalVersionKey @"SignalUpdateVersionKey"

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif

@interface AppDelegate ()

@property (nonatomic, retain) UIWindow            *blankWindow;
@property (nonatomic, strong) NotificationTracker *notificationTracker;

@property (nonatomic) TOCFutureSource *callPickUpFuture;

@end

@implementation AppDelegate

#pragma mark Detect updates - perform migrations

- (void)performUpdateCheck{
    // We check if NSUserDefaults key for version exists.
    NSString *previousVersion = Environment.preferences.lastRanVersion;
    NSString *currentVersion  = [Environment.preferences setAndGetCurrentVersion];
    
    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        [Environment resetAppData]; // We clean previous keychain entries in case their are some entries remaining.
    } else if ([currentVersion compare:previousVersion options:NSNumericSearch] == NSOrderedDescending){
        [Environment resetAppData];
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
    [NSFileManager.defaultManager setAttributes:attrs ofItemAtPath:preferencesPath error:&error];
    
    [pathsToExclude addObject:[[preferencesPath stringByAppendingString:NSBundle.mainBundle.bundleIdentifier] stringByAppendingString:@".plist"]];
    
    NSString *logPath    = [NSHomeDirectory() stringByAppendingString:@"/Library/Caches/Logs/"];
    NSArray  *logsFiles  = [NSFileManager.defaultManager contentsOfDirectoryAtPath:logPath error:&error];
    
    attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    [NSFileManager.defaultManager setAttributes:attrs ofItemAtPath:logPath error:&error];
    
    for (NSString *logsFile in logsFiles) {
        [pathsToExclude addObject:[logPath stringByAppendingString:logsFile]];
    }
    
    for (NSString *pathToExclude in pathsToExclude) {
        [[NSURL fileURLWithPath:pathToExclude] setResourceValue:@YES
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
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    if (getenv("runningTests_dontStartApp")) {
        return YES;
    }
    
    loggingIsEnabled = TRUE;
    [DebugLogger.sharedInstance enableTTYLogging];
    
#elif RELEASE
    loggingIsEnabled = Environment.preferences.loggingIsEnabled;
#endif

    if (loggingIsEnabled) {
        [DebugLogger.sharedInstance enableFileLogging];
    }
    
    [self performUpdateCheck];
    [self protectPreferenceFiles];
    
    [self prepareScreenshotProtection];
    
    self.notificationTracker = [NotificationTracker notificationTracker];
    
    CategorizingLogger* logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index) {}];
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];
    [Environment.getCurrent.phoneDirectoryManager startUntilCancelled:nil];
    [Environment.getCurrent.contactsManager doAfterEnvironmentInitSetup];
    [UIApplication.sharedApplication setStatusBarStyle:UIStatusBarStyleDefault];
    
    //Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }
    
    [Environment.phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall == nil){
            return;
        }
        
        InCallViewController *callViewController = [InCallViewController inCallViewControllerWithCallState:latestCall
                                                                                 andOptionallyKnownContact:latestCall.potentiallySpecifiedContact];
        
        if (latestCall.initiatedLocally == false){
            [self.callPickUpFuture.future thenDo:^(NSNumber *accept) {
                if ([accept isEqualToNumber:@YES]) {
                    [callViewController answerButtonTapped];
                } else if ([accept isEqualToNumber:@NO]){
                    [callViewController rejectButtonTapped];
                }
            }];
        }
    
    } onThread:NSThread.mainThread untilCancelled:nil];
    
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:[NSBundle mainBundle]];
    
    UIViewController *viewController;
    
    if (![TSAccountManager isRegistered]) {
        viewController = [storyboard instantiateViewControllerWithIdentifier:@"RegisterInitialViewController"];
    } else{
        viewController = [storyboard instantiateViewControllerWithIdentifier:@"UserInitialViewController"];
    }
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = viewController;

    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:deviceToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
    [PushManager.sharedManager.pushNotificationFutureSource trySetFailure:error];
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings{
    [PushManager.sharedManager.userNotificationFutureSource trySetResult:notificationSettings];
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
    self.callPickUpFuture = [TOCFutureSource new];
    [Environment.phoneManager incomingCallWithSession:call];
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
        [PushManager.sharedManager verifyPushPermissions];
        [AppAudioManager.sharedInstance requestRequiredPermissionsIfNeeded];
    }
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forRemoteNotification:(NSDictionary *)userInfo completionHandler:(void (^)())completionHandler{
    if ([identifier isEqualToString:Signal_Accept_Identifier]) {
        [self.callPickUpFuture trySetResult:@YES];
    } else if ([identifier isEqualToString:Signal_Decline_Identifier]){
        [self.callPickUpFuture trySetResult:@NO];
    }
    completionHandler();
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
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.blankWindow.rootViewController = [UIViewController new];
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
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.blankWindow.rootViewController = nil;
        self.blankWindow.hidden = YES;
    }
}

@end
