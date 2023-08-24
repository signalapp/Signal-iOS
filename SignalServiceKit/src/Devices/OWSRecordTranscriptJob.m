//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSRecordTranscriptJob.h"
#import "FunctionalUtil.h"
#import "HTTPUtils.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSReceiptManager.h"
#import "OWSUnknownProtocolVersionMessage.h"
#import "TSAttachmentPointer.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRecordTranscriptJob

+ (void)processIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                 transaction:(SDSAnyWriteTransaction *)transaction
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

    if (![SDS fitsInInt64:transcript.timestamp]) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    if (transcript.isEndSessionMessage) {
        if (!transcript.recipientAddress) {
            OWSFailDebug(@"Missing recipient address for end session message!");
            return;
        }

        OWSLogInfo(@"EndSession was sent to recipient: %@.", transcript.recipientAddress);
        [self archiveSessionsFor:transcript.recipientAddress transaction:transaction];

        TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithThread:transcript.thread
                                                               messageType:TSInfoMessageTypeSessionDidEnd];
        [infoMessage anyInsertWithTransaction:transaction];

        // Don't continue processing lest we print a bubble for the session reset.
        return;
    }

    if (transcript.timestamp < 1) {
        OWSFailDebug(@"Transcript is missing timestamp.");
        // This transcript is invalid, discard it.
        return;
    } else if (transcript.timestamp != transcript.dataMessageTimestamp) {
        OWSLogVerbose(
            @"Transcript timestamps do not match: %llu != %llu", transcript.timestamp, transcript.dataMessageTimestamp);
        OWSFailDebug(@"Transcript timestamps do not match, discarding message.");
        // This transcript is invalid, discard it.
        return;
    }

    if (transcript.requiredProtocolVersion != nil
        && transcript.requiredProtocolVersion.integerValue > SSKProtos.currentProtocolVersion) {
        [self insertUnknownProtocolVersionErrorForTranscript:transcript transaction:transaction];
        return;
    }

    uint64_t messageTimestamp = (transcript.serverTimestamp > 0 ? transcript.serverTimestamp : transcript.timestamp);
    OWSAssertDebug(messageTimestamp > 0);

    if (transcript.paymentNotification != nil) {
        OWSLogInfo(@"Processing payment notification from sync transcript.");
        [self.paymentsHelper processReceivedTranscriptPaymentNotificationWithThread:transcript.thread
                                                                paymentNotification:transcript.paymentNotification
                                                                   messageTimestamp:messageTimestamp
                                                                        transaction:transaction];
        return;
    }

    // The builder() factory method requires us to specify every
    // property so that this will break if we add any new properties.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessageBuilder builderWithThread:transcript.thread
                                           timestamp:transcript.timestamp
                                         messageBody:transcript.body
                                          bodyRanges:transcript.bodyRanges
                                       attachmentIds:@[]
                                    expiresInSeconds:transcript.expirationDuration
                                     expireStartedAt:transcript.expirationStartedAt
                                      isVoiceMessage:false
                                    groupMetaMessage:TSGroupMetaMessageUnspecified
                                       quotedMessage:transcript.quotedMessage
                                        contactShare:transcript.contact
                                         linkPreview:transcript.linkPreview
                                      messageSticker:transcript.messageSticker
                                   isViewOnceMessage:transcript.isViewOnceMessage
                              changeActionsProtoData:nil
                                additionalRecipients:nil
                                   skippedRecipients:nil
                                      storyAuthorAci:transcript.storyAuthorAci
                                      storyTimestamp:transcript.storyTimestamp
                                  storyReactionEmoji:nil
                                           giftBadge:transcript.giftBadge] buildWithTransaction:transaction];

    LocalIdentifiersObjC *_Nullable localIdentifiers = [self.tsAccountManager localIdentifiersObjCWithTx:transaction];
    if (localIdentifiers == nil) {
        OWSFailDebug(@"Missing localIdentifiers.");
        return;
    }

    if ([transcript.thread isKindOfClass:[TSContactThread class]]) {
        [GroupManager remoteUpdateDisappearingMessagesWithContactThread:(TSContactThread *)transcript.thread
                                               disappearingMessageToken:transcript.disappearingMessageToken
                                                           changeAuthor:localIdentifiers.aci
                                                       localIdentifiers:localIdentifiers
                                                            transaction:transaction];
    }

    if (transcript.isExpirationTimerUpdate) {
        // early return to avoid saving an empty incoming message.
        OWSAssertDebug(transcript.body.length == 0);
        OWSAssertDebug(transcript.attachmentPointerProtos.count == 0);

        return;
    }

    // Typically `hasRenderableContent` will depend on whether or not the message has any attachmentIds
    // But since outgoingMessage is partially built and doesn't have the attachments yet, we check
    // for attachments explicitly.
    BOOL outgoingMessageHasContent
        = (outgoingMessage.hasRenderableContent || transcript.attachmentPointerProtos.count > 0);
    if (!outgoingMessageHasContent && !outgoingMessage.isViewOnceMessage) {
        if (transcript.thread.isGroupV2Thread) {
            // This is probably a v2 group update.
            OWSLogWarn(@"Ignoring message transcript for empty v2 group message.");
        } else {
            OWSLogWarn(@"Ignoring message transcript for empty message.");
        }
        return;
    }

    // Check for any placeholders inserted because of a previously undecryptable message
    // The sender may have resent the message. If so, we should swap it in place of the placeholder
    [outgoingMessage insertOrReplacePlaceholderFrom:localIdentifiers.aciAddress transaction:transaction];

    NSArray<TSAttachmentPointer *> *attachmentPointers =
        [TSAttachmentPointer attachmentPointersFromProtos:transcript.attachmentPointerProtos
                                             albumMessage:outgoingMessage];
    NSMutableArray<NSString *> *attachmentIds = [outgoingMessage.attachmentIds mutableCopy];
    for (TSAttachmentPointer *pointer in attachmentPointers) {
        [pointer anyInsertWithTransaction:transaction];
        [attachmentIds addObject:pointer.uniqueId];
    }
    if (outgoingMessage.attachmentIds.count != attachmentIds.count) {
        [outgoingMessage anyUpdateOutgoingMessageWithTransaction:transaction
                                                           block:^(TSOutgoingMessage *message) {
                                                               message.attachmentIds = [attachmentIds copy];
                                                           }];
    }
    OWSAssertDebug(outgoingMessage.hasRenderableContent);

    [outgoingMessage updateWithWasSentFromLinkedDeviceWithUDRecipients:transcript.udRecipients
                                                       nonUdRecipients:transcript.nonUdRecipients
                                                          isSentUpdate:NO
                                                           transaction:transaction];
    // The insert and update methods above may start expiration for this message, but
    // transcript.expirationStartedAt may be earlier, so we need to pass that to
    // the OWSDisappearingMessagesJob in case it needs to back-date the expiration.
    [[OWSDisappearingMessagesJob shared] startAnyExpirationForMessage:outgoingMessage
                                                  expirationStartedAt:transcript.expirationStartedAt
                                                          transaction:transaction];

    [self.earlyMessageManager applyPendingMessagesFor:outgoingMessage transaction:transaction];

    if (outgoingMessage.isViewOnceMessage) {
        // Don't download attachments for "view-once" messages from linked devices.
        // To be extra-conservative, always mark as complete immediately.
        [ViewOnceMessages markAsCompleteWithMessage:outgoingMessage sendSyncMessages:NO transaction:transaction];
    } else {
        [self.attachmentDownloads enqueueDownloadOfAttachmentsForNewMessage:outgoingMessage transaction:transaction];
    }
}

