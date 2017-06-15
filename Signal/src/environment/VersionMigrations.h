//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#define RECENT_CALLS_DEFAULT_KEY @"RPRecentCallsDefaultKey"

@interface VersionMigrations : NSObject

+ (void)performUpdateCheck;

+ (void)runSafeBlockingMigrations;

+ (BOOL)isVersion:(NSString *)thisVersionString
          atLeast:(NSString *)openLowerBoundVersionString
      andLessThan:(NSString *)closedUpperBoundVersionString;

@end
