//
//  VersionMigrations.m
//  Signal
//
//  Created by Frederic Jacobs on 29/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"

#import "Environment.h"
#import "LockInteractionController.h"
#import "PreferencesUtil.h"
#import "PushManager.h"
#import "RecentCallManager.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "TSNetworkManager.h"

#define NEEDS_TO_REGISTER_PUSH_KEY @"Register For Push"
#define NEEDS_TO_REGISTER_ATTRIBUTES @"Register Attributes"

@interface SignalKeyingStorage (VersionMigrations)

+ (void)storeString:(NSString *)string forKey:(NSString *)key;
+ (void)storeData:(NSData *)data forKey:(NSString *)key;
@end

@implementation VersionMigrations

#pragma mark Utility methods

+ (void)performUpdateCheck {
    NSString *previousVersion = Environment.preferences.lastRanVersion;
    NSString *currentVersion  = [Environment.preferences setAndGetCurrentVersion];
    BOOL VOIPRegistration =
        [[PushManager sharedManager] supportsVOIPPush] && ![Environment.preferences hasRegisteredVOIPPush];

    if (!previousVersion) {
        DDLogError(@"No previous version found. Possibly first launch since install.");
        return;
    }

    if (([self isVersion:previousVersion atLeast:@"1.0.2" andLessThan:@"2.0"])) {
        // We don't migrate from RedPhone anymore, too painful to maintain.
        // Resetting the app data and quitting.
        [Environment resetAppData];
        exit(0);
    }

    // VOIP Push might need to be enabled because 1) user ran old version 2) Update to compatible iOS version
    if (VOIPRegistration && [TSAccountManager isRegistered]) {
        [self nonBlockingPushRegistration];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.1.70"] && [TSAccountManager isRegistered]) {
        [self clearVideoCache];
        [self blockingAttributesUpdate];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.3.0"] && [TSAccountManager isRegistered]) {
        NSFileManager *fm         = [NSFileManager defaultManager];
        NSArray *cachesDir        = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *bloomFilterPath = [[cachesDir objectAtIndex:0] stringByAppendingPathComponent:@"bloomfilter"];
        [fm removeItemAtPath:bloomFilterPath error:nil];
        [[TSStorageManager sharedManager]
                .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
          [transaction removeAllObjectsInCollection:@"TSRecipient"];
        }];
    }
}

+ (BOOL)isVersion:(NSString *)thisVersionString
          atLeast:(NSString *)openLowerBoundVersionString
      andLessThan:(NSString *)closedUpperBoundVersionString {
    return [self isVersion:thisVersionString atLeast:openLowerBoundVersionString] &&
           [self isVersion:thisVersionString lessThan:closedUpperBoundVersionString];
}

+ (BOOL)isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString {
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] != NSOrderedAscending;
}

+ (BOOL)isVersion:(NSString *)thisVersionString lessThan:(NSString *)thatVersionString {
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] == NSOrderedAscending;
}

#pragma mark Upgrading to 2.1 - Needs to register VOIP token + Removing video cache folder

+ (void)nonBlockingPushRegistration {
    __block failedBlock failedBlock = ^(NSError *error) {
      DDLogError(@"Failed to register VOIP push token: %@", error.debugDescription);
    };
    [[PushManager sharedManager] requestPushTokenWithSuccess:^(NSString *pushToken, NSString *voipToken) {
      [TSAccountManager registerForPushNotifications:pushToken
                                           voipToken:voipToken
                                             success:^{
                                               DDLogWarn(@"Registered for VOIP Push.");
                                             }
                                             failure:failedBlock];
    }
                                                     failure:failedBlock];
}

+ (void)blockingPushRegistration {
    LIControllerBlockingOperation blockingOperation = ^BOOL(void) {
      [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:NEEDS_TO_REGISTER_PUSH_KEY];

      __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);

      __block BOOL success;

      __block failedBlock failedBlock = ^(NSError *error) {
        success = NO;
        dispatch_semaphore_signal(sema);
      };

      [[PushManager sharedManager] requestPushTokenWithSuccess:^(NSString *pushToken, NSString *voipToken) {
        [TSAccountManager registerForPushNotifications:pushToken
                                             voipToken:voipToken
                                               success:^{
                                                 success = YES;
                                                 dispatch_semaphore_signal(sema);
                                               }
                                               failure:failedBlock];
      }
                                                       failure:failedBlock];

      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

      return success;
    };

    LIControllerRetryBlock retryBlock = [LockInteractionController defaultNetworkRetry];

    [LockInteractionController performBlock:blockingOperation
                            completionBlock:^{
                              [[NSUserDefaults standardUserDefaults] removeObjectForKey:NEEDS_TO_REGISTER_PUSH_KEY];
                              DDLogWarn(@"Successfully migrated to 2.1");
                            }
                                 retryBlock:retryBlock
                                usesNetwork:YES];
}

+ (BOOL)needsRegisterPush {
    return [self userDefaultsBoolForKey:NEEDS_TO_REGISTER_PUSH_KEY];
}

+ (void)clearVideoCache {
    NSArray *paths     = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath           = [basePath stringByAppendingPathComponent:@"videos"];

    NSError *error;
    if ([[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [NSFileManager.defaultManager removeItemAtPath:basePath error:&error];
    }

    if (error) {
        DDLogError(@"An error occured while removing the videos cache folder from old location: %@",
                   error.debugDescription);
    }
}

#pragma mark Upgrading to 2.1.3 - Adding VOIP flag on TS Server

+ (BOOL)needsRegisterAttributes {
    return [self userDefaultsBoolForKey:NEEDS_TO_REGISTER_ATTRIBUTES] && [TSAccountManager isRegistered];
}

+ (void)blockingAttributesUpdate {
    LIControllerBlockingOperation blockingOperation = ^BOOL(void) {
      [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:NEEDS_TO_REGISTER_ATTRIBUTES];

      __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);

      __block BOOL success;

      TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc] initWithUpdatedAttributesWithVoice:YES];
      [[TSNetworkManager sharedManager] makeRequest:request
          success:^(NSURLSessionDataTask *task, id responseObject) {
            success = YES;
            dispatch_semaphore_signal(sema);
          }
          failure:^(NSURLSessionDataTask *task, NSError *error) {
            success = NO;
            DDLogError(@"Updating attributess failed with error: %@", error.description);
            dispatch_semaphore_signal(sema);
          }];


      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

      return success;
    };

    LIControllerRetryBlock retryBlock = [LockInteractionController defaultNetworkRetry];

    [LockInteractionController performBlock:blockingOperation
                            completionBlock:^{
                              [[NSUserDefaults standardUserDefaults] removeObjectForKey:NEEDS_TO_REGISTER_ATTRIBUTES];
                              DDLogWarn(@"Successfully updated attributes.");
                            }
                                 retryBlock:retryBlock
                                usesNetwork:YES];
}

#pragma mark Util

+ (BOOL)userDefaultsBoolForKey:(NSString *)key {
    NSNumber *num = [[NSUserDefaults standardUserDefaults] objectForKey:key];

    if (!num) {
        return NO;
    } else {
        return [num boolValue];
    }
}

@end
