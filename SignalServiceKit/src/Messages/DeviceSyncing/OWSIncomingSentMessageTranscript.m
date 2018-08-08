//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingSentMessageTranscript.h"
#import "OWSContact.h"
#import "OWSMessageManager.h"
#import "OWSPrimaryStorage.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSIncomingSentMessageTranscript

- (instancetype)initWithProto:(SSKProtoSyncMessageSent *)sentProto
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _dataMessage = sentProto.message;
    _recipientId = sentProto.destination;
    _timestamp = sentProto.timestamp;
    _expirationStartedAt = sentProto.expirationStartTimestamp;
    _expirationDuration = sentProto.message.expireTimer;
    _body = _dataMessage.body;
    _groupId = _dataMessage.group.id;
    _isGroupUpdate = _dataMessage.group != nil && (_dataMessage.group.type == SSKProtoGroupContextTypeUpdate);
    _isExpirationTimerUpdate = (_dataMessage.flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0;
    _isEndSessionMessage = (_dataMessage.flags & SSKProtoDataMessageFlagsEndSession) != 0;

    if (self.dataMessage.group) {
        _thread = [TSGroupThread getOrCreateThreadWithGroupId:_dataMessage.group.id transaction:transaction];
    } else {
        _thread = [TSContactThread getOrCreateThreadWithContactId:_recipientId transaction:transaction];
    }

    _quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:_dataMessage thread:_thread transaction:transaction];
    _contact = [OWSContacts contactForDataMessage:_dataMessage transaction:transaction];

    return self;
}

- (NSArray<SSKProtoAttachmentPointer *> *)attachmentPointerProtos
{
    if (self.isGroupUpdate && self.dataMessage.group.avatar) {
        return @[ self.dataMessage.group.avatar ];
    } else {
        return self.dataMessage.attachments;
    }
}

@end

NS_ASSUME_NONNULL_END
