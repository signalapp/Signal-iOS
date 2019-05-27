#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(EphemeralMessage)
@interface LKEphemeralMessage : TSOutgoingMessage

- (instancetype)initInThread:(nullable TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
