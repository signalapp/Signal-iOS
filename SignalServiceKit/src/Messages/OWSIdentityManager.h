//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import <AxolotlKit/IdentityKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

// This notification will be fired whenever identities are created
// or their verification state changes.
extern NSNotificationName const kNSNotificationNameIdentityStateDidChange;

// number of bytes in a signal identity key, excluding the key-type byte.
extern const NSUInteger kIdentityKeyLength;

#ifdef DEBUG
extern const NSUInteger kStoredIdentityKeyLength;
#endif

@class OWSRecipientIdentity;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;
@class SSKProtoVerified;
@class SignalServiceAddress;

// This class can be safely accessed and used from any thread.
@interface OWSIdentityManager : NSObject <IdentityKeyStore>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage;
- (void)recreateDatabaseQueue;

+ (instancetype)shared;

- (void)generateNewIdentityKey;
- (void)storeIdentityKeyPair:(ECKeyPair *)keyPair transaction:(SDSAnyWriteTransaction *)transaction;

- (nullable ECKeyPair *)identityKeyPairWithTransaction:(SDSAnyReadTransaction *)transaction;

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
                 transaction:(SDSAnyWriteTransaction *)transaction;

- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address;
- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address
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

// This method can be called from any thread.
- (void)throws_processIncomingVerifiedProto:(SSKProtoVerified *)verified
                                transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_UNAVAILABLE("throws objc exceptions");

- (BOOL)processIncomingVerifiedProto:(SSKProtoVerified *)verified
                         transaction:(SDSAnyWriteTransaction *)transaction
                               error:(NSError **)error;

- (void)fireIdentityStateChangeNotificationAfterTransaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)saveRemoteIdentity:(NSData *)identityKey address:(SignalServiceAddress *)address;

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
                   address:(SignalServiceAddress *)address
               transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
                   direction:(TSMessageDirection)direction
                 transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address;

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction;

#pragma mark - Debug

- (nullable ECKeyPair *)identityKeyPair;

#if DEBUG
// Clears everything except the local identity key.
- (void)clearIdentityState:(SDSAnyWriteTransaction *)transaction;
#endif

- (void)tryToSyncQueuedVerificationStates;

#pragma mark - Deprecated IdentityStore methods

- (nullable ECKeyPair *)identityKeyPair:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (int)localRegistrationId:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)accountId
           protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)accountId
                   direction:(TSMessageDirection)direction
             protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (nullable NSData *)identityKeyForRecipientId:(NSString *)accountId
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (nullable NSData *)identityKeyForRecipientId:(NSString *)accountId
                               protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

@end

NS_ASSUME_NONNULL_END
