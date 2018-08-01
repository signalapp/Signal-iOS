//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
- (SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId;

@end

@interface OWSOutgoingSentMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
// sentRecipientId is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) NSString *sentRecipientId;

@end

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
{
    self = [super init];

    if (!self) {
        return self;
    }

    _message = message;
    // This will be nil for groups.
    _sentRecipientId = message.thread.contactIdentifier;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageSentBuilder *sentBuilder = [SSKProtoSyncMessageSentBuilder new];
    [sentBuilder setTimestamp:self.message.timestamp];
    [sentBuilder setDestination:self.sentRecipientId];
    [sentBuilder setMessage:[self.message buildDataMessage:self.sentRecipientId]];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    NSError *error;
    SSKProtoSyncMessageSent *_Nullable sentProto = [sentBuilder buildAndReturnError:&error];
    if (error || !sentProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setSent:sentProto];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
