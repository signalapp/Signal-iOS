//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentPointer.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFailedAttachmentDownloadsJob

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

@end

NS_ASSUME_NONNULL_END
