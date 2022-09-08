//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "MessageSender.h"
#import "NSData+keyVersionByte.h"
#import "NotificationsProtocol.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSOutgoingNullMessage.h"
#import "OWSRecipientIdentity.h"
#import "OWSVerificationStateChangeMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSPreKeyManager.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
static NSString *const kIdentityKeyStore_ACIIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
static NSString *const kIdentityKeyStore_PNIIdentityKey = @"TSStorageManagerIdentityKeyStorePNIIdentityKey";

static NSString *keyForIdentity(OWSIdentity identity)
{
    switch (identity) {
        case OWSIdentityACI:
            return kIdentityKeyStore_ACIIdentityKey;
        case OWSIdentityPNI:
            return kIdentityKeyStore_PNIIdentityKey;
    }
}

// The canonical key includes 32 bytes of identity material plus one byte specifying the key type
const NSUInteger kIdentityKeyLength = 33;

// Cryptographic operations do not use the "type" byte of the identity key, so, for legacy reasons we store just
// the identity material.
// TODO: migrate to storing the full 33 byte representation.
const NSUInteger kStoredIdentityKeyLength = 32;

NSNotificationName const kNSNotificationNameIdentityStateDidChange = @"kNSNotificationNameIdentityStateDidChange";

@interface OWSIdentityManager ()

@property (nonatomic, readonly) SDSKeyValueStore *ownIdentityKeyValueStore;
@property (nonatomic, readonly) SDSKeyValueStore *queuedVerificationStateSyncMessagesKeyValueStore;

@end

#pragma mark -

@implementation OWSIdentityManager

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _ownIdentityKeyValueStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerIdentityKeyStoreCollection"];
    _queuedVerificationStateSyncMessagesKeyValueStore =
        [[SDSKeyValueStore alloc] initWithCollection:@"OWSIdentityManager_QueuedVerificationStateSyncMessages"];

    OWSSingletonAssert();

    [self observeNotifications];
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self checkForPniIdentity]; });

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (ECKeyPair *)generateNewIdentityKeyForIdentity:(OWSIdentity)identity
{
    __block ECKeyPair *newKeyPair;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        newKeyPair = [Curve25519 generateKeyPair];
        [self storeIdentityKeyPair:newKeyPair forIdentity:identity transaction:transaction];
    });
    return newKeyPair;
}

- (void)storeIdentityKeyPair:(nullable ECKeyPair *)keyPair
                 forIdentity:(OWSIdentity)identity
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    // Under no circumstances may we *clear* our *ACI* identity key.
    OWSAssert(keyPair != nil || identity != OWSIdentityACI);
    [self.ownIdentityKeyValueStore setObject:keyPair key:keyForIdentity(identity) transaction:transaction];
}

- (NSString *)ensureAccountIdForAddress:(SignalServiceAddress *)address
                            transaction:(SDSAnyWriteTransaction *)transaction
{
    return [OWSAccountIdFinder ensureAccountIdForAddress:address transaction:transaction];
}

- (nullable NSString *)accountIdForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSAccountIdFinder accountIdForAddress:address transaction:transaction];
}

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address
{
    __block NSData *_Nullable result = nil;
    [self.databaseStorage readWithBlock:^(
        SDSAnyReadTransaction *transaction) { result = [self identityKeyForAddress:address transaction:transaction]; }];
    return result;
}

- (nullable NSData *)identityKeyForAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyReadTransaction *)transaction
{
    NSString *_Nullable accountId = [self accountIdForAddress:address transaction:transaction];
    if (accountId) {
        return [self identityKeyForAccountId:accountId transaction:transaction];
    }
    return nil;
}

- (nullable NSData *)identityKeyForAccountId:(NSString *)accountId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 1);
    OWSAssertDebug(transaction);

    return [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction].identityKey;
}

