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
#import "PushManager.h"
#import "TSAccountManager.h"
#import "RecentCallManager.h"
#import "SignalKeyingStorage.h"
#import "UICKeyChainStore.h"
#import "TSStorageManager.h"
#import "TSDatabaseView.h"

#define IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY @"Migrating from 1.0 to Larger"

@interface SignalKeyingStorage(VersionMigrations)

+(void)storeString:(NSString*)string forKey:(NSString*)key;
+(void)storeData:(NSData*)data forKey:(NSString*)key;
@end

@implementation VersionMigrations

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
    
    [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSString *signupToken) {
        [TSAccountManager registerWithRedPhoneToken:signupToken pushToken:pushToken success:^{
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

#pragma mark helper methods
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

+ (void)clearUserDefaults{
    NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];
    
    [Environment.preferences setAndGetCurrentVersion];
    [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isMigratingTo2Dot0{
    NSNumber *num = [[NSUserDefaults standardUserDefaults] objectForKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
    
    if (!num) {
        return NO;
    } else {
        return [num boolValue];
    }
}

+ (void)clearMigrationFlag{
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:IS_MIGRATING_FROM_1DOT0_TO_LARGER_KEY];
}

@end
