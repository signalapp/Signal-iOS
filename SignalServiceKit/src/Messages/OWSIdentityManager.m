//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSMessageSender.h"
#import "OWSOutgoingNullMessage.h"
#import "OWSPrimaryStorage.h"
#import "OWSRecipientIdentity.h"
#import "OWSVerificationStateChangeMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
NSString *const OWSPrimaryStorageIdentityKeyStoreIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
NSString *const OWSPrimaryStorageIdentityKeyStoreCollection = @"TSStorageManagerIdentityKeyStoreCollection";

// Storing recipients identity keys
NSString *const OWSPrimaryStorageTrustedKeysCollection = @"TSStorageManagerTrustedKeysCollection";

NSString *const OWSIdentityManager_QueuedVerificationStateSyncMessages =
    @"OWSIdentityManager_QueuedVerificationStateSyncMessages";

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

@property (nonatomic, readonly) SDSKeyValueStore *ownIdentityKeyValueStore;
@property (nonatomic, readonly) SDSKeyValueStore *queuedVerificationStateSyncMessagesKeyValueStore;
@property (nonatomic, readonly) SDSAnyDatabaseQueue *databaseQueue;
@end

#pragma mark -

@implementation OWSIdentityManager

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (instancetype)initWithDatabaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _ownIdentityKeyValueStore =
        [[SDSKeyValueStore alloc] initWithCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
    _queuedVerificationStateSyncMessagesKeyValueStore =
        [[SDSKeyValueStore alloc] initWithCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];
    _databaseQueue = [databaseStorage newDatabaseQueue];

    OWSSingletonAssert();

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)generateNewIdentityKey
{
    [self.databaseQueue writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.ownIdentityKeyValueStore setObject:[Curve25519 generateKeyPair]
                                             key:OWSPrimaryStorageIdentityKeyStoreIdentityKey
                                     transaction:transaction];
    }];
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
{
    __block NSData *_Nullable result = nil;
    [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self identityKeyForRecipientId:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
                               protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);

    SDSAnyReadTransaction *transaction = protocolContext;

    return [self identityKeyForRecipientId:recipientId transaction:transaction];
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    return [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction].identityKey;
}

- (nullable ECKeyPair *)identityKeyPair
{
    __block ECKeyPair *_Nullable identityKeyPair = nil;
    [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        identityKeyPair = [self identityKeyPairWithTransaction:transaction];
    }];
    return identityKeyPair;
}

// This method should only be called from SignalProtocolKit, which doesn't know about YapDatabaseTransactions.
// Whenever possible, prefer to call the strongly typed variant: `identityKeyPairWithTransaction:`.
- (nullable ECKeyPair *)identityKeyPair:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);

    SDSAnyReadTransaction *transaction = protocolContext;

    return [self identityKeyPairWithTransaction:transaction];
}

- (nullable ECKeyPair *)identityKeyPairWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    id _Nullable object =
        [self.ownIdentityKeyValueStore getObject:OWSPrimaryStorageIdentityKeyStoreIdentityKey transaction:transaction];
    if ([object isKindOfClass:[ECKeyPair class]]) {
        return (ECKeyPair *)object;
    } else {
        OWSAssertDebug(object == nil);
        return nil;
    }
}

- (int)localRegistrationId:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    return [self localRegistrationIdWithTransaction:transaction];
}

