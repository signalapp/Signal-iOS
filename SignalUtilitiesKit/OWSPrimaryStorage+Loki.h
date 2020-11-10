#import "OWSPrimaryStorage.h"

#import <SessionProtocolKit/AxolotlExceptions.h>
#import <SessionProtocolKit/PreKeyBundle.h>
#import <SessionProtocolKit/PreKeyRecord.h>
#import <Curve25519Kit/Ed25519.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Pre Key Record Management

- (BOOL)hasPreKeyRecordForContact:(NSString *)hexEncodedPublicKey;
- (PreKeyRecord *_Nullable)getPreKeyRecordForContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadTransaction *)transaction;
- (PreKeyRecord *)getOrCreatePreKeyRecordForContact:(NSString *)hexEncodedPublicKey;

# pragma mark - Pre Key Bundle Management

/**
 * Generates a pre key bundle for the given contact. Doesn't store the pre key bundle (pre key bundles are supposed to be sent without ever being stored).
 */
- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)hexEncodedPublicKey;
- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)hexEncodedPublicKey;
- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)removePreKeyBundleForContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction;

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
