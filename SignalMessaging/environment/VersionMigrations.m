//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "VersionMigrations.h"
#import "Environment.h"
#import "OWSDatabaseMigrationRunner.h"
#import "SignalKeyingStorage.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SessionServiceKit/AppContext.h>
#import <SessionServiceKit/AppVersion.h>
#import <SessionServiceKit/NSUserDefaults+OWS.h>
#import <SessionServiceKit/OWSPrimaryStorage+Loki.h>
#import <SessionServiceKit/OWSRequestFactory.h>
#import <SessionServiceKit/TSAccountManager.h>
#import <SessionServiceKit/TSNetworkManager.h>
#import <SessionServiceKit/TSThread.h>
#import <SessionServiceKit/TSGroupThread.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

#define NEEDS_TO_REGISTER_PUSH_KEY @"Register For Push"
#define NEEDS_TO_REGISTER_ATTRIBUTES @"Register Attributes"

@interface SignalKeyingStorage (VersionMigrations)

+ (void)storeString:(NSString *)string forKey:(NSString *)key;
+ (void)storeData:(NSData *)data forKey:(NSString *)key;

@end

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
        OWSLogInfo(@"No previous version found. Probably first launch since install - nothing to migrate.");
        OWSDatabaseMigrationRunner *runner = [[OWSDatabaseMigrationRunner alloc] init];
        [runner assumeAllExistingMigrationsRun];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
        return;
    }

    /*
    if ([self isVersion:previousVersion atLeast:@"1.0.2" andLessThan:@"2.0"]) {
        OWSLogError(@"Migrating from RedPhone no longer supported. Quitting.");
        // Not translating these as so few are affected.
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"You must reinstall Signal"
                             message:
                                 @"Sorry, your installation is too old for us to update. You'll have to start fresh."
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *quitAction = [UIAlertAction actionWithTitle:@"Quit"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *_Nonnull action) {
                                                               OWSFail(@"Obsolete install.");
                                                           }];
        [alert addAction:quitAction];

        [CurrentAppContext().frontmostViewController presentAlert:alert];
    }
     */

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.1.70"] && [self.tsAccountManager isRegistered]) {
        [self clearVideoCache];
    }

    if ([self isVersion:previousVersion atLeast:@"2.0.0" andLessThan:@"2.3.0"] && [self.tsAccountManager isRegistered]) {
        [self clearBloomFilterCache];
    }
    
    // Loki
    if ([self isVersion:previousVersion lessThan:@"1.2.1"] && [self.tsAccountManager isRegistered]) {
        [self updatePublicChatMapping];
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
            } error:nil];
            OWSLogInfo(@"Removed all TSRecipient records - will be replaced by SignalRecipients at next address sync.");
        } else {
            OWSLogError(@"Failed to remove bloom filter cache with error: %@", deleteError.localizedDescription);
        }
    } else {
        OWSLogDebug(@"No bloom filter cache to remove.");
    }
}

# pragma mark Loki - Upgrading to Public Chat Manager

// Versions less than or equal to 1.2.0 didn't store public chat mappings
+ (void)updatePublicChatMapping
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        for (LKPublicChat *chat in LKPublicChatAPI.defaultChats) {
            TSGroupThread *thread = [TSGroupThread threadWithGroupId:[LKGroupUtilities getEncodedOpenGroupIDAsData:chat.id] transaction:transaction];
            if (thread != nil) {
                [LKDatabaseUtilities setPublicChat:chat threadID:thread.uniqueId transaction:transaction];
            } else {
                // Update the group type and group ID for private group chat version.
                // If the thread is still using the old group ID, it needs to be updated.
                thread = [TSGroupThread threadWithGroupId:chat.idAsData transaction:transaction];
                if (thread != nil) {
                    thread.groupModel.groupType = openGroup;
                    [thread.groupModel updateGroupId:[LKGroupUtilities getEncodedOpenGroupIDAsData:chat.id]];
                    [thread saveWithTransaction:transaction];
                    [LKDatabaseUtilities setPublicChat:chat threadID:thread.uniqueId transaction:transaction];
                }
            }
        }
        // Update RSS feeds here
        LKRSSFeed *lokiNewsFeed = [[LKRSSFeed alloc] initWithId:@"loki.network.feed" server:@"https://loki.network/feed/" displayName:NSLocalizedString(@"Loki News", @"") isDeletable:true];
        LKRSSFeed *lokiMessengerUpdatesFeed = [[LKRSSFeed alloc] initWithId:@"loki.network.messenger-updates.feed" server:@"https://loki.network/category/messenger-updates/feed/" displayName:NSLocalizedString(@"Session Updates", @"") isDeletable:false];
        NSArray *feeds = @[ lokiNewsFeed, lokiMessengerUpdatesFeed ];
        for (LKRSSFeed *feed in feeds) {
            TSGroupThread *thread = [TSGroupThread threadWithGroupId:[feed.id dataUsingEncoding:NSUTF8StringEncoding] transaction:transaction];
            if (thread != nil) {
                thread.groupModel.groupType = rssFeed;
                [thread.groupModel updateGroupId:[LKGroupUtilities getEncodedRSSFeedIDAsData:feed.id]];
                [thread saveWithTransaction:transaction];
            }
        }
    } error:nil];
}

@end

NS_ASSUME_NONNULL_END
