#import "TSOutgoingMessage.h"

NS_SWIFT_NAME(DeviceLinkingMessage)
@interface LKDeviceLinkingMessage : TSOutgoingMessage

- (instancetype)initInThread:(TSThread *)thread;

@end
