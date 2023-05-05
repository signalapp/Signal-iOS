//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIDiskUsage.h"
#import "OWSOrphanDataCleaner.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIDiskUsage

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Orphans & Disk Usage";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    return [OWSTableSection
        sectionWithTitle:self.name
                   items:@[
                       [OWSTableItem itemWithTitle:@"Audit & Log"
                                       actionBlock:^{ [OWSOrphanDataCleaner auditAndCleanup:NO]; }],
                       [OWSTableItem itemWithTitle:@"Audit & Clean Up"
                                       actionBlock:^{ [OWSOrphanDataCleaner auditAndCleanup:YES]; }],
                       [OWSTableItem itemWithTitle:@"Save All Attachments"
                                       actionBlock:^{ [DebugUIDiskUsage saveAllAttachments]; }],
                       [OWSTableItem itemWithTitle:@"Clear All Attachment Thumbnails"
                                       actionBlock:^{ [DebugUIDiskUsage clearAllAttachmentThumbnails]; }],
                       [OWSTableItem itemWithTitle:@"Delete Messages older than 3 Months"
                                       actionBlock:^{ [DebugUIDiskUsage deleteOldMessages_3Months]; }],
                   ]];
}

+ (void)saveAllAttachments
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray new];
        [TSAttachment anyEnumerateWithTransaction:transaction
                                            block:^(TSAttachment *attachment, BOOL *stop) {
                                                if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                                                    return;
                                                }
                                                TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                                                [attachmentStreams addObject:attachmentStream];
                                            }];

        OWSLogInfo(@"Saving %zd attachment streams.", attachmentStreams.count);

        // Persist the new localRelativeFilePath property of TSAttachmentStream.
        // For performance, we want to upgrade all existing attachment streams in
        // a single transaction.
        for (TSAttachmentStream *attachmentStream in attachmentStreams) {
            [attachmentStream anyUpdateWithTransaction:transaction
                                                 block:^(TSAttachment *attachment){
                                                     // Do nothing, rewriting is sufficient.
                                                 }];
        }
    });
}

+ (void)clearAllAttachmentThumbnails
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL *> *cachesContents =
        [fileManager enumeratorAtURL:[NSURL fileURLWithPath:OWSFileSystem.cachesDirectoryPath]
            includingPropertiesForKeys:@[]
                               options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                          errorHandler:^BOOL(NSURL *url, NSError *error) {
                              OWSLogWarn(@"could not visit %@: %@", url, error);
                              return YES;
                          }];

    NSUInteger removedCount = 0;
    for (NSURL *cacheItem in cachesContents) {
        NSString *itemName = [cacheItem lastPathComponent];
        if (!([itemName hasSuffix:@"-thumbnails"] || [itemName hasSuffix:@"-signal-ios-thumbnail.jpg"])) {
            continue;
        }
        NSError *error;
        if ([fileManager removeItemAtURL:cacheItem error:&error]) {
            removedCount += 1;
        } else {
            OWSLogWarn(@"could not remove %@: %@", itemName, error);
        }
    }

    OWSLogInfo(@"removed thumbnails for %ld attachments", removedCount);
}

+ (void)deleteOldMessages_3Months
{
    [self deleteOldMessages:kMonthInterval * 3];
}

+ (void)deleteOldMessages:(NSTimeInterval)maxAgeSeconds
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSArray<NSString *> *threadIds = [TSThread anyAllUniqueIdsWithTransaction:transaction];
        NSMutableArray<TSInteraction *> *interactionsToDelete = [NSMutableArray new];
        for (NSString *threadId in threadIds) {
            InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:threadId];
            NSError *error;
            [interactionFinder
                enumerateRecentInteractionsWithTransaction:transaction
                                                     error:&error
                                                     block:^(TSInteraction *interaction, BOOL *stop) {
                                                         NSTimeInterval ageSeconds
                                                             = fabs(interaction.receivedAtDate.timeIntervalSinceNow);
                                                         if (ageSeconds >= maxAgeSeconds) {
                                                             [interactionsToDelete addObject:interaction];
                                                         }
                                                     }];
        }

        OWSLogInfo(@"Deleting %zd interactions.", interactionsToDelete.count);

        for (TSInteraction *interaction in interactionsToDelete) {
            [interaction anyRemoveWithTransaction:transaction];
        }
    });
}

@end

NS_ASSUME_NONNULL_END

#endif