- (nullable ECKeyPair *)identityKeyPairForIdentity:(OWSIdentity)identity
{
    __block ECKeyPair *_Nullable identityKeyPair = nil;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        identityKeyPair = [self identityKeyPairForIdentity:identity transaction:transaction];
    }];
    return identityKeyPair;
}

- (nullable ECKeyPair *)identityKeyPairForIdentity:(OWSIdentity)identity
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    id _Nullable object = [self.ownIdentityKeyValueStore getObjectForKey:keyForIdentity(identity)
                                                             transaction:transaction];
    if ([object isKindOfClass:[ECKeyPair class]]) {
        return (ECKeyPair *)object;
    } else {
        OWSAssertDebug(object == nil);
        return nil;
    }
}

- (int)localRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    return (int)[self.tsAccountManager getOrGenerateRegistrationIdWithTransaction:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey address:(SignalServiceAddress *)address
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(address.isValid);

    __block BOOL result;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        result = [self saveRemoteIdentity:identityKey address:address transaction:transaction];
    });

    return result;
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
                   address:(SignalServiceAddress *)address
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    NSString *accountId = [self ensureAccountIdForAddress:address transaction:transaction];
    return [self saveRemoteIdentity:identityKey accountId:accountId transaction:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
                 accountId:(NSString *)accountId
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(accountId.length > 1);

    OWSRecipientIdentity *_Nullable existingIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId
                                                                                      transaction:transaction];

    if (existingIdentity == nil) {
        OWSLogInfo(@"saving first use identity for accountId: %@", accountId);
        [[[OWSRecipientIdentity alloc] initWithAccountId:accountId
                                             identityKey:identityKey
                                         isFirstKnownKey:YES
                                               createdAt:[NSDate new]
                                       verificationState:OWSVerificationStateDefault]
            anyInsertWithTransaction:transaction];

        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForAccountId:accountId transaction:transaction];

        [self fireIdentityStateChangeNotificationAfterTransaction:transaction];

        // Identity key was created, schedule a social graph backup
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ accountId ]];

        return NO;
    }

    if (![existingIdentity.identityKey isEqual:identityKey]) {
        OWSVerificationState verificationState;
        BOOL wasIdentityVerified;
        switch (existingIdentity.verificationState) {
            case OWSVerificationStateDefault:
                verificationState = OWSVerificationStateDefault;
                wasIdentityVerified = NO;
                break;
            case OWSVerificationStateVerified:
            case OWSVerificationStateNoLongerVerified:
                verificationState = OWSVerificationStateNoLongerVerified;
                wasIdentityVerified = YES;
                break;
        }

        OWSLogInfo(@"replacing identity for existing recipient: %@ (%@ -> %@)",
            accountId,
            OWSVerificationStateToString(existingIdentity.verificationState),
            OWSVerificationStateToString(verificationState));

        [self createIdentityChangeInfoMessageForAccountId:accountId
                                      wasIdentityVerified:wasIdentityVerified
                                              transaction:transaction];

        [[[OWSRecipientIdentity alloc] initWithAccountId:accountId
                                             identityKey:identityKey
                                         isFirstKnownKey:NO
                                               createdAt:[NSDate new]
                                       verificationState:verificationState] anyUpsertWithTransaction:transaction];

        // PNI TODO: archive PNI sessions too
        SSKSessionStore *sessionStore = [self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore;
        [sessionStore archiveAllSessionsForAccountId:accountId transaction:transaction];

        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForAccountId:accountId transaction:transaction];

        [self fireIdentityStateChangeNotificationAfterTransaction:transaction];

        // Identity key was changed, schedule a social graph backup
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ accountId ]];

        return YES;
    }

    return NO;
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(address.isValid);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self setVerificationState:verificationState
                       identityKey:identityKey
                           address:address
             isUserInitiatedChange:isUserInitiatedChange
                       transaction:transaction];
    });
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    // Ensure a remote identity exists for this key. We may be learning about
    // it for the first time.
    [self saveRemoteIdentity:identityKey address:address transaction:transaction];

    NSString *accountId = [self ensureAccountIdForAddress:address transaction:transaction];
    OWSRecipientIdentity *_Nullable recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId
                                                                                       transaction:transaction];

    if (recipientIdentity == nil) {
        OWSFailDebug(@"Missing expected identity: %@", address);
        return;
    }

    if (recipientIdentity.verificationState == verificationState) {
        return;
    }

    OWSLogInfo(@"setVerificationState: %@ (%@ -> %@)",
        address,
        OWSVerificationStateToString(recipientIdentity.verificationState),
        OWSVerificationStateToString(verificationState));

    [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

    if (isUserInitiatedChange) {
        [self saveChangeMessagesForAddress:address
                         verificationState:verificationState
                             isLocalChange:YES
                               transaction:transaction];
        [self enqueueSyncMessageForVerificationStateForAddress:address transaction:transaction];
    } else {
        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForAddress:address transaction:transaction];
    }

    // Verification state has changed, schedule a social graph backup
    [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ accountId ]];

    [self fireIdentityStateChangeNotificationAfterTransaction:transaction];
}

