//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOrphanedDataCleaner.h"
#import "NSDate+OWS.h"
#import "OWSPrimaryStorage.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "TSMessage.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef SSK_BUILDING_FOR_TESTS
#define CleanupLogDebug NSLog
#define CleanupLogInfo NSLog
#else
#define CleanupLogDebug DDLogDebug
#define CleanupLogInfo DDLogInfo
#endif

@implementation OWSOrphanedDataCleaner

+ (void)auditAsync
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [OWSOrphanedDataCleaner auditAndCleanup:NO completion:nil];
    });
}

+ (void)auditAndCleanupAsync:(void (^_Nullable)(void))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [OWSOrphanedDataCleaner auditAndCleanup:YES completion:completion];
    });
}

// This method finds and optionally cleans up:
//
// * Orphan messages (with no thread).
// * Orphan attachments (with no message).
// * Orphan attachment files (with no attachment).
// * Missing attachment files (cannot be cleaned up).
//   These are attachments which have no file on disk.  They should be extremely rare -
//   the only cases I have seen are probably due to debugging.
//   They can't be cleaned up - we don't want to delete the TSAttachmentStream or
//   its corresponding message.  Better that the broken message shows up in the
//   conversation view.
+ (void)auditAndCleanup:(BOOL)shouldCleanup completion:(void (^_Nullable)(void))completion
{
    NSSet<NSString *> *diskFilePaths = [self filePathsInAttachmentsFolder];
    long long totalFileSize = [self fileSizeOfFilePaths:diskFilePaths.allObjects];
    NSUInteger fileCount = diskFilePaths.count;

    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    YapDatabaseConnection *databaseConnection = primaryStorage.newDatabaseConnection;

    __block int attachmentStreamCount = 0;
    NSMutableSet<NSString *> *attachmentFilePaths = [NSMutableSet new];
    NSMutableSet<NSString *> *attachmentIds = [NSMutableSet new];
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:TSAttachmentStream.collection
                                              usingBlock:^(NSString *key, TSAttachment *attachment, BOOL *stop) {
                                                  [attachmentIds addObject:attachment.uniqueId];
                                                  if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                                                      return;
                                                  }
                                                  TSAttachmentStream *attachmentStream
                                                      = (TSAttachmentStream *)attachment;
                                                  attachmentStreamCount++;
                                                  NSString *_Nullable filePath = [attachmentStream filePath];
                                                  OWSAssert(filePath);
                                                  [attachmentFilePaths addObject:filePath];

                                                  NSString *_Nullable thumbnailPath = [attachmentStream thumbnailPath];
                                                  if (thumbnailPath.length > 0) {
                                                      [attachmentFilePaths addObject:thumbnailPath];
                                                  }
                                              }];
    }];

    CleanupLogDebug(@"%@ fileCount: %zd", self.logTag, fileCount);
    CleanupLogDebug(@"%@ totalFileSize: %lld", self.logTag, totalFileSize);
    CleanupLogDebug(@"%@ attachmentStreams: %d", self.logTag, attachmentStreamCount);
    CleanupLogDebug(@"%@ attachmentStreams with file paths: %zd", self.logTag, attachmentFilePaths.count);

    NSMutableSet<NSString *> *orphanDiskFilePaths = [diskFilePaths mutableCopy];
    [orphanDiskFilePaths minusSet:attachmentFilePaths];
    NSMutableSet<NSString *> *missingAttachmentFilePaths = [attachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:diskFilePaths];

    CleanupLogDebug(@"%@ orphan disk file paths: %zd", self.logTag, orphanDiskFilePaths.count);
    CleanupLogDebug(@"%@ missing attachment file paths: %zd", self.logTag, missingAttachmentFilePaths.count);

    [self printPaths:orphanDiskFilePaths.allObjects label:@"orphan disk file paths"];
    [self printPaths:missingAttachmentFilePaths.allObjects label:@"missing attachment file paths"];

    __block NSMutableSet *threadIds;
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        threadIds = [[NSMutableSet alloc] initWithArray:[transaction allKeysInCollection:TSThread.collection]];
    }];

    NSMutableSet<NSString *> *orphanInteractionIds = [NSMutableSet new];
    NSMutableSet<NSString *> *messageAttachmentIds = [NSMutableSet new];
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:TSMessage.collection
                                              usingBlock:^(NSString *key, TSInteraction *interaction, BOOL *stop) {
                                                  if (![threadIds containsObject:interaction.uniqueThreadId]) {
                                                      [orphanInteractionIds addObject:interaction.uniqueId];
                                                  }

                                                  if (![interaction isKindOfClass:[TSMessage class]]) {
                                                      return;
                                                  }
                                                  TSMessage *message = (TSMessage *)interaction;
                                                  if (message.attachmentIds.count > 0) {
                                                      [messageAttachmentIds addObjectsFromArray:message.attachmentIds];
                                                  }
                                              }];
    }];

    CleanupLogDebug(@"%@ attachmentIds: %zd", self.logTag, attachmentIds.count);
    CleanupLogDebug(@"%@ messageAttachmentIds: %zd", self.logTag, messageAttachmentIds.count);

    NSMutableSet<NSString *> *orphanAttachmentIds = [attachmentIds mutableCopy];
    [orphanAttachmentIds minusSet:messageAttachmentIds];
    NSMutableSet<NSString *> *missingAttachmentIds = [messageAttachmentIds mutableCopy];
    [missingAttachmentIds minusSet:attachmentIds];

    CleanupLogDebug(@"%@ orphan attachmentIds: %zd", self.logTag, orphanAttachmentIds.count);
    CleanupLogDebug(@"%@ missing attachmentIds: %zd", self.logTag, missingAttachmentIds.count);
    CleanupLogDebug(@"%@ orphan interactions: %zd", self.logTag, orphanInteractionIds.count);

    // We need to avoid cleaning up new attachments and files that are still in the process of
    // being created/written, so we don't clean up anything recent.
