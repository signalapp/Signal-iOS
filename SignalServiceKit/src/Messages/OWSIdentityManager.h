//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import <AxolotlKit/IdentityKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSPrimaryStorageTrustedKeysCollection;

// This notification will be fired whenever identities are created
// or their verification state changes.
extern NSString *const kNSNotificationName_IdentityStateDidChange;

// number of bytes in a signal identity key, excluding the key-type byte.
extern const NSUInteger kIdentityKeyLength;

@class OWSRecipientIdentity;
@class OWSStorage;
@class SSKProtoVerified;
@class YapDatabaseReadWriteTransaction;

// This class can be safely accessed and used from any thread.
@interface OWSIdentityManager : NSObject <IdentityKeyStore>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)generateNewIdentityKey;

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId;

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
                                   transaction:(YapDatabaseReadTransaction *)transaction;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId;
- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
                                            transaction:(YapDatabaseReadTransaction *)transaction;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange;

- (nullable OWSRecipientIdentity *)recipientIdentityForRecipientId:(NSString *)recipientId;

/**
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 * @returns nil if the recipient does not exist, or is trusted for sending
 *          else returns the untrusted recipient.
 */
- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId;

// This method can be called from any thread.
- (void)processIncomingSyncMessage:(SSKProtoVerified *)verified
                       transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId;

#pragma mark - Debug

- (nullable ECKeyPair *)identityKeyPair;

#if DEBUG
// Clears everything except the local identity key.
- (void)clearIdentityState:(YapDatabaseReadWriteTransaction *)transaction;

- (void)snapshotIdentityState:(YapDatabaseReadWriteTransaction *)transaction;
- (void)restoreIdentityState:(YapDatabaseReadWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
