//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "OWSAttachmentDownloads.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSReadReceiptManager.h"
#import "SSKEnvironment.h"
#import "TSAttachmentPointer.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRecordTranscriptJob

#pragma mark - Dependencies

+ (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

+ (TSNetworkManager *)networkManager
{
    OWSAssertDebug(SSKEnvironment.shared.networkManager);

    return SSKEnvironment.shared.networkManager;
}

+ (OWSReadReceiptManager *)readReceiptManager
{
    OWSAssert(SSKEnvironment.shared.readReceiptManager);

    return SSKEnvironment.shared.readReceiptManager;
}

+ (id<ContactsManagerProtocol>)contactsManager
{
    OWSAssertDebug(SSKEnvironment.shared.contactsManager);

    return SSKEnvironment.shared.contactsManager;
}

+ (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

#pragma mark -

+ (void)processIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)transcript
                           attachmentHandler:(void (^)(
                                                 NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transcript);
    OWSAssertDebug(transaction);

    if (transcript.isRecipientUpdate) {
        // "Recipient updates" are processed completely separately in order
        // to avoid resurrecting threads or messages.
        [self processRecipientUpdateWithTranscript:transcript transaction:transaction];
        return;
    }

    OWSLogInfo(@"Recording transcript in thread: %@ timestamp: %llu", transcript.thread.uniqueId, transcript.timestamp);

    if (transcript.isEndSessionMessage) {
        OWSLogInfo(@"EndSession was sent to recipient: %@.", transcript.recipientId);
        [self.primaryStorage deleteAllSessionsForContact:transcript.recipientId protocolContext:transaction];

        // MJK TODO - we don't use this timestamp, safe to remove
        [[[TSInfoMessage alloc] initWithTimestamp:transcript.timestamp
                                         inThread:transcript.thread
                                      messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

        // Don't continue processing lest we print a bubble for the session reset.
        return;
    }

    // TODO group updates. Currently desktop doesn't support group updates, so not a problem yet.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:transcript.timestamp
                                                           inThread:transcript.thread
                                                        messageBody:transcript.body
                                                      attachmentIds:[NSMutableArray new]
                                                   expiresInSeconds:transcript.expirationDuration
                                                    expireStartedAt:transcript.expirationStartedAt
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMetaMessageUnspecified
                                                      quotedMessage:transcript.quotedMessage
                                                       contactShare:transcript.contact
                                                        linkPreview:transcript.linkPreview
                                                     messageSticker:transcript.messageSticker];

    NSArray<TSAttachmentPointer *> *attachmentPointers =
        [TSAttachmentPointer attachmentPointersFromProtos:transcript.attachmentPointerProtos
                                             albumMessage:outgoingMessage];
    for (TSAttachmentPointer *pointer in attachmentPointers) {
        [pointer saveWithTransaction:transaction];
        [outgoingMessage.attachmentIds addObject:pointer.uniqueId];
    }

    TSQuotedMessage *_Nullable quotedMessage = transcript.quotedMessage;
    if (quotedMessage && quotedMessage.thumbnailAttachmentPointerId) {
        // We weren't able to derive a local thumbnail, so we'll fetch the referenced attachment.
        TSAttachmentPointer *attachmentPointer =
            [TSAttachmentPointer fetchObjectWithUniqueID:quotedMessage.thumbnailAttachmentPointerId
                                             transaction:transaction];

        if ([attachmentPointer isKindOfClass:[TSAttachmentPointer class]]) {
            OWSLogDebug(@"downloading attachments for transcript: %lu", (unsigned long)transcript.timestamp);

            [self.attachmentDownloads downloadAttachmentPointer:attachmentPointer
                message:outgoingMessage
                success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                    OWSAssertDebug(attachmentStreams.count == 1);
                    TSAttachmentStream *attachmentStream = attachmentStreams.firstObject;
                    [self.primaryStorage.newDatabaseConnection
                        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                            [outgoingMessage setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                            [outgoingMessage saveWithTransaction:transaction];
                        }];
                }
                failure:^(NSError *error) {
                    OWSLogWarn(@"failed to fetch thumbnail for transcript: %lu with error: %@",
                        (unsigned long)transcript.timestamp,
                        error);
                }];
        }
    }

    [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithDisappearingDuration:outgoingMessage.expiresInSeconds
                                                                              thread:transcript.thread
                                                          createdByRemoteRecipientId:nil
                                                              createdInExistingGroup:NO
                                                                         transaction:transaction];

    if (transcript.isExpirationTimerUpdate) {
        // early return to avoid saving an empty incoming message.
        OWSAssertDebug(transcript.body.length == 0);
        OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
        
        return;
    }

    if (outgoingMessage.body.length < 1 && outgoingMessage.attachmentIds.count < 1 && !outgoingMessage.contactShare) {
        OWSFailDebug(@"Ignoring message transcript for empty message.");
        return;
    }

    [outgoingMessage saveWithTransaction:transaction];
    [outgoingMessage updateWithWasSentFromLinkedDeviceWithUDRecipientIds:transcript.udRecipientIds
                                                       nonUdRecipientIds:transcript.nonUdRecipientIds
                                                            isSentUpdate:NO
                                                             transaction:transaction];
    [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:outgoingMessage
                                                     expirationStartedAt:transcript.expirationStartedAt
                                                             transaction:transaction];
    [self.readReceiptManager applyEarlyReadReceiptsForOutgoingMessageFromLinkedDevice:outgoingMessage
                                                                          transaction:transaction];

    if (outgoingMessage.hasAttachments) {
        [self.attachmentDownloads
            downloadAllAttachmentsForMessage:outgoingMessage
                                 transaction:transaction
                                     success:attachmentHandler
                                     failure:^(NSError *error) {
                                         OWSLogError(@"failed to fetch transcripts attachments for message: %@",
                                             outgoingMessage);
                                     }];
    }

    if (outgoingMessage.messageSticker != nil) {
        [StickerManager.shared setHasUsedStickersWithTransaction:transaction.asAnyWrite];
    }
}

#pragma mark -

+ (void)processRecipientUpdateWithTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transcript);
    OWSAssertDebug(transaction);

    if (!AreRecipientUpdatesEnabled()) {
        OWSFailDebug(@"Ignoring 'recipient update' transcript; disabled.");
        return;
    }

    if (transcript.udRecipientIds.count < 1 && transcript.nonUdRecipientIds.count < 1) {
        OWSFailDebug(@"Ignoring empty 'recipient update' transcript.");
        return;
    }

    uint64_t timestamp = transcript.timestamp;
    if (timestamp < 1) {
        OWSFailDebug(@"'recipient update' transcript has invalid timestamp.");
        return;
    }

    if (!transcript.thread.isGroupThread) {
        OWSFailDebug(@"'recipient update' has missing or invalid thread.");
        return;
    }
    TSGroupThread *groupThread = (TSGroupThread *)transcript.thread;
    NSData *groupId = groupThread.groupModel.groupId;
    if (groupId.length < 1) {
        OWSFailDebug(@"'recipient update' transcript has invalid groupId.");
        return;
    }

    NSArray<TSOutgoingMessage *> *messages
        = (NSArray<TSOutgoingMessage *> *)[TSInteraction interactionsWithTimestamp:timestamp
                                                                           ofClass:[TSOutgoingMessage class]
                                                                   withTransaction:transaction];
    if (messages.count < 1) {
        // This message may have disappeared.
        OWSLogError(@"No matching message with timestamp: %llu.", timestamp);
        return;
    }

    BOOL messageFound = NO;
    for (TSOutgoingMessage *message in messages) {
        if (!message.isFromLinkedDevice) {
            // isFromLinkedDevice isn't always set for very old linked messages, but:
            //
            // a) We should never receive a "sent update" for a very old message.
            // b) It's safe to discard suspicious "sent updates."
            continue;
        }
        TSThread *thread = [message threadWithTransaction:transaction.asAnyRead];
        if (!thread.isGroupThread) {
            continue;
        }
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        if (![groupThread.groupModel.groupId isEqual:groupId]) {
            continue;
        }

        if (!message.isFromLinkedDevice) {
            OWSFailDebug(@"Ignoring 'recipient update' for message which was sent locally.");
            continue;
        }

        OWSLogInfo(@"Processing 'recipient update' transcript in thread: %@, timestamp: %llu, nonUdRecipientIds: %d, "
                   @"udRecipientIds: %d.",
            thread.uniqueId,
            timestamp,
            (int)transcript.nonUdRecipientIds.count,
            (int)transcript.udRecipientIds.count);

        [message updateWithWasSentFromLinkedDeviceWithUDRecipientIds:transcript.udRecipientIds
                                                   nonUdRecipientIds:transcript.nonUdRecipientIds
                                                        isSentUpdate:YES
                                                         transaction:transaction];

        messageFound = YES;
    }

    if (!messageFound) {
        // This message may have disappeared.
        OWSLogError(@"No matching message with timestamp: %llu.", timestamp);
    }
}

@end

NS_ASSUME_NONNULL_END
