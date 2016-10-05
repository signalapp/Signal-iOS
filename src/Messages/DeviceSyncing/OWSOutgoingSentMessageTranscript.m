//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 */
- (OWSSignalServiceProtosDataMessage *)buildDataMessage;

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

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];

    OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder = [OWSSignalServiceProtosSyncMessageSentBuilder new];
    [sentBuilder setTimestamp:self.message.timestamp];
    [sentBuilder setDestination:self.message.recipientIdentifier];
    [sentBuilder setMessage:[self.message buildDataMessage]];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    [syncMessageBuilder setSentBuilder:sentBuilder];

    return [syncMessageBuilder build];
}

@end

NS_ASSUME_NONNULL_END
