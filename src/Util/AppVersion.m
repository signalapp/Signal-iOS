//
//  AppVersion.m
//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppVersion.h"

@interface AppVersion ()

@property (nonatomic) NSString *firstAppVersion;
@property (nonatomic) NSString *lastAppVersion;
@property (nonatomic) NSString *currentAppVersion;

@end

#pragma mark -

@implementation AppVersion

+ (instancetype)instance {
    static AppVersion *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [AppVersion new];
        [instance configure];
    });
    return instance;
}

- (void)configure {
    self.currentAppVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    NSString *kNSUserDefaults_FirstAppVersion = @"kNSUserDefaults_FirstAppVersion";
    NSString *kNSUserDefaults_LastAppVersion = @"kNSUserDefaults_LastVersion";
    
    // The version of the app when it was first launched.
    // nil if the app has never been launched before.
    self.firstAppVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kNSUserDefaults_FirstAppVersion];
    // The version of the app the last time it was launched.
    // nil if the app has never been launched before.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
    self.lastAppVersion = [[NSUserDefaults standardUserDefaults] objectForKey:kNSUserDefaults_LastAppVersion];
#pragma clang diagnostic pop
    
    // Ensure the value for the "first launched version".
    if (!self.firstAppVersion) {
        self.firstAppVersion = self.currentAppVersion;
        [[NSUserDefaults standardUserDefaults] setObject:self.currentAppVersion
                                                  forKey:kNSUserDefaults_FirstAppVersion];
    }
    
    // Update the value for the "most recently launched version".
    [[NSUserDefaults standardUserDefaults] setObject:self.currentAppVersion
                                              forKey:kNSUserDefaults_LastAppVersion];
    [[NSUserDefaults standardUserDefaults] synchronize];

    DDLogInfo(@"firstAppVersion: %@", self.firstAppVersion);
    DDLogInfo(@"lastAppVersion: %@", self.lastAppVersion);
    DDLogInfo(@"currentAppVersion: %@", self.currentAppVersion);
}

@end
