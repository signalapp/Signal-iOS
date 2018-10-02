//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOrphanDataCleaner.h"
#import "DateUtil.h"
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/AppVersion.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSContact.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/YapDatabaseTransaction+OWS.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOrphanDataCleaner_Collection = @"OWSOrphanDataCleaner_Collection";
NSString *const OWSOrphanDataCleaner_LastCleaningVersionKey = @"OWSOrphanDataCleaner_LastCleaningVersionKey";
NSString *const OWSOrphanDataCleaner_LastCleaningDateKey = @"OWSOrphanDataCleaner_LastCleaningDateKey";

@interface OWSOrphanData : NSObject

@property (nonatomic) NSSet<NSString *> *interactionIds;
@property (nonatomic) NSSet<NSString *> *attachmentIds;
@property (nonatomic) NSSet<NSString *> *filePaths;

@end

#pragma mark -

@implementation OWSOrphanData

@end

#pragma mark -

typedef void (^OrphanDataBlock)(OWSOrphanData *);

@implementation OWSOrphanDataCleaner

// Unlike CurrentAppContext().isMainAppAndActive, this method can be safely
// invoked off the main thread.
+ (BOOL)isMainAppAndActive
{
    return CurrentAppContext().reportedApplicationState == UIApplicationStateActive;
}

+ (void)printPaths:(NSArray<NSString *> *)paths label:(NSString *)label
{
    for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        OWSLogDebug(@"%@: %@", label, path);
    }
}

