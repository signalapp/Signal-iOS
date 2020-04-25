#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

/// TODO: This is just an ephemeral message with a flag set. Not sure if it needs to be its own type.

NS_SWIFT_NAME(UnlinkDeviceMessage)
@interface LKUnlinkDeviceMessage : TSOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
