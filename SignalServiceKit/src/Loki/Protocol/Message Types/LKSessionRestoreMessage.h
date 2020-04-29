#import "LKFriendRequestMessage.h"

NS_ASSUME_NONNULL_BEGIN

// TODO: This is just a friend request message with a flag set. Not sure if it needs to be its own type.

NS_SWIFT_NAME(SessionRestoreMessage)
@interface LKSessionRestoreMessage : LKFriendRequestMessage

- (instancetype)initWithThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
