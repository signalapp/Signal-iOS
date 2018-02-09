//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSReadReceiptManager.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+SessionStore.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecordTranscriptJob ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;

@property (nonatomic, readonly) OWSIncomingSentMessageTranscript *incomingSentMessageTranscript;

@end

@implementation OWSRecordTranscriptJob

- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
{
    return [self initWithIncomingSentMessageTranscript:incomingSentMessageTranscript
                                        networkManager:TSNetworkManager.sharedManager
                                        storageManager:TSStorageManager.sharedManager
                                    readReceiptManager:OWSReadReceiptManager.sharedManager
                                       contactsManager:[TextSecureKitEnv sharedEnv].contactsManager];
}

- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                                       networkManager:(TSNetworkManager *)networkManager
                                       storageManager:(TSStorageManager *)storageManager
                                   readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _incomingSentMessageTranscript = incomingSentMessageTranscript;
    _networkManager = networkManager;
    _storageManager = storageManager;
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

    TSThread *thread = [transcript threadWithTransaction:transaction];
    if (transcript.isEndSessionMessage) {
        DDLogInfo(@"%@ EndSession was sent to recipient: %@.", self.logTag, transcript.recipientId);
        [self.storageManager deleteAllSessionsForContact:transcript.recipientId protocolContext:transaction];
        [[[TSInfoMessage alloc] initWithTimestamp:transcript.timestamp
                                         inThread:thread
                                      messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

        // Don't continue processing lest we print a bubble for the session reset.
        return;
    }

    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:transcript.attachmentPointerProtos
                                                        timestamp:transcript.timestamp
                                                            relay:transcript.relay
                                                           thread:thread
                                                   networkManager:self.networkManager
                                                   storageManager:self.storageManager
                                                      transaction:transaction];

    // TODO group updates. Currently desktop doesn't support group updates, so not a problem yet.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initWithTimestamp:transcript.timestamp
                                            inThread:thread
                                         messageBody:transcript.body
                                       attachmentIds:[attachmentsProcessor.attachmentIds mutableCopy]
                                    expiresInSeconds:transcript.expirationDuration
                                     expireStartedAt:transcript.expirationStartedAt];

    if (transcript.isExpirationTimerUpdate) {
        [OWSDisappearingMessagesJob becomeConsistentWithConfigurationForMessage:outgoingMessage
                                                                contactsManager:self.contactsManager];
        // early return to avoid saving an empty incoming message.
        return;
    }

    if (outgoingMessage.body.length < 1 && outgoingMessage.attachmentIds.count < 1) {
        OWSFail(@"Ignoring message transcript for empty message.");
        return;
    }

    [outgoingMessage saveWithTransaction:transaction];
    [outgoingMessage updateWithWasSentFromLinkedDeviceWithTransaction:transaction];
    [OWSDisappearingMessagesJob becomeConsistentWithConfigurationForMessage:outgoingMessage
                                                            contactsManager:self.contactsManager];
    [OWSDisappearingMessagesJob setExpirationForMessage:outgoingMessage
                                    expirationStartedAt:transcript.expirationStartedAt];
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

    // If there is an attachment + text, render the text here, as Signal-iOS renders two messages.
    if (attachmentsProcessor.hasSupportedAttachments && transcript.body && ![transcript.body isEqualToString:@""]) {
        // We want the text to appear after the attachment.
        uint64_t textMessageTimestamp = transcript.timestamp + 1;
        TSOutgoingMessage *textMessage = [[TSOutgoingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                             inThread:thread
                                                                          messageBody:transcript.body
                                                                        attachmentIds:[NSMutableArray new]
                                                                     expiresInSeconds:transcript.expirationDuration
                                                                      expireStartedAt:transcript.expirationStartedAt];
        // Since textMessage is a new message, updateWithWasSentAndDelivered will save it.
        [textMessage saveWithTransaction:transaction];
        [textMessage updateWithWasSentFromLinkedDeviceWithTransaction:transaction];
    }
}

@end

NS_ASSUME_NONNULL_END
