//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "AppVersion.h"
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSUserDefaults_FirstAppVersion = @"kNSUserDefaults_FirstAppVersion";
NSString *const kNSUserDefaults_LastAppVersion = @"kNSUserDefaults_LastVersion";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion = @"kNSUserDefaults_LastCompletedLaunchAppVersion";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp
    = @"kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion_SAE
    = @"kNSUserDefaults_LastCompletedLaunchAppVersion_SAE";
NSString *const kNSUserDefaults_LastCompletedLaunchAppVersion_NSE
    = @"kNSUserDefaults_LastCompletedLaunchAppVersion_NSE";

@interface AppVersion ()

@property (atomic) NSString *firstAppVersion;
@property (atomic, nullable) NSString *lastAppVersion;
@property (atomic) NSString *currentAppVersion;
@property (atomic) NSString *currentAppVersionLong;

@property (atomic, nullable) NSString *lastCompletedLaunchAppVersion;
@property (atomic, nullable) NSString *lastCompletedLaunchMainAppVersion;
@property (atomic, nullable) NSString *lastCompletedLaunchSAEAppVersion;
@property (atomic, nullable) NSString *lastCompletedLaunchNSEAppVersion;

@end

#pragma mark -

@implementation AppVersion

+ (instancetype)shared
{
    static AppVersion *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [AppVersion new];
        [instance configure];
    });
    return instance;
}

+ (NSString *)hardwareInfoString
{
    NSString *marketingString = UIDevice.currentDevice.model;
    NSString *machineString = [NSString stringFromSysctlKey:@"hw.machine"];
    NSString *modelString = [NSString stringFromSysctlKey:@"hw.model"];
    return [NSString stringWithFormat:@"%@ (%@; %@)", marketingString, machineString, modelString];
}

+ (NSString *)iOSVersionString
{
    NSString *majorMinor = UIDevice.currentDevice.systemVersion;
    NSString *buildNumber = [NSString stringFromSysctlKey:@"kern.osversion"];
    return [NSString stringWithFormat:@"%@ (%@)", majorMinor, buildNumber];
}

- (void)configure {
    OWSAssertIsOnMainThread();

    self.currentAppVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    self.currentAppVersionLong = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

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
    self.lastCompletedLaunchNSEAppVersion =
        [[NSUserDefaults appUserDefaults] objectForKey:kNSUserDefaults_LastCompletedLaunchAppVersion_NSE];

    // Ensure the value for the "first launched version".
    if (!self.firstAppVersion) {
        self.firstAppVersion = self.currentAppVersion;
        [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion forKey:kNSUserDefaults_FirstAppVersion];
    }
    
    // Update the value for the "most recently launched version".
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion forKey:kNSUserDefaults_LastAppVersion];
    [[NSUserDefaults appUserDefaults] synchronize];

    [self startupLogging];
}

- (void)startupLogging
{
    // The long version string looks like an IPv4 address.
    // To prevent the log scrubber from scrubbing it,
    // we replace . with _.
    NSString *longVersionString = [self.currentAppVersionLong stringByReplacingOccurrencesOfString:@"."
                                                                                        withString:@"_"];

    OWSLogInfo(@"firstAppVersion: %@", self.firstAppVersion);
    OWSLogInfo(@"lastAppVersion: %@", self.lastAppVersion);
    OWSLogInfo(@"currentAppVersion: %@ (%@)", self.currentAppVersion, longVersionString);

    OWSLogInfo(@"lastCompletedLaunchAppVersion: %@", self.lastCompletedLaunchAppVersion);
    OWSLogInfo(@"lastCompletedLaunchMainAppVersion: %@", self.lastCompletedLaunchMainAppVersion);
    OWSLogInfo(@"lastCompletedLaunchSAEAppVersion: %@", self.lastCompletedLaunchSAEAppVersion);
    OWSLogInfo(@"lastCompletedLaunchNSEAppVersion: %@", self.lastCompletedLaunchNSEAppVersion);

    OWSLogInfo(@"iOS Version: %@", [[self class] iOSVersionString]);

    NSString *localeIdentifier = [NSLocale.currentLocale objectForKey:NSLocaleIdentifier];
    if (localeIdentifier.length > 0) {
        OWSLogInfo(@"Locale Identifier: %@", localeIdentifier);
    }
    NSString *countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
    if (countryCode.length > 0) {
        OWSLogInfo(@"Country Code: %@", countryCode);
    }
    NSString *languageCode = [NSLocale.currentLocale objectForKey:NSLocaleLanguageCode];
    if (languageCode.length > 0) {
        OWSLogInfo(@"Language Code: %@", languageCode);
    }

    OWSLogInfo(@"Device Model: %@", [[self class] hardwareInfoString]);

    NSDictionary<NSString *, NSString *> *buildDetails =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildDetails"];
    OWSLogInfo(@"WebRTC Commit: %@", buildDetails[@"WebRTCCommit"]);
    OWSLogInfo(@"Build XCode Version: %@", buildDetails[@"XCodeVersion"]);
    OWSLogInfo(@"Build OS X Version: %@", buildDetails[@"OSXVersion"]);
    OWSLogInfo(@"Build Cocoapods Version: %@", buildDetails[@"CocoapodsVersion"]);
    OWSLogInfo(@"Build Date/Time: %@", buildDetails[@"DateTime"]);
}

- (void)appLaunchDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"appLaunchDidComplete");

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

- (void)nseLaunchDidComplete
{
    OWSAssertIsOnMainThread();

    self.lastCompletedLaunchNSEAppVersion = self.currentAppVersion;
    [[NSUserDefaults appUserDefaults] setObject:self.currentAppVersion
                                         forKey:kNSUserDefaults_LastCompletedLaunchAppVersion_NSE];

    [self appLaunchDidComplete];
}

- (BOOL)isFirstLaunch
{
    return self.firstAppVersion != nil;
}

@end

NS_ASSUME_NONNULL_END
