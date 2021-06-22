//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSIncomingSentMessageTranscript.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/OWSUnknownProtocolVersionMessage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

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
        OWSLogInfo(@"EndSession was sent to recipient: %@.", transcript.recipientAddress);
        [self.sessionStore archiveAllSessionsForAddress:transcript.recipientAddress transaction:transaction];

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
    } else if (transcript.dataMessageTimestamp < 1) {
        OWSLogError(@"Transcript is missing data message timestamp.");
        // Legacy desktop doesn't supply data message timestamp;
        // ignore until desktop are in production.
        if (SSKFeatureFlags.strictSyncTranscriptTimestamps) {
            OWSFailDebug(@"Transcript timestamps do not match, discarding message.");
            return;
        }
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

    if (transcript.paymentRequest != nil) {
        OWSLogInfo(@"Processing payment request from sync transcript.");
        [self.payments processReceivedTranscriptPaymentRequestWithThread:transcript.thread
                                                          paymentRequest:transcript.paymentRequest
                                                        messageTimestamp:messageTimestamp
                                                             transaction:transaction];
        return;
    } else if (transcript.paymentNotification != nil) {
        OWSLogInfo(@"Processing payment notification from sync transcript.");
        [self.payments processReceivedTranscriptPaymentNotificationWithThread:transcript.thread
                                                          paymentNotification:transcript.paymentNotification
                                                             messageTimestamp:messageTimestamp
                                                                  transaction:transaction];
        return;
    } else if (transcript.paymentCancellation != nil) {
        OWSLogInfo(@"Processing payment cancellation from sync transcript.");
        [self.payments processReceivedTranscriptPaymentCancellationWithThread:transcript.thread
                                                          paymentCancellation:transcript.paymentCancellation
                                                             messageTimestamp:messageTimestamp
                                                                  transaction:transaction];
        return;
    }

    // The builder() factory method requires us to specify every
    // property so that this will break if we add any new properties.
    TSOutgoingMessage *outgoingMessage = [[TSOutgoingMessageBuilder builderWithThread:transcript.thread
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
                                                                 additionalRecipients:nil] build];

    NSArray<TSAttachmentPointer *> *attachmentPointers =
        [TSAttachmentPointer attachmentPointersFromProtos:transcript.attachmentPointerProtos
                                             albumMessage:outgoingMessage];
    NSMutableArray<NSString *> *attachmentIds = [outgoingMessage.attachmentIds mutableCopy];
    for (TSAttachmentPointer *pointer in attachmentPointers) {
        [pointer anyInsertWithTransaction:transaction];
        [attachmentIds addObject:pointer.uniqueId];
    }
    outgoingMessage.attachmentIds = [attachmentIds copy];

    if (!transcript.thread.isGroupV2Thread) {
        SignalServiceAddress *_Nullable localAddress = self.tsAccountManager.localAddress;
        if (localAddress == nil) {
            OWSFailDebug(@"Missing localAddress.");
            return;
        }

        [GroupManager remoteUpdateDisappearingMessagesWithContactOrV1GroupThread:transcript.thread
                                                        disappearingMessageToken:transcript.disappearingMessageToken
                                                        groupUpdateSourceAddress:localAddress
                                                                     transaction:transaction];
    }

    if (transcript.isExpirationTimerUpdate) {
        // early return to avoid saving an empty incoming message.
        OWSAssertDebug(transcript.body.length == 0);
        OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
        
        return;
    }

    if (!outgoingMessage.hasRenderableContent && !outgoingMessage.isViewOnceMessage) {
        if (transcript.thread.isGroupV2Thread) {
            // This is probably a v2 group update.
            OWSLogWarn(@"Ignoring message transcript for empty v2 group message.");
        } else {
            OWSLogWarn(@"Ignoring message transcript for empty message.");
        }
        return;
    }

    [outgoingMessage anyInsertWithTransaction:transaction];
    [outgoingMessage updateWithWasSentFromLinkedDeviceWithUDRecipientAddresses:transcript.udRecipientAddresses
                                                       nonUdRecipientAddresses:transcript.nonUdRecipientAddresses
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

    if (!SSKFeatureFlags.sendRecipientUpdates) {
        OWSFailDebug(@"Ignoring 'recipient update' transcript; disabled.");
        return;
    }

    if (transcript.udRecipientAddresses.count < 1 && transcript.nonUdRecipientAddresses.count < 1) {
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
        TSThread *thread = [message threadWithTransaction:transaction];
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
            (int)transcript.nonUdRecipientAddresses.count,
            (int)transcript.udRecipientAddresses.count);

        [message updateWithWasSentFromLinkedDeviceWithUDRecipientAddresses:transcript.udRecipientAddresses
                                                   nonUdRecipientAddresses:transcript.nonUdRecipientAddresses
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
