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
#import "OWSRecipientIdentity.h"
#import "OWSVerificationStateChangeMessage.h"
#import "OWSVerificationStateSyncMessage.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSStorageManager+sessionStore.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseReadTransaction+OWS.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <Curve25519Kit/Curve25519.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
NSString *const TSStorageManagerIdentityKeyStoreIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
NSString *const TSStorageManagerIdentityKeyStoreCollection = @"TSStorageManagerIdentityKeyStoreCollection";

// Storing recipients identity keys
NSString *const TSStorageManagerTrustedKeysCollection = @"TSStorageManagerTrustedKeysCollection";

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

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// TODO: Should we get rid of this property?
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSIdentityManager

+ (instancetype)sharedManager
{
    static OWSIdentityManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initWithStorageManager:storageManager messageSender:messageSender];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                         messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);
    OWSAssert(messageSender);

    _storageManager = storageManager;
    _dbConnection = storageManager.newDatabaseConnection;
    self.dbConnection.objectCacheEnabled = NO;
#if DEBUG
    self.dbConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
    _messageSender = messageSender;

    OWSSingletonAssert();

    [self observeNotifications];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
                          forKey:TSStorageManagerIdentityKeyStoreIdentityKey
                    inCollection:TSStorageManagerIdentityKeyStoreCollection];
}

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId protocolContext:(nullable id)protocolContext
{
    OWSAssert(recipientId.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction].identityKey;
}

- (nullable ECKeyPair *)identityKeyPairWithoutProtocolContext
{
    __block ECKeyPair *_Nullable identityKeyPair = nil;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        identityKeyPair = [self identityKeyPair:transaction];
    }];
    return identityKeyPair;
}

- (nullable ECKeyPair *)identityKeyPair:(nullable id)protocolContext
{
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    ECKeyPair *_Nullable identityKeyPair = [transaction keyPairForKey:TSStorageManagerIdentityKeyStoreIdentityKey
                                                         inCollection:TSStorageManagerIdentityKeyStoreCollection];
    return identityKeyPair;
}

- (int)localRegistrationId:(nullable id)protocolContext
{
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return (int)[TSAccountManager getOrGenerateRegistrationId:transaction];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
           protocolContext:(nullable id)protocolContext
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    // Deprecated. We actually no longer use the TSStorageManagerTrustedKeysCollection for trust
    // decisions, but it's desirable to try to keep it up to date with our trusted identitys
    // while we're switching between versions, e.g. so we don't get into a state where we have a
    // session for an identity not in our key store.
    [transaction setObject:identityKey forKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];

    OWSRecipientIdentity *existingIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

    if (existingIdentity == nil) {
        DDLogInfo(@"%@ saving first use identity for recipient: %@", self.logTag, recipientId);
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

        DDLogInfo(@"%@ replacing identity for existing recipient: %@ (%@ -> %@)",
            self.logTag,
            recipientId,
            OWSVerificationStateToString(existingIdentity.verificationState),
            OWSVerificationStateToString(verificationState));
        [self createIdentityChangeInfoMessageForRecipientId:recipientId transaction:transaction];

        [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                               identityKey:identityKey
                                           isFirstKnownKey:NO
                                                 createdAt:[NSDate new]
                                         verificationState:verificationState] saveWithTransaction:transaction];

        [self.storageManager archiveAllSessionsForContact:recipientId protocolContext:protocolContext];

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
             protocolContext:(nullable id)protocolContext
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    // TODO: Remove all @synchronized
    // Ensure a remote identity exists for this key. We may be learning about
    // it for the first time.
    [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:protocolContext];

    OWSRecipientIdentity *recipientIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

    if (recipientIdentity == nil) {
        OWSFail(@"Missing expected identity: %@", recipientId);
        return;
    }

    if (recipientIdentity.verificationState == verificationState) {
        return;
    }

    DDLogInfo(@"%@ setVerificationState: %@ (%@ -> %@)",
        self.logTag,
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
    // Use a read/write transaction to block on latest.
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        result = [self verificationStateForRecipientId:recipientId transaction:transaction];
    }];
    return result;
}

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
                                            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

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
    OWSAssert(recipientId.length > 0);

    __block OWSRecipientIdentity *_Nullable result;
    // Use a read/write transaction to block on latest.
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        result = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];
    }];
    return result;
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId
                                                            protocolContext:(nullable id)protocolContext
{
    OWSAssert(recipientId.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    OWSRecipientIdentity *_Nullable recipientIdentity =
        [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId transaction:transaction];

    if (recipientIdentity == nil) {
        // trust on first use
        return nil;
    }

    BOOL isTrusted = [self isTrustedIdentityKey:recipientIdentity.identityKey
                                    recipientId:recipientId
                                      direction:TSMessageDirectionOutgoing
                                protocolContext:protocolContext];
    if (isTrusted) {
        return nil;
    } else {
        return recipientIdentity;
    }
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
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);
    OWSAssert(direction != TSMessageDirectionUnknown);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    @synchronized(self)
    {
        if ([[TSAccountManager localNumber] isEqualToString:recipientId]) {
            ECKeyPair *_Nullable localIdentityKeyPair = [self identityKeyPair:protocolContext];

            if ([localIdentityKeyPair.publicKey isEqualToData:identityKey]) {
                return YES;
            } else {
                OWSFail(@"%@ Wrong identity: %@ for local key: %@, recipientId: %@",
                    self.logTag,
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
                OWSFail(@"%@ unexpected message direction: %ld", self.logTag, (long)direction);
                return NO;
            }
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);

    if (recipientIdentity == nil) {
        return YES;
    }

    OWSAssert(recipientIdentity.identityKey.length == kStoredIdentityKeyLength);
    if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
        DDLogWarn(@"%@ key mismatch for recipient: %@", self.logTag, recipientIdentity.recipientId);
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
                DDLogWarn(
                    @"%@ not trusting new identity for recipient: %@", self.logTag, recipientIdentity.recipientId);
                return NO;
            } else {
                return YES;
            }
        }
        case OWSVerificationStateVerified:
            return YES;
        case OWSVerificationStateNoLongerVerified:
            DDLogWarn(@"%@ not trusting no longer verified identity for recipient: %@",
                self.logTag,
                recipientIdentity.recipientId);
            return NO;
    }
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
                                          transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
    OWSAssert(contactThread != nil);

    TSErrorMessage *errorMessage =
        [TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId];
    [messages addObject:errorMessage];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId transaction:transaction]) {
        [messages addObject:[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId]];
    }

    for (TSMessage *message in messages) {
        [message saveWithTransaction:transaction];
    }

    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:contactThread];
}

