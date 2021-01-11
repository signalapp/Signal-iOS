//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSPrimaryStorage.h"
#import "TSAttachmentPointer.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateColumn = @"state";
static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateIndex = @"index_attachment_downloads_on_state";

@implementation OWSFailedAttachmentDownloadsJob

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (NSArray<NSString *> *)unfailedAttachmentPointerIdsWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ != %d",
                                          OWSFailedAttachmentDownloadsJobAttachmentStateColumn,
                                          (int)TSAttachmentPointerStateFailed];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSFailedAttachmentDownloadsJobAttachmentStateIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [attachmentIds addObject:key];
                        }];

    return [attachmentIds copy];
}

- (void)enumerateAttemptingOutAttachmentsWithBlock:(void (^_Nonnull)(TSAttachmentPointer *attachment))block
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated attachments, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSAttachment objects one at a time.
    NSArray<NSString *> *attachmentIds = [AttachmentFinder unfailedAttachmentPointerIdsWithTransaction:transaction];
    for (NSString *attachmentId in attachmentIds) {
        TSAttachmentPointer *_Nullable attachment =
            [TSAttachmentPointer anyFetchAttachmentPointerWithUniqueId:attachmentId transaction:transaction];
        if (attachment == nil) {
            OWSFailDebug(@"Missing attachment.");
            continue;
        }
        block(attachment);
    }
}

- (void)runSync
{
    __block uint count = 0;
    DatabaseStorageWrite(
        self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self enumerateAttemptingOutAttachmentsWithBlock:^(TSAttachmentPointer *attachment) {
                // sanity check
                if (attachment.state == TSAttachmentPointerStateFailed) {
                    OWSFailDebug(@"Attachment has unexpected state.");
                    return;
                }

                switch (attachment.state) {
                    case TSAttachmentPointerStateFailed:
                        OWSFailDebug(@"Attachment has unexpected state.");
                        break;
                    case TSAttachmentPointerStatePendingMessageRequest:
                        // Do nothing. We don't want to mark this attachment as failed.
                        // It will be updated when the message request is resolved.
                        break;
                    case TSAttachmentPointerStateEnqueued:
                    case TSAttachmentPointerStateDownloading:
                        [attachment updateWithAttachmentPointerState:TSAttachmentPointerStateFailed
                                                         transaction:transaction];
                        count++;
                        return;
                    case TSAttachmentPointerStatePendingManualDownload:
                        // Do nothing. We don't want to mark this attachment as failed.
                        break;
                }
            }
                                                 transaction:transaction];
        });

    if (count > 0) {
        OWSLogDebug(@"Marked %u attachments as failed", count);
    }
}

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSFailedAttachmentDownloadsJobAttachmentStateColumn
            withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[TSAttachmentPointer class]]) {
                return;
            }
            TSAttachmentPointer *attachment = (TSAttachmentPointer *)object;
            dict[OWSFailedAttachmentDownloadsJobAttachmentStateColumn] = @(attachment.state);
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];
}

+ (NSString *)databaseExtensionName
{
    return OWSFailedAttachmentDownloadsJobAttachmentStateIndex;
}

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension]
                           withName:OWSFailedAttachmentDownloadsJobAttachmentStateIndex];
}

@end

NS_ASSUME_NONNULL_END