- (BOOL)groupContainsUnverifiedMember:(NSString *)threadUniqueID
{
    __block BOOL result = NO;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        result = [self groupContainsUnverifiedMember:threadUniqueID transaction:transaction];
    }];
    return result;
}

- (NSArray<SignalServiceAddress *> *)noLongerVerifiedAddressesInGroup:(NSString *)groupThreadID
                                                                limit:(NSInteger)limit
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    return [OWSRecipientIdentity noLongerVerifiedAddressesInGroup:groupThreadID limit:limit transaction:transaction];
}

- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address
{
    __block OWSVerificationState result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self verificationStateForAddress:address transaction:transaction];
    }];
    return result;
}

- (OWSVerificationState)verificationStateForAddress:(SignalServiceAddress *)address
                                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSString *_Nullable accountId = [self accountIdForAddress:address transaction:transaction];
    OWSRecipientIdentity *_Nullable currentIdentity;
    if (accountId) {
        currentIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction];
    }

    if (!currentIdentity) {
        // We might not know the identity for this recipient yet.
        return OWSVerificationStateDefault;
    }

    return currentIdentity.verificationState;
}

- (nullable OWSRecipientIdentity *)recipientIdentityForAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    __block OWSRecipientIdentity *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self recipientIdentityForAddress:address transaction:transaction];
    }];

    return result;
}

- (nullable OWSRecipientIdentity *)recipientIdentityForAddress:(SignalServiceAddress *)address
                                                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSString *_Nullable accountId = [self accountIdForAddress:address transaction:transaction];
    if (accountId) {
        return [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction];
    }
    return nil;
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    __block OWSRecipientIdentity *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self untrustedIdentityForSendingToAddress:address transaction:transaction];
    }];

    return result;
}


- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address
                                                            transaction:(SDSAnyReadTransaction *)transaction
{
    return [self untrustedIdentityForSendingToAddress:address
                                   untrustedThreshold:[self class].minimumUntrustedThreshold
                                          transaction:transaction];
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToAddress:(SignalServiceAddress *)address
                                                     untrustedThreshold:(NSTimeInterval)untrustedThreshold
                                                            transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSString *_Nullable accountId = [self accountIdForAddress:address transaction:transaction];
    OWSRecipientIdentity *_Nullable recipientIdentity;

    if (accountId) {
        recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction];
    }

    if (recipientIdentity == nil) {
        // trust on first use
        return nil;
    }

    BOOL isTrusted = [self isTrustedIdentityKey:recipientIdentity.identityKey
                                        address:address
                                      direction:TSMessageDirectionOutgoing
                             untrustedThreshold:untrustedThreshold
                                    transaction:transaction];
    if (isTrusted) {
        return nil;
    } else {
        return recipientIdentity;
    }
}

