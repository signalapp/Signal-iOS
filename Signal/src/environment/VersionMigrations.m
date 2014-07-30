//
//  VersionMigrations.m
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"

@implementation VersionMigrations

+ (void)migrationFrom1Dot0Dot2toLarger{
    // Read everything in preference file, drop into NSUserDefaults
    
    NSString* documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"/Documents/"];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist", documentsDirectory, @"RedPhone-Data"];
    
    NSData *plistData = [NSData dataWithContentsOfFile:path];
    
    NSString *error;
    NSPropertyListFormat format;
    NSDictionary *dict = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
    
    NSLog(@"%@", dict);
    NSArray *entries = [dict allKeys];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    for (NSUInteger i = 0; i < [entries count]; i++) {
        NSString *key = [entries objectAtIndex:i];
        [defaults setObject:[dict objectForKey:key] forKey:key];
    }
    
    [defaults synchronize];
    
    // delete
}

@end
