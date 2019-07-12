//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

@interface OWSIncomingSentMessageTranscript ()

@property (nonatomic, readonly) SSKProtoDataMessage *dataMessage;

@end

#pragma mark -

@implementation OWSIncomingSentMessageTranscript

- (instancetype)initWithProto:(SSKProtoSyncMessageSent *)sentProto
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    _dataMessage = sentProto.message;
    _recipientAddress = sentProto.destinationAddress;
    _timestamp = sentProto.timestamp;
    _expirationStartedAt = sentProto.expirationStartTimestamp;
    _expirationDuration = sentProto.message.expireTimer;
    _body = _dataMessage.body;
    _dataMessageTimestamp = _dataMessage.timestamp;
    _groupId = _dataMessage.group.id;
    _isGroupUpdate = (_dataMessage.group != nil && _dataMessage.group.hasType
        && _dataMessage.group.unwrappedType == SSKProtoGroupContextTypeUpdate);
    _isExpirationTimerUpdate = (_dataMessage.flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0;
    _isEndSessionMessage = (_dataMessage.flags & SSKProtoDataMessageFlagsEndSession) != 0;
    _isRecipientUpdate = sentProto.isRecipientUpdate;
    _perMessageExpirationDurationSeconds = _dataMessage.messageTimer;

    if (self.dataMessage.hasRequiredProtocolVersion) {
        _requiredProtocolVersion = @(self.dataMessage.requiredProtocolVersion);
    }

    if (self.isRecipientUpdate) {
        // Fetch, don't create.  We don't want recipient updates to resurrect messages or threads.
        if (self.dataMessage.group) {
            _thread = [TSGroupThread threadWithGroupId:_dataMessage.group.id transaction:transaction.asAnyRead];
        } else {
            OWSFailDebug(@"We should never receive a 'recipient update' for messages in contact threads.");
        }
        // Skip the other processing for recipient updates.
    } else {
        if (self.dataMessage.group) {
            _thread =
                [TSGroupThread getOrCreateThreadWithGroupId:_dataMessage.group.id transaction:transaction.asAnyWrite];
        } else {
            _thread = [TSContactThread getOrCreateThreadWithContactAddress:_recipientAddress
                                                               transaction:transaction.asAnyWrite];
        }

        _quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:_dataMessage
                                                               thread:_thread
                                                          transaction:transaction.asAnyWrite];
        _contact = [OWSContacts contactForDataMessage:_dataMessage transaction:transaction.asAnyWrite];

        NSError *linkPreviewError;
        _linkPreview = [OWSLinkPreview buildValidatedLinkPreviewWithDataMessage:_dataMessage
                                                                           body:_body
                                                                    transaction:transaction.asAnyWrite
                                                                          error:&linkPreviewError];
        if (linkPreviewError && ![OWSLinkPreview isNoPreviewError:linkPreviewError]) {
            OWSLogError(@"linkPreviewError: %@", linkPreviewError);
        }

        NSError *stickerError;
        _messageSticker = [MessageSticker buildValidatedMessageStickerWithDataMessage:_dataMessage
                                                                          transaction:transaction.asAnyWrite
                                                                                error:&stickerError];
        if (stickerError && ![MessageSticker isNoStickerError:stickerError]) {
            OWSFailDebug(@"stickerError: %@", stickerError);
        }
    }

    if (sentProto.unidentifiedStatus.count > 0) {
        NSMutableArray<SignalServiceAddress *> *nonUdRecipientAddresses = [NSMutableArray new];
        NSMutableArray<SignalServiceAddress *> *udRecipientAddresses = [NSMutableArray new];
        for (SSKProtoSyncMessageSentUnidentifiedDeliveryStatus *statusProto in sentProto.unidentifiedStatus) {
            if (!statusProto.hasValidDestination) {
                OWSFailDebug(@"Delivery status proto is missing destination.");
                continue;
            }
            if (!statusProto.hasUnidentified) {
                OWSFailDebug(@"Delivery status proto is missing value.");
                continue;
            }
            SignalServiceAddress *recipientAddress = statusProto.destinationAddress;
            if (statusProto.unidentified) {
                [udRecipientAddresses addObject:recipientAddress];
            } else {
                [nonUdRecipientAddresses addObject:recipientAddress];
            }
        }
        _nonUdRecipientAddresses = [nonUdRecipientAddresses copy];
        _udRecipientAddresses = [udRecipientAddresses copy];
    }

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
