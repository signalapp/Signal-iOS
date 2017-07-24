//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"

#import "Environment.h"
#import "LockInteractionController.h"
#import "OWSDatabaseMigrationRunner.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "TSNetworkManager.h"
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/OWSOrphanedDataCleaner.h>

#define NEEDS_TO_REGISTER_PUSH_KEY @"Register For Push"
#define NEEDS_TO_REGISTER_ATTRIBUTES @"Register Attributes"

@interface SignalKeyingStorage (VersionMigrations)

+ (void)storeString:(NSString *)string forKey:(NSString *)key;
+ (void)storeData:(NSData *)data forKey:(NSString *)key;

@end

@implementation VersionMigrations

#pragma mark Utility methods

+ (void)performUpdateCheck
{
    // performUpdateCheck must be invoked after Environment has been initialized because
    // upgrade process may depend on Environment.
    OWSAssert([Environment getCurrent]);

    NSString *previousVersion = AppVersion.instance.lastAppVersion;
    NSString *currentVersion = AppVersion.instance.currentAppVersion;

    DDLogInfo(
        @"%@ Checking migrations. currentVersion: %@, lastRanVersion: %@", self.tag, currentVersion, previousVersion);

    if (!previousVersion) {
        DDLogInfo(@"No previous version found. Probably first launch since install - nothing to migrate.");
        OWSDatabaseMigrationRunner *runner =
            [[OWSDatabaseMigrationRunner alloc] initWithStorageManager:[TSStorageManager sharedManager]];
        [runner assumeAllExistingMigrationsRun];
        return;
    }

    if ([self isVersion:previousVersion atLeast:@"1.0.2" andLessThan:@"2.0"]) {
        DDLogError(@"Migrating from RedPhone no longer supported. Quitting.");
        // Not translating these as so few are affected.
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:@"You must reinstall Signal"
                             message:
                                 @"Sorry, your installation is too old for us to update. You'll have to start fresh."
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *quitAction = [UIAlertAction actionWithTitle:@"Quit"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *_Nonnull action) {
                                                               [DDLog flushLog];
                                                               exit(0);
                                                           }];
        [alertController addAction:quitAction];

        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController
                                                                                     animated:YES
                                                                                   completion:nil];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.1.70"] && [TSAccountManager isRegistered]) {
        [self clearVideoCache];
        [self blockingAttributesUpdate];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.3.0"] && [TSAccountManager isRegistered]) {
        [self clearBloomFilterCache];
    }

#ifdef DEBUG
    // A bug in orphan cleanup could be disastrous so let's only
    // run it in DEBUG builds for a few releases.
    //
    // TODO: Release to production once we have analytics.
    // TODO: Orphan cleanup is somewhat expensive - not least in doing a bunch
    //       of disk access.  We might want to only run it "once per version"
    //       or something like that in production.
    [OWSOrphanedDataCleaner auditAndCleanupAsync:nil];
#endif

    [[[OWSDatabaseMigrationRunner alloc] initWithStorageManager:[TSStorageManager sharedManager]] runAllOutstanding];
}

+ (void)runSafeBlockingMigrations
{
    [[[OWSDatabaseMigrationRunner alloc] initWithStorageManager:[TSStorageManager sharedManager]]
        runSafeBlockingMigrations];
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

#pragma mark Upgrading to 2.1 - Removing video cache folder

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

+ (void)blockingAttributesUpdate {
    LIControllerBlockingOperation blockingOperation = ^BOOL(void) {
      [[NSUserDefaults standardUserDefaults] setObject:@YES forKey:NEEDS_TO_REGISTER_ATTRIBUTES];

      __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);

      __block BOOL success;

      TSUpdateAttributesRequest *request = [[TSUpdateAttributesRequest alloc] initWithUpdatedAttributesWithVoice];
      [[TSNetworkManager sharedManager] makeRequest:request
          success:^(NSURLSessionDataTask *task, id responseObject) {
              success = YES;
              dispatch_semaphore_signal(sema);
          }
          failure:^(NSURLSessionDataTask *task, NSError *error) {
              if (!IsNSErrorNetworkFailure(error)) {
                  OWSProdErrorWNSError(@"error_update_attributes_request_failed", error);
              }
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

#pragma mark Upgrading to 2.3.0

// We removed bloom filter contact discovery. Clean up any local bloom filter data.
+ (void)clearBloomFilterCache {
    NSFileManager *fm         = [NSFileManager defaultManager];
    NSArray *cachesDir        = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *bloomFilterPath = [[cachesDir objectAtIndex:0] stringByAppendingPathComponent:@"bloomfilter"];

    if ([fm fileExistsAtPath:bloomFilterPath]) {
        NSError *deleteError;
        if ([fm removeItemAtPath:bloomFilterPath error:&deleteError]) {
            DDLogInfo(@"Successfully removed bloom filter cache.");
            [[TSStorageManager sharedManager].dbReadWriteConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                    [transaction removeAllObjectsInCollection:@"TSRecipient"];
                }];
            DDLogInfo(@"Removed all TSRecipient records - will be replaced by SignalRecipients at next address sync.");
        } else {
            DDLogError(@"Failed to remove bloom filter cache with error: %@", deleteError.localizedDescription);
        }
    } else {
        DDLogDebug(@"No bloom filter cache to remove.");
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
