//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSRecipientIdentity.h>

NS_ASSUME_NONNULL_BEGIN

// This notification will be fired whenever identities are created
// or their verification state changes.
extern NSNotificationName const kNSNotificationNameIdentityStateDidChange;

// number of bytes in a signal identity key, excluding the key-type byte.
extern const NSUInteger kIdentityKeyLength;

#ifdef TESTABLE_BUILD
extern const NSUInteger kStoredIdentityKeyLength;
#endif

typedef NS_ENUM(NSInteger, TSMessageDirection) {
    TSMessageDirectionUnknown = 0,
    TSMessageDirectionIncoming,
    TSMessageDirectionOutgoing
};

/// Distinguishes which kind of identity we're referring to.
///
/// The ACI ("account identifier") represents the user in question,
/// while the PNI ("phone number identifier") represents the user's phone number (e164).
///
/// And yes, that means the full enumerator names mean "account identifier identity" and
/// "phone number identifier identity".
typedef NS_CLOSED_ENUM(uint8_t, OWSIdentity) {
    OWSIdentityACI NS_SWIFT_NAME(aci),
    OWSIdentityPNI NS_SWIFT_NAME(pni)
};

@class AuthedAccount;
@class ECKeyPair;
@class OWSRecipientIdentity;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class SSKProtoVerified;
@class SignalServiceAddress;

// This class can be safely accessed and used from any thread.
@interface OWSIdentityManager : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage;

- (ECKeyPair *)generateNewIdentityKeyPair;
- (void)storeIdentityKeyPair:(nullable ECKeyPair *)keyPair
                 forIdentity:(OWSIdentity)identity
                 transaction:(SDSAnyWriteTransaction *)transaction;

- (int)localRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (nullable ECKeyPair *)identityKeyPairForIdentity:(OWSIdentity)identity
                                       transaction:(SDSAnyReadTransaction *)transaction;
- (nullable ECKeyPair *)identityKeyPairForIdentity:(OWSIdentity)identity;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
                 transaction:(SDSAnyWriteTransaction *)transaction;

- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address;
- (BOOL)groupContainsUnverifiedMember:(NSString *)threadUniqueID;
- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address
                                        transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<SignalServiceAddress *> *)noLongerVerifiedAddressesInGroup:(NSString *)groupThreadID
                                                                limit:(NSInteger)limit
                                                          transaction:(SDSAnyReadTransaction *)transaction;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
       isUserInitiatedChange:(BOOL)isUserInitiatedChange;

- (nullable OWSRecipientIdentity *)recipientIdentityForAddress:(SignalServiceAddress *)address;
- (nullable OWSRecipientIdentity *)recipientIdentityForAddress:(SignalServiceAddress *)address
                                                   transaction:(SDSAnyReadTransaction *)transaction;

/**
 * @param   address of the recipient
 * @returns nil if the recipient does not exist, or is trusted for sending
 *          else returns the untrusted recipient.
 */
- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address;
- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address
                                                            transaction:(SDSAnyReadTransaction *)transaction;
- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address
                                                     untrustedThreshold:(NSTimeInterval)untrustedThreshold
                                                            transaction:(SDSAnyReadTransaction *)transaction;

- (void)fireIdentityStateChangeNotificationAfterTransaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)saveRemoteIdentity:(NSData *)identityKey address:(SignalServiceAddress *)address;

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
                   address:(SignalServiceAddress *)address
               transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
                   direction:(TSMessageDirection)direction
          untrustedThreshold:(NSTimeInterval)untrustedThreshold
                 transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
                   direction:(TSMessageDirection)direction
                 transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address;

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction;

#pragma mark - Tests

#if TESTABLE_BUILD
- (ECKeyPair *)generateAndPersistNewIdentityKeyForIdentity:(OWSIdentity)identity;
#endif

#pragma mark - Debug

#if USE_DEBUG_UI
// Clears everything except the local identity key.
- (void)clearIdentityState:(SDSAnyWriteTransaction *)transaction;
#endif

- (void)tryToSyncQueuedVerificationStates;

@end

NS_ASSUME_NONNULL_END
