//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSDate+OWS.h"
#import "NSNotificationCenter+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "OWSMessageSender.h"
#import "OWSOutgoingNullMessage.h"
#import "OWSPrimaryStorage+sessionStore.h"
#import "OWSPrimaryStorage.h"
#import "OWSRecipientIdentity.h"
#import "OWSVerificationStateChangeMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <Curve25519Kit/Curve25519.h>
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

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSIdentityManager

+ (instancetype)sharedManager
{
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(primaryStorage);

    _primaryStorage = primaryStorage;
    _dbConnection = primaryStorage.newDatabaseConnection;
    self.dbConnection.objectCacheEnabled = NO;

    OWSSingletonAssert();

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)generateNewIdentityKey
{
    [self.dbConnection setObject:[Curve25519 generateKeyPair]
                          forKey:OWSPrimaryStorageIdentityKeyStoreIdentityKey
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

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
                                   transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

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
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadTransaction class]]);

    YapDatabaseReadTransaction *transaction = protocolContext;

    return [self identityKeyPairWithTransaction:transaction];
}

- (nullable ECKeyPair *)identityKeyPairWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    ECKeyPair *_Nullable identityKeyPair = [transaction keyPairForKey:OWSPrimaryStorageIdentityKeyStoreIdentityKey
                                                         inCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
    return identityKeyPair;
}

- (int)localRegistrationId:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return (int)[TSAccountManager getOrGenerateRegistrationId:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);

    __block BOOL result;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        result = [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:transaction];
    }];

    return result;
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
           protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    // Deprecated. We actually no longer use the OWSPrimaryStorageTrustedKeysCollection for trust
    // decisions, but it's desirable to try to keep it up to date with our trusted identitys
    // while we're switching between versions, e.g. so we don't get into a state where we have a
    // session for an identity not in our key store.
    [transaction setObject:identityKey forKey:recipientId inCollection:OWSPrimaryStorageTrustedKeysCollection];

    OWSRecipientIdentity *existingIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

    if (existingIdentity == nil) {
        OWSLogInfo(@"saving first use identity for recipient: %@", recipientId);
        [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                               identityKey:identityKey
                                           isFirstKnownKey:YES
                                                 createdAt:[NSDate new]
                                         verificationState:OWSVerificationStateDefault]
            saveWithTransaction:transaction];

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
                                         verificationState:verificationState] saveWithTransaction:transaction];

        [self.primaryStorage archiveAllSessionsForContact:recipientId protocolContext:protocolContext];

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

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
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
             protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

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
                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    // Ensure a remote identity exists for this key. We may be learning about
    // it for the first time.
    [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:transaction];

    OWSRecipientIdentity *recipientIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

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
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [self verificationStateForRecipientId:recipientId transaction:transaction];
    }];
    return result;
}

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
                                            transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    OWSRecipientIdentity *_Nullable currentIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

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
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        result = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

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
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(direction != TSMessageDirectionUnknown);
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [self isTrustedIdentityKey:identityKey recipientId:recipientId direction:direction transaction:transaction];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
                 transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kStoredIdentityKeyLength);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(direction != TSMessageDirectionUnknown);
    OWSAssertDebug(transaction);

    if ([[TSAccountManager localNumber] isEqualToString:recipientId]) {
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
                [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];
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
                                          transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
    OWSAssertDebug(contactThread != nil);

    TSErrorMessage *errorMessage =
        [TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId];
    [messages addObject:errorMessage];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId transaction:transaction]) {
        [messages addObject:[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId]];
    }

    for (TSMessage *message in messages) {
        [message saveWithTransaction:transaction];
    }

    [SSKEnvironment.shared.notificationsManager notifyUserForErrorMessage:errorMessage
                                                                   thread:contactThread
                                                              transaction:transaction];
}

- (void)enqueueSyncMessageForVerificationStateForRecipientId:(NSString *)recipientId
                                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    [transaction setObject:recipientId
                    forKey:recipientId
              inCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self tryToSyncQueuedVerificationStates];
    });
}

- (void)tryToSyncQueuedVerificationStates
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppIsReady:^{
        [self syncQueuedVerificationStates];
    }];
}

