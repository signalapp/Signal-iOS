//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSentUpdateMessageTranscript.h"
#import "TSGroupThread.h"
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
- (nullable SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId;

@end

@interface OWSOutgoingSentUpdateMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) TSGroupThread *groupThread;

@end

@implementation OWSOutgoingSentUpdateMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
                            transaction:(YapDatabaseReadTransaction *)transaction
{
    self = [super init];

    if (!self) {
        return self;
    }

    _message = message;
    _groupThread = (TSGroupThread *)[message threadWithTransaction:transaction];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageSentUpdateBuilder *sentBuilder =
        [SSKProtoSyncMessageSentUpdate builderWithGroupID:self.groupThread.groupModel.groupId
                                                timestamp:self.message.timestamp];

    for (NSString *recipientId in self.message.sentRecipientIds) {
        TSOutgoingMessageRecipientState *_Nullable recipientState =
            [self.message recipientStateForRecipientId:recipientId];
        if (!recipientState) {
            OWSFailDebug(@"missing recipient state for: %@", recipientId);
            continue;
        }
        if (recipientState.state != OWSOutgoingMessageRecipientStateSent) {
            OWSFailDebug(@"unexpected recipient state for: %@", recipientId);
            continue;
        }

        NSError *error;
        SSKProtoSyncMessageSentUpdateUnidentifiedDeliveryStatusBuilder *statusBuilder =
            [SSKProtoSyncMessageSentUpdateUnidentifiedDeliveryStatus builderWithDestination:recipientId];
        [statusBuilder setUnidentified:recipientState.wasSentByUD];
        SSKProtoSyncMessageSentUpdateUnidentifiedDeliveryStatus *_Nullable status =
            [statusBuilder buildAndReturnError:&error];
        if (error || !status) {
            OWSFailDebug(@"Couldn't build UD status proto: %@", error);
            continue;
        }
        [sentBuilder addUnidentifiedStatus:status];
    }

    NSError *error;
    SSKProtoSyncMessageSentUpdate *_Nullable sentUpdateProto = [sentBuilder buildAndReturnError:&error];
    if (error || !sentUpdateProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setSentUpdate:sentUpdateProto];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
