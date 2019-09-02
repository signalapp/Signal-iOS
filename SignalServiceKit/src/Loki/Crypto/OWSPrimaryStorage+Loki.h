#import "OWSPrimaryStorage.h"
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Prekey for Contact

/**
 Check if we have a `PreKeyRecord` for the given contact.

 @param pubKey The hex encoded public key of the contact.
 @return Whether we have a prekey or not.
 */
- (BOOL)hasPreKeyForContact:(NSString *)pubKey;

/**
 Get the `PreKeyRecord` associated with the given contact.
 
 @param pubKey The hex encoded public key of the contact.
 @param transaction A `YapDatabaseReadTransaction`.
 @return The record associated with the contact or `nil` if it doesn't exist.
 */
- (PreKeyRecord *_Nullable)getPreKeyForContact:(NSString *)pubKey transaction:(YapDatabaseReadTransaction *)transaction;

/**
 Get the `PreKeyRecord` associated with the given contact.
 If the record doesn't exist then this will create a new one.

 @param pubKey The hex encoded public key of the contact.
 @return The record associated with the contact.
 */
- (PreKeyRecord *)getOrCreatePreKeyForContact:(NSString *)pubKey;

# pragma mark - PreKeyBundle

/**
 Generate a `PreKeyBundle` for the given contact.
 This doesn't store the prekey bundle, and you shouldn't store this bundle.
 It's used for generating bundles to send to other users.

 @param pubKey The hex encoded public key of the contact.
 @return A prekey bundle for the contact.
 */
- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey;

/**
 Get the `PreKeyBundle` associated with the given contact.

 @param pubKey The hex encoded public key of the contact.
 @return The prekey bundle or `nil` if it doesn't exist.
 */
- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)pubKey;

/**
 Set the `PreKeyBundle` for the given contact.

 @param bundle The prekey bundle.
 @param transaction A `YapDatabaseReadWriteTransaction`.
 @param pubKey The hex encoded public key of the contact.
 */
- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 Remove the `PreKeyBundle` for the given contact.

 @param pubKey The hex encoded public key of the contact.
 @param transaction A `YapDatabaseReadWriteTransaction`.
 */
- (void)removePreKeyBundleForContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction;

# pragma mark - Last Hash Handling

/**
 Get the last message hash for the given service node.
 This function will check the stored last hash and remove it if the `expiresAt` has already passed.

 @param serviceNode The service node ID.
 @param transaction A read write transaction.
 @return The last hash or `nil` if it doesn't exist.
 */
- (NSString *_Nullable)getLastMessageHashForServiceNode:(NSString *)serviceNode transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 Set the last message hash for the given service node.
 This will override any previous hashes stored for the given service node.

 @param serviceNode The service node ID.
 @param hash The last message hash.
 @param expiresAt The time the message expires on the server.
 @param transaction A read write transaction.
 */
- (void)setLastMessageHashForServiceNode:(NSString *)serviceNode hash:(NSString *)hash expiresAt:(u_int64_t)expiresAt transaction:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(setLastMessageHash(forServiceNode:hash:expiresAt:transaction:));

# pragma mark - Public chat

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction;
- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction;
- (void)setIsModerator:(BOOL)isModerator forGroup:(NSUInteger)group onServer:(NSString *)server in:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(setIsModerator(_:for:on:in:));
- (BOOL)isModeratorForGroup:(NSUInteger)group onServer:(NSString *)server in:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(isModerator(for:on:in:));

@end

NS_ASSUME_NONNULL_END