- (void)fireIdentityStateChangeNotificationAfterTransaction:(SDSAnyWriteTransaction *)transaction
{
    [transaction addAsyncCompletionOnMain:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationNameIdentityStateDidChange
                                                            object:nil];
    }];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
                   direction:(TSMessageDirection)direction
                 transaction:(SDSAnyReadTransaction *)transaction
{
    return [self isTrustedIdentityKey:identityKey
                              address:address
                            direction:direction
                   untrustedThreshold:[self class].minimumUntrustedThreshold
                          transaction:transaction];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                     address:(SignalServiceAddress *)address
                   direction:(TSMessageDirection)direction
          untrustedThreshold:(NSTimeInterval)untrustedThreshold
                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(direction != TSMessageDirectionUnknown);
    OWSAssertDebug(transaction);

    if (address.isLocalAddress) {
        ECKeyPair *_Nullable localIdentityKeyPair = [self identityKeyPairForIdentity:OWSIdentityACI
                                                                         transaction:transaction];

        if ([localIdentityKeyPair.publicKey isEqualToData:identityKey]) {
            return YES;
        } else {
            OWSFailDebug(@"Wrong identity: %@ for local key: %@, address: %@",
                identityKey,
                localIdentityKeyPair.publicKey,
                address);
            return NO;
        }
    }

    switch (direction) {
        case TSMessageDirectionIncoming: {
            return YES;
        }
        case TSMessageDirectionOutgoing: {
            NSString *_Nullable accountId = [self accountIdForAddress:address transaction:transaction];
            if (!accountId) {
                OWSFailDebug(@"AccountId unexpectedly nil");
                return NO;
            }
            OWSRecipientIdentity *existingIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId
                                                                                    transaction:transaction];
            return [self isTrustedKey:identityKey
                 forSendingToIdentity:existingIdentity
                   untrustedThreshold:untrustedThreshold];
        }
        default: {
            OWSFailDebug(@"unexpected message direction: %ld", (long)direction);
            return NO;
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey
    forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
      untrustedThreshold:(NSTimeInterval)untrustedThreshold
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);

    if (recipientIdentity == nil) {
        return YES;
    }

    OWSAssertDebug(recipientIdentity.identityKey.length == kStoredIdentityKeyLength);
    if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
        OWSLogWarn(@"key mismatch for accountId: %@", recipientIdentity.accountId);
        return NO;
    }

    if ([recipientIdentity isFirstKnownKey]) {
        return YES;
    }

    switch (recipientIdentity.verificationState) {
        case OWSVerificationStateDefault: {
            // This user has never been explicitly verified, but we still want to check
            // if the identity key is one we newly learned about to give the local user
            // time to ensure they wish to send. If it has been created in the last N
            // seconds, we'll treat it as untrusted so sends fail. We enforce a minimum
            // and maximum threshold for the new window to ensure that we never inadvertently
            // block sending indefinitely or use a window so small it would be impossible
            // for the local user to notice a key change. This is a best effort, and we'll
            // continue to allow sending to the user after the "new" window elapses without
            // any explicit action from the local user.
            NSTimeInterval clampedUntrustedThreshold = CGFloatClamp(
                untrustedThreshold, [self class].minimumUntrustedThreshold, [self class].maximumUntrustedThreshold);
            BOOL isNew = (fabs([recipientIdentity.createdAt timeIntervalSinceNow]) < clampedUntrustedThreshold);
            if (isNew) {
                OWSLogWarn(@"not trusting new identity for accountId: %@", recipientIdentity.accountId);
                return NO;
            } else {
                return YES;
            }
        }
        case OWSVerificationStateVerified:
            return YES;
        case OWSVerificationStateNoLongerVerified:
            // This user was previously verified and their key has changed. We will not trust
            // them again until the user explicitly acknowledges the key change.
            OWSLogWarn(@"not trusting no longer verified identity for accountId: %@", recipientIdentity.accountId);
            return NO;
    }
}