- (void)enqueueSyncMessageForVerificationStateForRecipientId:(NSString *)recipientId
                                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

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
        @synchronized(self)
        {
            NSMutableArray<NSString *> *recipientIds = [NSMutableArray new];
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [transaction enumerateKeysAndObjectsInCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages
                                                      usingBlock:^(NSString *_Nonnull recipientId,
                                                                   id _Nonnull object,
                                                                   BOOL *_Nonnull stop) {
                                                          [recipientIds addObject:recipientId];
                                                      }];
            }];

            NSMutableArray<OWSVerificationStateSyncMessage *> *messages = [NSMutableArray new];
            for (NSString *recipientId in recipientIds) {
                OWSRecipientIdentity *recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
                if (!recipientIdentity) {
                    OWSFail(@"Could not load recipient identity for recipientId: %@", recipientId);
                    continue;
                }
                if (recipientIdentity.recipientId.length < 1) {
                    OWSFail(@"Invalid recipient identity for recipientId: %@", recipientId);
                    continue;
                }

                // Prepend key type for transit.
                // TODO we should just be storing the key type so we don't have to juggle re-adding it.
                NSData *identityKey = [recipientIdentity.identityKey prependKeyType];
                if (identityKey.length != kIdentityKeyLength) {
                    OWSFail(@"Invalid recipient identitykey for recipientId: %@ key: %@", recipientId, identityKey);
                    continue;
                }
                if (recipientIdentity.verificationState == OWSVerificationStateNoLongerVerified) {
                    // We don't want to sync "no longer verified" state.  Other clients can
                    // figure this out from the /profile/ endpoint, and this can cause data
                    // loss as a user's devices overwrite each other's verification.
                    OWSFail(@"Queue verification state had unexpected value: %@ recipientId: %@",
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
            if (messages.count > 0) {
                for (OWSVerificationStateSyncMessage *message in messages) {
                    [self sendSyncVerificationStateMessage:message];
                }
            }
        }
    });
}

- (void)sendSyncVerificationStateMessage:(OWSVerificationStateSyncMessage *)message
{
    OWSAssert(message);
    OWSAssert(message.verificationForRecipientId.length > 0);
    OWSAssertIsOnMainThread();

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:message.verificationForRecipientId];
    
    // Send null message to appear as though we're sending a normal message to cover the sync messsage sent
    // subsequently
    OWSOutgoingNullMessage *nullMessage = [[OWSOutgoingNullMessage alloc] initWithContactThread:contactThread
                                                                   verificationStateSyncMessage:message];
    [self.messageSender enqueueMessage:nullMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent verification state NullMessage", self.logTag);
            [self.messageSender enqueueMessage:message
                success:^{
                    DDLogInfo(@"%@ Successfully sent verification state sync message", self.logTag);

                    // Record that this verification state was successfully synced.
                    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * transaction) {
                        [self clearSyncMessageForRecipientId:message.verificationForRecipientId transaction:transaction];
                    }];
                }
                failure:^(NSError *error) {
                    DDLogError(@"%@ Failed to send verification state sync message with error: %@", self.logTag, error);
                }];
        }
        failure:^(NSError *_Nonnull error) {
            DDLogError(@"%@ Failed to send verification state NullMessage with error: %@", self.logTag, error);
            if (error.code == OWSErrorCodeNoSuchSignalRecipient) {
                DDLogInfo(@"%@ Removing retries for syncing verification state, since user is no longer registered: %@",
                    self.logTag,
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
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    [transaction removeObjectForKey:recipientId inCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];
}

- (void)processIncomingSyncMessage:(OWSSignalServiceProtosVerified *)verified
{
    NSString *recipientId = verified.destination;
    if (recipientId.length < 1) {
        OWSFail(@"Verification state sync message missing recipientId.");
        return;
    }
    NSData *rawIdentityKey = verified.identityKey;
    if (rawIdentityKey.length != kIdentityKeyLength) {
        OWSFail(@"Verification state sync message for recipient: %@ with malformed identityKey: %@",
            recipientId,
            rawIdentityKey);
        return;
    }
    NSData *identityKey = [rawIdentityKey removeKeyType];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * transaction) {
            switch (verified.state) {
                case OWSSignalServiceProtosVerifiedStateDefault:
                    [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateDefault
                                                         recipientId:recipientId
                                                         identityKey:identityKey
                                                 overwriteOnConflict:NO
                                                         transaction:transaction];
                    break;
                case OWSSignalServiceProtosVerifiedStateVerified:
                    [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateVerified
                                                         recipientId:recipientId
                                                         identityKey:identityKey
                                                 overwriteOnConflict:YES
                                                         transaction:transaction];
                    break;
                case OWSSignalServiceProtosVerifiedStateUnverified:
                    OWSFail(@"Verification state sync message for recipientId: %@ has unexpected value: %@.",
                            recipientId,
                            OWSVerificationStateToString(OWSVerificationStateNoLongerVerified));
                    return;
            }
        }];
        [self fireIdentityStateChangeNotification];
    });
}

