//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "OWSRecipientIdentity.h"
#import "OWSIdentityManager.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSMessage.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
NSString *const OWSPrimaryStorageIdentityKeyStoreIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
NSString *const LKSeedKey = @"LKLokiSeed";
NSString *const LKED25519SecretKey = @"LKED25519SecretKey";
NSString *const LKED25519PublicKey = @"LKED25519PublicKey";
NSString *const OWSPrimaryStorageIdentityKeyStoreCollection = @"TSStorageManagerIdentityKeyStoreCollection";

// Don't trust an identity for sending to unless they've been around for at least this long
const NSTimeInterval kIdentityKeyStoreNonBlockingSecondsThreshold = 5.0;

// The canonical key includes 32 bytes of identity material plus one byte specifying the key type
const NSUInteger kIdentityKeyLength = 33;

// Cryptographic operations do not use the "type" byte of the identity key, so, for legacy reasons we store just
// the identity material.
// TODO: migrate to storing the full 33 byte representation.
const NSUInteger kStoredIdentityKeyLength = 32;

NSString *const kNSNotificationName_IdentityStateDidChange = @"kNSNotificationName_IdentityStateDidChange";

@interface OWSIdentityManager ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

@end

#pragma mark -

@implementation OWSIdentityManager

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.identityManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;
    _dbConnection = primaryStorage.newDatabaseConnection;
    self.dbConnection.objectCacheEnabled = NO;

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

- (void)generateNewIdentityKeyPair
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];
    [self.dbConnection setObject:keyPair forKey:OWSPrimaryStorageIdentityKeyStoreIdentityKey inCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
}

- (void)clearIdentityKey
{
    [self.dbConnection removeObjectForKey:OWSPrimaryStorageIdentityKeyStoreIdentityKey
                             inCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
{
    __block NSData *_Nullable result = nil;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        result = [self identityKeyForRecipientId:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId protocolContext:(nullable id)protocolContext
{
    YapDatabaseReadTransaction *transaction = protocolContext;

    return [self identityKeyForRecipientId:recipientId transaction:transaction];
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
                                   transaction:(YapDatabaseReadTransaction *)transaction
{
    return [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction].identityKey;
}

- (nullable ECKeyPair *)identityKeyPair
{
    __block ECKeyPair *_Nullable identityKeyPair = nil;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        identityKeyPair = [self identityKeyPairWithTransaction:transaction];
    }];
    return identityKeyPair;
}

// This method should only be called from SignalProtocolKit, which doesn't know about YapDatabaseTransactions.
// Whenever possible, prefer to call the strongly typed variant: `identityKeyPairWithTransaction:`.
- (nullable ECKeyPair *)identityKeyPair:(nullable id)protocolContext
{
    YapDatabaseReadTransaction *transaction = protocolContext;

    return [self identityKeyPairWithTransaction:transaction];
}

- (nullable ECKeyPair *)identityKeyPairWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    ECKeyPair *_Nullable identityKeyPair = [transaction keyPairForKey:OWSPrimaryStorageIdentityKeyStoreIdentityKey
                                                         inCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
    return identityKeyPair;
}

- (int)localRegistrationId:(nullable id)protocolContext
{
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return (int)[TSAccountManager getOrGenerateRegistrationId:transaction];
}

- (nullable OWSRecipientIdentity *)recipientIdentityForRecipientId:(NSString *)recipientId
{
    __block OWSRecipientIdentity *_Nullable result;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId
{
    __block OWSRecipientIdentity *_Nullable result;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *_Nullable recipientIdentity =
            [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

        if (recipientIdentity == nil) {
            // trust on first use
            return;
        }

        BOOL isTrusted = [self isTrustedIdentityKey:recipientIdentity.identityKey
                                        recipientId:recipientId
                                          direction:TSMessageDirectionOutgoing
                                        transaction:transaction];
        if (isTrusted) {
            return;
        } else {
            result = recipientIdentity;
        }
    }];
    return result;
}

- (void)fireIdentityStateChangeNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_IdentityStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
             protocolContext:(nullable id)protocolContext
{
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [self isTrustedIdentityKey:identityKey recipientId:recipientId direction:direction transaction:transaction];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
                 transaction:(YapDatabaseReadTransaction *)transaction
{
    if ([[TSAccountManager localNumber] isEqualToString:recipientId]) {
        ECKeyPair *_Nullable localIdentityKeyPair = [self identityKeyPairWithTransaction:transaction];

        if ([localIdentityKeyPair.publicKey isEqualToData:identityKey]) {
            return YES;
        } else {
            return NO;
        }
    }

    switch (direction) {
        case TSMessageDirectionIncoming: {
            return YES;
        }
        case TSMessageDirectionOutgoing: {
            OWSRecipientIdentity *existingIdentity =
                [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];
            return [self isTrustedKey:identityKey forSendingToIdentity:existingIdentity];
        }
        default: {
            return NO;
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    if (recipientIdentity == nil) {
        return YES;
    }

    if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
        return NO;
    }

    if ([recipientIdentity isFirstKnownKey]) {
        return YES;
    }

    switch (recipientIdentity.verificationState) {
        case OWSVerificationStateDefault: {
            BOOL isNew = (fabs([recipientIdentity.createdAt timeIntervalSinceNow])
                < kIdentityKeyStoreNonBlockingSecondsThreshold);
            if (isNew) {
                return NO;
            } else {
                return YES;
            }
        }
        case OWSVerificationStateVerified:
            return YES;
        case OWSVerificationStateNoLongerVerified:
            return NO;
    }
}

@end

NS_ASSUME_NONNULL_END
