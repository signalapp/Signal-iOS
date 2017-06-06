//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIdentityManager.h"
#import "OWSMessageSender.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

// TODO: Review
#import "NSDate+millisecondTimeStamp.h"
#import "NotificationsProtocol.h"
#import "OWSIdentityManager.h"
#import "OWSRecipientIdentity.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSPreferences.h"
#import "TSStorageManager+SessionStore.h"
#import "TextSecureKitEnv.h"
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

// NSString *const kOWSIdentityManager_Collection = @"kOWSIdentityManager_Collection";
//// This key is used to persist the current "verification map" state.
// NSString *const kOWSIdentityManager_VerificationMapKey = @"kOWSIdentityManager_VerificationMapKey";

@interface OWSIdentityManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

//// We don't store the phone numbers as instances of PhoneNumber to avoid
//// consistency issues between clients, but these should all be valid e164
//// phone numbers.
//@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *verificationMap;

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

//- (OWSVerificationState)verificationStateForPhoneNumber:(NSString *)phoneNumber
//{
//    OWSAssert(phoneNumber.length > 0);
//
//    @synchronized(self)
//    {
//        [self lazyLoadStateIfNecessary];
//        OWSAssert(self.verificationMap);
//
//        NSNumber * _Nullable existingValue = self.verificationMap[phoneNumber];
//
//        return (existingValue
//                ? (OWSVerificationState) existingValue.intValue
//                : OWSVerificationStateDefault);
//    }
//}
//
//- (void)handleUpdate:(NSDictionary<NSString *, NSNumber *> *)verificationMap
//            sendSyncMessage:(BOOL)sendSyncMessage
//{
//    OWSAssert(verificationMap);
//
//    [_storageManager setObject:verificationMap
//                        forKey:kOWSIdentityManager_VerificationMapKey
//                  inCollection:kOWSIdentityManager_Collection];
//
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_VerificationStateDidChange
//                                                            object:nil
//                                                          userInfo:nil];
//    });
//}
//
//// This method should only be called from within a synchronized block.
//- (void)lazyLoadStateIfNecessary
//{
//    if (self.verificationMap) {
//        // verificationMap has already been loaded, abort.
//        return;
//    }
//
//    NSDictionary<NSString *, NSNumber *> *verificationMap =
//        [_storageManager objectForKey:kOWSIdentityManager_VerificationMapKey
//                         inCollection:kOWSIdentityManager_Collection];
//    _verificationMap = (verificationMap ? [verificationMap mutableCopy] : [NSMutableDictionary new]);
//}

- (BOOL)isCurrentIdentityTrustedForSendingWithRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    @synchronized(self)
    {
        OWSRecipientIdentity *currentIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
        return [self isTrustedIdentityKey:currentIdentity.identityKey
                              recipientId:recipientId
                                direction:TSMessageDirectionOutgoing];
    }
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

    //    NSDictionary<NSString *, NSNumber *> *verificationMapCopy = nil;

    @synchronized(self)
    {

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
        if ([[[self class] localNumber] isEqualToString:recipientId]) {
            if ([[self identityKeyPair].publicKey isEqualToData:identityKey]) {
                return YES;
            } else {
                DDLogError(@"%s Wrong identity: %@ for local key: %@",
                    __PRETTY_FUNCTION__,
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
                DDLogError(@"%s unexpected message direction: %ld", __PRETTY_FUNCTION__, (long)direction);
                OWSAssert(NO);
                return NO;
            }
        }
    }
}

// TODO: Cull unused methods within this class.

//- (nullable OWSRecipientIdentity *)unconfirmedIdentityThatShouldBlockSendingForRecipientId:(NSString *)recipientId;
//{
//    OWSAssert(recipientId != nil);
//
//    @synchronized(self)
//    {
//        OWSRecipientIdentity *currentIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
//        if (currentIdentity == nil) {
//            // No preexisting key, Trust On First Use
//            return nil;
//        }
//
//        if ([self isTrustedIdentityKey:currentIdentity.identityKey
//                           recipientId:currentIdentity.recipientId
//                             direction:TSMessageDirectionOutgoing]) {
//            return nil;
//        }
//
//        // identity not yet trusted for sending
//        return currentIdentity;
//    }
//}

//- (nullable OWSRecipientIdentity *)unseenIdentityChangeForRecipientId:(NSString *)recipientId
//{
//    OWSAssert(recipientId != nil);
//
//    @synchronized(self)
//    {
//        OWSRecipientIdentity *currentIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];
//        if (currentIdentity == nil) {
//            // No preexisting key, Trust On First Use
//            return nil;
//        }
//
//        if (currentIdentity.isFirstKnownKey) {
//            return nil;
//        }
//
//        if (currentIdentity.wasSeen) {
//            return nil;
//        }
//
//        // identity not yet seen
//        return currentIdentity;
//    }
//}

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(identityKey != nil);

    @synchronized(self)
    {
        if (recipientIdentity == nil) {
            DDLogDebug(
                @"%s Trusting on first use for recipient: %@", __PRETTY_FUNCTION__, recipientIdentity.recipientId);
            return YES;
        }

        OWSAssert(recipientIdentity.identityKey != nil);
        if (![recipientIdentity.identityKey isEqualToData:identityKey]) {
            DDLogWarn(@"%s key mismatch for recipient: %@", __PRETTY_FUNCTION__, recipientIdentity.recipientId);
            return NO;
        }

        switch (recipientIdentity.verificationState) {
            case OWSVerificationStateDefault: {
                BOOL isNew = (fabs([recipientIdentity.createdAt timeIntervalSinceNow])
                    < kIdentityKeyStoreNonBlockingSecondsThreshold);
                if (isNew) {
                    DDLogWarn(@"%s not trusting new identity for recipient: %@",
                        __PRETTY_FUNCTION__,
                        recipientIdentity.recipientId);
                    return NO;
                } else {
                    DDLogWarn(@"%s trusting existing identity for recipient: %@",
                        __PRETTY_FUNCTION__,
                        recipientIdentity.recipientId);
                    return YES;
                }
            }
            case OWSVerificationStateVerified:
                DDLogWarn(@"%s trusting verified identity for recipient: %@",
                    __PRETTY_FUNCTION__,
                    recipientIdentity.recipientId);
                return YES;
            case OWSVerificationStateNoLongerVerified:
                DDLogWarn(@"%s not trusting no longer verified identity for recipient: %@",
                    __PRETTY_FUNCTION__,
                    recipientIdentity.recipientId);
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
