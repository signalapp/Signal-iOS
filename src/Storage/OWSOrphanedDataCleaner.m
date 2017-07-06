//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOrphanedDataCleaner.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "TSMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"

@implementation OWSOrphanedDataCleaner

+ (void)auditAsync
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [OWSOrphanedDataCleaner auditAndCleanup:NO];
    });
}

+ (void)auditAndCleanupAsync
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [OWSOrphanedDataCleaner auditAndCleanup:YES];
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
+ (void)auditAndCleanup:(BOOL)shouldCleanup
{
    NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
    DDLogDebug(@"attachmentsFolder: %@", attachmentsFolder);

    __block int fileCount = 0;
    __block long long totalFileSize = 0;
    NSMutableSet *diskFilePaths = [NSMutableSet new];
    __unsafe_unretained __block void (^visitAttachmentFilesRecursable)(NSString *);
    void (^visitAttachmentFiles)(NSString *);
    visitAttachmentFiles = ^(NSString *dirPath) {
        NSError *error;
        NSArray<NSString *> *fileNames =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
        if (error) {
            OWSFail(@"contentsOfDirectoryAtPath error: %@", error);
            return;
        }
        for (NSString *fileName in fileNames) {
            NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
            BOOL isDirectory;
            [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
            if (isDirectory) {
                visitAttachmentFilesRecursable(filePath);
            } else {
                NSNumber *fileSize =
                    [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize];
                if (error) {
                    OWSFail(@"attributesOfItemAtPath: %@ error: %@", filePath, error);
                    continue;
                }
                totalFileSize += fileSize.longLongValue;
                fileCount++;
                [diskFilePaths addObject:filePath];
            }
        }
    };
    visitAttachmentFilesRecursable = visitAttachmentFiles;
    visitAttachmentFiles(attachmentsFolder);

    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    YapDatabaseConnection *databaseConnection = storageManager.newDatabaseConnection;

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
                                              }];
    }];

    DDLogDebug(@"fileCount: %d", fileCount);
    DDLogDebug(@"totalFileSize: %lld", totalFileSize);
    DDLogDebug(@"attachmentStreams: %d", attachmentStreamCount);
    DDLogDebug(@"attachmentStreams with file paths: %zd", attachmentFilePaths.count);

    NSMutableSet<NSString *> *orphanDiskFilePaths = [diskFilePaths mutableCopy];
    [orphanDiskFilePaths minusSet:attachmentFilePaths];
    NSMutableSet<NSString *> *missingAttachmentFilePaths = [attachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:diskFilePaths];

    DDLogDebug(@"orphan disk file paths: %zd", orphanDiskFilePaths.count);
    DDLogDebug(@"missing attachment file paths: %zd", missingAttachmentFilePaths.count);

    [self printPaths:orphanDiskFilePaths.allObjects label:@"orphan disk file paths"];
    [self printPaths:missingAttachmentFilePaths.allObjects label:@"missing attachment file paths"];

    NSMutableSet *threadIds = [NSMutableSet new];
    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [transaction enumerateKeysInCollection:TSThread.collection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        [threadIds addObject:key];
                                    }];
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

    DDLogDebug(@"attachmentIds: %zd", attachmentIds.count);
    DDLogDebug(@"messageAttachmentIds: %zd", messageAttachmentIds.count);

    NSMutableSet<NSString *> *orphanAttachmentIds = [attachmentIds mutableCopy];
    [orphanAttachmentIds minusSet:messageAttachmentIds];
    NSMutableSet<NSString *> *missingAttachmentIds = [messageAttachmentIds mutableCopy];
    [missingAttachmentIds minusSet:attachmentIds];

    DDLogDebug(@"orphan attachmentIds: %zd", orphanAttachmentIds.count);
    DDLogDebug(@"missing attachmentIds: %zd", missingAttachmentIds.count);
    DDLogDebug(@"orphan interactions: %zd", orphanInteractionIds.count);

    // We need to avoid cleaning up new attachments and files that are still in the process of
    // being created/written, so we don't clean up anything recent.
    const NSTimeInterval kMinimumOrphanAge = 15 * 60.f;

    if (!shouldCleanup) {
        return;
    }

    [databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        for (NSString *interactionId in orphanInteractionIds) {
            TSInteraction *interaction = [TSInteraction fetchObjectWithUniqueID:interactionId];
            if (!interaction) {
                // This could just be a race condition, but it should be very unlikely.
                OWSFail(@"Could not load interaction: %@", interactionId);
                continue;
            }
            DDLogInfo(@"Removing orphan message: %@", interaction.uniqueId);
            [interaction removeWithTransaction:transaction];
        }
        for (NSString *attachmentId in orphanAttachmentIds) {
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
            if (!attachment) {
                // This could just be a race condition, but it should be very unlikely.
                OWSFail(@"Could not load attachment: %@", attachmentId);
                continue;
            }
            if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                continue;
            }
            TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
            // Don't delete attachments which were created in the last N minutes.
            if (fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]) < kMinimumOrphanAge) {
                DDLogInfo(@"Skipping orphan attachment due to age: %f",
                    fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]));
                continue;
            }
            DDLogInfo(@"Removing orphan attachment: %@", attachmentStream.uniqueId);
            [attachmentStream removeWithTransaction:transaction];
        }
    }];

    for (NSString *filePath in orphanDiskFilePaths) {
        NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        if (!attributes || error) {
            OWSFail(@"Could not get attributes of file at: %@", filePath);
            continue;
        }
        // Don't delete files which were created in the last N minutes.
        if (fabs([attributes.fileModificationDate timeIntervalSinceNow]) < kMinimumOrphanAge) {
            DDLogInfo(@"Skipping orphan attachment file due to age: %f",
                fabs([attributes.fileModificationDate timeIntervalSinceNow]));
            continue;
        }

        DDLogInfo(@"Removing orphan attachment file: %@", filePath);
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (error) {
            OWSFail(@"Could not remove orphan file at: %@", filePath);
        }
    }
}

+ (void)printPaths:(NSArray<NSString *> *)paths label:(NSString *)label
{
    for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        DDLogDebug(@"%@: %@", label, path);
    }
}

@end
