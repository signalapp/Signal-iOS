//
//  VersionMigrations.m
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "PushManager.h"
#import "VersionMigrations.h"

@implementation VersionMigrations

+ (void)migrateFrom1Dot0Dot2ToVersion2Dot0{
    
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

@end