+ (void)insertUnknownProtocolVersionErrorForTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transcript.thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(transcript.requiredProtocolVersion != nil);

    OWSFailDebug(@"Unknown protocol version: %@", transcript.requiredProtocolVersion);

    if (![SDS fitsInInt64:transcript.timestamp]) {
        OWSFailDebug(@"Invalid timestamp.");
        return;
    }

    TSInteraction *message =
        [[OWSUnknownProtocolVersionMessage alloc] initWithThread:transcript.thread
                                                          sender:nil
                                                 protocolVersion:transcript.requiredProtocolVersion.intValue];
    [message anyInsertWithTransaction:transaction];
}

#pragma mark -

+ (void)processRecipientUpdateWithTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transcript);
    OWSAssertDebug(transaction);

    if (transcript.udRecipients.count < 1 && transcript.nonUdRecipients.count < 1) {
        OWSFailDebug(@"Ignoring empty 'recipient update' transcript.");
        return;
    }

    uint64_t timestamp = transcript.timestamp;
    if (timestamp < 1) {
        OWSFailDebug(@"'recipient update' transcript has invalid timestamp.");
        return;
    }
    if (![SDS fitsInInt64:timestamp]) {
        OWSFailDebug(@"Invalid timestamp.");
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

    NSError *error;
    NSArray<TSOutgoingMessage *> *messages = (NSArray<TSOutgoingMessage *> *)[InteractionFinder
        interactionsWithTimestamp:timestamp
                           filter:^(TSInteraction *interaction) {
                               return [interaction isKindOfClass:[TSOutgoingMessage class]];
                           }
                      transaction:transaction
                            error:&error];
    if (error != nil) {
        OWSFailDebug(@"Error loading interactions: %@", error);
        return;
    }

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
        if (![message.uniqueThreadId isEqualToString:groupThread.uniqueId]) {
            continue;
        }

        OWSLogInfo(@"Processing 'recipient update' transcript in thread: %@, timestamp: %llu, nonUdRecipientIds: %d, "
                   @"udRecipientIds: %d.",
            groupThread.uniqueId,
            timestamp,
            (int)transcript.nonUdRecipients.count,
            (int)transcript.udRecipients.count);

        [message updateWithWasSentFromLinkedDeviceWithUDRecipients:transcript.udRecipients
                                                   nonUdRecipients:transcript.nonUdRecipients
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
