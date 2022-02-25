//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"
#import "OWSDatabaseMigrationRunner.h"
#import <SessionUtilitiesKit/AppContext.h>
#import <SignalUtilitiesKit/AppVersion.h>
#import <SessionUtilitiesKit/NSUserDefaults+OWS.h>
#import <SignalUtilitiesKit/OWSPrimaryStorage+Loki.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionMessagingKit/TSThread.h>
#import <SessionMessagingKit/TSGroupThread.h>
#import <YapDatabase/YapDatabase.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#define NEEDS_TO_REGISTER_PUSH_KEY @"Register For Push"
#define NEEDS_TO_REGISTER_ATTRIBUTES @"Register Attributes"

@implementation VersionMigrations

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark - Utility methods

+ (void)performUpdateCheckWithCompletion:(VersionMigrationCompletion)completion
{
    OWSLogInfo(@"");

    // performUpdateCheck must be invoked after Environment has been initialized because
    // upgrade process may depend on Environment.
    OWSAssertDebug(Environment.shared);
    OWSAssertDebug(completion);

    NSString *previousVersion = AppVersion.sharedInstance.lastAppVersion;
    NSString *currentVersion = AppVersion.sharedInstance.currentAppVersion;

    OWSLogInfo(@"Checking migrations. currentVersion: %@, lastRanVersion: %@", currentVersion, previousVersion);

    if (!previousVersion) {
        // Note: We need to run the migrations here anyway to ensure that they don't run on subsequent launches
        // and result in unexpected data changes (eg. 'MessageRequestsMigration' auto-approves all threads
        // if this happens on the 2nd launch then any threads created during the 1st launch which haven't
        // been approved would get auto-approved, allowing the user to use contacts which haven't approved
        // comms to appear as options when creating closed groups)
        OWSLogInfo(@"No previous version found. Probably first launch since install - running migrations so they don't run on second launch.");
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[[OWSDatabaseMigrationRunner alloc] init] runAllOutstandingWithCompletion:completion];
        });
        return;
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.1.70"] && [self.tsAccountManager isRegistered]) {
        [self clearVideoCache];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.3.0"] && [self.tsAccountManager isRegistered]) {
        [self clearBloomFilterCache];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[[OWSDatabaseMigrationRunner alloc] init] runAllOutstandingWithCompletion:completion];
    });
}

+ (BOOL)isVersion:(NSString *)thisVersionString
          atLeast:(NSString *)openLowerBoundVersionString
      andLessThan:(NSString *)closedUpperBoundVersionString
{
    return [self isVersion:thisVersionString atLeast:openLowerBoundVersionString] &&
        [self isVersion:thisVersionString lessThan:closedUpperBoundVersionString];
}

+ (BOOL)isVersion:(NSString *)thisVersionString atLeast:(NSString *)thatVersionString
{
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] != NSOrderedAscending;
}

+ (BOOL)isVersion:(NSString *)thisVersionString lessThan:(NSString *)thatVersionString
{
    return [thisVersionString compare:thatVersionString options:NSNumericSearch] == NSOrderedAscending;
}

#pragma mark Upgrading to 2.1 - Removing video cache folder

+ (void)clearVideoCache
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath = [basePath stringByAppendingPathComponent:@"videos"];

    NSError *error;
    if ([[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [NSFileManager.defaultManager removeItemAtPath:basePath error:&error];
    }

    if (error) {
        OWSLogError(
            @"An error occured while removing the videos cache folder from old location: %@", error.debugDescription);
    }
}

#pragma mark Upgrading to 2.3.0

// We removed bloom filter contact discovery. Clean up any local bloom filter data.
+ (void)clearBloomFilterCache
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *cachesDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *bloomFilterPath = [[cachesDir objectAtIndex:0] stringByAppendingPathComponent:@"bloomfilter"];

    if ([fm fileExistsAtPath:bloomFilterPath]) {
        NSError *deleteError;
        if ([fm removeItemAtPath:bloomFilterPath error:&deleteError]) {
            OWSLogInfo(@"Successfully removed bloom filter cache.");
            [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [transaction removeAllObjectsInCollection:@"TSRecipient"];
            }];
            OWSLogInfo(@"Removed all TSRecipient records - will be replaced by SignalRecipients at next address sync.");
        } else {
            OWSLogError(@"Failed to remove bloom filter cache with error: %@", deleteError.localizedDescription);
        }
    } else {
        OWSLogDebug(@"No bloom filter cache to remove.");
    }
}

@end

NS_ASSUME_NONNULL_END
