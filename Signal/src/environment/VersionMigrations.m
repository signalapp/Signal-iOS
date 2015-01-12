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

@interface SignalKeyingStorage(VersionMigrations)

+(void)storeString:(NSString*)string forKey:(NSString*)key;
+(void)storeData:(NSData*)data forKey:(NSString*)key;
@end

@implementation VersionMigrations

+ (void)migrateFrom1Dot0Dot2ToVersion2Dot0 {
    [Environment.preferences setIsMigratingToVersion2Dot0:YES];
    [self migrateFrom1Dot0Dot2ToGreater];
    [self migrateRecentCallsToVersion2Dot0]; 
    [self migrateKeyingStorageToVersion2Dot0];
    [PushManager.sharedManager registrationAndRedPhoneTokenRequestWithSuccess:^(NSData *pushToken, NSString *signupToken) {
        [TSAccountManager registerWithRedPhoneToken:signupToken pushToken:pushToken success:^{
            Environment *env = [Environment getCurrent];
            PhoneNumberDirectoryFilterManager *manager = [env phoneDirectoryManager];
            [manager forceUpdate];
            [Environment.preferences setIsMigratingToVersion2Dot0:NO];
        } failure:^(NSError *error) {
            // TODO: should we have a UI response here?
        }];
    } failure:^{
        // TODO: should we have a UI response here?
    }];

    
}

+ (void)migrateFrom1Dot0Dot2ToGreater {
    
    // Preferences were stored in both a preference file and a plist in the documents folder, as a temporary measure, we are going to move all the preferences to the NSUserDefaults preference store, those will be migrated to a SQLCipher-backed database
    
    NSString* documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"/Documents/"];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist", documentsDirectory, @"RedPhone-Data"];
    
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSData *plistData = [NSData dataWithContentsOfFile:path];
        
        NSError *error;
        NSPropertyListFormat format;
        NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:&format error:&error];
        
        
        NSArray *entries = [dict allKeys];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        
        for (NSUInteger i = 0; i < entries.count; i++) {
            NSString *key = entries[i];
            [defaults setObject:dict[key] forKey:key];
        }
        
        [defaults synchronize];
        
        [NSFileManager.defaultManager removeItemAtPath:path error:&error];
        
        if (error) {
            DDLogError(@"Error while migrating data: %@", error.description);
        }
        
        // Some users push IDs were not correctly registered, by precaution, we are going to re-register all of them
        
        [PushManager.sharedManager registrationWithSuccess:^{
            
        } failure:^{
            DDLogError(@"Error re-registering on migration from 1.0.2");
        }];
        
        [NSFileManager.defaultManager removeItemAtPath:path error:&error];
        
        if (error) {
            DDLogError(@"Error upgrading from 1.0.2 : %@", error.description);
        }
    }
    
    return;
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
        // Erasing recent calls in the defaults
        NSUserDefaults *localDefaults = NSUserDefaults.standardUserDefaults;
        NSData *saveData = [NSKeyedArchiver archivedDataWithRootObject:[NSMutableArray array]];
        [localDefaults setObject:saveData forKey:RECENT_CALLS_DEFAULT_KEY];
        [localDefaults synchronize];
        
    }
}


+ (void)migrateKeyingStorageToVersion2Dot0{
    [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY] forKey:LOCAL_NUMBER_KEY];
    [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:PASSWORD_COUNTER_KEY] forKey:PASSWORD_COUNTER_KEY];
    [SignalKeyingStorage storeString:[UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY] forKey:SAVED_PASSWORD_KEY];
    
    [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_MAC_KEY] forKey:SIGNALING_MAC_KEY];
    [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY] forKey:SIGNALING_CIPHER_KEY];
    [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:ZID_KEY] forKey:ZID_KEY];
    [SignalKeyingStorage storeData:[UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY] forKey:SIGNALING_EXTRA_KEY];
    
    // Erasing keys in the old key chain store
    [UICKeyChainStore removeItemForKey:LOCAL_NUMBER_KEY];
    [UICKeyChainStore removeItemForKey:PASSWORD_COUNTER_KEY];
    [UICKeyChainStore removeItemForKey:SAVED_PASSWORD_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_MAC_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_CIPHER_KEY];
    [UICKeyChainStore removeItemForKey:ZID_KEY];
    [UICKeyChainStore removeItemForKey:SIGNALING_EXTRA_KEY];
    
}

@end