- (void)createIdentityChangeInfoMessageForAccountId:(NSString *)accountId
                                wasIdentityVerified:(BOOL)wasIdentityVerified
                                        transaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *_Nullable address = [OWSAccountIdFinder addressForAccountId:accountId
                                                                          transaction:transaction];

    if (!address.isValid) {
        OWSFailDebug(@"address unexpectedly invalid for accountId: %@", accountId);
        return;
    }

    [self createIdentityChangeInfoMessageForAddress:address
                                wasIdentityVerified:wasIdentityVerified
                                        transaction:transaction];
}

- (void)createIdentityChangeInfoMessageForAddress:(SignalServiceAddress *)address
                              wasIdentityVerified:(BOOL)wasIdentityVerified
                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactAddress:address
                                                                              transaction:transaction];
    OWSAssertDebug(contactThread != nil);

    TSErrorMessage *errorMessage = [TSErrorMessage nonblockingIdentityChangeInThread:contactThread
                                                                             address:address
                                                                 wasIdentityVerified:wasIdentityVerified];
    [messages addObject:errorMessage];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithAddress:address transaction:transaction]) {
        [messages addObject:[TSErrorMessage nonblockingIdentityChangeInThread:groupThread
                                                                      address:address
                                                          wasIdentityVerified:wasIdentityVerified]];
    }

    // MJK TODO - why not save immediately, why build up this array?
    for (TSMessage *message in messages) {
        [message anyInsertWithTransaction:transaction];
    }

    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

- (void)enqueueSyncMessageForVerificationStateForAddress:(SignalServiceAddress *)address
                                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSString *accountId = [self ensureAccountIdForAddress:address transaction:transaction];
    [self.queuedVerificationStateSyncMessagesKeyValueStore setObject:address key:accountId transaction:transaction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self tryToSyncQueuedVerificationStates];
    });
}

- (void)tryToSyncQueuedVerificationStates
{
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(^{ [self syncQueuedVerificationStates]; });
}

- (void)syncQueuedVerificationStates
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!self.tsAccountManager.isRegisteredAndReady) {
            OWSLogInfo(@"Skipping sync of verification states; not registered.");
            return;
        }
        TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithSneakyTransaction];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }
        NSMutableArray<OWSVerificationStateSyncMessage *> *messages = [NSMutableArray new];
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            [self.queuedVerificationStateSyncMessagesKeyValueStore
                enumerateKeysAndObjectsWithTransaction:transaction
                                                 block:^(NSString *key, id value, BOOL *stop) {
                                                     NSString *_Nullable accountId;
                                                     SignalServiceAddress *address;
                                                     if ([value isKindOfClass:[SignalServiceAddress class]]) {
                                                         accountId = (NSString *)key;
                                                         address = (SignalServiceAddress *)value;
                                                     } else if ([value isKindOfClass:[NSString class]]) {
                                                         // Previously, we stored phone numbers in this KV store.
                                                         NSString *phoneNumber = (NSString *)value;
                                                         address = [[SignalServiceAddress alloc]
                                                             initWithPhoneNumber:phoneNumber];
                                                         accountId =
                                                             [OWSAccountIdFinder accountIdForAddress:address
                                                                                         transaction:transaction];
                                                         if (accountId == nil) {
                                                             OWSFailDebug(@"Missing accountId for address.");
                                                             return;
                                                         }
                                                     } else {
                                                         OWSFailDebug(@"Invalid object: %@", [value class]);
                                                         return;
                                                     }

                                                     OWSRecipientIdentity *recipientIdentity =
                                                         [OWSRecipientIdentity anyFetchWithUniqueId:accountId
                                                                                        transaction:transaction];
                                                     if (!recipientIdentity) {
                                                         OWSFailDebug(
                                                             @"Could not load recipient identity for address: %@",
                                                             address);
                                                         return;
                                                     }
                                                     if (recipientIdentity.accountId.length < 1) {
                                                         OWSFailDebug(
                                                             @"Invalid recipient identity for address: %@", address);
                                                         return;
                                                     }

                                                     // Prepend key type for transit.
                                                     // TODO we should just be storing the key type so we don't have to
                                                     // juggle re-adding it.
                                                     NSData *identityKey =
                                                         [recipientIdentity.identityKey prependKeyType];
                                                     if (identityKey.length != kIdentityKeyLength) {
                                                         OWSFailDebug(
                                                             @"Invalid recipient identitykey for address: %@ key: %@",
                                                             address,
                                                             identityKey);
                                                         return;
                                                     }
                                                     if (recipientIdentity.verificationState
                                                         == OWSVerificationStateNoLongerVerified) {
                                                         // We don't want to sync "no longer verified" state.  Other
                                                         // clients can figure this out from the /profile/ endpoint, and
                                                         // this can cause data loss as a user's devices overwrite each
                                                         // other's verification.
                                                         OWSFailDebug(@"Queue verification state had unexpected value: "
                                                                      @"%@ address: %@",
                                                             OWSVerificationStateToString(
                                                                 recipientIdentity.verificationState),
                                                             address);
                                                         return;
                                                     }
                                                     OWSVerificationStateSyncMessage *message =
                                                         [[OWSVerificationStateSyncMessage alloc]
                                                                              initWithThread:thread
                                                                           verificationState:recipientIdentity
                                                                                                 .verificationState
                                                                                 identityKey:identityKey
                                                             verificationForRecipientAddress:address
                                                                                 transaction:transaction];
                                                     [messages addObject:message];
                                                 }];
        }];
        if (messages.count > 0) {
            for (OWSVerificationStateSyncMessage *message in messages) {
                [self sendSyncVerificationStateMessage:message];
            }
        }
    });
}

