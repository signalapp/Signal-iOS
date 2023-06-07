//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSIncomingSentMessageTranscript.h"
#import "OWSContact.h"
#import "OWSMessageManager.h"
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

- (nullable instancetype)initWithProto:(SSKProtoSyncMessageSent *)sentProto
                       serverTimestamp:(uint64_t)serverTimestamp
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    self = [super init];
    if (!self) {
        return self;
    }

    BOOL isEdit = NO;
    if (sentProto.message != nil) {
        _dataMessage = sentProto.message;
    } else if (sentProto.editMessage.dataMessage != nil) {
        _dataMessage = sentProto.editMessage.dataMessage;
        isEdit = YES;
    } else {
        OWSFailDebug(@"Missing message.");
        return nil;
    }

    if (sentProto.timestamp < 1) {
        OWSFailDebug(@"Sent missing timestamp.");
        return nil;
    }
    _timestamp = sentProto.timestamp;
    _serverTimestamp = serverTimestamp;
    _expirationStartedAt = sentProto.expirationStartTimestamp;
    _expirationDuration = _dataMessage.expireTimer;
    _body = _dataMessage.body;
    if (_dataMessage.bodyRanges.count > 0) {
        _bodyRanges = [[MessageBodyRanges alloc] initWithProtos:_dataMessage.bodyRanges];
    }
    _dataMessageTimestamp = _dataMessage.timestamp;
    _disappearingMessageToken = [DisappearingMessageToken tokenForProtoExpireTimer:_dataMessage.expireTimer];

    SSKProtoGroupContextV2 *_Nullable groupContextV2 = _dataMessage.groupV2;
    if (groupContextV2 != nil) {
        NSData *_Nullable masterKey = groupContextV2.masterKey;
        if (masterKey.length < 1) {
            OWSFailDebug(@"Missing masterKey.");
            return nil;
        }
        NSError *_Nullable error;
        GroupV2ContextInfo *_Nullable contextInfo = [self.groupsV2 groupV2ContextInfoForMasterKeyData:masterKey
                                                                                                error:&error];
        if (error != nil || contextInfo == nil) {
            OWSFailDebug(@"Couldn't parse contextInfo: %@.", error);
            return nil;
        }
        _groupId = contextInfo.groupId;
        if (_groupId.length < 1) {
            OWSFailDebug(@"Missing groupId.");
            return nil;
        }
        if (![GroupManager isValidGroupId:_groupId groupsVersion:GroupsVersionV2]) {
            OWSFailDebug(@"Invalid groupId.");
            return nil;
        }
    } else if (sentProto.destinationAddress) {
        _recipientAddress = sentProto.destinationAddress;
    } else {
        OWSFailDebug(@"Neither a group ID nor recipient address found!");
        return nil;
    }

    if (_groupId != nil) {
        [TSGroupThread ensureGroupIdMappingForGroupId:_groupId transaction:transaction];
    }

    if (_dataMessage.hasFlags) {
        uint32_t flags = _dataMessage.flags;
        _isExpirationTimerUpdate = (flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0;
        _isEndSessionMessage = (flags & SSKProtoDataMessageFlagsEndSession) != 0;
    }
    _isRecipientUpdate = sentProto.hasIsRecipientUpdate && sentProto.isRecipientUpdate;
    _isViewOnceMessage = _dataMessage.hasIsViewOnce && _dataMessage.isViewOnce;

    if (_dataMessage.hasRequiredProtocolVersion) {
        _requiredProtocolVersion = @(_dataMessage.requiredProtocolVersion);
    }

    // There were scenarios where isRecipientUpdate would be true for edit sync
    // messages, but would be missing the groupId. isRecipientUpdate has no effect
    // on edit messages, so can be safely ignored here to avoid an unnecessary failure.
    if (!isEdit && self.isRecipientUpdate) {
        // Fetch, don't create.  We don't want recipient updates to resurrect messages or threads.
        if (_groupId != nil) {
            _thread = [TSGroupThread fetchWithGroupId:_groupId transaction:transaction];
        } else {
            OWSFailDebug(@"We should never receive a 'recipient update' for messages in contact threads.");
            return nil;
        }
        // Skip the other processing for recipient updates.
    } else {
        if (_groupId != nil) {
            TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:_groupId transaction:transaction];
            _thread = groupThread;

            if (groupContextV2 != nil) {
                if (groupThread == nil) {
                    // GroupsV2MessageProcessor should have already created the v2 group
                    // by now.
                    OWSFailDebug(@"Missing thread for v2 group.");
                    return nil;
                } else if (!_thread.isGroupV2Thread) {
                    OWSFailDebug(@"Invalid thread for v2 group.");
                    return nil;
                }
                if (!groupContextV2.hasRevision) {
                    OWSFailDebug(@"Missing revision.");
                    return nil;
                }
                uint32_t revision = groupContextV2.revision;
                if (![groupThread.groupModel isKindOfClass:TSGroupModelV2.class]) {
                    OWSFailDebug(@"Invalid group model.");
                    return nil;
                }
                TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;
                if (revision > groupModel.revision) {
                    OWSFailDebug(@"Unexpected revision.");
                    return nil;
                }
            } else {
                OWSFailDebug(@"Missing group context.");
                return nil;
            }
        } else if (_recipientAddress) {
            _thread = [TSContactThread getOrCreateThreadWithContactAddress:_recipientAddress transaction:transaction];
        }

        _quotedMessage = [TSQuotedMessage quotedMessageForDataMessage:_dataMessage
                                                               thread:_thread
                                                          transaction:transaction];
        _contact = [OWSContacts contactForDataMessage:_dataMessage transaction:transaction];

        NSError *linkPreviewError;
        _linkPreview = [OWSLinkPreview buildValidatedLinkPreviewWithDataMessage:_dataMessage
                                                                           body:_body
                                                                    transaction:transaction
                                                                          error:&linkPreviewError];
        if (linkPreviewError && ![OWSLinkPreview isNoPreviewError:linkPreviewError]) {
            OWSLogError(@"linkPreviewError: %@", linkPreviewError);
        }

        _giftBadge = [OWSGiftBadge maybeBuildFromDataMessage:_dataMessage];
        if ((_giftBadge != nil) && _thread.isGroupThread) {
            OWSFailDebug(@"Ignoring gift sent to group");
            return nil;
        }

        NSError *stickerError;
        _messageSticker = [MessageSticker buildValidatedMessageStickerWithDataMessage:_dataMessage
                                                                          transaction:transaction
                                                                                error:&stickerError];
        if (stickerError && ![MessageSticker isNoStickerError:stickerError]) {
            OWSFailDebug(@"stickerError: %@", stickerError);
        }

        TSPaymentModels *_Nullable paymentModels = [TSPaymentModels parsePaymentProtosInDataMessage:_dataMessage
                                                                                             thread:_thread];
        _paymentRequest = paymentModels.request;
        _paymentNotification = paymentModels.notification;
        _paymentCancellation = paymentModels.cancellation;

        if (_dataMessage.storyContext != nil && _dataMessage.storyContext.hasSentTimestamp
            && _dataMessage.storyContext.hasAuthorUuid) {
            _storyTimestamp = @(_dataMessage.storyContext.sentTimestamp);
            _storyAuthorAddress =
                [[SignalServiceAddress alloc] initWithUuidString:_dataMessage.storyContext.authorUuid];

            if (!_storyAuthorAddress.isValid) {
                OWSFailDebug(@"Discarding story reply transcript with invalid address %@", _storyAuthorAddress);
                return nil;
            }
        }
    }

    if (sentProto.unidentifiedStatus.count > 0) {
        NSMutableArray<ServiceIdObjC *> *nonUdRecipients = [NSMutableArray new];
        NSMutableArray<ServiceIdObjC *> *udRecipients = [NSMutableArray new];
        for (SSKProtoSyncMessageSentUnidentifiedDeliveryStatus *statusProto in sentProto.unidentifiedStatus) {
            ServiceIdObjC *serviceId = [[ServiceIdObjC alloc] initWithUuidString:statusProto.destinationUuid];
            if (serviceId == nil) {
                OWSFailDebug(@"Delivery status proto is missing destination.");
                continue;
            }
            if (!statusProto.hasUnidentified) {
                OWSFailDebug(@"Delivery status proto is missing value.");
                continue;
            }
            if (statusProto.unidentified) {
                [udRecipients addObject:serviceId];
            } else {
                [nonUdRecipients addObject:serviceId];
            }
        }
        _nonUdRecipients = [nonUdRecipients copy];
        _udRecipients = [udRecipients copy];
    }

    return self;
}

- (NSArray<SSKProtoAttachmentPointer *> *)attachmentPointerProtos
{
    return self.dataMessage.attachments;
}

@end

NS_ASSUME_NONNULL_END
