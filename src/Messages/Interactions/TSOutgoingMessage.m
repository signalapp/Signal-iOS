//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSOutgoingMessage

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
{
    return [self initWithTimestamp:timestamp inThread:nil];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread
{
    return [self initWithTimestamp:timestamp inThread:thread messageBody:nil];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
{
    return [self initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:[NSMutableArray new]];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:attachmentIds
                  expiresInSeconds:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:attachmentIds
                  expiresInSeconds:expiresInSeconds
                   expireStartedAt:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt
{
    self = [super initWithTimestamp:timestamp
                           inThread:thread
                        messageBody:body
                      attachmentIds:attachmentIds
                   expiresInSeconds:expiresInSeconds
                    expireStartedAt:expireStartedAt];
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

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!(self.groupMetaMessage == TSGroupMessageDeliver || self.groupMetaMessage == TSGroupMessageNone)) {
        DDLogDebug(@"%@ Skipping save for group meta message.", self.tag);
        return;
    }

    [super saveWithTransaction:transaction];
}

- (nullable NSString *)recipientIdentifier
{
    return self.thread.contactIdentifier;
}

- (BOOL)shouldStartExpireTimer
{
    switch (self.messageState) {
        case TSOutgoingMessageStateSent:
        case TSOutgoingMessageStateDelivered:
            return self.isExpiringMessage;
        case TSOutgoingMessageStateAttemptingOut:
        case TSOutgoingMessageStateUnsent:
            return NO;
    }
}

- (void)setSendingError:(NSError *)error
{
    _mostRecentFailureText = error.localizedDescription;
}

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    TSThread *thread = self.thread;
    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setBody:self.body];
    BOOL attachmentWasGroupAvatar = NO;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];

        switch (self.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if (gThread.groupModel.groupImage != nil && self.attachmentIds.count == 1) {
                    attachmentWasGroupAvatar = YES;
                    [groupBuilder setAvatar:[self buildAttachmentProtoForAttachmentId:self.attachmentIds[0]]];
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
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            [attachments addObject:[self buildAttachmentProtoForAttachmentId:attachmentId]];
        }
        [builder setAttachmentsArray:attachments];
    }
    [builder setExpireTimer:self.expiresInSeconds];
    return builder;
}

- (OWSSignalServiceProtosDataMessage *)buildDataMessage
{
    return [[self dataMessageBuilder] build];
}

- (NSData *)buildPlainTextData
{
    return [[self buildDataMessage] data];
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
}

- (OWSSignalServiceProtosAttachmentPointer *)buildAttachmentProtoForAttachmentId:(NSString *)attachmentId
{
    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

    OWSSignalServiceProtosAttachmentPointerBuilder *builder = [OWSSignalServiceProtosAttachmentPointerBuilder new];
    [builder setId:attachmentStream.serverId];
    [builder setContentType:attachmentStream.contentType];
    [builder setKey:attachmentStream.encryptionKey];

    return [builder build];
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
