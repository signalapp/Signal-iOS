//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
- (nullable SSKProtoDataMessage *)buildDataMessage:(SignalServiceAddress *_Nullable)address;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;

// sentRecipientAddress is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) SignalServiceAddress *sentRecipientAddress;

@property (nonatomic, readonly) BOOL isRecipientUpdate;

@end

#pragma mark -

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message isRecipientUpdate:(BOOL)isRecipientUpdate
{
    OWSAssertDebug(message);

    // The sync message's timestamp must match the original outgoing message's timestamp.
    self = [super initWithTimestamp:message.timestamp];

    if (!self) {
        return self;
    }

    _message = message;
    _isRecipientUpdate = isRecipientUpdate;

    if ([message.thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)message.thread;
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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageSentBuilder *sentBuilder = [SSKProtoSyncMessageSent builder];
    [sentBuilder setTimestamp:self.timestamp];
    [sentBuilder setDestinationE164:self.sentRecipientAddress.phoneNumber];
    [sentBuilder setDestinationUuid:self.sentRecipientAddress.uuidString];
    [sentBuilder setIsRecipientUpdate:self.isRecipientUpdate];

    SSKProtoDataMessage *_Nullable dataMessage;
    if (self.message.hasPerMessageExpiration) {
        // Create data message without renderable content.
        SSKProtoDataMessageBuilder *dataBuilder = [SSKProtoDataMessage builder];
        [dataBuilder setTimestamp:self.message.timestamp];

        NSError *error;
        dataMessage = [dataBuilder buildAndReturnError:&error];
        if (error || !dataMessage) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
    } else {
        dataMessage = [self.message buildDataMessage:self.sentRecipientAddress];
    }

    if (!dataMessage) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    [sentBuilder setMessage:dataMessage];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

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
        [statusBuilder setDestinationE164:recipientAddress.phoneNumber];
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

@end

NS_ASSUME_NONNULL_END