- (void)syncQueuedVerificationStates
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<NSString *> *recipientIds = [NSMutableArray new];
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [transaction
                enumerateKeysAndObjectsInCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages
                                         usingBlock:^(
                                             NSString *_Nonnull recipientId, id _Nonnull object, BOOL *_Nonnull stop) {
                                             [recipientIds addObject:recipientId];
                                         }];
        }];

        NSMutableArray<OWSVerificationStateSyncMessage *> *messages = [NSMutableArray new];
        for (NSString *recipientId in recipientIds) {
            OWSRecipientIdentity *recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
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
                OWSFailDebug(@"Invalid recipient identitykey for recipientId: %@ key: %@", recipientId, identityKey);
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
            OWSVerificationStateSyncMessage *message =
                [[OWSVerificationStateSyncMessage alloc] initWithVerificationState:recipientIdentity.verificationState
                                                                       identityKey:identityKey
                                                        verificationForRecipientId:recipientIdentity.recipientId];
            [messages addObject:message];
        }
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
    [self.messageSender enqueueMessage:nullMessage
        success:^{
            OWSLogInfo(@"Successfully sent verification state NullMessage");
            [self.messageSender enqueueMessage:message
                success:^{
                    OWSLogInfo(@"Successfully sent verification state sync message");

                    // Record that this verification state was successfully synced.
                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * transaction) {
                        [self clearSyncMessageForRecipientId:message.verificationForRecipientId transaction:transaction];
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
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * transaction) {
                    [self clearSyncMessageForRecipientId:message.verificationForRecipientId transaction:transaction];
                }];
            }
        }];
}

- (void)clearSyncMessageForRecipientId:(NSString *)recipientId
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    [transaction removeObjectForKey:recipientId inCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];
}

- (void)processIncomingSyncMessage:(SSKProtoVerified *)verified
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
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
    NSData *identityKey = [rawIdentityKey removeKeyType];

    switch (verified.state) {
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
                                       transaction:(YapDatabaseReadWriteTransaction *)transaction
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
    
    OWSRecipientIdentity *_Nullable recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId
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
        [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:transaction];
        
        recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId
                                                              transaction:transaction];
        
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

        [recipientIdentity updateWithVerificationState:verificationState
         transaction:transaction];
        
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
            [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:transaction];
            
            recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId
                                                                  transaction:transaction];
            
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
        
        [recipientIdentity updateWithVerificationState:verificationState
                                           transaction:transaction];
        
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
                             transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
    OWSAssertDebug(contactThread);
    [messages addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                              thread:contactThread
                                                                         recipientId:recipientId
                                                                   verificationState:verificationState
                                                                       isLocalChange:isLocalChange]];

    for (TSGroupThread *groupThread in
        [TSGroupThread groupThreadsWithRecipientId:recipientId transaction:transaction]) {
        [messages
            addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                            thread:groupThread
                                                                       recipientId:recipientId
                                                                 verificationState:verificationState
                                                                     isLocalChange:isLocalChange]];
    }

    for (TSMessage *message in messages) {
        [message saveWithTransaction:transaction];
    }
}

#pragma mark - Debug

#if DEBUG
- (void)clearIdentityState:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *identityKeysToRemove = [NSMutableArray new];
    [transaction enumerateKeysInCollection:OWSPrimaryStorageIdentityKeyStoreCollection
                                usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                    if ([key isEqualToString:OWSPrimaryStorageIdentityKeyStoreIdentityKey]) {
                                        // Don't delete our own key.
                                        return;
                                    }
                                    [identityKeysToRemove addObject:key];
                                }];
    for (NSString *key in identityKeysToRemove) {
        [transaction removeObjectForKey:key inCollection:OWSPrimaryStorageIdentityKeyStoreCollection];
    }
    [transaction removeAllObjectsInCollection:OWSPrimaryStorageTrustedKeysCollection];
}

- (NSString *)identityKeySnapshotFilePath
{
    // Prefix name with period "." so that backups will ignore these snapshots.
    NSString *dirPath = [OWSFileSystem appDocumentDirectoryPath];
    return [dirPath stringByAppendingPathComponent:@".identity-key-snapshot"];
}

- (NSString *)trustedKeySnapshotFilePath
{
    // Prefix name with period "." so that backups will ignore these snapshots.
    NSString *dirPath = [OWSFileSystem appDocumentDirectoryPath];
    return [dirPath stringByAppendingPathComponent:@".trusted-key-snapshot"];
}

- (void)snapshotIdentityState:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [transaction snapshotCollection:OWSPrimaryStorageIdentityKeyStoreCollection
                   snapshotFilePath:self.identityKeySnapshotFilePath];
    [transaction snapshotCollection:OWSPrimaryStorageTrustedKeysCollection
                   snapshotFilePath:self.trustedKeySnapshotFilePath];
}

- (void)restoreIdentityState:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [transaction restoreSnapshotOfCollection:OWSPrimaryStorageIdentityKeyStoreCollection
                            snapshotFilePath:self.identityKeySnapshotFilePath];
    [transaction restoreSnapshotOfCollection:OWSPrimaryStorageTrustedKeysCollection
                            snapshotFilePath:self.trustedKeySnapshotFilePath];
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
