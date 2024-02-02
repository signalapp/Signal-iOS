//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOrphanDataCleaner.h"
#import "OWSProfileManager.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOrphanDataCleaner_LastCleaningVersionKey = @"OWSOrphanDataCleaner_LastCleaningVersionKey";
NSString *const OWSOrphanDataCleaner_LastCleaningDateKey = @"OWSOrphanDataCleaner_LastCleaningDateKey";

@interface OWSOrphanData : NSObject

@property (nonatomic) NSSet<NSString *> *interactionIds;
@property (nonatomic) NSSet<NSString *> *attachmentIds;
@property (nonatomic) NSSet<NSString *> *filePaths;
@property (nonatomic) NSSet<NSString *> *reactionIds;
@property (nonatomic) NSSet<NSString *> *mentionIds;
@property (nonatomic) NSSet<NSString *> *fileAndDirectoryPaths;
@property (nonatomic) BOOL hasOrphanedPacksOrStickers;

@end

#pragma mark -

@implementation OWSOrphanData

@end

#pragma mark -

typedef void (^OrphanDataBlock)(OWSOrphanData *);

@implementation OWSOrphanDataCleaner

+ (SDSKeyValueStore *)keyValueStore
{
    static SDSKeyValueStore *keyValueStore = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *const OWSOrphanDataCleaner_Collection = @"OWSOrphanDataCleaner_Collection";
        keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSOrphanDataCleaner_Collection];
    });
    return keyValueStore;
}

/// Unlike CurrentAppContext().isMainAppAndActive, this method can be safely
/// invoked off the main thread.
+ (BOOL)isMainAppAndActive
{
    return CurrentAppContext().reportedApplicationState == UIApplicationStateActive;
}

+ (long long)fileSizeOfFilePath:(NSString *)filePath
{
    NSError *error;
    NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize];
    if (error) {
        if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == 260) {
            OWSLogWarn(@"can't find size of missing file.");
        } else {
            OWSFailDebug(@"attributesOfItemAtPath: %@ error: %@", filePath, error);
        }
        return 0;
    }
    return fileSize.longLongValue;
}

+ (nullable NSNumber *)fileSizeOfFilePathsSafe:(NSArray<NSString *> *)filePaths
{
    long long result = 0;
    for (NSString *filePath in filePaths) {
        if (!self.isMainAppAndActive) {
            return nil;
        }
        result += [self fileSizeOfFilePath:filePath];
    }
    return @(result);
}

+ (nullable NSSet<NSString *> *)filePathsInDirectorySafe:(NSString *)dirPath
{
    NSMutableSet *filePaths = [NSMutableSet new];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dirPath]) {
        return filePaths;
    }
    NSError *error;
    NSArray<NSString *> *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
    if (error) {
        if ([error hasDomain:NSPOSIXErrorDomain code:ENOENT] ||
            [error hasDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError]) {
            // Races may cause files to be removed while we crawl the directory contents.
            OWSLogWarn(@"Error: %@", error);
        } else {
            OWSFailDebug(@"Error: %@", error);
        }
        return [NSSet new];
    }
    for (NSString *fileName in fileNames) {
        if (!self.isMainAppAndActive) {
            return nil;
        }
        NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
        BOOL isDirectory;
        [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
        if (isDirectory) {
            NSSet<NSString *> *_Nullable dirPaths = [self filePathsInDirectorySafe:filePath];
            if (!dirPaths) {
                return nil;
            }
            [filePaths unionSet:dirPaths];
        } else {
            [filePaths addObject:filePath];
        }
    }
    return filePaths;
}

