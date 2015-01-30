#import "AppDelegate.h"
#import "AppAudioManager.h"
#import "CategorizingLogger.h"
#import "ContactsManager.h"
#import "DebugLogger.h"
#import "DiscardingLog.h"
#import "Environment.h"
#import "InCallViewController.h"
#import "PreferencesUtil.h"
#import "NotificationTracker.h"
#import "PushManager.h"
#import "PriorityQueue.h"
#import "Release.h"
#import "SignalsViewController.h"
#import "TSAccountManager.h"
#import "TSPreKeyManager.h"
#import "TSSocketManager.h"
#import "TSStorageManager.h"
#import "Util.h"
#import "VersionMigrations.h"
#import "UIColor+OWS.h"
#import "CodeVerificationViewController.h"
#import "MIMETypeUtil.h"

#import <PastelogKit/Pastelog.h>

#define kSignalVersionKey @"SignalUpdateVersionKey"

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif


static NSString* const kCallSegue = @"2.0_6.0_Call_Segue";

@interface AppDelegate ()

@property (nonatomic, retain) UIWindow            *blankWindow;
@property (nonatomic, strong) NotificationTracker *notificationTracker;

@property (nonatomic) TOCFutureSource *callPickUpFuture;

@end

@implementation AppDelegate

#pragma mark Detect updates - perform migrations

- (void)performUpdateCheck{
    NSString *previousVersion = Environment.preferences.lastRanVersion;
    NSString *currentVersion = [Environment.preferences setAndGetCurrentVersion];
    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        [Environment resetAppData]; // We clean previous keychain entries in case their are some entries remaining.
    }
    else if ([Environment.preferences getIsMigratingToVersion2Dot0] || [currentVersion compare:previousVersion options:NSNumericSearch] == NSOrderedDescending){
        if([self isVersion:previousVersion atLeast:@"1.0.2"]) {
            [VersionMigrations migrateFrom1Dot0Dot2ToVersion2Dot0]; // this is only necessary for older apps
        }
    }
}


- (BOOL) isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString {
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] != NSOrderedAscending;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL loggingIsEnabled;
    [self setupAppearance];
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
    
    [[TSStorageManager sharedManager] setupDatabase];

    self.notificationTracker = [NotificationTracker notificationTracker];
    
    [self performUpdateCheck];
    CategorizingLogger* logger = [CategorizingLogger categorizingLogger];
    [logger addLoggingCallback:^(NSString *category, id details, NSUInteger index) {}];
    [Environment setCurrent:[Release releaseEnvironmentWithLogging:logger]];
    [Environment.getCurrent.phoneDirectoryManager startUntilCancelled:nil];
    [Environment.getCurrent.contactsManager doAfterEnvironmentInitSetup];
    
    //Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        DDLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif ];
    }
    
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Storyboard" bundle:[NSBundle mainBundle]];
    UIViewController *viewController = [storyboard instantiateViewControllerWithIdentifier:@"UserInitialViewController"];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = viewController;
    
    [self.window makeKeyAndVisible];
    
    [self prepareScreenshotProtection];
    
    [Environment.phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall == nil){
            return;
        }
        SignalsViewController *vc = [[Environment getCurrent] signalsViewController];
        [vc dismissViewControllerAnimated:NO completion:nil];
        vc.latestCall = latestCall;
        [vc performSegueWithIdentifier:kCallSegue sender:self];
    } onThread:NSThread.mainThread untilCancelled:nil];
    
    if ([TSAccountManager isRegistered]) {
        [TSSocketManager becomeActive];
        [self refreshContacts];
        [TSPreKeyManager refreshPreKeys];
    }
    [MIMETypeUtil initialize];
    
    return YES;
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:deviceToken];
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
#ifdef DEBUG
    DDLogWarn(@"We're in debug mode, and registered a fake push identifier");
    [PushManager.sharedManager.pushNotificationFutureSource trySetResult:[@"aFakePushIdentifier" dataUsingEncoding:NSUTF8StringEncoding]];
#else
    [PushManager.sharedManager.pushNotificationFutureSource trySetFailure:error];
#endif
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings{
    [PushManager.sharedManager.userNotificationFutureSource trySetResult:notificationSettings];
}

-(BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
    if ([url.scheme isEqualToString:@"sgnl"]) {
        if ([url.host hasPrefix:@"verify"] && ![TSAccountManager isRegistered]) {
            id signupController                   = [Environment getCurrent].signUpFlowNavigationController;
            if ([signupController isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navController = (UINavigationController*)signupController;
                UIViewController *controller          = [navController.childViewControllers lastObject];
                if ([controller isKindOfClass:[CodeVerificationViewController class]]) {
                    CodeVerificationViewController *cvvc  = (CodeVerificationViewController*)controller;
                    NSString *verificationCode            = [url.path substringFromIndex:1];
                    
                    cvvc.challengeTextField.text          = verificationCode;
                    [cvvc verifyChallengeAction:nil];
                } else{
                    DDLogWarn(@"Not the verification view controller we expected. Got %@ instead", NSStringFromClass(controller.class));
                }
                
            }
        } else{
            DDLogWarn(@"Application opened with an unknown URL action: %@", url.host);
        }
    } else {
        DDLogWarn(@"Application opened with an unknown URL scheme: %@", url.scheme);
    }
    return NO;
}

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    if ([self isRedPhonePush:userInfo]) {
        ResponderSessionDescriptor* call;
        if (![self.notificationTracker shouldProcessNotification:userInfo]){
            return;
        }
        
        @try {
            call = [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:userInfo];
            DDLogDebug(@"Received remote notification. Parsed session descriptor: %@.", call);
            self.callPickUpFuture = [TOCFutureSource new];
        } @catch (OperationFailed* ex) {
            DDLogError(@"Error parsing remote notification. Error: %@.", ex);
            return;
        }
        
        if (!call) {
            DDLogError(@"Decryption of session descriptor failed");
            return;
        }
        
        [Environment.phoneManager incomingCallWithSession:call];
    }    
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    
    if ([self isRedPhonePush:userInfo]) {
        [self application:application didReceiveRemoteNotification:userInfo];
    } else {
        [TSSocketManager becomeActive];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                       completionHandler(UIBackgroundFetchResultNewData);
                   });
}

