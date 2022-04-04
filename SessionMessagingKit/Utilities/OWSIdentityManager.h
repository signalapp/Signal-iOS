//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <YapDatabase/YapDatabase.h>

@class OWSPrimaryStorage;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSPrimaryStorageIdentityKeyStoreIdentityKey;
extern NSString *const LKSeedKey;
extern NSString *const LKED25519SecretKey;
extern NSString *const LKED25519PublicKey;
extern NSString *const OWSPrimaryStorageIdentityKeyStoreCollection;

// This notification will be fired whenever identities are created
// or their verification state changes.
extern NSString *const kNSNotificationName_IdentityStateDidChange;

// number of bytes in a signal identity key, excluding the key-type byte.
extern const NSUInteger kIdentityKeyLength;

#ifdef DEBUG
extern const NSUInteger kStoredIdentityKeyLength;
#endif

@class OWSRecipientIdentity;
@class OWSStorage;
@class SNProtoVerified;
@class YapDatabaseReadWriteTransaction;

// This class can be safely accessed and used from any thread.
@interface OWSIdentityManager : NSObject

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)generateNewIdentityKeyPair;
- (void)clearIdentityKey;

- (nullable OWSRecipientIdentity *)recipientIdentityForRecipientId:(NSString *)recipientId;

/**
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 * @returns nil if the recipient does not exist, or is trusted for sending
 *          else returns the untrusted recipient.
 */
- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId;

- (nullable ECKeyPair *)identityKeyPair;

@end

NS_ASSUME_NONNULL_END
