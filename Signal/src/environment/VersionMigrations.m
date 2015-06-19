//
//  VersionMigrations.m
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"

#import "Environment.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "PreferencesUtil.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "TSAccountManager.h"
#import "RecentCallManager.h"
#import "SignalKeyingStorage.h"
#import "UICKeyChainStore.h"
#import "TSStorageManager.h"
#import "TSDatabaseView.h"

#define IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY @"Migrating from 1.0 to Larger"
#define NEEDS_TO_REGISTER_PUSH_KEY            @"Register For Push"



@interface SignalKeyingStorage(VersionMigrations)

+(void)storeString:(NSString*)string forKey:(NSString*)key;
+(void)storeData:(NSData*)data forKey:(NSString*)key;
@end

@implementation VersionMigrations

#pragma mark Utility methods

+ (void)performUpdateCheck{
    NSString *previousVersion     = Environment.preferences.lastRanVersion;
    NSString *currentVersion      = [Environment.preferences setAndGetCurrentVersion];
    BOOL     isCurrentlyMigrating = [VersionMigrations isMigratingTo2Dot0];
    BOOL     needsToRegisterPush  = [VersionMigrations needsRegisterPush];
    BOOL     VOIPRegistration     = [[PushManager sharedManager] supportsVOIPPush]
                                    && ![Environment.preferences hasRegisteredVOIPPush];
    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        return;
    }
    
    if(([self isVersion:previousVersion atLeast:@"1.0.2" andLessThan:@"2.0"]) || isCurrentlyMigrating) {
        [VersionMigrations migrateFrom1Dot0Dot2ToVersion2Dot0];
    }
    
    if(([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.0.18"])) {
        [VersionMigrations migrateBloomFilter];
    }
    
    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.0.21"] || needsToRegisterPush) {
        [self clearVideoCache];
        [self blockingPushRegistration];
    }
    
    if (VOIPRegistration && [TSAccountManager isRegistered]) {
        [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSData *voipToken, NSString *signupToken) {
            [TSAccountManager registerWithRedPhoneToken:signupToken
                                              pushToken:pushToken
                                              voipToken:voipToken
                                                success:^{[Environment.preferences setHasRegisteredVOIPPush:YES];}
                                                failure:^(NSError *error) {
                DDLogError(@"Couldn't register with TextSecure server: %@", error.debugDescription);
            }];
        } failure:^(NSError *error) {
            DDLogError(@"Couldn't register with RedPhone server.");
        }];
    }
}

+ (BOOL)isMigrating{
    return [self isMigratingTo2Dot0];
}

+ (BOOL) isVersion:(NSString *)thisVersionString atLeast:(NSString *)openLowerBoundVersionString andLessThan:(NSString *)closedUpperBoundVersionString {
    return [self isVersion:thisVersionString atLeast:openLowerBoundVersionString] && [self isVersion:thisVersionString lessThan:closedUpperBoundVersionString];
}

+ (BOOL) isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString {
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] != NSOrderedAscending;
}

+ (BOOL) isVersion:(NSString *)thisVersionString lessThan:(NSString *)thatVersionString {
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] == NSOrderedAscending;
}

+ (void)clearUserDefaults{
    NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];
    
    [Environment.preferences setAndGetCurrentVersion];
    [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark 2.0.1

+ (void)migrateBloomFilter {
    // The bloom filter had to be moved to the cache folder after rejection of the 2.0.1
    NSString *oldBloomKey = @"Directory Bloom Data";
    [[Environment preferences] setValueForKey:oldBloomKey toValue:nil];
    return;
}

#pragma mark 2.0

+ (void)migrateFrom1Dot0Dot2ToVersion2Dot0 {
    
    if (!([self wasRedPhoneRegistered] || [self isMigratingTo2Dot0])) {
        return;
    }
    
    if ([self wasRedPhoneRegistered]) {
        [self migrateRecentCallsToVersion2Dot0];
        [self migrateKeyingStorageToVersion2Dot0];
        [self clearUserDefaults];
    }
    
    [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:YES];
    
    UIAlertController *waitingController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTER_TEXTSECURE_COMPONENT", nil)
                                                                               message:nil
                                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:waitingController animated:YES completion:nil];
    
    [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSData *voipToken, NSString *signupToken) {
        [TSAccountManager registerWithRedPhoneToken:signupToken pushToken:pushToken voipToken:voipToken success:^{
            [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:NO];
            [self clearMigrationFlag];
            Environment *env = [Environment getCurrent];
            PhoneNumberDirectoryFilterManager *manager = [env phoneDirectoryManager];
            [manager forceUpdate];
            [waitingController dismissViewControllerAnimated:YES completion:nil];
        } failure:^(NSError *error) {
            [self refreshLock:waitingController];
            DDLogError(@"Couldn't register with TextSecure server: %@", error.debugDescription);
        }];
    } failure:^(NSError *error) {
        [self refreshLock:waitingController];
        DDLogError(@"Couldn't register with RedPhone server.");
    }];
}

+ (void)refreshLock:(UIAlertController*)waitingController {
    [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:NO];
    [waitingController dismissViewControllerAnimated:NO completion:^{
        UIAlertController *retryController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTER_TEXTSECURE_FAILED_TITLE", nil)
                                                                                 message:NSLocalizedString(@"REGISTER_TEXTSECURE_FAILED", nil)
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        
        [retryController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"REGISTER_FAILED_TRY_AGAIN", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [self migrateFrom1Dot0Dot2ToVersion2Dot0];
                                                          }]];
        
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:retryController animated:YES completion:nil];
    }];
}

