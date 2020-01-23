#import "LKFriendRequestMessage.h"

NS_SWIFT_NAME(SessionRestoreMessage)
@interface LKSessionRestoreMessage : LKFriendRequestMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end