- (int)localRegistrationIdWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    return (int)[self.tsAccountManager getOrGenerateRegistrationIdWithTransaction:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);

    __block BOOL result;
    [self.databaseQueue writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        result = [self saveRemoteIdentity:identityKey recipientId:recipientId transaction:transaction];
    }];

    return result;
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
           protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    return [self saveRemoteIdentity:identityKey recipientId:recipientId transaction:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);

    OWSRecipientIdentity *existingIdentity =
        [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

    if (existingIdentity == nil) {
        OWSLogInfo(@"saving first use identity for recipient: %@", recipientId);
        [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                               identityKey:identityKey
                                           isFirstKnownKey:YES
                                                 createdAt:[NSDate new]
                                         verificationState:OWSVerificationStateDefault]
            anyInsertWithTransaction:transaction];

        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForRecipientId:recipientId transaction:transaction];

        [self fireIdentityStateChangeNotification];

        return NO;
    }

    if (![existingIdentity.identityKey isEqual:identityKey]) {
        OWSVerificationState verificationState;
        switch (existingIdentity.verificationState) {
            case OWSVerificationStateDefault:
                verificationState = OWSVerificationStateDefault;
                break;
            case OWSVerificationStateVerified:
            case OWSVerificationStateNoLongerVerified:
                verificationState = OWSVerificationStateNoLongerVerified;
                break;
        }

        OWSLogInfo(@"replacing identity for existing recipient: %@ (%@ -> %@)",
            recipientId,
            OWSVerificationStateToString(existingIdentity.verificationState),
            OWSVerificationStateToString(verificationState));
        [self createIdentityChangeInfoMessageForRecipientId:recipientId transaction:transaction];

        [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                               identityKey:identityKey
                                           isFirstKnownKey:NO
                                                 createdAt:[NSDate new]
                                         verificationState:verificationState] anyInsertWithTransaction:transaction];

        [self.sessionStore archiveAllSessionsForContact:recipientId transaction:transaction];

        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForRecipientId:recipientId transaction:transaction];

        [self fireIdentityStateChangeNotification];

        return YES;
    }

    return NO;
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);

    [self.databaseQueue writeWithBlock:^(SDSAnyWriteTransaction *_Nonnull transaction) {
        [self setVerificationState:verificationState
                       identityKey:identityKey
                       recipientId:recipientId
             isUserInitiatedChange:isUserInitiatedChange
                       transaction:transaction];
    }];
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
             protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);

    SDSAnyWriteTransaction *transaction = protocolContext;

    [self setVerificationState:verificationState
                   identityKey:identityKey
                   recipientId:recipientId
         isUserInitiatedChange:isUserInitiatedChange
                   transaction:transaction];
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    // Ensure a remote identity exists for this key. We may be learning about
    // it for the first time.
    [self saveRemoteIdentity:identityKey recipientId:recipientId transaction:transaction];

    OWSRecipientIdentity *recipientIdentity =
        [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

    if (recipientIdentity == nil) {
        OWSFailDebug(@"Missing expected identity: %@", recipientId);
        return;
    }

    if (recipientIdentity.verificationState == verificationState) {
        return;
    }

    OWSLogInfo(@"setVerificationState: %@ (%@ -> %@)",
        recipientId,
        OWSVerificationStateToString(recipientIdentity.verificationState),
        OWSVerificationStateToString(verificationState));

    [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

    if (isUserInitiatedChange) {
        [self saveChangeMessagesForRecipientId:recipientId
                             verificationState:verificationState
                                 isLocalChange:YES
                                   transaction:transaction];
        [self enqueueSyncMessageForVerificationStateForRecipientId:recipientId transaction:transaction];
    } else {
        // Cancel any pending verification state sync messages for this recipient.
        [self clearSyncMessageForRecipientId:recipientId transaction:transaction];
    }

    [self fireIdentityStateChangeNotification];
}

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
{
    __block OWSVerificationState result;
    [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        result = [self verificationStateForRecipientId:recipientId transaction:transaction];
    }];
    return result;
}

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
                                            transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    OWSRecipientIdentity *_Nullable currentIdentity =
        [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

    if (!currentIdentity) {
        // We might not know the identity for this recipient yet.
        return OWSVerificationStateDefault;
    }

    return currentIdentity.verificationState;
}

