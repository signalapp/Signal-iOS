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

// NSString *const kNSNotificationName_VerificationStateDidChange = @"kNSNotificationName_VerificationStateDidChange";
//
// NSString *const kOWSIdentityManager_Collection = @"kOWSIdentityManager_Collection";
//// This key is used to persist the current "verification map" state.
// NSString *const kOWSIdentityManager_VerificationMapKey = @"kOWSIdentityManager_VerificationMapKey";

NSString *OWSVerificationStateToString(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return @"OWSVerificationStateDefault";
        case OWSVerificationStateVerified:
            return @"OWSVerificationStateVerified";
        case OWSVerificationStateNoLongerVerified:
            return @"OWSVerificationStateNoLongerVerified";
    }
}

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

//- (void)setVerificationState:(OWSVerificationState)verificationState
//              forPhoneNumber:(NSString *)phoneNumber
//       isUserInitiatedChange:(BOOL)isUserInitiatedChange
//{
//    OWSAssert(phoneNumber.length > 0);
//
//    DDLogInfo(@"%@ setVerificationState: %@ forPhoneNumber: %@", self.tag,
//    OWSVerificationStateToString(verificationState), phoneNumber);
//
//    NSDictionary<NSString *, NSNumber *> *verificationMapCopy = nil;
//
//    @synchronized(self)
//    {
//        [self lazyLoadStateIfNecessary];
//        OWSAssert(self.verificationMap);
//
//        NSNumber * _Nullable existingValue = self.verificationMap[phoneNumber];
//        if (existingValue && existingValue.intValue == (int) verificationState) {
//            // Ignore redundant changes.
//            return;
//        }
//
//        self.verificationMap[phoneNumber] = @(verificationState);
//
//        verificationMapCopy = [self.verificationMap copy];
//    }
//
//    [self handleUpdate:verificationMapCopy
//       sendSyncMessage:isUserInitiatedChange];
//}
//
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


//@implementation TSStorageManager (IdentityKeyStore)

//+ (id)sharedIdentityKeyLock
//{
//    static id identityKeyLock;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        identityKeyLock = [NSObject new];
//    });
//    return identityKeyLock;
//}

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

        // If send-blocking is disabled at the time the identity was saved, we want to consider the identity as
        // approved for blocking. Otherwise the user will see inexplicable failures when trying to send to this
        // identity, if they later enabled send-blocking.
        BOOL approvedForBlockingUse = ![TextSecureKitEnv sharedEnv].preferences.isSendingIdentityApprovalRequired;
        return [self saveRemoteIdentity:identityKey
                            recipientId:recipientId
                 approvedForBlockingUse:approvedForBlockingUse
              approvedForNonBlockingUse:NO];
    }
}

// TODO: Stuff
- (BOOL)saveRemoteIdentity:(NSData *)identityKey
                  recipientId:(NSString *)recipientId
       approvedForBlockingUse:(BOOL)approvedForBlockingUse
    approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse
{
    OWSAssert(identityKey != nil);
    OWSAssert(recipientId != nil);

    NSString const *logTag = @"[IdentityKeyStore]";
    @synchronized(self)
    {
        OWSRecipientIdentity *existingIdentity = [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId];

        if (existingIdentity == nil) {
            DDLogInfo(@"%@ saving first use identity for recipient: %@", logTag, recipientId);
            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:YES
                                                     createdAt:[NSDate new]
                                        approvedForBlockingUse:approvedForBlockingUse
                                     approvedForNonBlockingUse:approvedForNonBlockingUse] save];
            return NO;
        }

        if (![existingIdentity.identityKey isEqual:identityKey]) {
            DDLogInfo(@"%@ replacing identity for existing recipient: %@", logTag, recipientId);
            [self createIdentityChangeInfoMessageForRecipientId:recipientId];
            [[[OWSRecipientIdentity alloc] initWithRecipientId:recipientId
                                                   identityKey:identityKey
                                               isFirstKnownKey:NO
                                                     createdAt:[NSDate new]
                                        approvedForBlockingUse:approvedForBlockingUse
                                     approvedForNonBlockingUse:approvedForNonBlockingUse] save];

            return YES;
        }

        if ([self isBlockingApprovalRequiredForIdentity:existingIdentity] ||
            [self isNonBlockingApprovalRequiredForIdentity:existingIdentity]) {
            [existingIdentity updateWithApprovedForBlockingUse:approvedForBlockingUse
                                     approvedForNonBlockingUse:approvedForNonBlockingUse];
            return NO;
        }

        DDLogDebug(@"%@ no changes for identity saved for recipient: %@", logTag, recipientId);
        return NO;
    }
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

        if ([self isBlockingApprovalRequiredForIdentity:recipientIdentity]) {
            DDLogWarn(@"%s not trusting until blocking approval is granted. recipient: %@",
                __PRETTY_FUNCTION__,
                recipientIdentity.recipientId);
            return NO;
        }

        if ([self isNonBlockingApprovalRequiredForIdentity:recipientIdentity]) {
            DDLogWarn(@"%s not trusting until non-blocking approval is granted. recipient: %@",
                __PRETTY_FUNCTION__,
                recipientIdentity.recipientId);
            return NO;
        }

        return YES;
    }
}

- (BOOL)isBlockingApprovalRequiredForIdentity:(OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(recipientIdentity != nil);
    OWSAssert([TextSecureKitEnv sharedEnv].preferences != nil);

    return !recipientIdentity.isFirstKnownKey &&
        [TextSecureKitEnv sharedEnv].preferences.isSendingIdentityApprovalRequired
        && !recipientIdentity.approvedForBlockingUse;
}

- (BOOL)isNonBlockingApprovalRequiredForIdentity:(OWSRecipientIdentity *)recipientIdentity
{
    OWSAssert(recipientIdentity != nil);

    return !recipientIdentity.isFirstKnownKey &&
        [[NSDate new] timeIntervalSinceDate:recipientIdentity.createdAt] < kIdentityKeyStoreNonBlockingSecondsThreshold
        && !recipientIdentity.approvedForNonBlockingUse;
}

//- (void)removeIdentityKeyForRecipient:(NSString *)recipientId
//{
//    OWSAssert(recipientId != nil);
//
//    [[OWSRecipientIdentity fetchObjectWithUniqueID:recipientId] remove];
//}

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
