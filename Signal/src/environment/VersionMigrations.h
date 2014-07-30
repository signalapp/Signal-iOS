//
//  VersionMigrations.h
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VersionMigrations : NSObject

+ (void)migrationFrom1Dot0Dot2toLarger;

@end
