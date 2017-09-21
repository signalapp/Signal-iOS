//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageManager.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSContactThread.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

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
    _expirationStartedAt = sentProto.expirationStartTimestamp;
    _expirationDuration = sentProto.message.expireTimer;
    _body = _dataMessage.body;
    _groupId = _dataMessage.group.id;
    _isGroupUpdate = _dataMessage.hasGroup && (_dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate);
    _isExpirationTimerUpdate = (_dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0;
    _isEndSessionMessage = (_dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0;

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

- (TSThread *)threadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (self.dataMessage.hasGroup) {
        return [TSGroupThread getOrCreateThreadWithGroupIdData:self.dataMessage.group.id transaction:transaction];
    } else {
        return [TSContactThread getOrCreateThreadWithContactId:self.recipientId transaction:transaction];
    }
}

@end

NS_ASSUME_NONNULL_END
