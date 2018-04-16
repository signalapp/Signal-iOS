//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSReadReceiptManager.h"
#import "TSAttachmentPointer.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecordTranscriptJob ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;

@property (nonatomic, readonly) OWSIncomingSentMessageTranscript *incomingSentMessageTranscript;

@end

@implementation OWSRecordTranscriptJob

- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
{
    return [self initWithIncomingSentMessageTranscript:incomingSentMessageTranscript
                                        networkManager:TSNetworkManager.sharedManager
                                        primaryStorage:OWSPrimaryStorage.sharedManager
                                    readReceiptManager:OWSReadReceiptManager.sharedManager
                                       contactsManager:[TextSecureKitEnv sharedEnv].contactsManager];
}

- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                                       networkManager:(TSNetworkManager *)networkManager
                                       primaryStorage:(OWSPrimaryStorage *)primaryStorage
                                   readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _incomingSentMessageTranscript = incomingSentMessageTranscript;
    _networkManager = networkManager;
    _primaryStorage = primaryStorage;
    _readReceiptManager = readReceiptManager;
    _contactsManager = contactsManager;

    return self;
}

- (void)runWithAttachmentHandler:(void (^)(TSAttachmentStream *attachmentStream))attachmentHandler
                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    OWSIncomingSentMessageTranscript *transcript = self.incomingSentMessageTranscript;
    DDLogDebug(@"%@ Recording transcript: %@", self.logTag, transcript);

    if (transcript.isEndSessionMessage) {
        DDLogInfo(@"%@ EndSession was sent to recipient: %@.", self.logTag, transcript.recipientId);
        [self.primaryStorage deleteAllSessionsForContact:transcript.recipientId protocolContext:transaction];
        [[[TSInfoMessage alloc] initWithTimestamp:transcript.timestamp
                                         inThread:transcript.thread
                                      messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

        // Don't continue processing lest we print a bubble for the session reset.
        return;
    }

    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:transcript.attachmentPointerProtos
                                                            relay:transcript.relay
                                                   networkManager:self.networkManager
                                                      transaction:transaction];


    // TODO group updates. Currently desktop doesn't support group updates, so not a problem yet.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:transcript.timestamp
                                                           inThread:transcript.thread
                                                        messageBody:transcript.body
                                                      attachmentIds:[attachmentsProcessor.attachmentIds mutableCopy]
                                                   expiresInSeconds:transcript.expirationDuration
                                                    expireStartedAt:transcript.expirationStartedAt
                                                     isVoiceMessage:NO
                                                   groupMetaMessage:TSGroupMessageNone
                                                      quotedMessage:transcript.quotedMessage];

    // TODO: When written, desktop didn't yet support sending quotedMessages, so we didn't have a
    // good way to test the handling of transcripts with a quotedMessage. This assertion can be delete
    // once we've tested transcripts with quoted messages are processed correctly.
    OWSAssert(transcript.quotedMessage == nil);

    TSQuotedMessage *_Nullable quotedMessage = transcript.quotedMessage;
    if (quotedMessage && quotedMessage.thumbnailAttachmentPointerId) {
        // We weren't able to derive a local thumbnail, so we'll fetch the referenced attachment.
        TSAttachmentPointer *attachmentPointer =
            [TSAttachmentPointer fetchObjectWithUniqueID:quotedMessage.thumbnailAttachmentPointerId
                                             transaction:transaction];

        if ([attachmentPointer isKindOfClass:[TSAttachmentPointer class]]) {
            OWSAttachmentsProcessor *attachmentProcessor =
                [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                            networkManager:self.networkManager];

            DDLogDebug(@"%@ downloading thumbnail for transcript: %tu", self.logTag, transcript.timestamp);
            [attachmentProcessor fetchAttachmentsForMessage:outgoingMessage
                transaction:transaction
                success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                    [self.primaryStorage.newDatabaseConnection
                        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                            [outgoingMessage setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                            [outgoingMessage saveWithTransaction:transaction];
                        }];
                }
                failure:^(NSError *_Nonnull error) {
                    DDLogWarn(@"%@ failed to fetch thumbnail for transcript: %tu with error: %@",
                        self.logTag,
                        transcript.timestamp,
                        error);
                }];
        }
    }

    if (transcript.isExpirationTimerUpdate) {
        [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithConfigurationForMessage:outgoingMessage
                                                                            contactsManager:self.contactsManager
                                                                                transaction:transaction];
        // early return to avoid saving an empty incoming message.
        OWSAssert(transcript.body.length == 0);
        OWSAssert(outgoingMessage.attachmentIds.count == 0);
        
        return;
    }

    if (outgoingMessage.body.length < 1 && outgoingMessage.attachmentIds.count < 1) {
        OWSFail(@"Ignoring message transcript for empty message.");
        return;
    }

    [outgoingMessage saveWithTransaction:transaction];
    [outgoingMessage updateWithWasSentFromLinkedDeviceWithTransaction:transaction];
    [[OWSDisappearingMessagesJob sharedJob] becomeConsistentWithConfigurationForMessage:outgoingMessage
                                                                        contactsManager:self.contactsManager
                                                                            transaction:transaction];
    [[OWSDisappearingMessagesJob sharedJob] setExpirationForMessage:outgoingMessage
                                                expirationStartedAt:transcript.expirationStartedAt
                                                        transaction:transaction];
    [self.readReceiptManager applyEarlyReadReceiptsForOutgoingMessageFromLinkedDevice:outgoingMessage
                                                                          transaction:transaction];

    [attachmentsProcessor
        fetchAttachmentsForMessage:outgoingMessage
                       transaction:transaction
                           success:attachmentHandler
                           failure:^(NSError *_Nonnull error) {
                               DDLogError(@"%@ failed to fetch transcripts attachments for message: %@",
                                   self.logTag,
                                   outgoingMessage);
                           }];
}

@end

NS_ASSUME_NONNULL_END
