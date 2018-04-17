//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 *
 * recipientId is nil when building "sent" sync messages for messages
 * sent to groups.
 */
- (OWSSignalServiceProtosDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId;

@end

@interface OWSOutgoingSentMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;

@end

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
{
    self = [super init];

    if (!self) {
        return self;
    }

    _message = message;

    return self;
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];

    OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder = [OWSSignalServiceProtosSyncMessageSentBuilder new];
    [sentBuilder setTimestamp:self.message.timestamp];
    [sentBuilder setDestination:self.recipientIdentifierForMessage];
    [sentBuilder setMessage:[self.message buildDataMessage:self.recipientIdentifierForMessage]];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    [syncMessageBuilder setSentBuilder:sentBuilder];

    return syncMessageBuilder;
}

// Note that this will return nil for group messages.
- (nullable NSString *)recipientIdentifierForMessage
{
    return self.message.thread.contactIdentifier;
}

@end

NS_ASSUME_NONNULL_END