// This method finds (but does not delete):
//
// * Orphan TSInteractions (with no thread).
// * Orphan TSAttachments (with no message).
// * Orphan attachment files (with no corresponding TSAttachment).
// * Orphan profile avatars.
// * Temporary files (all).
//
// It also finds (we don't clean these up).
//
// * Missing attachment files (cannot be cleaned up).
//   These are attachments which have no file on disk.  They should be extremely rare -
//   the only cases I have seen are probably due to debugging.
//   They can't be cleaned up - we don't want to delete the TSAttachmentStream or
//   its corresponding message.  Better that the broken message shows up in the
//   conversation view.
+ (void)findOrphanDataWithRetries:(NSInteger)remainingRetries
                          success:(OrphanDataBlock)success
                          failure:(dispatch_block_t)failure
{
    if (remainingRetries < 1) {
        OWSLogInfo(@"Aborting orphan data search. No more retries.");
        dispatch_async(self.workQueue, ^{ failure(); });
        return;
    }

    OWSLogInfo(@"Enqueuing an orphan data search. Remaining retries: %ld", (long)remainingRetries);

    // Wait until the app is active...
    [CurrentAppContext() runNowOrWhenMainAppIsActive:^{
        // ...but perform the work off the main thread.
        OWSBackgroundTask *_Nullable backgroundTask =
            [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
        dispatch_async(self.workQueue, ^{
            OWSOrphanData *_Nullable orphanData = [self findOrphanDataSync];
            if (orphanData) {
                success(orphanData);
            } else {
                [self findOrphanDataWithRetries:remainingRetries - 1 success:success failure:failure];
            }
            [backgroundTask endBackgroundTask];
        });
    }];
}

// Returns nil on failure, usually indicating that the search
// aborted due to the app resigning active.  This method is extremely careful to
// abort if the app resigns active, in order to avoid 0xdead10cc crashes.
+ (nullable OWSOrphanData *)findOrphanDataSync
{
    __block BOOL shouldAbort = NO;

    NSString *legacyAttachmentsDirPath = TSAttachmentStream.legacyAttachmentsDirPath;
    NSString *sharedDataAttachmentsDirPath = TSAttachmentStream.sharedDataAttachmentsDirPath;
    NSSet<NSString *> *_Nullable legacyAttachmentFilePaths = [self filePathsInDirectorySafe:legacyAttachmentsDirPath];
    if (!legacyAttachmentFilePaths || !self.isMainAppAndActive) {
        return nil;
    }
    NSSet<NSString *> *_Nullable sharedDataAttachmentFilePaths =
        [self filePathsInDirectorySafe:sharedDataAttachmentsDirPath];
    if (!sharedDataAttachmentFilePaths || !self.isMainAppAndActive) {
        return nil;
    }

    NSString *legacyProfileAvatarsDirPath = OWSUserProfile.legacyProfileAvatarsDirPath;
    NSString *sharedDataProfileAvatarsDirPath = OWSUserProfile.sharedDataProfileAvatarsDirPath;
    NSSet<NSString *> *_Nullable legacyProfileAvatarsFilePaths =
        [self filePathsInDirectorySafe:legacyProfileAvatarsDirPath];
    if (!legacyProfileAvatarsFilePaths || !self.isMainAppAndActive) {
        return nil;
    }
    NSSet<NSString *> *_Nullable sharedDataProfileAvatarFilePaths =
        [self filePathsInDirectorySafe:sharedDataProfileAvatarsDirPath];
    if (!sharedDataProfileAvatarFilePaths || !self.isMainAppAndActive) {
        return nil;
    }

    NSSet<NSString *> *_Nullable allGroupAvatarFilePaths =
        [self filePathsInDirectorySafe:TSGroupModel.avatarsDirectory.path];
    if (!allGroupAvatarFilePaths || !self.isMainAppAndActive) {
        return nil;
    }

    NSString *stickersDirPath = StickerManager.cacheDirUrl.path;
    NSSet<NSString *> *_Nullable allStickerFilePaths = [self filePathsInDirectorySafe:stickersDirPath];
    if (!allStickerFilePaths || !self.isMainAppAndActive) {
        return nil;
    }

    NSMutableSet<NSString *> *allOnDiskFilePaths = [NSMutableSet new];
    [allOnDiskFilePaths unionSet:legacyAttachmentFilePaths];
    [allOnDiskFilePaths unionSet:sharedDataAttachmentFilePaths];
    [allOnDiskFilePaths unionSet:legacyProfileAvatarsFilePaths];
    [allOnDiskFilePaths unionSet:sharedDataProfileAvatarFilePaths];
    [allOnDiskFilePaths unionSet:allGroupAvatarFilePaths];
    [allOnDiskFilePaths unionSet:allStickerFilePaths];
    // TODO: Badges?

    // This should be redundant, but this will future-proof us against
    // ever accidentally removing the GRDB databases during
    // orphan clean up.
    NSString *grdbPrimaryDirectoryPath =
        [GRDBDatabaseStorageAdapter databaseDirUrlWithDirectoryMode:DirectoryModePrimary].path;
    NSString *grdbHotswapDirectoryPath =
        [GRDBDatabaseStorageAdapter databaseDirUrlWithDirectoryMode:DirectoryModeHotswapLegacy].path;
    NSString *grdbTransferDirectoryPath = nil;
    if (GRDBDatabaseStorageAdapter.hasAssignedTransferDirectory &&
        [TSAccountManagerObjcBridge isTransferInProgressWithMaybeTransaction]) {
        grdbTransferDirectoryPath =
            [GRDBDatabaseStorageAdapter databaseDirUrlWithDirectoryMode:DirectoryModeTransfer].path;
    }

    NSMutableSet<NSString *> *databaseFilePaths = [NSMutableSet new];
    for (NSString *filePath in allOnDiskFilePaths) {
        if ([filePath hasPrefix:grdbPrimaryDirectoryPath]) {
            OWSLogInfo(@"Protecting database file: %@", filePath);
            [databaseFilePaths addObject:filePath];
        } else if ([filePath hasPrefix:grdbHotswapDirectoryPath]) {
            OWSLogInfo(@"Protecting database hotswap file: %@", filePath);
            [databaseFilePaths addObject:filePath];
        } else if (grdbTransferDirectoryPath && [filePath hasPrefix:grdbTransferDirectoryPath]) {
            OWSLogInfo(@"Protecting database hotswap file: %@", filePath);
            [databaseFilePaths addObject:filePath];
        }
    }
    [allOnDiskFilePaths minusSet:databaseFilePaths];

    __block NSSet<NSString *> *profileAvatarFilePaths;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        profileAvatarFilePaths = [OWSProfileManager allProfileAvatarFilePathsWithTransaction:transaction];
    }];

    __block NSSet<NSString *> *groupAvatarFilePaths;
    __block NSError *groupAvatarFilePathError;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        groupAvatarFilePaths = [TSGroupModel allGroupAvatarFilePathsWithTransaction:transaction
                                                                              error:&groupAvatarFilePathError];
    }];

    if (groupAvatarFilePathError) {
        OWSFailDebug(@"Failed to query group avatar file paths %@", groupAvatarFilePathError);
        return nil;
    }

    NSNumber *_Nullable totalFileSize = [self fileSizeOfFilePathsSafe:allOnDiskFilePaths.allObjects];

    if (!totalFileSize || !self.isMainAppAndActive) {
        return nil;
    }

    NSSet<NSString *> *voiceMessageDraftOrphanedPaths = [self findOrphanedVoiceMessageDraftPaths];

    if (!self.isMainAppAndActive) {
        return nil;
    }

    NSSet<NSString *> *wallpaperOrphanedPaths = [self findOrphanedWallpaperPaths];

    if (!self.isMainAppAndActive) {
        return nil;
    }

    // Attachments
    __block int attachmentStreamCount = 0;
    NSMutableSet<NSString *> *allAttachmentFilePaths = [NSMutableSet new];
    NSMutableSet<NSString *> *allAttachmentIds = [NSMutableSet new];
    // Reactions
    NSMutableSet<NSString *> *allReactionIds = [NSMutableSet new];
    // Mentions
    NSMutableSet<NSString *> *allMentionIds = [NSMutableSet new];
    // Threads
    __block NSSet *threadIds;
    // Messages
    NSMutableSet<NSString *> *orphanInteractionIds = [NSMutableSet new];
    NSMutableSet<NSString *> *allMessageAttachmentIds = [NSMutableSet new];
    NSMutableSet<NSString *> *allStoryAttachmentIds = [NSMutableSet new];
    NSMutableSet<NSString *> *allMessageReactionIds = [NSMutableSet new];
    NSMutableSet<NSString *> *allMessageMentionIds = [NSMutableSet new];
    // Stickers
    NSMutableSet<NSString *> *activeStickerFilePaths = [NSMutableSet new];
    __block BOOL hasOrphanedPacksOrStickers = NO;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [TSAttachmentStream
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(TSAttachment *attachment, BOOL *stop) {
                                      if (!self.isMainAppAndActive) {
                                          shouldAbort = YES;
                                          *stop = YES;
                                          return;
                                      }
                                      if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                                          return;
                                      }
                                      [allAttachmentIds addObject:attachment.uniqueId];

                                      TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                                      attachmentStreamCount++;
                                      NSString *_Nullable filePath = [attachmentStream originalFilePath];
                                      if (filePath) {
                                          [allAttachmentFilePaths addObject:filePath];
                                      } else {
                                          OWSFailDebug(@"attachment has no file path.");
                                      }

                                      [allAttachmentFilePaths
                                          addObjectsFromArray:attachmentStream.allSecondaryFilePaths];
                                  }];

        if (shouldAbort) {
            return;
        }

        threadIds = [NSSet setWithArray:[TSThread anyAllUniqueIdsWithTransaction:transaction]];

        NSMutableSet<NSString *> *allInteractionIds = [NSMutableSet new];
        [TSInteraction anyEnumerateWithTransaction:transaction
                                           batched:YES
                                             block:^(TSInteraction *interaction, BOOL *stop) {
                                                 if (!self.isMainAppAndActive) {
                                                     shouldAbort = YES;
                                                     *stop = YES;
                                                     return;
                                                 }
                                                 if (interaction.uniqueThreadId.length < 1
                                                     || ![threadIds containsObject:interaction.uniqueThreadId]) {
                                                     [orphanInteractionIds addObject:interaction.uniqueId];
                                                 }

                                                 [allInteractionIds addObject:interaction.uniqueId];
                                                 if (![interaction isKindOfClass:[TSMessage class]]) {
                                                     return;
                                                 }

                                                 TSMessage *message = (TSMessage *)interaction;
                                                 [allMessageAttachmentIds addObjectsFromArray:message.allAttachmentIds];
                                             }];

        if (shouldAbort) {
            return;
        }

        [OWSReaction anyEnumerateObjcWithTransaction:transaction
                                             batched:YES
                                               block:^(OWSReaction *reaction, BOOL *stop) {
                                                   if (!self.isMainAppAndActive) {
                                                       shouldAbort = YES;
                                                       *stop = YES;
                                                       return;
                                                   }
                                                   if (![reaction isKindOfClass:[OWSReaction class]]) {
                                                       return;
                                                   }
                                                   [allReactionIds addObject:reaction.uniqueId];
                                                   if ([allInteractionIds containsObject:reaction.uniqueMessageId]) {
                                                       [allMessageReactionIds addObject:reaction.uniqueId];
                                                   }
                                               }];

        if (shouldAbort) {
            return;
        }

        [TSMention anyEnumerateObjcWithTransaction:transaction
                                           batched:YES
                                             block:^(TSMention *mention, BOOL *stop) {
                                                 if (!self.isMainAppAndActive) {
                                                     shouldAbort = YES;
                                                     *stop = YES;
                                                     return;
                                                 }
                                                 if (![mention isKindOfClass:[TSMention class]]) {
                                                     return;
                                                 }
                                                 [allMentionIds addObject:mention.uniqueId];
                                                 if ([allInteractionIds containsObject:mention.uniqueMessageId]) {
                                                     [allMessageMentionIds addObject:mention.uniqueId];
                                                 }
                                             }];

        if (shouldAbort) {
            return;
        }

        [StoryMessage
            anyEnumerateObjcWithTransaction:transaction
                                    batched:YES
                                      block:^(StoryMessage *message, BOOL *stop) {
                                          if (!self.isMainAppAndActive) {
                                              shouldAbort = YES;
                                              *stop = YES;
                                              return;
                                          }
                                          if (![message isKindOfClass:[StoryMessage class]]) {
                                              return;
                                          }
                                          [allStoryAttachmentIds
                                              addObject:[message attachmentUniqueIdWithTx:transaction]];
                                      }];

        if (shouldAbort) {
            return;
        }

        NSArray<NSString *> *jobRecordAttachmentIds = [self findJobRecordAttachmentIdsWithTransaction:transaction];
        if (jobRecordAttachmentIds == nil) {
            shouldAbort = YES;
            return;
        }

        [allMessageAttachmentIds addObjectsFromArray:jobRecordAttachmentIds];

        [activeStickerFilePaths
            addObjectsFromArray:[StickerManager filePathsForAllInstalledStickersWithTransaction:transaction]];

        hasOrphanedPacksOrStickers = [StickerManager hasOrphanedDataWithTx:transaction];
    }];
    if (shouldAbort) {
        return nil;
    }

    NSMutableSet<NSString *> *orphanFilePaths = [allOnDiskFilePaths mutableCopy];
    [orphanFilePaths minusSet:allAttachmentFilePaths];
    [orphanFilePaths minusSet:profileAvatarFilePaths];
    [orphanFilePaths minusSet:groupAvatarFilePaths];
    [orphanFilePaths minusSet:activeStickerFilePaths];
    NSMutableSet<NSString *> *missingAttachmentFilePaths = [allAttachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:allOnDiskFilePaths];

    NSMutableSet<NSString *> *orphanAttachmentIds = [allAttachmentIds mutableCopy];
    [orphanAttachmentIds minusSet:allMessageAttachmentIds];
    [orphanAttachmentIds minusSet:allStoryAttachmentIds];
    NSMutableSet<NSString *> *missingAttachmentIds = [allMessageAttachmentIds mutableCopy];
    [missingAttachmentIds minusSet:allAttachmentIds];

    NSMutableSet<NSString *> *orphanReactionIds = [allReactionIds mutableCopy];
    [orphanReactionIds minusSet:allMessageReactionIds];
    NSMutableSet<NSString *> *missingReactionIds = [allMessageReactionIds mutableCopy];
    [missingReactionIds minusSet:allReactionIds];

    NSMutableSet<NSString *> *orphanMentionIds = [allMentionIds mutableCopy];
    [orphanMentionIds minusSet:allMessageMentionIds];
    NSMutableSet<NSString *> *missingMentionIds = [allMessageMentionIds mutableCopy];
    [missingMentionIds minusSet:allMentionIds];

    NSMutableSet<NSString *> *orphanFileAndDirectoryPaths = [NSMutableSet set];
    [orphanFileAndDirectoryPaths unionSet:voiceMessageDraftOrphanedPaths];
    [orphanFileAndDirectoryPaths unionSet:wallpaperOrphanedPaths];

    OWSOrphanData *result = [OWSOrphanData new];
    result.interactionIds = [orphanInteractionIds copy];
    result.attachmentIds = [orphanAttachmentIds copy];
    result.filePaths = [orphanFilePaths copy];
    result.reactionIds = [orphanReactionIds copy];
    result.mentionIds = [orphanMentionIds copy];
    result.fileAndDirectoryPaths = [orphanFileAndDirectoryPaths copy];
    result.hasOrphanedPacksOrStickers = hasOrphanedPacksOrStickers;
    return result;
}

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans
{
    [self auditAndCleanup:shouldRemoveOrphans completion:^ {}];
}

