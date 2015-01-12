//
//  VersionMigrations.h
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VersionMigrations : NSObject

+ (void)migrateFrom1Dot0Dot2ToGreater;
+ (void)migrateFrom1Dot0Dot2ToVersion2Dot0;

@end