- (void)sendSyncVerificationStateMessage:(OWSVerificationStateSyncMessage *)message
{
    OWSAssertDebug(message);
    OWSAssertDebug(message.verificationForRecipientAddress.isValid);

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactAddress:message.verificationForRecipientAddress];

    // DURABLE CLEANUP - we could replace the custom durability logic in this class
    // with a durable JobQueue.
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        // Send null message to appear as though we're sending a normal message to cover the sync message sent
        // subsequently
        OWSOutgoingNullMessage *nullMessage = [[OWSOutgoingNullMessage alloc] initWithContactThread:contactThread
                                                                       verificationStateSyncMessage:message
                                                                                        transaction:transaction];

        [self.messageSenderJobQueue addPromiseWithMessage:nullMessage.asPreparer
                                removeMessageAfterSending:NO
                            limitToCurrentProcessLifetime:YES
                                           isHighPriority:NO
                                              transaction:transaction]
            .doneInBackground(^(id value) {
                OWSLogInfo(@"Successfully sent verification state NullMessage");
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    [self.messageSenderJobQueue addPromiseWithMessage:message.asPreparer
                                            removeMessageAfterSending:NO
                                        limitToCurrentProcessLifetime:YES
                                                       isHighPriority:NO
                                                          transaction:transaction]
                        .doneInBackground(^(id value) {
                            OWSLogInfo(@"Successfully sent verification state sync message");

                            // Record that this verification state was successfully synced.
                            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                [self clearSyncMessageForAddress:message.verificationForRecipientAddress
                                                     transaction:transaction];
                            });
                        })
                        .catchInBackground(^(NSError *error) {
                            OWSLogError(@"Failed to send verification state sync message with error: %@", error);
                        });
                });
            })
            .catchInBackground(^(NSError *error) {
                OWSLogError(@"Failed to send verification state NullMessage with error: %@", error);
                if ([MessageSenderNoSuchSignalRecipientError isNoSuchSignalRecipientError:error]) {
                    OWSLogInfo(
                        @"Removing retries for syncing verification state, since user is no longer registered: %@",
                        message.verificationForRecipientAddress);
                    // Otherwise this will fail forever.
                    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                        [self clearSyncMessageForAddress:message.verificationForRecipientAddress
                                             transaction:transaction];
                    });
                }
            });
    });
}

