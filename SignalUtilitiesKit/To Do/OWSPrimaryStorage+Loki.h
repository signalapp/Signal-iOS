#import <SessionMessagingKit/OWSPrimaryStorage.h>

#import <Curve25519Kit/Ed25519.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Last Message Hash

/**
 * Gets the last message hash and removes it if its `expiresAt` has already passed.
 */
- (NSString *_Nullable)getLastMessageHashForSnode:(NSString *)snode transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)setLastMessageHashForSnode:(NSString *)snode hash:(NSString *)hash expiresAt:(u_int64_t)expiresAt transaction:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(setLastMessageHash(forSnode:hash:expiresAt:transaction:));

# pragma mark - Open Groups

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction;
- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction;
- (void)updateMessageIDCollectionByPruningMessagesWithIDs:(NSSet<NSString *> *)targetMessageIDs in:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(updateMessageIDCollectionByPruningMessagesWithIDs(_:in:));

# pragma mark - Restoration from Seed

- (void)setRestorationTime:(NSTimeInterval)time;
- (NSTimeInterval)getRestorationTime;

@end

NS_ASSUME_NONNULL_END
