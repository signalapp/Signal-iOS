#import "TSOutgoingMessage.h"

NS_SWIFT_NAME(UnlinkDeviceMessage)
@interface LKUnlinkDeviceMessage : TSOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end