- (void)clearSyncMessageForAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSString *accountId = [self ensureAccountIdForAddress:address transaction:transaction];
    [self clearSyncMessageForAccountId:accountId transaction:transaction];
}

- (void)clearSyncMessageForAccountId:(NSString *)accountId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 1);
    OWSAssertDebug(transaction);

    [self.queuedVerificationStateSyncMessagesKeyValueStore setObject:nil key:accountId transaction:transaction];
}

- (BOOL)processIncomingVerifiedProto:(SSKProtoVerified *)verified
                         transaction:(SDSAnyWriteTransaction *)transaction
                               error:(NSError **)error
{
    return [SCKExceptionWrapper
        tryBlock:^{
            [self throws_processIncomingVerifiedProto:verified transaction:transaction];
        }
           error:error];
}

- (void)throws_processIncomingVerifiedProto:(SSKProtoVerified *)verified
                                transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(verified);
    OWSAssertDebug(transaction);

    SignalServiceAddress *address = verified.destinationAddress;
    if (!address.isValid) {
        OWSFailDebug(@"Verification state sync message missing address.");
        return;
    }
    NSData *rawIdentityKey = verified.identityKey;
    if (rawIdentityKey.length != kIdentityKeyLength) {
        OWSFailDebug(@"Verification state sync message for recipient: %@ with malformed identityKey: %@",
            address,
            rawIdentityKey);
        return;
    }
    NSData *identityKey = [rawIdentityKey throws_removeKeyType];

    if (!verified.hasState) {
        OWSFailDebug(@"Verification state sync message missing state.");
        return;
    }
    switch (verified.unwrappedState) {
        case SSKProtoVerifiedStateDefault:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateDefault
                                                     address:address
                                                 identityKey:identityKey
                                         overwriteOnConflict:NO
                                                 transaction:transaction];
            break;
        case SSKProtoVerifiedStateVerified:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateVerified
                                                     address:address
                                                 identityKey:identityKey
                                         overwriteOnConflict:YES
                                                 transaction:transaction];
            break;
        case SSKProtoVerifiedStateUnverified:
            OWSFailDebug(@"Verification state sync message for address: %@ has unexpected value: %@.",
                address,
                OWSVerificationStateToString(OWSVerificationStateNoLongerVerified));
            return;
    }
}