#ifdef SSK_BUILDING_FOR_TESTS
    const NSTimeInterval kMinimumOrphanAge = 0.f;
#else
    const NSTimeInterval kMinimumOrphanAge = 15 * kMinuteInterval;
#endif

    if (!shouldCleanup) {
        return;
    }

    [databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        for (NSString *interactionId in orphanInteractionIds) {
            TSInteraction *interaction = [TSInteraction fetchObjectWithUniqueID:interactionId transaction:transaction];
            if (!interaction) {
                // This could just be a race condition, but it should be very unlikely.
                OWSFail(@"%@ Could not load interaction: %@", self.logTag, interactionId);
                continue;
            }
            CleanupLogInfo(@"%@ Removing orphan message: %@", self.logTag, interaction.uniqueId);
            [interaction removeWithTransaction:transaction];
        }
        for (NSString *attachmentId in orphanAttachmentIds) {
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            if (!attachment) {
                // This can happen on launch since we sync contacts/groups, especially if you have a lot of attachments
                // to churn through, it's likely it's been deleted since starting this job.
                DDLogWarn(@"%@ Could not load attachment: %@", self.logTag, attachmentId);
                continue;
            }
            if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                continue;
            }
            TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
            // Don't delete attachments which were created in the last N minutes.
            if (fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]) < kMinimumOrphanAge) {
                CleanupLogInfo(@"%@ Skipping orphan attachment due to age: %f", self.logTag,
                    fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]));
                continue;
            }
            CleanupLogInfo(@"%@ Removing orphan attachmentStream from DB: %@", self.logTag, attachmentStream.uniqueId);
            [attachmentStream removeWithTransaction:transaction];
        }
    }];

    for (NSString *filePath in orphanDiskFilePaths) {
        NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (!attributes || error) {
            OWSFail(@"%@ Could not get attributes of file at: %@", self.logTag, filePath);
            continue;
        }
        // Don't delete files which were created in the last N minutes.
        if (fabs([attributes.fileModificationDate timeIntervalSinceNow]) < kMinimumOrphanAge) {
            CleanupLogInfo(@"%@ Skipping orphan attachment file due to age: %f", self.logTag,
                fabs([attributes.fileModificationDate timeIntervalSinceNow]));
            continue;
        }

        CleanupLogInfo(@"%@ Deleting orphan attachment file: %@", self.logTag, filePath);
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (error) {
            OWSFail(@"%@ Could not remove orphan file at: %@", self.logTag, filePath);
        }
    }

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
}

+ (void)printPaths:(NSArray<NSString *> *)paths label:(NSString *)label
{
    for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        CleanupLogDebug(@"%@ %@: %@", self.logTag, label, path);
    }
}

+ (NSSet<NSString *> *)filePathsInAttachmentsFolder
{
    NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
    CleanupLogDebug(@"%@ attachmentsFolder: %@", self.logTag, attachmentsFolder);

    return [self filePathsInDirectory:attachmentsFolder];
}

+ (NSSet<NSString *> *)filePathsInDirectory:(NSString *)dirPath
{
    NSMutableSet *filePaths = [NSMutableSet new];
    NSError *error;
    NSArray<NSString *> *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
    if (error) {
        OWSFail(@"%@ contentsOfDirectoryAtPath error: %@", self.logTag, error);
        return [NSSet new];
    }
    for (NSString *fileName in fileNames) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
        BOOL isDirectory;
        [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
        if (isDirectory) {
            [filePaths addObjectsFromArray:[self filePathsInDirectory:filePath].allObjects];
        } else {
            [filePaths addObject:filePath];
        }
    }
    return filePaths;
}

+ (long long)fileSizeOfFilePath:(NSString *)filePath
{
    NSError *error;
    NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize];
    if (error) {
        OWSFail(@"%@ attributesOfItemAtPath: %@ error: %@", self.logTag, filePath, error);
        return 0;
    }
    return fileSize.longLongValue;
}

+ (long long)fileSizeOfFilePaths:(NSArray<NSString *> *)filePaths
{
    long long result = 0;
    for (NSString *filePath in filePaths) {
        result += [self fileSizeOfFilePath:filePath];
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
