#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(EphemeralMessage)
@interface OWSEphemeralMessage : TSOutgoingMessage

/// Used to establish sessions.
+ (OWSEphemeralMessage *)createEmptyOutgoingMessageInThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
