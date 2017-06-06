//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import <AxolotlKit/IdentityKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSStorageManagerTrustedKeysCollection;

// This notification will be fired whenever identities are created
// or their verification state changes.
extern NSString *const kNSNotificationName_IdentityStateDidChange;

@class OWSRecipientIdentity;

// This class can be safely accessed and used from any thread.
@interface OWSIdentityManager : NSObject <IdentityKeyStore>

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

/**
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 * @returns if the recipient's current identity is trusted.
 */
- (BOOL)isCurrentIdentityTrustedForSendingWithRecipientId:(NSString *)recipientId;

- (void)generateNewIdentityKey;

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
             sendSyncMessage:(BOOL)sendSyncMessage;

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId;

/**
 * @param   recipientId unique stable identifier for the recipient, e.g. e164 phone number
 * @returns nil if the recipient does not exist, or if the recipient exists and is OWSVerificationStateVerified or
 * OWSVerificationStateDefault else return the no longer verified identity
 */
- (OWSRecipientIdentity *)noLongerVerifiedIdentityForRecipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