- (void)tryToApplyVerificationStateFromSyncMessage:(OWSVerificationState)verificationState
                                       recipientId:(NSString *)recipientId
                                       identityKey:(NSData *)identityKey
                               overwriteOnConflict:(BOOL)overwriteOnConflict
                                       transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    if (recipientId.length < 1) {
        OWSFail(@"Verification state sync message missing recipientId.");
        return;
    }

    if (identityKey.length != kStoredIdentityKeyLength) {
        OWSFail(@"Verification state sync message missing identityKey: %@", recipientId);
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
            OWSFail(@"Missing expected identity: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.recipientId isEqualToString:recipientId]) {
            OWSFail(@"recipientIdentity has unexpected recipientId: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            OWSFail(@"recipientIdentity has unexpected identityKey: %@", recipientId);
            return;
        }
        
        if (recipientIdentity.verificationState == verificationState) {
            return;
        }
        
        DDLogInfo(@"%@ setVerificationState: %@ (%@ -> %@)",
                  self.logTag,
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
            OWSFail(@"recipientIdentity has unexpected recipientId: %@", recipientId);
            return;
        }
        
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            // The conflict case where we receive a verification sync message
            // whose identity key disagrees with the local identity key for
            // this recipient.
            if (!overwriteOnConflict) {
                DDLogWarn(@"recipientIdentity has non-matching identityKey: %@", recipientId);
                return;
            }
            
            DDLogWarn(@"recipientIdentity has non-matching identityKey; overwriting: %@", recipientId);
            [self saveRemoteIdentity:identityKey recipientId:recipientId protocolContext:transaction];
            
            recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId
                                                                  transaction:transaction];
            
            if (recipientIdentity == nil) {
                OWSFail(@"Missing expected identity: %@", recipientId);
                return;
            }
            
            if (![recipientIdentity.recipientId isEqualToString:recipientId]) {
                OWSFail(@"recipientIdentity has unexpected recipientId: %@", recipientId);
                return;
            }
            
            if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
                OWSFail(@"recipientIdentity has unexpected identityKey: %@", recipientId);
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
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread =
        [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
    OWSAssert(contactThread);
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
- (void)clearIdentityState
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSMutableArray<NSString *> *identityKeysToRemove = [NSMutableArray new];
        [transaction enumerateKeysInCollection:TSStorageManagerIdentityKeyStoreCollection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        if ([key isEqualToString:TSStorageManagerIdentityKeyStoreIdentityKey]) {
                                            // Don't delete our own key.
                                            return;
                                        }
                                        [identityKeysToRemove addObject:key];
                                    }];
        for (NSString *key in identityKeysToRemove) {
            [transaction removeObjectForKey:key inCollection:TSStorageManagerIdentityKeyStoreCollection];
        }
        [transaction removeAllObjectsInCollection:TSStorageManagerTrustedKeysCollection];
    }];
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

- (void)snapshotIdentityState
{
    [self.dbConnection snapshotCollection:TSStorageManagerIdentityKeyStoreCollection
                         snapshotFilePath:self.identityKeySnapshotFilePath];
    [self.dbConnection snapshotCollection:TSStorageManagerTrustedKeysCollection
                         snapshotFilePath:self.trustedKeySnapshotFilePath];
}

- (void)restoreIdentityState
{
    [self.dbConnection restoreSnapshotOfCollection:TSStorageManagerIdentityKeyStoreCollection
                                  snapshotFilePath:self.identityKeySnapshotFilePath];
    [self.dbConnection restoreSnapshotOfCollection:TSStorageManagerTrustedKeysCollection
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
