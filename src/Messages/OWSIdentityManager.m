//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "NotificationsProtocol.h"
#import "OWSMessageSender.h"
#import "OWSRecipientIdentity.h"
#import "TextSecureKitEnv.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSStorageManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
NSString *const TSStorageManagerIdentityKeyStoreIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
NSString *const TSStorageManagerIdentityKeyStoreCollection = @"TSStorageManagerIdentityKeyStoreCollection";

// Storing recipients identity keys
NSString *const TSStorageManagerTrustedKeysCollection = @"TSStorageManagerTrustedKeysCollection";

// Don't trust an identity for sending to unless they've been around for at least this long
const NSTimeInterval kIdentityKeyStoreNonBlockingSecondsThreshold = 5.0;

NSString *const kNSNotificationName_IdentityStateDidChange = @"kNSNotificationName_IdentityStateDidChange";

@interface OWSIdentityManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
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
    _messageSender = messageSender;

    OWSSingletonAssert();

    return self;
}


- (void)generateNewIdentityKey
{
    [self.storageManager setObject:[Curve25519 generateKeyPair]
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
    return [self.storageManager keyPairForKey:TSStorageManagerIdentityKeyStoreIdentityKey
                                 inCollection:TSStorageManagerIdentityKeyStoreCollection];
}

- (int)localRegistrationId
{
    return (int)[TSAccountManager getOrGenerateRegistrationId];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId
{
    OWSAssert(identityKey != nil);
    OWSAssert(recipientId != nil);

    @synchronized(self)
    {
        // Deprecated. We actually no longer use the TSStorageManagerTrustedKeysCollection for trust
        // decisions, but it's desirable to try to keep it up to date with our trusted identitys
        // while we're switching between versions, e.g. so we don't get into a state where we have a
        // session for an identity not in our key store.
        [self.storageManager setObject:identityKey
                                forKey:recipientId
                          inCollection:TSStorageManagerTrustedKeysCollection];

        OWSRecipientIdentity *existingIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (existingIdentity == nil) {
            DDLogInfo(@"%@ saving first use identity for recipient: %@", self.tag, recipientId);
            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:YES
                                                     createdAt:[NSDate new]
                                             verificationState:OWSVerificationStateDefault] save];

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

            [self fireIdentityStateChangeNotification];

            return YES;
        }

        DDLogDebug(@"%@ no changes for identity saved for recipient: %@", self.tag, recipientId);
        return NO;
    }
}

- (void)setVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
             sendSyncMessage:(BOOL)sendSyncMessage
{
    OWSAssert(identityKey.length > 0);
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        // Ensure a remote identity exists for this key. We may be learning about
        // it for the first time.
        [self saveRemoteIdentity:identityKey recipientId:recipientId];

        OWSRecipientIdentity *identity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (identity == nil) {
            OWSFail(@"Missing expected identity: %@", recipientId);
            return;
        }

        if (identity.verificationState == verificationState) {
            return;
        }

        DDLogInfo(@"%@ setVerificationState: %@ (%@ -> %@)",
            self.tag,
            recipientId,
            OWSVerificationStateToString(identity.verificationState),
            OWSVerificationStateToString(verificationState));

        [identity updateWithVerificationState:verificationState];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_IdentityStateDidChange
                                                            object:nil
                                                          userInfo:nil];
    });
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
                   direction:(TSMessageDirection)direction
{
    OWSAssert(identityKey != nil);
    OWSAssert(recipientId != nil);
    OWSAssert(direction != TSMessageDirectionUnknown);

    @synchronized(self)
    {
        if ([[self.storageManager localNumber] isEqualToString:recipientId]) {
            if ([[self identityKeyPair].publicKey isEqualToData:identityKey]) {
                return YES;
            } else {
                DDLogError(@"%@ Wrong identity: %@ for local key: %@",
                    self.tag,
                    identityKey,
                    [self identityKeyPair].publicKey);
                OWSAssert(NO);
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
                DDLogError(@"%@ unexpected message direction: %ld", self.tag, (long)direction);
                OWSAssert(NO);
                return NO;
            }
        }
    }
}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(identityKey.length == 32);

    @synchronized(self)
    {
        if (recipientIdentity == nil) {
            DDLogDebug(@"%@ Trusting previously unknown recipient: %@", self.tag, recipientIdentity.recipientId);
            return YES;
        }

        OWSAssert(recipientIdentity.identityKey.length == 32);
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            DDLogWarn(@"%@ key mismatch for recipient: %@", self.tag, recipientIdentity.recipientId);
            return NO;
        }

        switch (recipientIdentity.verificationState) {
            case OWSVerificationStateDefault: {
                BOOL isNew = (fabs([recipientIdentity.createdAt timeIntervalSinceNow])
                    < kIdentityKeyStoreNonBlockingSecondsThreshold);
                if (isNew) {
                    DDLogWarn(@"%@ not trusting new identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                    return NO;
                } else {
                    DDLogWarn(@"%@ trusting existing identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                    return YES;
                }
            }
            case OWSVerificationStateVerified:
                DDLogWarn(@"%@ trusting verified identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                return YES;
            case OWSVerificationStateNoLongerVerified:
                DDLogWarn(@"%@ not trusting no longer verified identity for recipient: %@", self.tag, recipientIdentity.recipientId);
                return NO;
        }
    }
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId != nil);

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    OWSAssert(contactThread != nil);

    TSErrorMessage *errorMessage =
        [TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId];
    [errorMessage save];

    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:contactThread];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId]) {
        [[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId] save];
    }
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