- (void)tryToApplyVerificationStateFromSyncMessage:(OWSVerificationState)verificationState
                                           address:(SignalServiceAddress *)address
                                       identityKey:(NSData *)identityKey
                               overwriteOnConflict:(BOOL)overwriteOnConflict
                                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    if (!address.isValid) {
        OWSFailDebug(@"Verification state sync message missing recipientId.");
        return;
    }

    if (identityKey.length != kStoredIdentityKeyLength) {
        OWSFailDebug(@"Verification state sync message missing identityKey: %@", address);
        return;
    }

    NSString *accountId = [self ensureAccountIdForAddress:address transaction:transaction];
    OWSRecipientIdentity *_Nullable recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId
                                                                                       transaction:transaction];
    if (!recipientIdentity) {
        // There's no existing recipient identity for this recipient.
        // We should probably create one.
        
        if (verificationState == OWSVerificationStateDefault) {
            // There's no point in creating a new recipient identity just to
            // set its verification state to default.
            return;
        }
        
        // Ensure a remote identity exists for this key. We may be learning about
        // it for the first time.
        [self saveRemoteIdentity:identityKey address:address transaction:transaction];

        recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction];

        if (recipientIdentity == nil) {
            OWSFailDebug(@"Missing expected identity: %@", address);
            return;
        }

        if (![recipientIdentity.accountId isEqualToString:accountId]) {
            OWSFailDebug(@"recipientIdentity has unexpected accountId: %@", address);
            return;
        }

        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            OWSFailDebug(@"recipientIdentity has unexpected identityKey: %@", address);
            return;
        }
        
        if (recipientIdentity.verificationState == verificationState) {
            return;
        }

        OWSLogInfo(@"setVerificationState: %@ (%@ -> %@)",
            address,
            OWSVerificationStateToString(recipientIdentity.verificationState),
            OWSVerificationStateToString(verificationState));

        [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

        // No need to call [saveChangeMessagesForAddress:..] since this is
        // a new recipient.
    } else {
        // There's an existing recipient identity for this recipient.
        // We should update it.
        if (![recipientIdentity.accountId isEqualToString:accountId]) {
            OWSFailDebug(@"recipientIdentity has unexpected accountId: %@", address);
            return;
        }

        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            // The conflict case where we receive a verification sync message
            // whose identity key disagrees with the local identity key for
            // this recipient.
            if (!overwriteOnConflict) {
                OWSLogWarn(@"recipientIdentity has non-matching identityKey: %@", address);
                return;
            }

            OWSLogWarn(@"recipientIdentity has non-matching identityKey; overwriting: %@", address);
            [self saveRemoteIdentity:identityKey address:address transaction:transaction];

            recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:accountId transaction:transaction];

            if (recipientIdentity == nil) {
                OWSFailDebug(@"Missing expected identity: %@", address);
                return;
            }

            if (![recipientIdentity.accountId isEqualToString:accountId]) {
                OWSFailDebug(@"recipientIdentity has unexpected accountId: %@", address);
                return;
            }

            if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
                OWSFailDebug(@"recipientIdentity has unexpected identityKey: %@", address);
                return;
            }
        }
        
        if (recipientIdentity.verificationState == verificationState) {
            return;
        }

        [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

        [self saveChangeMessagesForAddress:address
                         verificationState:verificationState
                             isLocalChange:NO
                               transaction:transaction];
    }
}

// We only want to create change messages in response to user activity,
// on any of their devices.
- (void)saveChangeMessagesForAddress:(SignalServiceAddress *)address
                   verificationState:(OWSVerificationState)verificationState
                       isLocalChange:(BOOL)isLocalChange
                         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactAddress:address
                                                                              transaction:transaction];
    OWSAssertDebug(contactThread);
    [messages addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:contactThread
                                                                 recipientAddress:address
                                                                verificationState:verificationState
                                                                    isLocalChange:isLocalChange]];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithAddress:address transaction:transaction]) {
        [messages addObject:[[OWSVerificationStateChangeMessage alloc] initWithThread:groupThread
                                                                     recipientAddress:address
                                                                    verificationState:verificationState
                                                                        isLocalChange:isLocalChange]];
    }

    // MJK TODO - why not save in-line, vs storing in an array and saving the array?
    for (TSMessage *message in messages) {
        [message anyInsertWithTransaction:transaction];
    }
}

#pragma mark - Debug

#if DEBUG
- (void)clearIdentityState:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *identityKeysToRemove = [NSMutableArray new];
    for (NSString *key in [self.ownIdentityKeyValueStore allKeysWithTransaction:transaction]) {
        if ([key isEqualToString:kIdentityKeyStore_ACIIdentityKey] ||
            [key isEqualToString:kIdentityKeyStore_PNIIdentityKey]) {
            // Don't delete our own keys.
            return;
        }
        [identityKeysToRemove addObject:key];
    }
    for (NSString *key in identityKeysToRemove) {
        [self.ownIdentityKeyValueStore setValue:nil forKey:key];
    }
}
#endif

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // We want to defer this so that we never call this method until
    // [UIApplicationDelegate applicationDidBecomeActive:] is complete.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self tryToSyncQueuedVerificationStates];
    });
}

@end

NS_ASSUME_NONNULL_END
