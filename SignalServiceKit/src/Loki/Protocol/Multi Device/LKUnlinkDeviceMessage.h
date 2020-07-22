#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(UnlinkDeviceMessage)
@interface LKUnlinkDeviceMessage : TSOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
