#import "OWSPrimaryStorage.h"
#import "PreKeyRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (Loki)

# pragma mark - Prekey for contacts

/**
 Check if we have PreKeyRecord for the given contact.

 @param pubKey The hex encoded public ket of the contact.
 @return Whether we have a prekey or not.
 */
- (BOOL)hasPreKeyForContact:(NSString *)pubKey;

/**
 Get the PreKeyRecord associated with the given contact.
 If the record doesn't exist then this will generate a new one.

 @param pubKey The hex encoded public key of the contact.
 @return The record associated with the contact.
 */
- (PreKeyRecord *)getPreKeyForContact:(NSString *)pubKey;

@end

NS_ASSUME_NONNULL_END
