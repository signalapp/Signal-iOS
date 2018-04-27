//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingSentMessageTranscript.h"
#import "OWSContactShare.h"
#import "OWSMessageManager.h"
#import "OWSPrimaryStorage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSIncomingSentMessageTranscript

- (instancetype)initWithProto:(OWSSignalServiceProtosSyncMessageSent *)sentProto
                        relay:(nullable NSString *)relay
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _relay = relay;
    _dataMessage = sentProto.message;
    _recipientId = sentProto.destination;
    _timestamp = sentProto.timestamp;
    _expirationStartedAt = sentProto.expirationStartTimestamp;
    _expirationDuration = sentProto.message.expireTimer;
    _body = _dataMessage.body;
    _groupId = _dataMessage.group.id;
    _isGroupUpdate = _dataMessage.hasGroup && (_dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate);
    _isExpirationTimerUpdate = (_dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0;
    _isEndSessionMessage = (_dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0;

    if (self.dataMessage.hasGroup) {
        _thread = [TSGroupThread getOrCreateThreadWithGroupId:_dataMessage.group.id transaction:transaction];
    } else {
        _thread = [TSContactThread getOrCreateThreadWithContactId:_recipientId transaction:transaction];
    }

    _quotedMessage =
        [TSQuotedMessage quotedMessageForDataMessage:_dataMessage thread:_thread relay:relay transaction:transaction];
    _contactShare = [OWSContactShare contactShareForDataMessage:_dataMessage transaction:transaction];

    return self;
}

- (NSArray<OWSSignalServiceProtosAttachmentPointer *> *)attachmentPointerProtos
{
    if (self.isGroupUpdate && self.dataMessage.group.hasAvatar) {
        return @[ self.dataMessage.group.avatar ];
    } else {
        return self.dataMessage.attachments;
    }
}

@end

NS_ASSUME_NONNULL_END
