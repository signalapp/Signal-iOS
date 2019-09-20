#import "OWSPrimaryStorage.h"
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Pre Key for Contact

- (BOOL)hasPreKeyForContact:(NSString *)pubKey;
- (PreKeyRecord *_Nullable)getPreKeyForContact:(NSString *)pubKey transaction:(YapDatabaseReadTransaction *)transaction;
- (PreKeyRecord *)getOrCreatePreKeyForContact:(NSString *)pubKey;

# pragma mark - Pre Key Bundle

/**
 * Generates a pre key bundle but doesn't store it as pre key bundles are supposed to be sent to other users without ever being stored.
 */
- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey;
- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)pubKey;
- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)removePreKeyBundleForContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction;

# pragma mark - Last Message Hash

/**
 * Gets the last message hash and removes it if its `expiresAt` has already passed.
 */
- (NSString *_Nullable)getLastMessageHashForServiceNode:(NSString *)serviceNode transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)setLastMessageHashForServiceNode:(NSString *)serviceNode hash:(NSString *)hash expiresAt:(u_int64_t)expiresAt transaction:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(setLastMessageHash(forServiceNode:hash:expiresAt:transaction:));

# pragma mark - Group Chat

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction;
- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
