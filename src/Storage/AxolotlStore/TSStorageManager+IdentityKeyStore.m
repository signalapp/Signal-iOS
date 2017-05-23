//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSPreferences.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+SessionStore.h"
#import "TextSecureKitEnv.h"
#import "OWSRecipientIdentity.h"
#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

// Storing our own identity key
NSString *const TSStorageManagerIdentityKeyStoreIdentityKey = @"TSStorageManagerIdentityKeyStoreIdentityKey";
NSString *const TSStorageManagerIdentityKeyStoreCollection = @"TSStorageManagerIdentityKeyStoreCollection";

// Storing recipients identity keys
NSString *const TSStorageManagerTrustedKeysCollection = @"TSStorageManagerTrustedKeysCollection";

// Don't trust an identity for sending to unless they've been around for at least this long
const NSTimeInterval kIdentityKeyStoreNonBlockingSecondsThreshold = 5.0;

@implementation TSStorageManager (IdentityKeyStore)

+ (id)sharedIdentityKeyLock
{
    static id identityKeyLock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identityKeyLock = [NSObject new];
    });
    return identityKeyLock;
}

- (void)generateNewIdentityKey {
    [self setObject:[Curve25519 generateKeyPair]
              forKey:TSStorageManagerIdentityKeyStoreIdentityKey
        inCollection:TSStorageManagerIdentityKeyStoreCollection];
}


- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId
{
    @synchronized([[self class] sharedIdentityKeyLock])
    {
        return [OWSRecipientIdentity fetchObjectWithUniqueID:recipientId].identityKey;
    }
}


- (nullable ECKeyPair *)identityKeyPair
{
    return [self keyPairForKey:TSStorageManagerIdentityKeyStoreIdentityKey
                  inCollection:TSStorageManagerIdentityKeyStoreCollection];
}

- (int)localRegistrationId {
    return (int)[TSAccountManager getOrGenerateRegistrationId];
}

- (BOOL)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId
{
    NSParameterAssert(identityKey != nil);
    NSParameterAssert(recipientId != nil);

    @synchronized([[self class] sharedIdentityKeyLock])
    {
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

- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
    approvedForBlockingUse:(BOOL)approvedForBlockingUse
 approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse
{
    NSParameterAssert(identityKey != nil);
    NSParameterAssert(recipientId != nil);

    NSString const *logTag = @"[IdentityKeyStore]";
    @synchronized ([[self class] sharedIdentityKeyLock]) {
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
        
        if ([self isBlockingApprovalRequiredForIdentity:existingIdentity] || [self isNonBlockingApprovalRequiredForIdentity:existingIdentity]) {
            existingIdentity.approvedForBlockingUse = approvedForBlockingUse;
            existingIdentity.approvedForNonBlockingUse = approvedForNonBlockingUse;
            [existingIdentity save];
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
    NSParameterAssert(identityKey != nil);
    NSParameterAssert(recipientId != nil);
    NSParameterAssert(direction != TSMessageDirectionUnknown);

    @synchronized([[self class] sharedIdentityKeyLock])
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

- (BOOL)isTrustedKey:(NSData *)identityKey forSendingToIdentity:(nullable OWSRecipientIdentity *)recipientIdentity
{
    NSParameterAssert(identityKey != nil);

    @synchronized([[self class] sharedIdentityKeyLock])
    {
        if (recipientIdentity == nil) {
            DDLogDebug(@"%s Trusting on first use for recipient: %@", __PRETTY_FUNCTION__, recipientIdentity.recipientId);
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
    NSParameterAssert(recipientIdentity != nil);
    OWSAssert([TextSecureKitEnv sharedEnv].preferences != nil);

    return !recipientIdentity.isFirstKnownKey &&
        [TextSecureKitEnv sharedEnv].preferences.isSendingIdentityApprovalRequired &&
        !recipientIdentity.approvedForBlockingUse;
}

- (BOOL)isNonBlockingApprovalRequiredForIdentity:(OWSRecipientIdentity *)recipientIdentity
{
    NSParameterAssert(recipientIdentity != nil);

    return !recipientIdentity.isFirstKnownKey &&
        [[NSDate new] timeIntervalSinceDate:recipientIdentity.createdAt] < kIdentityKeyStoreNonBlockingSecondsThreshold &&
        !recipientIdentity.approvedForNonBlockingUse;
}

- (void)removeIdentityKeyForRecipient:(NSString *)recipientId
{
    NSParameterAssert(recipientId != nil);

    [[OWSRecipientIdentity fetchObjectWithUniqueID:recipientId] remove];
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
{
    NSParameterAssert(recipientId != nil);

    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    OWSAssert(contactThread != nil);

    [[TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId] save];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId]) {
        [[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId] save];
    }
}

@end

NS_ASSUME_NONNULL_END