+ (long long)fileSizeOfFilePath:(NSString *)filePath
{
    NSError *error;
    NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize];
    if (error) {
        if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == 260) {
            OWSLogWarn(@"can't find size of missing file.");
            OWSLogDebug(@"can't find size of missing file: %@", filePath);
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
        OWSFailDebug(@"contentsOfDirectoryAtPath error: %@", error);
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
               databaseConnection:(YapDatabaseConnection *)databaseConnection
                          success:(OrphanDataBlock)success
                          failure:(dispatch_block_t)failure
{
    OWSAssertDebug(databaseConnection);

    if (remainingRetries < 1) {
        OWSLogInfo(@"Aborting orphan data search.");
        dispatch_async(self.workQueue, ^{
            failure();
        });
        return;
    }

    // Wait until the app is active...
    [CurrentAppContext() runNowOrWhenMainAppIsActive:^{
        // ...but perform the work off the main thread.
        dispatch_async(self.workQueue, ^{
            OWSOrphanData *_Nullable orphanData = [self findOrphanDataSync:databaseConnection];
            if (orphanData) {
                success(orphanData);
            } else {
                [self findOrphanDataWithRetries:remainingRetries - 1
                             databaseConnection:databaseConnection
                                        success:success
                                        failure:failure];
            }
        });
    }];
}

// Returns nil on failure, usually indicating that the search
// aborted due to the app resigning active.  This method is extremely careful to
// abort if the app resigns active, in order to avoid 0xdead10cc crashes.
+ (nullable OWSOrphanData *)findOrphanDataSync:(YapDatabaseConnection *)databaseConnection
{
    OWSAssertDebug(databaseConnection);

    __block BOOL shouldAbort = NO;

    // LOG_ALL_FILE_PATHS can be used to determine if there are other kinds of files
    // that we're not cleaning up.
//#define LOG_ALL_FILE_PATHS
#ifdef LOG_ALL_FILE_PATHS
    {
        NSString *documentDirPath = [OWSFileSystem appDocumentDirectoryPath];
        NSArray<NSString *> *_Nullable allDocumentFilePaths =
            [self filePathsInDirectorySafe:documentDirPath].allObjects;
        allDocumentFilePaths = [allDocumentFilePaths sortedArrayUsingSelector:@selector(compare:)];
        NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
        for (NSString *filePath in allDocumentFilePaths) {
            if ([filePath hasPrefix:attachmentsFolder]) {
                continue;
            }
            OWSLogVerbose(@"non-attachment file: %@", filePath);
        }
    }
    {
        NSString *documentDirPath = [OWSFileSystem appSharedDataDirectoryPath];
        NSArray<NSString *> *_Nullable allDocumentFilePaths =
            [self filePathsInDirectorySafe:documentDirPath].allObjects;
        allDocumentFilePaths = [allDocumentFilePaths sortedArrayUsingSelector:@selector(compare:)];
        NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
        for (NSString *filePath in allDocumentFilePaths) {
            if ([filePath hasPrefix:attachmentsFolder]) {
                continue;
            }
            OWSLogVerbose(@"non-attachment file: %@", filePath);
        }
    }
#endif

    // We treat _all_ temp files as orphan files.  This is safe
    // because temp files only need to be retained for the
    // a single launch of the app.  Since our "date threshold"
    // for deletion is relative to the current launch time,
    // all temp files currently in use should be safe.
    NSArray<NSString *> *_Nullable tempFilePaths = [self getTempFilePaths];
    if (!tempFilePaths || !self.isMainAppAndActive) {
        return nil;
    }

#ifdef LOG_ALL_FILE_PATHS
    {
        NSDateFormatter *dateFormatter = [NSDateFormatter new];
        [dateFormatter setDateStyle:NSDateFormatterLongStyle];
        [dateFormatter setTimeStyle:NSDateFormatterLongStyle];

        tempFilePaths = [tempFilePaths sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *filePath in tempFilePaths) {
            NSError *error;
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
            if (!attributes || error) {
                OWSLogDebug(@"Could not get attributes of file at: %@", filePath);
                OWSFailDebug(@"Could not get attributes of file");
                continue;
            }
            OWSLogVerbose(
                @"temp file: %@, %@", filePath, [dateFormatter stringFromDate:attributes.fileModificationDate]);
        }
    }
#endif

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

    NSMutableSet<NSString *> *allOnDiskFilePaths = [NSMutableSet new];
    [allOnDiskFilePaths unionSet:legacyAttachmentFilePaths];
    [allOnDiskFilePaths unionSet:sharedDataAttachmentFilePaths];
    [allOnDiskFilePaths unionSet:legacyProfileAvatarsFilePaths];
    [allOnDiskFilePaths unionSet:sharedDataProfileAvatarFilePaths];
    [allOnDiskFilePaths addObjectsFromArray:tempFilePaths];

    NSSet<NSString *> *profileAvatarFilePaths = [OWSUserProfile allProfileAvatarFilePaths];

    if (!self.isMainAppAndActive) {
        return nil;
    }

    NSNumber *_Nullable totalFileSize = [self fileSizeOfFilePathsSafe:allOnDiskFilePaths.allObjects];

    if (!totalFileSize || !self.isMainAppAndActive) {
        return nil;
    }

    NSUInteger fileCount = allOnDiskFilePaths.count;

    // Attachments
    __block int attachmentStreamCount = 0;
    NSMutableSet<NSString *> *allAttachmentFilePaths = [NSMutableSet new];
    NSMutableSet<NSString *> *allAttachmentIds = [NSMutableSet new];
    // Threads
    __block NSSet *threadIds;
    // Messages
    NSMutableSet<NSString *> *orphanInteractionIds = [NSMutableSet new];
    NSMutableSet<NSString *> *messageAttachmentIds = [NSMutableSet new];
    NSMutableSet<NSString *> *quotedReplyThumbnailAttachmentIds = [NSMutableSet new];
    NSMutableSet<NSString *> *contactShareAvatarAttachmentIds = [NSMutableSet new];
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [transaction
            enumerateKeysAndObjectsInCollection:TSAttachmentStream.collection
                                     usingBlock:^(NSString *key, TSAttachment *attachment, BOOL *stop) {
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
                                             addObjectsFromArray:attachmentStream.allThumbnailPaths];
                                     }];

        if (shouldAbort) {
            return;
        }

        threadIds = [NSSet setWithArray:[transaction allKeysInCollection:TSThread.collection]];

        [transaction
            enumerateKeysAndObjectsInCollection:TSMessage.collection
                                     usingBlock:^(NSString *key, TSInteraction *interaction, BOOL *stop) {
                                         if (!self.isMainAppAndActive) {
                                             shouldAbort = YES;
                                             *stop = YES;
                                             return;
                                         }
                                         if (interaction.uniqueThreadId.length < 1
                                             || ![threadIds containsObject:interaction.uniqueThreadId]) {
                                             [orphanInteractionIds addObject:interaction.uniqueId];
                                         }

                                         if (![interaction isKindOfClass:[TSMessage class]]) {
                                             return;
                                         }

                                         TSMessage *message = (TSMessage *)interaction;
                                         if (message.attachmentIds.count > 0) {
                                             [messageAttachmentIds addObjectsFromArray:message.attachmentIds];
                                         }

                                         TSQuotedMessage *_Nullable quotedMessage = message.quotedMessage;
                                         if (quotedMessage) {
                                             [quotedReplyThumbnailAttachmentIds
                                                 addObjectsFromArray:quotedMessage.thumbnailAttachmentStreamIds];
                                         }

                                         OWSContact *_Nullable contactShare = message.contactShare;
                                         if (contactShare && contactShare.avatarAttachmentId) {
                                             [contactShareAvatarAttachmentIds
                                                 addObject:contactShare.avatarAttachmentId];
                                         }
                                     }];
    }];
    if (shouldAbort) {
        return nil;
    }

    OWSLogDebug(@"fileCount: %zu", fileCount);
    OWSLogDebug(@"totalFileSize: %lld", totalFileSize.longLongValue);
    OWSLogDebug(@"attachmentStreams: %d", attachmentStreamCount);
    OWSLogDebug(@"attachmentStreams with file paths: %zu", allAttachmentFilePaths.count);

    NSMutableSet<NSString *> *orphanFilePaths = [allOnDiskFilePaths mutableCopy];
    [orphanFilePaths minusSet:allAttachmentFilePaths];
    [orphanFilePaths minusSet:profileAvatarFilePaths];
    NSMutableSet<NSString *> *missingAttachmentFilePaths = [allAttachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:allOnDiskFilePaths];

    OWSLogDebug(@"orphan file paths: %zu", orphanFilePaths.count);
    OWSLogDebug(@"missing attachment file paths: %zu", missingAttachmentFilePaths.count);

    [self printPaths:orphanFilePaths.allObjects label:@"orphan file paths"];
    [self printPaths:missingAttachmentFilePaths.allObjects label:@"missing attachment file paths"];

    OWSLogDebug(@"attachmentIds: %zu", allAttachmentIds.count);
    OWSLogDebug(@"messageAttachmentIds: %zu", messageAttachmentIds.count);
    OWSLogDebug(@"quotedReplyThumbnailAttachmentIds: %zu", quotedReplyThumbnailAttachmentIds.count);
    OWSLogDebug(@"contactShareAvatarAttachmentIds: %zu", contactShareAvatarAttachmentIds.count);

    NSMutableSet<NSString *> *orphanAttachmentIds = [allAttachmentIds mutableCopy];
    [orphanAttachmentIds minusSet:messageAttachmentIds];
    [orphanAttachmentIds minusSet:quotedReplyThumbnailAttachmentIds];
    [orphanAttachmentIds minusSet:contactShareAvatarAttachmentIds];
    NSMutableSet<NSString *> *missingAttachmentIds = [messageAttachmentIds mutableCopy];
    [missingAttachmentIds minusSet:allAttachmentIds];

    OWSLogDebug(@"orphan attachmentIds: %zu", orphanAttachmentIds.count);
    OWSLogDebug(@"missing attachmentIds: %zu", missingAttachmentIds.count);
    OWSLogDebug(@"orphan interactions: %zu", orphanInteractionIds.count);

    OWSOrphanData *result = [OWSOrphanData new];
    result.interactionIds = [orphanInteractionIds copy];
    result.attachmentIds = [orphanAttachmentIds copy];
    result.filePaths = [orphanFilePaths copy];
    return result;
}