+ (void) migrateRecentCallsToVersion2Dot0 {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *encodedData = [defaults objectForKey:RECENT_CALLS_DEFAULT_KEY];
    id data = [NSKeyedUnarchiver unarchiveObjectWithData:encodedData];
    
    if(![data isKindOfClass:NSArray.class]) {
        return;
    } else {
        NSMutableArray *allRecents = [NSMutableArray arrayWithArray:data];
        
        for (RecentCall* recentCall in allRecents) {
            [Environment.getCurrent.recentCallManager addRecentCall:recentCall];
        }
    }
}

+(BOOL)wasRedPhoneRegistered{
    BOOL hasLocalNumber    = [UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY]!=nil;
    BOOL hasPassKey        = [UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY]!=nil;
    BOOL hasSignaling      = [UICKeyChainStore dataForKey:SIGNALING_MAC_KEY]!=nil;
    BOOL hasCipherKey      = [UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY]!=nil;
    BOOL hasZIDKey         = [UICKeyChainStore dataForKey:ZID_KEY]!=nil;
    BOOL hasSignalingExtra = [UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY]!=nil;
    
    BOOL registered = [[NSUserDefaults.standardUserDefaults objectForKey:@"isRegistered"] boolValue];
    
    return registered && hasLocalNumber && hasPassKey && hasSignaling
    && hasCipherKey && hasZIDKey && hasSignalingExtra;
}

+ (void)migrateKeyingStorageToVersion2Dot0{
    // if statements ensure that if this migration is called more than once for whatever reason, the original data isn't rewritten the second time
    if([UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY]!=nil) {
        [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY] forKey:LOCAL_NUMBER_KEY];
    }
    if([UICKeyChainStore stringForKey:PASSWORD_COUNTER_KEY]!=nil) {
        [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:PASSWORD_COUNTER_KEY] forKey:PASSWORD_COUNTER_KEY];
    }
    if([UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY]!=nil) {
        [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY] forKey:SAVED_PASSWORD_KEY];
    }
    if([UICKeyChainStore dataForKey:SIGNALING_MAC_KEY]!=nil) {
        [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_MAC_KEY] forKey:SIGNALING_MAC_KEY];
    }
    if([UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY]!=nil) {
        [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY] forKey:SIGNALING_CIPHER_KEY];
    }
    if([UICKeyChainStore dataForKey:ZID_KEY]!=nil) {
        [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:ZID_KEY] forKey:ZID_KEY];
    }
    if([UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY]!=nil) {
        [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY] forKey:SIGNALING_EXTRA_KEY];
    }
    // Erasing keys in the old key chain store
    [UICKeyChainStore removeItemForKey:LOCAL_NUMBER_KEY];
    [UICKeyChainStore removeItemForKey:PASSWORD_COUNTER_KEY];
    [UICKeyChainStore removeItemForKey:SAVED_PASSWORD_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_MAC_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_CIPHER_KEY];
    [UICKeyChainStore removeItemForKey:ZID_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_EXTRA_KEY];
}

+ (BOOL)isMigratingTo2Dot0{
    return [self userDefaultsBoolForKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
}

+ (void)clearMigrationFlag{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
}

#pragma mark Upgrading to 2.1 - Needs to register VOIP token + Removing video cache folder

+ (void)blockingPushRegistration{
    [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:YES];
    [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:NEEDS_TO_REGISTER_PUSH_KEY];
    
    UIAlertController *waitingController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Upgrading Signal ...", nil)
                                                                               message:nil
                                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:waitingController
                                                                                 animated:YES
                                                                               completion:nil];
    
    __block failedPushRegistrationBlock failure = ^(NSError *error) {
        [self refreshPushLock:waitingController];
    };
    
    [[PushManager sharedManager] requestPushTokenWithSuccess:^(NSData *pushToken, NSData *voipToken) {
        [TSAccountManager registerForPushNotifications:pushToken voipToken:voipToken success:^{
            [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:NO];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:NEEDS_TO_REGISTER_PUSH_KEY];
            [waitingController dismissViewControllerAnimated:YES completion:nil];
        } failure:failure];
    } failure:failure];
}

+ (void)refreshPushLock:(UIAlertController*)waitingController {
    [UIApplication.sharedApplication setNetworkActivityIndicatorVisible:NO];
    [waitingController dismissViewControllerAnimated:NO completion:^{
        UIAlertController *retryController = [UIAlertController alertControllerWithTitle:@"Upgrading Signal failed"
                                                                                 message:@"An error occured while upgrading, please try again."
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        
        [retryController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"REGISTER_FAILED_TRY_AGAIN", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [self blockingPushRegistration];
                                                          }]];
        
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:retryController
                                                                                     animated:YES
                                                                                   completion:nil];
    }];
}

+ (BOOL)needsRegisterPush {
    return [self userDefaultsBoolForKey:NEEDS_TO_REGISTER_PUSH_KEY];
}

+ (void)clearVideoCache {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath = [basePath stringByAppendingPathComponent:@"videos"];
    
    NSError *error;
    if([[NSFileManager defaultManager] fileExistsAtPath:basePath]){
        [NSFileManager.defaultManager removeItemAtPath:basePath error:&error];
    }
    DDLogError(@"An error occured while removing the videos cache folder from old location: %@",
               error.debugDescription);
}

+ (BOOL)userDefaultsBoolForKey:(NSString*)key {
    NSNumber *num = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    
    if (!num) {
        return NO;
    } else {
        return [num boolValue];
    }
}

@end
