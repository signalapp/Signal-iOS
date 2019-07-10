//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "FunctionalUtil.h"
#import "OWSAttachmentDownloads.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSPrimaryStorage.h"
#import "OWSReadReceiptManager.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSAttachmentPointer.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/OWSUnknownProtocolVersionMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRecordTranscriptJob

#pragma mark - Dependencies

+ (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

+ (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
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
        OWSLogInfo(@"EndSession was sent to recipient: %@.", transcript.recipientAddress);
        [self.sessionStore deleteAllSessionsForAddress:transcript.recipientAddress transaction:transaction.asAnyWrite];

        // MJK TODO - we don't use this timestamp, safe to remove
        [[[TSInfoMessage alloc] initWithTimestamp:transcript.timestamp
                                         inThread:transcript.thread
                                      messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

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
        [self insertUnknownProtocolVersionErrorForTranscript:transcript transaction:transaction.asAnyWrite];
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
                                                     messageSticker:transcript.messageSticker
                                perMessageExpirationDurationSeconds:transcript.perMessageExpirationDurationSeconds];

    NSArray<TSAttachmentPointer *> *attachmentPointers =
        [TSAttachmentPointer attachmentPointersFromProtos:transcript.attachmentPointerProtos
                                             albumMessage:outgoingMessage];
    for (TSAttachmentPointer *pointer in attachmentPointers) {
        [pointer anyInsertWithTransaction:transaction.asAnyWrite];
        [outgoingMessage.attachmentIds addObject:pointer.uniqueId];
    }

    TSQuotedMessage *_Nullable quotedMessage = transcript.quotedMessage;
    if (quotedMessage && quotedMessage.thumbnailAttachmentPointerId) {
        // We weren't able to derive a local thumbnail, so we'll fetch the referenced attachment.
        TSAttachment *_Nullable attachment =
            [TSAttachment anyFetchWithUniqueId:quotedMessage.thumbnailAttachmentPointerId
                                   transaction:transaction.asAnyRead];

        if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)attachment;

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
                                                                         transaction:transaction.asAnyWrite];

    if (transcript.isExpirationTimerUpdate) {
        // early return to avoid saving an empty incoming message.
        OWSAssertDebug(transcript.body.length == 0);
        OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
        
        return;
    }

    if (!outgoingMessage.hasRenderableContent) {
        OWSFailDebug(@"Ignoring message transcript for empty message.");
        return;
    }

    NSArray<NSString *> *transitional_udRecipientPhoneNumbers =
        [transcript.udRecipientAddresses map:^NSString *(SignalServiceAddress *address) {
            return address.transitional_phoneNumber;
        }];
    NSArray<NSString *> *transitional_nonUdRecipientPhoneNumbers =
        [transcript.nonUdRecipientAddresses map:^NSString *(SignalServiceAddress *address) {
            return address.transitional_phoneNumber;
        }];

    [outgoingMessage saveWithTransaction:transaction];
    [outgoingMessage updateWithWasSentFromLinkedDeviceWithUDRecipientIds:transitional_udRecipientPhoneNumbers
                                                       nonUdRecipientIds:transitional_nonUdRecipientPhoneNumbers
                                                            isSentUpdate:NO
                                                             transaction:transaction];
    [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:outgoingMessage
                                                     expirationStartedAt:transcript.expirationStartedAt
                                                             transaction:transaction.asAnyWrite];
    [self.readReceiptManager applyEarlyReadReceiptsForOutgoingMessageFromLinkedDevice:outgoingMessage
                                                                          transaction:transaction.asAnyWrite];
    [PerMessageExpiration expireIfNecessaryWithMessage:outgoingMessage
                                           transaction:transaction.asAnyWrite];

    if (outgoingMessage.hasAttachments) {
        [self.attachmentDownloads
            downloadAllAttachmentsForMessage:outgoingMessage
                                 transaction:transaction.asAnyRead
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

+ (void)insertUnknownProtocolVersionErrorForTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transcript.thread);
    OWSAssertDebug(transaction);
    OWSAssertDebug(transcript.requiredProtocolVersion != nil);

    OWSFailDebug(@"Unknown protocol version: %@", transcript.requiredProtocolVersion);

    TSInteraction *message =
        [[OWSUnknownProtocolVersionMessage alloc] initWithTimestamp:transcript.timestamp
                                                             thread:transcript.thread
                                                           senderId:nil
                                                    protocolVersion:transcript.requiredProtocolVersion.intValue];
    [message anyInsertWithTransaction:transaction];
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

    if (transcript.udRecipientAddresses.count < 1 && transcript.nonUdRecipientAddresses.count < 1) {
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
            (int)transcript.nonUdRecipientAddresses.count,
            (int)transcript.udRecipientAddresses.count);

        NSArray<NSString *> *transitional_udRecipientPhoneNumbers =
            [transcript.udRecipientAddresses map:^NSString *(SignalServiceAddress *address) {
                return address.transitional_phoneNumber;
            }];
        NSArray<NSString *> *transitional_nonUdRecipientPhoneNumbers =
            [transcript.nonUdRecipientAddresses map:^NSString *(SignalServiceAddress *address) {
                return address.transitional_phoneNumber;
            }];

        [message updateWithWasSentFromLinkedDeviceWithUDRecipientIds:transitional_udRecipientPhoneNumbers
                                                   nonUdRecipientIds:transitional_nonUdRecipientPhoneNumbers
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