- (nullable OWSRecipientIdentity *)recipientIdentityForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    __block OWSRecipientIdentity *_Nullable result;
    [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        result = [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    __block OWSRecipientIdentity *_Nullable result;
    [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *_Nullable recipientIdentity =
            [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

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
             protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(direction != TSMessageDirectionUnknown);
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);

    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self isTrustedIdentityKey:identityKey recipientId:recipientId direction:direction transaction:transaction];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(direction != TSMessageDirectionUnknown);
    OWSAssertDebug(transaction);

    if ([self.tsAccountManager.localNumber isEqualToString:recipientId]) {
        ECKeyPair *_Nullable localIdentityKeyPair = [self identityKeyPairWithTransaction:transaction];

        if ([localIdentityKeyPair.publicKey isEqualToData:identityKey]) {
            return YES;
        } else {
            OWSFailDebug(@"Wrong identity: %@ for local key: %@, recipientId: %@",
                identityKey,
                localIdentityKeyPair.publicKey,
                recipientId);
            return NO;
        }
    }

    switch (direction) {
        case TSMessageDirectionIncoming: {
            return YES;
        }
        case TSMessageDirectionOutgoing: {
            OWSRecipientIdentity *existingIdentity =
                [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];
            return [self isTrustedKey:identityKey forSendingToIdentity:existingIdentity];
        }
        default: {
            OWSFailDebug(@"unexpected message direction: %ld", (long)direction);
            return NO;
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);

    if (recipientIdentity == nil) {
        return YES;
    }

    OWSAssertDebug(recipientIdentity.identityKey.length == kStoredIdentityKeyLength);
    if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
        OWSLogWarn(@"key mismatch for recipient: %@", recipientIdentity.recipientId);
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
                OWSLogWarn(@"not trusting new identity for recipient: %@", recipientIdentity.recipientId);
                return NO;
            } else {
                return YES;
            }
        }
        case OWSVerificationStateVerified:
            return YES;
        case OWSVerificationStateNoLongerVerified:
            OWSLogWarn(@"not trusting no longer verified identity for recipient: %@", recipientIdentity.recipientId);
            return NO;
    }
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
                                          transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId anyTransaction:transaction];
    OWSAssertDebug(contactThread != nil);

    TSErrorMessage *errorMessage =
        [TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId];
    [messages addObject:errorMessage];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId transaction:transaction]) {
        [messages addObject:[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId]];
    }

    // MJK TODO - why not save immediately, why build up this array?
    for (TSMessage *message in messages) {
        [message anyInsertWithTransaction:transaction];
    }

    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

- (void)enqueueSyncMessageForVerificationStateForRecipientId:(NSString *)recipientId
                                                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    [self.queuedVerificationStateSyncMessagesKeyValueStore setObject:recipientId
                                                                 key:recipientId
                                                         transaction:transaction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self tryToSyncQueuedVerificationStates];
    });
}

- (void)tryToSyncQueuedVerificationStates
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self syncQueuedVerificationStates];
    }];
}