- (BOOL)isRedPhonePush:(NSDictionary*)pushDict {
    NSDictionary *aps  = [pushDict objectForKey:@"aps"];
    NSString *category = [aps      objectForKey:@"category"];
    
    if ([category isEqualToString:Signal_Call_Category]) {
        return YES;
    } else{
        return NO;
    }
}

-(void) applicationDidBecomeActive:(UIApplication *)application {
    if ([TSAccountManager isRegistered]) {
        [TSSocketManager becomeActive];
        [AppAudioManager.sharedInstance awake];
        [PushManager.sharedManager verifyPushPermissions];
        [AppAudioManager.sharedInstance requestRequiredPermissionsIfNeeded];
    }
    // Hacky way to clear notification center after processed push
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];
    
    [self removeScreenProtection];
}

- (void)applicationWillResignActive:(UIApplication *)application{
    [self protectScreen];
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forRemoteNotification:(NSDictionary *)userInfo completionHandler:(void (^)())completionHandler{
    
    [self application:application didReceiveRemoteNotification:userInfo];
    if ([identifier isEqualToString:Signal_Call_Accept_Identifier]) {
        [self.callPickUpFuture trySetResult:@YES];
        completionHandler();
    } else if ([identifier isEqualToString:Signal_Call_Decline_Identifier]){
        [self.callPickUpFuture trySetResult:@NO];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                           completionHandler();
                       });
    } else{
        completionHandler();
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application{
    [TSSocketManager resignActivity];
}

- (void)prepareScreenshotProtection{
    self.blankWindow = ({
        UIWindow *window              = [[UIWindow alloc] initWithFrame:self.window.bounds];
        window.hidden                 = YES;
        window.opaque                 = YES;
        window.userInteractionEnabled = NO;
        window.windowLevel            = CGFLOAT_MAX;
        
        // There appears to be no more reliable way to get the launchscreen image from an asset bundle
        NSDictionary *dict = @{@"320x480" : @"LaunchImage-700", @"320x568" : @"LaunchImage-700-568h", @"375x667" : @"LaunchImage-800-667h", @"414x736" : @"LaunchImage-800-Portrait-736h"};
        NSString *key = [NSString stringWithFormat:@"%dx%d", (int)[UIScreen mainScreen].bounds.size.width, (int)[UIScreen mainScreen].bounds.size.height];
        UIImage *launchImage = [UIImage imageNamed:dict[key]];
        UIImageView *imgView = [[UIImageView alloc] initWithImage:launchImage];
        UIViewController *vc = [[UIViewController alloc] initWithNibName:nil bundle:nil];
        vc.view.frame        = [[UIScreen mainScreen] bounds];
        imgView.frame        = [[UIScreen mainScreen] bounds];
        [vc.view addSubview:imgView];
        [vc.view setBackgroundColor:[UIColor ows_blackColor]];
        window.rootViewController = vc;
        
        window;
    });
}

- (void)protectScreen{
    if (Environment.preferences.screenSecurityIsEnabled){
        self.blankWindow.hidden = NO;
    }
}

- (void)removeScreenProtection{
    if (Environment.preferences.screenSecurityIsEnabled) {
        self.blankWindow.hidden = YES;
    }
}

-(void)setupAppearance {
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    [[UINavigationBar appearance] setBarTintColor:[UIColor ows_materialBlueColor]];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
    
    [[UIBarButtonItem appearanceWhenContainedIn: [UISearchBar class], nil] setTintColor:[UIColor ows_materialBlueColor]];


    [[UIToolbar appearance] setTintColor:[UIColor ows_materialBlueColor]];
    [[UIBarButtonItem appearance] setTintColor:[UIColor whiteColor]];
    
    NSShadow *shadow = [NSShadow new];
    [shadow setShadowColor:[UIColor clearColor]];
    
    NSDictionary *navbarTitleTextAttributes = @{
                                                NSForegroundColorAttributeName:[UIColor whiteColor],
                                                NSShadowAttributeName:shadow,
                                                };
    
    [[UISwitch appearance] setOnTintColor:[UIColor ows_materialBlueColor]];
    
    [[UINavigationBar appearance] setTitleTextAttributes:navbarTitleTextAttributes];

}

- (void)refreshContacts {
    Environment *env = [Environment getCurrent];
    PhoneNumberDirectoryFilterManager *manager = [env phoneDirectoryManager];
    [manager forceUpdate];
}

@end
