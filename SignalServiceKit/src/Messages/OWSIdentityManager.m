//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NSNotificationCenter+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSError.h"
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
#import <25519/Curve25519.h>
#import <AxolotlKit/NSData+keyVersionByte.h>

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
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

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

- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
{
    @synchronized(self)
    {
        return [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId].identityKey;
    }
}

- (nullable ECKeyPair *)identityKeyPair
{
    return [self.dbConnection keyPairForKey:TSStorageManagerIdentityKeyStoreIdentityKey
                               inCollection:TSStorageManagerIdentityKeyStoreCollection];
}

- (int)localRegistrationId
{
    return (int)[TSAccountManager getOrGenerateRegistrationId];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        // Deprecated. We actually no longer use the TSStorageManagerTrustedKeysCollection for trust
        // decisions, but it's desirable to try to keep it up to date with our trusted identitys
        // while we're switching between versions, e.g. so we don't get into a state where we have a
        // session for an identity not in our key store.
        [self.dbConnection setObject:identityKey forKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];

        OWSRecipientIdentity *existingIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (existingIdentity == nil) {
            DDLogInfo(@"%@ saving first use identity for recipient: %@", self.tag, recipientId);
            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:YES
                                                     createdAt:[NSDate new]
                                             verificationState:OWSVerificationStateDefault] save];

            // Cancel any pending verification state sync messages for this recipient.
            [self clearSyncMessageForRecipientId:recipientId];

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
                self.tag,
                recipientId,
                OWSVerificationStateToString(existingIdentity.verificationState),
                OWSVerificationStateToString(verificationState));
            [self createIdentityChangeInfoMessageForRecipientId:recipientId];

            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:NO
                                                     createdAt:[NSDate new]
                                             verificationState:verificationState] save];

            dispatch_async([OWSDispatch sessionStoreQueue], ^{
                [self.storageManager archiveAllSessionsForContact:recipientId];
            });

            // Cancel any pending verification state sync messages for this recipient.
            [self clearSyncMessageForRecipientId:recipientId];

            [self fireIdentityStateChangeNotification];

            return YES;
        }

        return NO;
    }
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        // Ensure a remote identity exists for this key. We may be learning about
        // it for the first time.
        [self saveRemoteIdentity:identityKey recipientId:recipientId];

        OWSRecipientIdentity *recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (recipientIdentity == nil) {
            OWSFail(@"Missing expected identity: %@", recipientId);
            return;
        }

        if (recipientIdentity.verificationState == verificationState) {
            return;
        }

        DDLogInfo(@"%@ setVerificationState: %@ (%@ -> %@)",
            self.tag,
            recipientId,
            OWSVerificationStateToString(recipientIdentity.verificationState),
            OWSVerificationStateToString(verificationState));

        [recipientIdentity updateWithVerificationState:verificationState];

        if (isUserInitiatedChange) {
            [self saveChangeMessagesForRecipientId:recipientId verificationState:verificationState isLocalChange:YES];
            [self enqueueSyncMessageForVerificationStateForRecipientId:recipientId];
        } else {
            // Cancel any pending verification state sync messages for this recipient.
            [self clearSyncMessageForRecipientId:recipientId];
        }
    }

    [self fireIdentityStateChangeNotification];
}

- (OWSVerificationState)verificationStateForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        OWSRecipientIdentity *_Nullable currentIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (!currentIdentity) {
            // We might not know the identity for this recipient yet.
            return OWSVerificationStateDefault;
        }

        return currentIdentity.verificationState;
    }
}

- (nullable OWSRecipientIdentity *)recipientIdentityForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        return [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
    }
}

- (nullable OWSRecipientIdentity *)untrustedIdentityForSendingToRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        OWSRecipientIdentity *_Nullable recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (recipientIdentity == nil) {
            // trust on first use
            return nil;
        }

        BOOL isTrusted = [self isTrustedIdentityKey:recipientIdentity.identityKey
                                        recipientId:recipientId
                                          direction:TSMessageDirectionOutgoing];
        if (isTrusted) {
            return nil;
        } else {
            return recipientIdentity;
        }
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
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);
    OWSAssert(recipientId.length > 0);
    OWSAssert(direction != TSMessageDirectionUnknown);

    @synchronized(self)
    {
        if ([[TSAccountManager localNumber] isEqualToString:recipientId]) {
            if ([[self identityKeyPair].publicKey isEqualToData:identityKey]) {
                return YES;
            } else {
                OWSFail(@"%@ Wrong identity: %@ for local key: %@, recipientId: %@",
                    self.tag,
                    identityKey,
                    [self identityKeyPair].publicKey,
                    recipientId);
                return NO;
            }
        }

        switch (direction) {
            case TSMessageDirectionIncoming: {
                return YES;
            }
            case TSMessageDirectionOutgoing: {
                OWSRecipientIdentity *existingIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
                return [self isTrustedKey:identityKey forSendingToIdentity:existingIdentity];
            }
            default: {
                OWSFail(@"%@ unexpected message direction: %ld", self.tag, (long)direction);
                return NO;
            }
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(identityKey.length == kStoredIdentityKeyLength);

    @synchronized(self)
    {
        if (recipientIdentity == nil) {
            return YES;
        }

        OWSAssert(recipientIdentity.identityKey.length == kStoredIdentityKeyLength);
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            DDLogWarn(@"%@ key mismatch for recipient: %@", self.tag, recipientIdentity.recipientId);
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
                    DDLogWarn(@"%@ not trusting new identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                    return NO;
                } else {
                    return YES;
                }
            }
            case OWSVerificationStateVerified:
                return YES;
            case OWSVerificationStateNoLongerVerified:
                DDLogWarn(@"%@ not trusting no longer verified identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                return NO;
        }
    }
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    OWSAssert(contactThread != nil);

    TSErrorMessage *errorMessage =
        [TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId];
    [messages addObject:errorMessage];
    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:contactThread];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId]) {
        [messages addObject:[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId]];
    }

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (TSMessage *message in messages) {
            [message saveWithTransaction:transaction];
        }
    }];
}

