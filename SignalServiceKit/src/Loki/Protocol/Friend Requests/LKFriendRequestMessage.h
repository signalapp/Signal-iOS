#import "TSOutgoingMessage.h"

/// See [The Session Friend Request Protocol](https://github.com/loki-project/session-protocol-docs/wiki/Friend-Requests) for more information.
NS_SWIFT_NAME(FriendRequestMessage)
@interface LKFriendRequestMessage : TSOutgoingMessage

- (_Nonnull instancetype)initWithTimestamp:(uint64_t)timestamp thread:(nullable TSThread *)thread body:(nullable NSString *)body;

@end