+ (void)auditOnLaunchIfNecessary
{
    OWSAssertIsOnMainThread();

    // In production, do not audit or clean up.
#ifndef DEBUG
    return;
#endif

    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    YapDatabaseConnection *databaseConnection = primaryStorage.dbReadWriteConnection;

    __block NSString *_Nullable lastCleaningVersion;
    __block NSDate *_Nullable lastCleaningDate;
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        lastCleaningVersion = [transaction stringForKey:OWSOrphanDataCleaner_LastCleaningVersionKey
                                           inCollection:OWSOrphanDataCleaner_Collection];
        lastCleaningDate = [transaction dateForKey:OWSOrphanDataCleaner_LastCleaningDateKey
                                      inCollection:OWSOrphanDataCleaner_Collection];
    }];

    // Only clean up once per app version.
    NSString *currentAppVersion = AppVersion.sharedInstance.currentAppVersion;
    if (lastCleaningVersion && [lastCleaningVersion isEqualToString:currentAppVersion]) {
        OWSLogVerbose(@"skipping orphan data cleanup; already done on %@.", currentAppVersion);
        return;
    }

    // Only clean up once per day.
    if (lastCleaningDate && [DateUtil dateIsToday:lastCleaningDate]) {
        OWSLogVerbose(@"skipping orphan data cleanup; already done today.");
        return;
    }

    // If we want to be cautious, we can disable orphan deletion using
    // flag - the cleanup will just be a dry run with logging.
    BOOL shouldRemoveOrphans = NO;
    [self auditAndCleanup:shouldRemoveOrphans databaseConnection:databaseConnection completion:nil];
}

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    YapDatabaseConnection *databaseConnection = primaryStorage.dbReadWriteConnection;

    [self auditAndCleanup:shouldRemoveOrphans databaseConnection:databaseConnection completion:nil];
}

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans completion:(dispatch_block_t)completion
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    YapDatabaseConnection *databaseConnection = primaryStorage.dbReadWriteConnection;

    [self auditAndCleanup:shouldRemoveOrphans databaseConnection:databaseConnection completion:completion];
}