- (void)enqueueSyncMessageForVerificationStateForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            [self.dbConnection setObject:recipientId
                                  forKey:recipientId
                            inCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self tryToSyncQueuedVerificationStates];
        });
    });
}

- (void)tryToSyncQueuedVerificationStates
{
    OWSAssert([NSThread isMainThread]);

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        // Only try to sync if the app is active to avoid interfering with startup.
        //
        // applicationDidBecomeActive: will try to sync again when the app becomes active.
        return;
    }

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
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (OWSVerificationStateSyncMessage *message in messages) {
                        [self sendSyncVerificationStateMessage:message];
                    }
                });
            }
        }
    });
}

- (void)sendSyncVerificationStateMessage:(OWSVerificationStateSyncMessage *)message
{
    OWSAssert(message);
    OWSAssert(message.verificationForRecipientId.length > 0);
    OWSAssert([NSThread isMainThread]);

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:message.verificationForRecipientId];
    
    // Send null message to appear as though we're sending a normal message to cover the sync messsage sent
    // subsequently
    OWSOutgoingNullMessage *nullMessage = [[OWSOutgoingNullMessage alloc] initWithContactThread:contactThread
                                                                   verificationStateSyncMessage:message];
    [self.messageSender sendMessage:nullMessage
        success:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                DDLogInfo(@"%@ Successfully sent verification state NullMessage", self.tag);
                [self.messageSender sendMessage:message
                    success:^{
                        DDLogInfo(@"%@ Successfully sent verification state sync message", self.tag);

                        // Record that this verification state was successfully synced.
                        [self clearSyncMessageForRecipientId:message.verificationForRecipientId];
                    }
                    failure:^(NSError *error) {
                        DDLogError(
                            @"%@ Failed to send verification state sync message with error: %@", self.tag, error);
                    }];
            });
        }
        failure:^(NSError *_Nonnull error) {
            DDLogError(@"%@ Failed to send verification state NullMessage with error: %@", self.tag, error);
            if (error.code == OWSErrorCodeNoSuchSignalRecipient) {
                DDLogInfo(@"%@ Removing retries for syncing verification state, since user is no longer registered: %@",
                    self.tag,
                    message.verificationForRecipientId);
                // Otherwise this will fail forever.
                [self clearSyncMessageForRecipientId:message.verificationForRecipientId];
            }
        }];
}

- (void)clearSyncMessageForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self)
        {
            [self.dbConnection removeObjectForKey:recipientId
                                     inCollection:OWSIdentityManager_QueuedVerificationStateSyncMessages];
        }
    });
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

    switch (verified.state) {
        case OWSSignalServiceProtosVerifiedStateDefault:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateDefault
                                                 recipientId:recipientId
                                                 identityKey:identityKey
                                         overwriteOnConflict:NO];
            break;
        case OWSSignalServiceProtosVerifiedStateVerified:
            [self tryToApplyVerificationStateFromSyncMessage:OWSVerificationStateVerified
                                                 recipientId:recipientId
                                                 identityKey:identityKey
                                         overwriteOnConflict:YES];
            break;
        case OWSSignalServiceProtosVerifiedStateUnverified:
            OWSFail(@"Verification state sync message for recipientId: %@ has unexpected value: %@.",
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
{
    if (recipientId.length < 1) {
        OWSFail(@"Verification state sync message missing recipientId.");
        return;
    }

    if (identityKey.length != kStoredIdentityKeyLength) {
        OWSFail(@"Verification state sync message missing identityKey: %@", recipientId);
        return;
    }
    
    @synchronized(self)
    {
        OWSRecipientIdentity *_Nullable recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
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
            [self saveRemoteIdentity:identityKey recipientId:recipientId];

            recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

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
                self.tag,
                recipientId,
                OWSVerificationStateToString(recipientIdentity.verificationState),
                OWSVerificationStateToString(verificationState));

            [recipientIdentity updateWithVerificationState:verificationState];

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
                [self saveRemoteIdentity:identityKey recipientId:recipientId];

                recipientIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

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

            [recipientIdentity updateWithVerificationState:verificationState];

            [self saveChangeMessagesForRecipientId:recipientId verificationState:verificationState isLocalChange:NO];
        }
    }
}

// We only want to create change messages in response to user activity,
// on any of their devices.
- (void)saveChangeMessagesForRecipientId:(NSString *)recipientId
                       verificationState:(OWSVerificationState)verificationState
                           isLocalChange:(BOOL)isLocalChange
{
    OWSAssert(recipientId.length > 0);

    NSMutableArray<TSMessage *> *messages = [NSMutableArray new];

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    OWSAssert(contactThread);
    [messages addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                              thread:contactThread
                                                                         recipientId:recipientId
                                                                   verificationState:verificationState
                                                                       isLocalChange:isLocalChange]];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId]) {
        [messages
            addObject:[[OWSVerificationStateChangeMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                            thread:groupThread
                                                                       recipientId:recipientId
                                                                 verificationState:verificationState
                                                                     isLocalChange:isLocalChange]];
    }

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (TSMessage *message in messages) {
            [message saveWithTransaction:transaction];
        }
    }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    // We want to defer this so that we never call this method until
    // [UIApplicationDelegate applicationDidBecomeActive:] is complete.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self tryToSyncQueuedVerificationStates];
    });
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
