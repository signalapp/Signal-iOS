#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SyncOpenGroupsMessage)
@interface LKSyncOpenGroupsMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