// We use the lowest priority possible.
+ (dispatch_queue_t)workQueue
{
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
}

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans completion:(nullable dispatch_block_t)completion
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        OWSFailDebug(@"can't audit orphan data until app is ready.");
        return;
    }
    if (!CurrentAppContext().isMainApp) {
        OWSFailDebug(@"can't audit orphan data in app extensions.");
        return;
    }

    if (shouldRemoveOrphans) {
        OWSLogInfo(@"Starting orphan data cleanup");
    } else {
        OWSLogInfo(@"Starting orphan data audit");
    }

    // Orphan cleanup has two risks:
    //
    // * As a long-running process that involves access to the
    //   shared data container, it could cause 0xdead10cc.
    // * It could accidentally delete data still in use,
    //   e.g. a profile avatar which has been saved to disk
    //   but whose OWSUserProfile hasn't been saved yet.
    //
    // To prevent 0xdead10cc, the cleaner continually checks
    // whether the app has resigned active.  If so, it aborts.
    // Each phase (search, re-search, processing) retries N times,
    // then gives up until the next app launch.
    //
    // To prevent accidental data deletion, we take the following
    // measures:
    //
    // * Only cleanup data of the following types (which should
    //   include all relevant app data): profile avatar,
    //   attachment, temporary files (including temporary
    //   attachments).
    // * We don't delete any data created more recently than N seconds
    //   _before_ when the app launched.  This prevents any stray data
    //   currently in use by the app from being accidentally cleaned
    //   up.
    const NSInteger kMaxRetries = 3;
    [self findOrphanDataWithRetries:kMaxRetries
        success:^(OWSOrphanData *orphanData) {
            [self processOrphans:orphanData
                remainingRetries:kMaxRetries
                shouldRemoveOrphans:shouldRemoveOrphans
                success:^{
                    OWSLogInfo(@"Completed orphan data cleanup.");

                    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                        [self.keyValueStore setString:AppVersion.shared.currentAppReleaseVersion
                                                  key:OWSOrphanDataCleaner_LastCleaningVersionKey
                                          transaction:transaction];

                        [self.keyValueStore setDate:[NSDate new]
                                                key:OWSOrphanDataCleaner_LastCleaningDateKey
                                        transaction:transaction];
                    });

                    if (completion) {
                        completion();
                    }
                }
                failure:^{
                    OWSLogInfo(@"Aborting orphan data cleanup.");
                    if (completion) {
                        completion();
                    }
                }];
        }
        failure:^{
            OWSLogInfo(@"Aborting orphan data cleanup.");
            if (completion) {
                completion();
            }
        }];
}

