//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

#define RECENT_CALLS_DEFAULT_KEY @"RPRecentCallsDefaultKey"

typedef void (^VersionMigrationCompletion)(void);

@interface VersionMigrations : NSObject

+ (void)performUpdateCheckWithCompletion:(VersionMigrationCompletion)completion;

+ (BOOL)isVersion:(NSString *)thisVersionString
          atLeast:(NSString *)openLowerBoundVersionString
      andLessThan:(NSString *)closedUpperBoundVersionString;

+ (BOOL)isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString;

+ (BOOL)isVersion:(NSString *)thisVersionString lessThan:(NSString *)thatVersionString;

@end

NS_ASSUME_NONNULL_END
