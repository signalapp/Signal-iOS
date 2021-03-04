#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <Curve25519Kit/Ed25519.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

- (void)updateMessageIDCollectionByPruningMessagesWithIDs:(NSSet<NSString *> *)targetMessageIDs in:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(updateMessageIDCollectionByPruningMessagesWithIDs(_:in:));

@end

NS_ASSUME_NONNULL_END