// We use the lowest priority possible.
+ (dispatch_queue_t)workQueue
{
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
}

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans
     databaseConnection:(YapDatabaseConnection *)databaseConnection
             completion:(nullable dispatch_block_t)completion
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(databaseConnection);

    if (!AppReadiness.isAppReady) {
        OWSFailDebug(@"can't audit orphan data until app is ready.");
        return;
    }
    if (!CurrentAppContext().isMainApp) {
        OWSFailDebug(@"can't audit orphan data in app extensions.");
        return;
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
        databaseConnection:databaseConnection
        success:^(OWSOrphanData *orphanData) {
            [self processOrphans:orphanData
                remainingRetries:kMaxRetries
                databaseConnection:databaseConnection
                shouldRemoveOrphans:shouldRemoveOrphans
                success:^{
                    OWSLogInfo(@"Completed orphan data cleanup.");

                    [databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [transaction setObject:AppVersion.sharedInstance.currentAppVersion
                                        forKey:OWSOrphanDataCleaner_LastCleaningVersionKey
                                  inCollection:OWSOrphanDataCleaner_Collection];
                        [transaction setDate:[NSDate new]
                                      forKey:OWSOrphanDataCleaner_LastCleaningDateKey
                                inCollection:OWSOrphanDataCleaner_Collection];
                    }];

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
     databaseConnection:(YapDatabaseConnection *)databaseConnection
    shouldRemoveOrphans:(BOOL)shouldRemoveOrphans
                success:(dispatch_block_t)success
                failure:(dispatch_block_t)failure
{
    OWSAssertDebug(databaseConnection);
    OWSAssertDebug(orphanData);

    if (remainingRetries < 1) {
        OWSLogInfo(@"Aborting orphan data audit.");
        dispatch_async(self.workQueue, ^{
            failure();
        });
        return;
    }

    // Wait until the app is active...
    [CurrentAppContext() runNowOrWhenMainAppIsActive:^{
        // ...but perform the work off the main thread.
        dispatch_async(self.workQueue, ^{
            if ([self processOrphansSync:orphanData
                      databaseConnection:databaseConnection
                     shouldRemoveOrphans:shouldRemoveOrphans]) {
                success();
                return;
            } else {
                [self processOrphans:orphanData
                       remainingRetries:remainingRetries - 1
                     databaseConnection:databaseConnection
                    shouldRemoveOrphans:shouldRemoveOrphans
                                success:success
                                failure:failure];
            }
        });
    }];
}

// Returns NO on failure, usually indicating that orphan processing
// aborted due to the app resigning active.  This method is extremely careful to
// abort if the app resigns active, in order to avoid 0xdead10cc crashes.
+ (BOOL)processOrphansSync:(OWSOrphanData *)orphanData
        databaseConnection:(YapDatabaseConnection *)databaseConnection
       shouldRemoveOrphans:(BOOL)shouldRemoveOrphans
{
    OWSAssertDebug(databaseConnection);
    OWSAssertDebug(orphanData);

    __block BOOL shouldAbort = NO;

    // We need to avoid cleaning up new attachments and files that are still in the process of
    // being created/written, so we don't clean up anything recent.
    const NSTimeInterval kMinimumOrphanAgeSeconds = CurrentAppContext().isRunningTests ? 0.f : 15 * kMinuteInterval;
    NSDate *appLaunchTime = CurrentAppContext().appLaunchTime;
    NSTimeInterval thresholdTimestamp = appLaunchTime.timeIntervalSince1970 - kMinimumOrphanAgeSeconds;
    NSDate *thresholdDate = [NSDate dateWithTimeIntervalSince1970:thresholdTimestamp];
    [databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSUInteger interactionsRemoved = 0;
        for (NSString *interactionId in orphanData.interactionIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }
            TSInteraction *_Nullable interaction =
                [TSInteraction fetchObjectWithUniqueID:interactionId transaction:transaction];
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
            [interaction removeWithTransaction:transaction];
        }
        OWSLogInfo(@"Deleted orphan interactions: %zu", interactionsRemoved);

        NSUInteger attachmentsRemoved = 0;
        for (NSString *attachmentId in orphanData.attachmentIds) {
            if (!self.isMainAppAndActive) {
                shouldAbort = YES;
                return;
            }
            TSAttachment *_Nullable attachment =
                [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
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
            [attachmentStream removeWithTransaction:transaction];
        }
        OWSLogInfo(@"Deleted orphan attachments: %zu", attachmentsRemoved);
    }];

    if (shouldAbort) {
        return nil;
    }

    NSUInteger filesRemoved = 0;
    NSArray<NSString *> *filePaths = [orphanData.filePaths.allObjects sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *filePath in filePaths) {
        if (!self.isMainAppAndActive) {
            return nil;
        }

        NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (!attributes || error) {
            OWSLogDebug(@"Could not get attributes of file at: %@", filePath);
            OWSFailDebug(@"Could not get attributes of file");
            continue;
        }
        // Don't delete files which were created in the last N minutes.
        NSDate *creationDate = attributes.fileModificationDate;
        if ([creationDate isAfterDate:thresholdDate]) {
            OWSLogInfo(@"Skipping orphan attachment file due to age: %f", fabs([creationDate timeIntervalSinceNow]));
            continue;
        }
        OWSLogInfo(@"Deleting orphan attachment file: %@", filePath);
        filesRemoved++;
        if (!shouldRemoveOrphans) {
            continue;
        }
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (error) {
            OWSLogDebug(@"Could not remove orphan file at: %@", filePath);
            OWSFailDebug(@"Could not remove orphan file");
        }
    }
    OWSLogInfo(@"Deleted orphan attachment files: %zu", filesRemoved);

    return YES;
}

+ (nullable NSArray<NSString *> *)getTempFilePaths
{
    NSString *dir1 = OWSTemporaryDirectory();
    NSArray<NSString *> *_Nullable paths1 = [[self filePathsInDirectorySafe:dir1].allObjects mutableCopy];

    NSString *dir2 = OWSTemporaryDirectoryAccessibleAfterFirstAuth();
    NSArray<NSString *> *_Nullable paths2 = [[self filePathsInDirectorySafe:dir2].allObjects mutableCopy];

    if (paths1 && paths2) {
        return [paths1 arrayByAddingObjectsFromArray:paths2];
    } else {
        return nil;
    }
}

@end

NS_ASSUME_NONNULL_END
