//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIDiskUsage.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIDiskUsage

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Orphans & Disk Usage";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    return [OWSTableSection sectionWithTitle:self.name
                                       items:@[
                                           [OWSTableItem itemWithTitle:@"Audit & Log"
                                                           actionBlock:^{
                                                               [DebugUIDiskUsage auditWithoutCleanup];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Audit & Clean Up"
                                                           actionBlock:^{
                                                               [DebugUIDiskUsage auditWithCleanup];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Save All Attachments"
                                                           actionBlock:^{
                                                               [DebugUIDiskUsage saveAllAttachments];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Delete Messages older than 3 Months"
                                                           actionBlock:^{
                                                               [DebugUIDiskUsage deleteOldMessages_3Months];
                                                           }],
                                       ]];
}

+ (void)auditWithoutCleanup
{
    [self auditAndCleanup:NO];
}

+ (void)auditWithCleanup
{
    [self auditAndCleanup:YES];
}

+ (void)auditAndCleanup:(BOOL)shouldCleanup
{
    NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
    DDLogError(@"attachmentsFolder: %@", attachmentsFolder);

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

    __block int attachmentStreamCount = 0;
    NSMutableSet<NSString *> *attachmentFilePaths = [NSMutableSet new];
    NSMutableSet<NSString *> *attachmentIds = [NSMutableSet new];
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager.newDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
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

    DDLogError(@"fileCount: %d", fileCount);
    DDLogError(@"totalFileSize: %lld", totalFileSize);
    DDLogError(@"attachmentStreams: %d", attachmentStreamCount);
    DDLogError(@"attachmentStreams with file paths: %zd", attachmentFilePaths.count);

    NSMutableSet<NSString *> *orphanDiskFilePaths = [diskFilePaths mutableCopy];
    [orphanDiskFilePaths minusSet:attachmentFilePaths];
    NSMutableSet<NSString *> *missingAttachmentFilePaths = [attachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:diskFilePaths];

    DDLogError(@"orphan disk file paths: %zd", orphanDiskFilePaths.count);
    DDLogError(@"missing attachment file paths: %zd", missingAttachmentFilePaths.count);

    [self printPaths:orphanDiskFilePaths.allObjects label:@"orphan disk file paths"];
    [self printPaths:missingAttachmentFilePaths.allObjects label:@"missing attachment file paths"];

    NSMutableSet *threadIds = [NSMutableSet new];
    [storageManager.newDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [transaction enumerateKeysInCollection:TSThread.collection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        [threadIds addObject:key];
                                    }];
    }];

    NSMutableSet<TSInteraction *> *orphanInteractions = [NSMutableSet new];
    NSMutableSet<NSString *> *messageAttachmentIds = [NSMutableSet new];
    [storageManager.newDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:TSMessage.collection
                                              usingBlock:^(NSString *key, TSInteraction *interaction, BOOL *stop) {
                                                  if (![threadIds containsObject:interaction.uniqueThreadId]) {
                                                      [orphanInteractions addObject:interaction];
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

    DDLogError(@"attachmentIds: %zd", attachmentIds.count);
    DDLogError(@"messageAttachmentIds: %zd", messageAttachmentIds.count);

    NSMutableSet<NSString *> *orphanAttachmentIds = [attachmentIds mutableCopy];
    [orphanAttachmentIds minusSet:messageAttachmentIds];
    NSMutableSet<NSString *> *missingAttachmentIds = [messageAttachmentIds mutableCopy];
    [missingAttachmentIds minusSet:attachmentIds];

    DDLogError(@"orphan attachmentIds: %zd", orphanAttachmentIds.count);
    DDLogError(@"missing attachmentIds: %zd", missingAttachmentIds.count);

    DDLogError(@"orphan interactions: %zd", orphanInteractions.count);

    if (shouldCleanup) {
        [storageManager.newDatabaseConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                for (TSInteraction *interaction in orphanInteractions) {
                    [interaction removeWithTransaction:transaction];
                }
                for (NSString *attachmentId in orphanAttachmentIds) {
                    TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId];
                    OWSAssert(attachment);
                    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                        continue;
                    }
                    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                    // Don't delete attachments which were created in the last N minutes.
                    const NSTimeInterval kMinimumOrphanAttachmentAge = 2 * 60.f;
                    if (fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]) < kMinimumOrphanAttachmentAge) {
                        DDLogInfo(@"Skipping orphan attachment due to age: %f",
                            fabs([attachmentStream.creationTimestamp timeIntervalSinceNow]));
                        continue;
                    }
                    [attachmentStream removeWithTransaction:transaction];
                }
            }];

        for (NSString *filePath in orphanDiskFilePaths) {
            NSError *error;
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
            if (error) {
                OWSFail(@"Could not remove orphan file at: %@", filePath);
            }
        }
    }
}

+ (void)printPaths:(NSArray<NSString *> *)paths label:(NSString *)label
{
    for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        DDLogError(@"%@: %@", label, path);
    }
}

+ (void)saveAllAttachments
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager.newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {

        NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray new];
        [transaction enumerateKeysAndObjectsInCollection:TSAttachmentStream.collection
                                              usingBlock:^(NSString *key, TSAttachment *attachment, BOOL *stop) {
                                                  if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                                                      return;
                                                  }
                                                  TSAttachmentStream *attachmentStream
                                                      = (TSAttachmentStream *)attachment;
                                                  [attachmentStreams addObject:attachmentStream];
                                              }];

        DDLogInfo(@"Saving %zd attachment streams.", attachmentStreams.count);

        // Persist the new localRelativeFilePath property of TSAttachmentStream.
        // For performance, we want to upgrade all existing attachment streams in
        // a single transaction.
        for (TSAttachmentStream *attachmentStream in attachmentStreams) {
            [attachmentStream saveWithTransaction:transaction];
        }
    }];
}

+ (void)deleteOldMessages_3Months
{
    NSTimeInterval kMinute = 60.f;
    NSTimeInterval kHour = 60 * kMinute;
    NSTimeInterval kDay = 24 * kHour;
    NSTimeInterval kMonth = 30 * kDay;
    [self deleteOldMessages:kMonth * 3];
}

+ (void)deleteOldMessages:(NSTimeInterval)maxAgeSeconds
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager.newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {

        NSMutableArray<NSString *> *threadIds = [NSMutableArray new];
        YapDatabaseViewTransaction *interactionsByThread = [transaction ext:TSMessageDatabaseViewExtensionName];
        [interactionsByThread enumerateGroupsUsingBlock:^(NSString *group, BOOL *stop) {
            [threadIds addObject:group];
        }];
        NSMutableArray<TSInteraction *> *interactionsToDelete = [NSMutableArray new];
        for (NSString *threadId in threadIds) {
            [interactionsByThread enumerateKeysAndObjectsInGroup:threadId
                                                      usingBlock:^(NSString *collection,
                                                          NSString *key,
                                                          TSInteraction *interaction,
                                                          NSUInteger index,
                                                          BOOL *stop) {
                                                          NSTimeInterval ageSeconds
                                                              = fabs(interaction.dateForSorting.timeIntervalSinceNow);
                                                          if (ageSeconds < maxAgeSeconds) {
                                                              *stop = YES;
                                                              return;
                                                          }
                                                          [interactionsToDelete addObject:interaction];
                                                      }];
        }

        DDLogInfo(@"Deleting %zd interactions.", interactionsToDelete.count);

        for (TSInteraction *interaction in interactionsToDelete) {
            [interaction removeWithTransaction:transaction];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
