//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#define RECENT_CALLS_DEFAULT_KEY @"RPRecentCallsDefaultKey"

@interface VersionMigrations : NSObject

+ (void)performUpdateCheck;

+ (BOOL)isVersion:(NSString *)thisVersionString
          atLeast:(NSString *)openLowerBoundVersionString
      andLessThan:(NSString *)closedUpperBoundVersionString;

+ (BOOL)isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString;

+ (BOOL)isVersion:(NSString *)thisVersionString lessThan:(NSString *)thatVersionString;

@end
