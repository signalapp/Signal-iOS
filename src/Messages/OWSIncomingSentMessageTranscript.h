//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosSyncMessageSent;

/**
 * Represents notification of a message sent on our behalf from another device.
 * E.g. When we send a message from Signal-Desktop we want to see it in our conversation on iPhone.
 */
@interface OWSIncomingSentMessageTranscript : NSObject

- (instancetype)initWithProto:(OWSSignalServiceProtosSyncMessageSent *)sentProto relay:(NSString *)relay;

/**
 * Record an outgoing message based on the transcription
 */
- (void)record;

@end

NS_ASSUME_NONNULL_END
