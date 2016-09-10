//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSIncomingSentMessageTranscript.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSMessagesManager.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"

// Thread finding imports
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingSentMessageTranscript ()

@property (nonatomic, readonly) NSString *relay;
@property (nonatomic, readonly) OWSSignalServiceProtosDataMessage *dataMessage;
@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) uint64_t timestamp;

@end

@implementation OWSIncomingSentMessageTranscript

- (instancetype)initWithProto:(OWSSignalServiceProtosSyncMessageSent *)sentProto relay:(NSString *)relay
{
    self = [super init];
    if (!self) {
        return self;
    }

    _relay = relay;
    _dataMessage = sentProto.message;
    _recipientId = sentProto.destination;
    _timestamp = sentProto.timestamp;

    return self;
}


- (void)record
{
    TSThread *thread;

    if (self.dataMessage.hasGroup) {
        thread = [TSGroupThread getOrCreateThreadWithGroupIdData:self.dataMessage.group.id];
    } else {
        thread = [TSContactThread getOrCreateThreadWithContactId:self.recipientId];
    }

    NSData *avatarGroupId;
    NSArray<OWSSignalServiceProtosAttachmentPointer *> *attachmentPointerProtos;
    if (self.dataMessage.hasGroup && (self.dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate)) {
        avatarGroupId = self.dataMessage.group.id;
        attachmentPointerProtos = @[ self.dataMessage.group.avatar ];
    } else {
        attachmentPointerProtos = self.dataMessage.attachments;
    }

    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointersProtos:attachmentPointerProtos
                                                                timestamp:self.timestamp
                                                                    relay:self.relay
                                                            avatarGroupId:avatarGroupId
                                                                 inThread:thread
                                                          messagesManager:[TSMessagesManager sharedManager]];

    // TODO group updates. Currently desktop doesn't support group updates, so not a problem yet.
    TSOutgoingMessage *outgoingMessage =
        [[TSOutgoingMessage alloc] initWithTimestamp:self.timestamp
                                            inThread:thread
                                         messageBody:self.dataMessage.body
                                       attachmentIds:attachmentsProcessor.attachmentIds];
    outgoingMessage.messageState = TSOutgoingMessageStateDelivered;
    [outgoingMessage save];

    [attachmentsProcessor fetchAttachmentsForMessageId:outgoingMessage.uniqueId];

    // If there is an attachment + text, render the text here, as Signal-iOS renders two messages.
    if (attachmentsProcessor.hasSupportedAttachments && self.dataMessage.body != nil
        && ![self.dataMessage.body isEqualToString:@""]) {

        // render text *after* the attachment
        uint64_t textMessageTimestamp = self.timestamp + 1000;
        TSOutgoingMessage *textMessage = [[TSOutgoingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                             inThread:thread
                                                                          messageBody:self.dataMessage.body];
        textMessage.messageState = TSOutgoingMessageStateDelivered;
        [textMessage save];
    }
}

@end

NS_ASSUME_NONNULL_END
