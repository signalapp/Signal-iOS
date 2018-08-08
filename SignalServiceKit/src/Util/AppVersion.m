//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppVersion.h"
#import <SignalServiceKit/NSUserDefaults+OWS.h>

NSString *const kNSUserDefaults_FirstAppVersion = @"kNSUserDefaults_FirstAppVersion";
NSString *const kNSUserDefaults_LastAppVersion = @"kNSUserDefaults_LastVersion";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion = @"kNSUserDefaults_LastCompletedLaunchAppVersion";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp
    = @"kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion_SAE
    = @"kNSUserDefaults_LastCompletedLaunchAppVersion_SAE";

@interface AppVersion ()

@property (atomic) NSString *firstAppVersion;
@property (atomic) NSString *lastAppVersion;
@property (atomic) NSString *currentAppVersion;

@property (atomic) NSString *lastCompletedLaunchAppVersion;
@property (atomic) NSString *lastCompletedLaunchMainAppVersion;
@property (atomic) NSString *lastCompletedLaunchSAEAppVersion;

@end

#pragma mark -

@implementation AppVersion

+ (instancetype)sharedInstance
{
    static AppVersion *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [AppVersion new];
        [instance configure];
    });
    return instance;
}

- (void)configure {
    OWSAssertIsOnMainThread();

    self.currentAppVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    // The version of the app when it was first launched.
    // nil if the app has never been launched before.
    self.firstAppVersion = [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_FirstAppVersion];
    // The version of the app the last time it was launched.
    // nil if the app has never been launched before.
    self.lastAppVersion = [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_LastAppVersion];
    self.lastCompletedLaunchAppVersion =
        [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_LastCompletedLaunchAppVersion];
    self.lastCompletedLaunchMainAppVersion =
        [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp];
    self.lastCompletedLaunchSAEAppVersion =
        [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_LastCompletedLaunchAppVersion_SAE];

    // Ensure the value for the "first launched version".
    if (!self.firstAppVersion) {
        self.firstAppVersion = self.currentAppVersion;
        [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion forKey:kNSUserDefaults_FirstAppVersion];
    }
    
    // Update the value for the "most recently launched version".
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion forKey:kNSUserDefaults_LastAppVersion];
    [[NSUserDefaults appUserDefaults] synchronize];

    DDLogInfo(@"%@ firstAppVersion: %@", self.logTag, self.firstAppVersion);
    DDLogInfo(@"%@ lastAppVersion: %@", self.logTag, self.lastAppVersion);
    DDLogInfo(@"%@ currentAppVersion: %@ (%@)",
        self.logTag,
        self.currentAppVersion,
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]);

    DDLogInfo(@"%@ lastCompletedLaunchAppVersion: %@", self.logTag, self.lastCompletedLaunchAppVersion);
    DDLogInfo(@"%@ lastCompletedLaunchMainAppVersion: %@", self.logTag, self.lastCompletedLaunchMainAppVersion);
    DDLogInfo(@"%@ lastCompletedLaunchSAEAppVersion: %@", self.logTag, self.lastCompletedLaunchSAEAppVersion);
}

- (void)appLaunchDidComplete
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ appLaunchDidComplete", self.logTag);

    self.lastCompletedLaunchAppVersion = self.currentAppVersion;

    // Update the value for the "most recently launch-completed version".
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion
                                         forKey:kNSUserDefaults_LastCompletedLaunchAppVersion];
    [[NSUserDefaults appUserDefaults] synchronize];
}

- (void)mainAppLaunchDidComplete
{
    OWSAssertIsOnMainThread();

    self.lastCompletedLaunchMainAppVersion = self.currentAppVersion;
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion
                                         forKey:kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp];

    [self appLaunchDidComplete];
}

- (void)saeLaunchDidComplete
{
    OWSAssertIsOnMainThread();

    self.lastCompletedLaunchSAEAppVersion = self.currentAppVersion;
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion
                                         forKey:kNSUserDefaults_LastCompletedLaunchAppVersion_SAE];

    [self appLaunchDidComplete];
}

- (BOOL)isFirstLaunch
{
    return self.firstAppVersion != nil;
}

@end
