#import "OWSPrimaryStorage.h"
#import "PreKeyRecord.h"
#import "PreKeyBundle.h"
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
 @return The record associated with the contact or nil if it didn't exist.
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

@end

NS_ASSUME_NONNULL_END
