#import "LKFriendRequestMessage.h"

NS_SWIFT_NAME(FriendRequestMessage)
@interface LKSessionRestoreMessage : LKFriendRequestMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end
