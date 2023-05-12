//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingSentMessageTranscript.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 *
 * recipientId is nil when building "sent" sync messages for messages
 * sent to groups.
 */
- (nullable SSKProtoDataMessage *)buildDataMessage:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript ()

// sentRecipientAddress is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) SignalServiceAddress *sentRecipientAddress;

@end

#pragma mark -

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithLocalThread:(TSThread *)localThread
                      messageThread:(TSThread *)messageThread
                    outgoingMessage:(TSOutgoingMessage *)message
                  isRecipientUpdate:(BOOL)isRecipientUpdate
                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(localThread != nil);
    OWSAssertDebug(messageThread != nil);

    // The sync message's timestamp must match the original outgoing message's timestamp.
    self = [super initWithTimestamp:message.timestamp thread:localThread transaction:transaction];

    if (!self) {
        return self;
    }

    _message = message;
    _messageThread = messageThread;
    _isRecipientUpdate = isRecipientUpdate;

    if ([messageThread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)messageThread;
        _sentRecipientAddress = contactThread.contactAddress;
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_sentRecipientAddress == nil) {
        _sentRecipientAddress =
            [[SignalServiceAddress alloc] initWithPhoneNumber:[coder decodeObjectForKey:@"sentRecipientId"]];
        OWSAssertDebug(_sentRecipientAddress.isValid);
    }

    return self;
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageSentBuilder *sentBuilder = [SSKProtoSyncMessageSent builder];
    [sentBuilder setTimestamp:self.timestamp];
    [sentBuilder setDestinationE164:self.sentRecipientAddress.phoneNumber];
    [sentBuilder setDestinationUuid:self.sentRecipientAddress.uuidString];
    [sentBuilder setIsRecipientUpdate:self.isRecipientUpdate];

    if (![self prepareDataSyncMessageContentWithSentBuilder:sentBuilder transaction:transaction]) {
        return nil;
    }

    for (SignalServiceAddress *recipientAddress in self.message.sentRecipientAddresses) {
        TSOutgoingMessageRecipientState *_Nullable recipientState =
            [self.message recipientStateForAddress:recipientAddress];
        if (!recipientState) {
            OWSFailDebug(@"missing recipient state for: %@", recipientAddress);
            continue;
        }
        if (recipientState.state != OWSOutgoingMessageRecipientStateSent) {
            OWSFailDebug(@"unexpected recipient state for: %@", recipientAddress);
            continue;
        }

        NSError *error;
        SSKProtoSyncMessageSentUnidentifiedDeliveryStatusBuilder *statusBuilder =
            [SSKProtoSyncMessageSentUnidentifiedDeliveryStatus builder];
        [statusBuilder setDestinationUuid:recipientAddress.uuidString];
        [statusBuilder setUnidentified:recipientState.wasSentByUD];
        SSKProtoSyncMessageSentUnidentifiedDeliveryStatus *_Nullable status =
            [statusBuilder buildAndReturnError:&error];
        if (error || !status) {
            OWSFailDebug(@"Couldn't build UD status proto: %@", error);
            continue;
        }
        [sentBuilder addUnidentifiedStatus:status];
    }

    NSError *error;
    SSKProtoSyncMessageSent *_Nullable sentProto = [sentBuilder buildAndReturnError:&error];
    if (error || !sentProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setSent:sentProto];
    return syncMessageBuilder;
}

- (BOOL)prepareDataSyncMessageContentWithSentBuilder:(SSKProtoSyncMessageSentBuilder *)sentBuilder
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessage *_Nullable dataMessage;
    if (self.message.isViewOnceMessage) {
        // Create data message without renderable content.
        SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
        [dataBuilder setTimestamp:self.message.timestamp];
        [dataBuilder setExpireTimer:self.message.expiresInSeconds];
        [dataBuilder setIsViewOnce:YES];
        [dataBuilder setRequiredProtocolVersion:(uint32_t)SSKProtoDataMessageProtocolVersionViewOnceVideo];

        if (self.messageThread.isGroupThread) {
            TSGroupThread *groupThread = (TSGroupThread *)self.messageThread;

            switch (groupThread.groupModel.groupsVersion) {
                case GroupsVersionV1: {
                    SSKProtoGroupContextBuilder *groupBuilder =
                        [SSKProtoGroupContext builderWithId:groupThread.groupModel.groupId];
                    [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
                    NSError *error;
                    SSKProtoGroupContext *_Nullable groupContextProto = [groupBuilder buildAndReturnError:&error];
                    if (error || !groupContextProto) {
                        OWSFailDebug(@"could not build protobuf: %@.", error);
                        return NO;
                    }
                    [dataBuilder setGroup:groupContextProto];
                    break;
                }
                case GroupsVersionV2: {
                    if (![groupThread.groupModel isKindOfClass:[TSGroupModelV2 class]]) {
                        OWSFailDebug(@"Invalid group model.");
                        return NO;
                    }
                    TSGroupModelV2 *groupModel = (TSGroupModelV2 *)groupThread.groupModel;

                    NSError *error;
                    SSKProtoGroupContextV2 *_Nullable groupContextV2 =
                        [self.groupsV2 buildGroupContextV2ProtoWithGroupModel:groupModel
                                                       changeActionsProtoData:nil
                                                                        error:&error];
                    if (groupContextV2 == nil || error != nil) {
                        OWSFailDebug(@"Error: %@", error);
                        return NO;
                    }
                    [dataBuilder setGroupV2:groupContextV2];
                    break;
                }
            }
        }

        NSError *error;
        dataMessage = [dataBuilder buildAndReturnError:&error];
        if (error || !dataMessage) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return NO;
        }
    } else {
        dataMessage = [self.message buildDataMessage:self.messageThread transaction:transaction];
    }

    if (!dataMessage) {
        OWSFailDebug(@"could not build protobuf.");
        return NO;
    }

    [sentBuilder setMessage:dataMessage];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    return YES;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.message.uniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
