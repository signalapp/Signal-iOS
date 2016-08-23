//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSOutgoingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _messageState = TSOutgoingMessageStateAttemptingOut;
    _hasSyncedTranscript = NO;

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        self.groupMetaMessage = TSGroupMessageDeliver;
    } else {
        self.groupMetaMessage = TSGroupMessageNone;
    }

    return self;
}

- (nullable NSString *)recipientIdentifier
{
    return self.thread.contactIdentifier;
}

- (OWSSignalServiceProtosDataMessage *)buildDataMessage
{
    TSThread *thread = self.thread;

    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setBody:self.body];
    BOOL processAttachments = YES;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];

        switch (self.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if (gThread.groupModel.groupImage != nil && [self.attachmentIds count] == 1) {
                    id dbObject = [TSAttachmentStream fetchObjectWithUniqueID:self.attachmentIds[0]];
                    if ([dbObject isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attachment = (TSAttachmentStream *)dbObject;
                        OWSSignalServiceProtosAttachmentPointerBuilder *attachmentbuilder =
                            [OWSSignalServiceProtosAttachmentPointerBuilder new];
                        [attachmentbuilder setId:[attachment.identifier unsignedLongLongValue]];
                        [attachmentbuilder setContentType:attachment.contentType];
                        [attachmentbuilder setKey:attachment.encryptionKey];
                        [groupBuilder setAvatar:[attachmentbuilder build]];
                        processAttachments = NO;
                    }
                }
                [groupBuilder setMembersArray:gThread.groupModel.groupMemberIds];
                [groupBuilder setName:gThread.groupModel.groupName];
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeUpdate];
                break;
            }
            default:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeDeliver];
                break;
        }
        [groupBuilder setId:gThread.groupModel.groupId];
        [builder setGroup:groupBuilder.build];
    }
    if (processAttachments) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            id dbObject = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];

            if ([dbObject isKindOfClass:[TSAttachmentStream class]]) {
                TSAttachmentStream *attachment = (TSAttachmentStream *)dbObject;

                OWSSignalServiceProtosAttachmentPointerBuilder *attachmentbuilder =
                    [OWSSignalServiceProtosAttachmentPointerBuilder new];
                [attachmentbuilder setId:[attachment.identifier unsignedLongLongValue]];
                [attachmentbuilder setContentType:attachment.contentType];
                [attachmentbuilder setKey:attachment.encryptionKey];

                [attachments addObject:[attachmentbuilder build]];
            }
        }
        [builder setAttachmentsArray:attachments];
    }
    return [builder build];
}

- (NSData *)buildPlainTextData
{
    return [[self buildDataMessage] data];
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
}

@end

NS_ASSUME_NONNULL_END