- (void)syncQueuedVerificationStates
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<OWSVerificationStateSyncMessage *> *messages = [NSMutableArray new];
        [self.databaseQueue readWithBlock:^(SDSAnyReadTransaction *transaction) {
            NSArray<NSString *> *recipientIds =
                [self.queuedVerificationStateSyncMessagesKeyValueStore allKeysWithTransaction:transaction];

            for (NSString *recipientId in recipientIds) {
                OWSRecipientIdentity *recipientIdentity =
                    [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];
                if (!recipientIdentity) {
                    OWSFailDebug(@"Could not load recipient identity for recipientId: %@", recipientId);
                    continue;
                }
                if (recipientIdentity.recipientId.length < 1) {
                    OWSFailDebug(@"Invalid recipient identity for recipientId: %@", recipientId);
                    continue;
                }

                // Prepend key type for transit.
                // TODO we should just be storing the key type so we don't have to juggle re-adding it.
                NSData *identityKey = [recipientIdentity.identityKey prependKeyType];
                if (identityKey.length != kIdentityKeyLength) {
                    OWSFailDebug(
                        @"Invalid recipient identitykey for recipientId: %@ key: %@", recipientId, identityKey);
                    continue;
                }
                if (recipientIdentity.verificationState == OWSVerificationStateNoLongerVerified) {
                    // We don't want to sync "no longer verified" state.  Other clients can
                    // figure this out from the /profile/ endpoint, and this can cause data
                    // loss as a user's devices overwrite each other's verification.
                    OWSFailDebug(@"Queue verification state had unexpected value: %@ recipientId: %@",
                        OWSVerificationStateToString(recipientIdentity.verificationState),
                        recipientId);
                    continue;
                }
                OWSVerificationStateSyncMessage *message = [[OWSVerificationStateSyncMessage alloc]
                     initWithVerificationState:recipientIdentity.verificationState
                                   identityKey:identityKey
                    verificationForRecipientId:recipientIdentity.recipientId];
                [messages addObject:message];
            }
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
    OWSAssertDebug(message.verificationForRecipientId.length > 0);

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:message.verificationForRecipientId];
    
    // Send null message to appear as though we're sending a normal message to cover the sync messsage sent
    // subsequently
    OWSOutgoingNullMessage *nullMessage = [[OWSOutgoingNullMessage alloc] initWithContactThread:contactThread
                                                                   verificationStateSyncMessage:message];

    // DURABLE CLEANUP - we could replace the custom durability logic in this class
    // with a durable JobQueue.
    [self.messageSender sendMessage:nullMessage
        success:^{
            OWSLogInfo(@"Successfully sent verification state NullMessage");
            [self.messageSender sendMessage:message
                success:^{
                    OWSLogInfo(@"Successfully sent verification state sync message");

                    // Record that this verification state was successfully synced.
                    [self.databaseQueue writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                        [self clearSyncMessageForRecipientId:message.verificationForRecipientId
                                                 transaction:transaction];
                    }];
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send verification state sync message with error: %@", error);
                }];
        }
        failure:^(NSError *_Nonnull error) {
            OWSLogError(@"Failed to send verification state NullMessage with error: %@", error);
            if (error.code == OWSErrorCodeNoSuchSignalRecipient) {
                OWSLogInfo(@"Removing retries for syncing verification state, since user is no longer registered: %@",
                    message.verificationForRecipientId);
                // Otherwise this will fail forever.
                [self.databaseQueue writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                    [self clearSyncMessageForRecipientId:message.verificationForRecipientId transaction:transaction];
                }];
            }
        }];
}

- (void)clearSyncMessageForRecipientId:(NSString *)recipientId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    [self.queuedVerificationStateSyncMessagesKeyValueStore setObject:nil key:recipientId transaction:transaction];
}

- (void)throws_processIncomingSyncMessage:(SSKProtoVerified *)verified transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(verified);
    OWSAssertDebug(transaction);

    NSString *recipientId = verified.destination;
    if (recipientId.length < 1) {
        OWSFailDebug(@"Verification state sync message missing recipientId.");
        return;
    }
    NSData *rawIdentityKey = verified.identityKey;
    if (rawIdentityKey.length != kIdentityKeyLength) {
        OWSFailDebug(@"Verification state sync message for recipient: %@ with malformed identityKey: %@",
            recipientId,
            rawIdentityKey);
        return;
    }
    NSData *identityKey = [rawIdentityKey throws_removeKeyType];

    if (!verified.hasState) {
        OWSFailDebug(@"Verification state sync message missing state.");
        return;
    }
    switch (verified.stateRequired) {
        case SSKProtoVerifiedStateDefault:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateDefault
                                                 recipientId:recipientId
                                                 identityKey:identityKey
                                         overwriteOnConflict:NO
                                                 transaction:transaction];
            break;
        case SSKProtoVerifiedStateVerified:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateVerified
                                                 recipientId:recipientId
                                                 identityKey:identityKey
                                         overwriteOnConflict:YES
                                                 transaction:transaction];
            break;
        case SSKProtoVerifiedStateUnverified:
            OWSFailDebug(@"Verification state sync message for recipientId: %@ has unexpected value: %@.",
                recipientId,
                OWSVerificationStateToString(OWSVerificationStateNoLongerVerified));
            return;
    }

    [self fireIdentityStateChangeNotification];
}