// Returns NO on failure, usually indicating that orphan processing
// aborted due to the app resigning active.  This method is extremely careful to
// abort if the app resigns active, in order to avoid 0xdead10cc crashes.
+ (void)processOrphans:(OWSOrphanData *)orphanData
       remainingRetries:(NSInteger)remainingRetries
    shouldRemoveOrphans:(BOOL)shouldRemoveOrphans
                success:(dispatch_block_t)success
                failure:(dispatch_block_t)failure
{
    OWSAssertDebug(orphanData);

    if (remainingRetries < 1) {
        OWSLogInfo(@"Aborting orphan data audit.");
        dispatch_async(self.workQueue, ^{ failure(); });
        return;
    }

    // Wait until the app is active...
    [CurrentAppContext() runNowOrWhenMainAppIsActive:^{
        // ...but perform the work off the main thread.
        OWSBackgroundTask *_Nullable backgroundTask =
            [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
        dispatch_async(self.workQueue, ^{
            BOOL result = [self processOrphansSync:orphanData shouldRemoveOrphans:shouldRemoveOrphans];
            if (result) {
                success();
            } else {
                [self processOrphans:orphanData
                       remainingRetries:remainingRetries - 1
                    shouldRemoveOrphans:shouldRemoveOrphans
                                success:success
                                failure:failure];
            }
            [backgroundTask endBackgroundTask];
        });
    }];
}

// Returns NO on failure, usually indicating that orphan processing
// aborted due to the app resigning active.  This method is extremely careful to
// abort if the app resigns active, in order to avoid 0xdead10cc crashes.
+ (BOOL)processOrphansSync:(OWSOrphanData *)orphanData shouldRemoveOrphans:(BOOL)shouldRemoveOrphans
{
    OWSAssertDebug(orphanData);

    if (!self.isMainAppAndActive) {
        return NO;
    }

    __block BOOL shouldAbort = NO;

    // We need to avoid cleaning up new files that are still in the process of
    // being created/written, so we don't clean up anything recent.
    const NSTimeInterval kMinimumOrphanAgeSeconds = CurrentAppContext().isRunningTests ? 0.f : 15 * kMinuteInterval;
    NSDate *appLaunchTime = CurrentAppContext().appLaunchTime;
    NSTimeInterval thresholdTimestamp = appLaunchTime.timeIntervalSince1970 - kMinimumOrphanAgeSeconds;
    NSDate *thresholdDate = [NSDate dateWithTimeIntervalSince1970:thresholdTimestamp];
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSUInteger interactionsRemoved = 0;
        for (NSString *interactionId in orphanData.interactionIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }
            TSInteraction *_Nullable interaction = [TSInteraction anyFetchWithUniqueId:interactionId
                                                                           transaction:transaction];
            if (!interaction) {
                // This could just be a race condition, but it should be very unlikely.
                OWSLogWarn(@"Could not load interaction: %@", interactionId);
                continue;
            }
            // Don't delete interactions which were created in the last N minutes.
            NSDate *creationDate = [NSDate ows_dateWithMillisecondsSince1970:interaction.timestamp];
            if ([creationDate isAfterDate:thresholdDate]) {
                OWSLogInfo(@"Skipping orphan interaction due to age: %f", fabs(creationDate.timeIntervalSinceNow));
                continue;
            }
            OWSLogInfo(@"Removing orphan message: %@", interaction.uniqueId);
            interactionsRemoved++;
            if (!shouldRemoveOrphans) {
                continue;
            }
            [interaction anyRemoveWithTransaction:transaction];
        }
        OWSLogInfo(@"Deleted orphan interactions: %zu", interactionsRemoved);

        NSUInteger attachmentsRemoved = 0;
        for (NSString *attachmentId in orphanData.attachmentIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }
            TSAttachment *_Nullable attachment = [TSAttachment anyFetchWithUniqueId:attachmentId
                                                                        transaction:transaction];
            if (!attachment) {
                // This can happen on launch since we sync contacts/groups, especially if you have a lot of attachments
                // to churn through, it's likely it's been deleted since starting this job.
                OWSLogWarn(@"Could not load attachment: %@", attachmentId);
                continue;
            }
            if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                continue;
            }
            TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
            // Don't delete attachments which were created in the last N minutes.
            NSDate *creationDate = attachmentStream.creationTimestamp;
            if ([creationDate isAfterDate:thresholdDate]) {
                OWSLogInfo(@"Skipping orphan attachment due to age: %f", fabs(creationDate.timeIntervalSinceNow));
                continue;
            }
            OWSLogInfo(@"Removing orphan attachmentStream: %@", attachmentStream.uniqueId);
            attachmentsRemoved++;
            if (!shouldRemoveOrphans) {
                continue;
            }
            [attachmentStream anyRemoveWithTransaction:transaction];
        }
        OWSLogInfo(@"Deleted orphan attachments: %zu", attachmentsRemoved);

        NSUInteger reactionsRemoved = 0;
        for (NSString *reactionId in orphanData.reactionIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }

            BOOL performedCleanup = [OWSReactionManager tryToCleanupOrphanedReactionWithUniqueId:reactionId
                                                                                   thresholdDate:thresholdDate
                                                                             shouldPerformRemove:shouldRemoveOrphans
                                                                                     transaction:transaction];
            if (performedCleanup) {
                reactionsRemoved++;
            }
        }
        OWSLogInfo(@"Deleted orphan reactions: %zu", reactionsRemoved);

        NSUInteger mentionsRemoved = 0;
        for (NSString *mentionId in orphanData.mentionIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }

            BOOL performedCleanup = [MentionFinder tryToCleanupOrphanedMentionWithUniqueId:mentionId
                                                                             thresholdDate:thresholdDate
                                                                       shouldPerformRemove:shouldRemoveOrphans
                                                                               transaction:transaction];
            if (performedCleanup) {
                mentionsRemoved++;
            }
        }
        OWSLogInfo(@"Deleted orphan mentions: %zu", mentionsRemoved);

        if (orphanData.hasOrphanedPacksOrStickers) {
            [StickerManager cleanUpOrphanedDataWithTx:transaction];
        }
    });

    if (shouldAbort) {
        return NO;
    }

    NSUInteger filesRemoved = 0;
    NSArray<NSString *> *filePaths = [orphanData.filePaths.allObjects sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *filePath in filePaths) {
        if (!self.isMainAppAndActive) {
            return NO;
        }

        NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (!attributes || error) {
            // This is fine; the file may have been deleted since we found it.
            OWSLogWarn(@"Could not get attributes of file at: %@", filePath);
            continue;
        }
        // Don't delete files which were created in the last N minutes.
        NSDate *creationDate = attributes.fileModificationDate;
        if ([creationDate isAfterDate:thresholdDate]) {
            OWSLogInfo(@"Skipping file due to age: %f", fabs([creationDate timeIntervalSinceNow]));
            continue;
        }
        OWSLogInfo(@"Deleting file: %@", filePath);
        filesRemoved++;
        if (!shouldRemoveOrphans) {
            continue;
        }
        if (![OWSFileSystem fileOrFolderExistsAtPath:filePath]) {
            // Already removed.
            continue;
        }
        if (![OWSFileSystem deleteFile:filePath ignoreIfMissing:YES]) {
            OWSFailDebug(@"Could not remove orphan file");
        }
    }
    OWSLogInfo(@"Deleted orphan files: %zu", filesRemoved);

    if (shouldRemoveOrphans) {
        BOOL cancelled = ![self removeOrphanedFileAndDirectoryPaths:orphanData.fileAndDirectoryPaths];
        if (cancelled) {
            return NO;
        }
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
