//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageSender.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+SessionStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecordTranscriptJob ()

@property (nonatomic, readonly) OWSIncomingSentMessageTranscript *incomingSentMessageTranscript;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;

@end

@implementation OWSRecordTranscriptJob

- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                                        messageSender:(OWSMessageSender *)messageSender
                                       networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _incomingSentMessageTranscript = incomingSentMessageTranscript;
    _messageSender = messageSender;
    _networkManager = networkManager;
    _storageManager = [TSStorageManager sharedManager];

    return self;
}

- (void)runWithAttachmentHandler:(void (^)(TSAttachmentStream *attachmentStream))attachmentHandler
{
    OWSIncomingSentMessageTranscript *transcript = self.incomingSentMessageTranscript;
    DDLogDebug(@"%@ Recording transcript: %@", self.tag, transcript);

    if (transcript.isEndSessionMessage) {
        DDLogInfo(@"%@ EndSession was sent to recipient: %@.", self.tag, transcript.recipientId);
        [self.storageManager deleteAllSessionsForContact:transcript.recipientId];
        [[[TSInfoMessage alloc] initWithTimestamp:transcript.timestamp
                                         inThread:transcript.thread
                                      messageType:TSInfoMessageTypeSessionDidEnd] save];

        // Don't continue processing lest we print a bubble for the session reset.
        return;
    }

    TSThread *thread = transcript.thread;
    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:transcript.attachmentPointerProtos
                                                        timestamp:transcript.timestamp
                                                            relay:transcript.relay
                                                           thread:thread
                                                   networkManager:self.networkManager];

    // TODO group updates. Currently desktop doesn't support group updates, so not a problem yet.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initWithTimestamp:transcript.timestamp
                                            inThread:thread
                                         messageBody:transcript.body
                                       attachmentIds:[attachmentsProcessor.attachmentIds mutableCopy]
                                    expiresInSeconds:transcript.expirationDuration
                                     expireStartedAt:transcript.expirationStartedAt];

    if (transcript.isExpirationTimerUpdate) {
        [self.messageSender becomeConsistentWithDisappearingConfigurationForMessage:outgoingMessage];
        // early return to avoid saving an empty incoming message.
        return;
    }

    [self.messageSender handleMessageSentRemotely:outgoingMessage sentAt:transcript.expirationStartedAt];

    [attachmentsProcessor
        fetchAttachmentsForMessage:outgoingMessage
                           success:attachmentHandler
                           failure:^(NSError *_Nonnull error) {
                               DDLogError(@"%@ failed to fetch transcripts attachments for message: %@",
                                   self.tag,
                                   outgoingMessage);
                           }];

    // If there is an attachment + text, render the text here, as Signal-iOS renders two messages.
    if (attachmentsProcessor.hasSupportedAttachments && transcript.body && ![transcript.body isEqualToString:@""]) {
        // render text *after* the attachment
        uint64_t textMessageTimestamp = transcript.timestamp + 1;
        TSOutgoingMessage *textMessage = [[TSOutgoingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                             inThread:thread
                                                                          messageBody:transcript.body
                                                                        attachmentIds:[NSMutableArray new]
                                                                     expiresInSeconds:transcript.expirationDuration
                                                                      expireStartedAt:transcript.expirationStartedAt];
        // Since textMessage is a new message, updateWithWasSentAndDelivered will save it.
        [textMessage updateWithWasSentAndDelivered];
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
