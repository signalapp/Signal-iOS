#import "OWSPrimaryStorage.h"
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <YapDatabase/YapDatabase.h>
#import <Curve25519Kit/Ed25519.h>
#import <AxolotlKit/AxolotlExceptions.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Pre Key for Contact

- (BOOL)hasPreKeyForContact:(NSString *)pubKey;
- (PreKeyRecord *_Nullable)getPreKeyForContact:(NSString *)pubKey transaction:(YapDatabaseReadTransaction *)transaction;
- (PreKeyRecord *)getOrCreatePreKeyForContact:(NSString *)pubKey;

# pragma mark - Pre Key Management

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
- (NSString *_Nullable)getLastMessageHashForServiceNode:(NSString *)serviceNode transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)setLastMessageHashForServiceNode:(NSString *)serviceNode hash:(NSString *)hash expiresAt:(u_int64_t)expiresAt transaction:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(setLastMessageHash(forServiceNode:hash:expiresAt:transaction:));

# pragma mark - Group Chat

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction;
- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction;
- (void)updateMessageIDCollectionByPruningMessagesWithIDs:(NSSet<NSString *> *)targetMessageIDs in:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(updateMessageIDCollectionByPruningMessagesWithIDs(_:in:));

# pragma mark - Restoration

- (void)setRestorationTime:(NSTimeInterval)time;
- (NSTimeInterval)getRestorationTime;

@end

NS_ASSUME_NONNULL_END