- (void)tryToApplyVerificationStateFromSyncMessage:(OWSVerificationState)verificationState
                                       recipientId:(NSString *)recipientId
                                       identityKey:(NSData *)identityKey
                               overwriteOnConflict:(BOOL)overwriteOnConflict
                                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    if (recipientId.length < 1) {
        OWSFailDebug(@"Verification state sync message missing recipientId.");
        return;
    }

    if (identityKey.length != kStoredIdentityKeyLength) {
        OWSFailDebug(@"Verification state sync message missing identityKey: %@", recipientId);
        return;
    }

    OWSRecipientIdentity *_Nullable recipientIdentity =
        [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];
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
        [self saveRemoteIdentity:identityKey recipientId:recipientId transaction:transaction];

        recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

        if (recipientIdentity == nil) {
            OWSFailDebug(@"Missing expected identity: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.recipientId isEqualToString:recipientId]) {
            OWSFailDebug(@"recipientIdentity has unexpected recipientId: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            OWSFailDebug(@"recipientIdentity has unexpected identityKey: %@", recipientId);
            return;
        }
        
        if (recipientIdentity.verificationState == verificationState) {
            return;
        }

        OWSLogInfo(@"setVerificationState: %@ (%@ -> %@)",
            recipientId,
            OWSVerificationStateToString(recipientIdentity.verificationState),
            OWSVerificationStateToString(verificationState));

        [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

        // No need to call [saveChangeMessagesForRecipientId:..] since this is
        // a new recipient.
    } else {
        // There's an existing recipient identity for this recipient.
        // We should update it.
        if (![recipientIdentity.recipientId isEqualToString:recipientId]) {
            OWSFailDebug(@"recipientIdentity has unexpected recipientId: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            // The conflict case where we receive a verification sync message
            // whose identity key disagrees with the local identity key for
            // this recipient.
            if (!overwriteOnConflict) {
                OWSLogWarn(@"recipientIdentity has non-matching identityKey: %@", recipientId);
                return;
            }

            OWSLogWarn(@"recipientIdentity has non-matching identityKey; overwriting: %@", recipientId);
            [self saveRemoteIdentity:identityKey recipientId:recipientId transaction:transaction];

            recipientIdentity = [OWSRecipientIdentity anyFetchWithUniqueId:recipientId transaction:transaction];

            if (recipientIdentity == nil) {
                OWSFailDebug(@"Missing expected identity: %@", recipientId);
                return;
            }
            
            if (![recipientIdentity.recipientId isEqualToString:recipientId]) {
                OWSFailDebug(@"recipientIdentity has unexpected recipientId: %@", recipientId);
                return;
            }
            
            if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
                OWSFailDebug(@"recipientIdentity has unexpected identityKey: %@", recipientId);
                return;
            }
        }
        
        if (recipientIdentity.verificationState == verificationState) {
            return;
        }

        [recipientIdentity updateWithVerificationState:verificationState transaction:transaction];

        [self saveChangeMessagesForRecipientId:recipientId
                             verificationState:verificationState
                                 isLocalChange:NO
                                   transaction:transaction];
    }
}

// We only want to create change messages in response to user activity,
// on any of their devices.
- (void)saveChangeMessagesForRecipientId:(NSString *)recipientId
                       verificationState:(OWSVerificationState)verificationState
                           isLocalChange:(BOOL)isLocalChange
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId anyTransaction:transaction];
    OWSAssertDebug(contactThread);
    // MJK TODO - should be safe to remove senderTimestamp
    [messages addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                              thread:contactThread
                                                                         recipientId:recipientId
                                                                   verificationState:verificationState
                                                                       isLocalChange:isLocalChange]];

    for (TSGroupThread *groupThread in
        [TSGroupThread groupThreadsWithRecipientId:recipientId transaction:transaction]) {
        // MJK TODO - should be safe to remove senderTimestamp
        [messages
            addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                            thread:groupThread
                                                                       recipientId:recipientId
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
        if ([key isEqualToString:OWSPrimaryStorageIdentityKeyStoreIdentityKey]) {
            // Don't delete our own key.
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
