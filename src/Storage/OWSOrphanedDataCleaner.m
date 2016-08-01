// Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSOrphanedDataCleaner.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "TSMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"

@implementation OWSOrphanedDataCleaner

- (void)removeOrphanedData
{
    // Remove interactions whose threads have been deleted
    for (NSString *interactionId in [self orphanedInteractionIds]) {
        DDLogWarn(@"Removing orphaned interaction with id: %@", interactionId);
        TSInteraction *interaction = [TSInteraction fetchObjectWithUniqueID:interactionId];
        [interaction remove];
    }

    // Remove any lingering attachments
    for (NSString *path in [self orphanedFilePaths]) {
        DDLogWarn(@"Removing orphaned file attachment at path: %@", path);
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        if (error) {
            DDLogError(@"Unable to remove orphaned file attachment at path:%@", path);
        }
    }
}

- (NSArray<NSString *> *)orphanedInteractionIds
{
    NSMutableArray *interactionIds = [NSMutableArray new];
    [[TSInteraction dbConnection] readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [TSInteraction enumerateCollectionObjectsWithTransaction:transaction
                                                      usingBlock:^(TSInteraction *interaction, BOOL *stop) {
                                                          TSThread *thread = [TSThread
                                                              fetchObjectWithUniqueID:interaction.uniqueThreadId
                                                                          transaction:transaction];
                                                          if (!thread) {
                                                              [interactionIds addObject:interaction.uniqueId];
                                                          }
                                                      }];
    }];


    return [interactionIds copy];
}

- (NSArray<NSString *> *)orphanedFilePaths
{
    NSError *error;
    NSMutableArray<NSString *> *filenames =
        [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[TSAttachmentStream attachmentsFolder] error:&error]
            mutableCopy];
    if (error) {
        DDLogError(@"error getting orphanedFilePaths:%@", error);
        return @[];
    }

    NSMutableDictionary<NSString *, NSString *> *attachmentIdFilenames = [NSMutableDictionary new];
    for (NSString *filename in filenames) {
        // Remove extension from (e.g.) 1234.png to get the attachmentId "1234"
        NSString *attachmentId = [filename stringByDeletingPathExtension];
        attachmentIdFilenames[attachmentId] = filename;
    }

    [TSInteraction enumerateCollectionObjectsUsingBlock:^(TSInteraction *interaction, BOOL *stop) {
        if ([interaction isKindOfClass:[TSMessage class]]) {
            TSMessage *message = (TSMessage *)interaction;
            if ([message hasAttachments]) {
                for (NSString *attachmentId in message.attachmentIds) {
                    [attachmentIdFilenames removeObjectForKey:attachmentId];
                }
            }
        }
    }];

    NSArray<NSString *> *filenamesToDelete = [attachmentIdFilenames allValues];
    NSMutableArray<NSString *> *absolutePathsToDelete = [NSMutableArray arrayWithCapacity:[filenamesToDelete count]];
    for (NSString *filename in filenamesToDelete) {
        NSString *absolutePath = [[TSAttachmentStream attachmentsFolder] stringByAppendingFormat:@"/%@", filename];
        [absolutePathsToDelete addObject:absolutePath];
    }

    return [absolutePathsToDelete copy];
}

@end
