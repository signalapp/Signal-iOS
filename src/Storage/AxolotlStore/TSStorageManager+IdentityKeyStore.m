//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSPrivacyPreferences.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+SessionStore.h"
#import <25519/Curve25519.h>

#define TSStorageManagerIdentityKeyStoreIdentityKey \
    @"TSStorageManagerIdentityKeyStoreIdentityKey" // Key for our identity key
#define TSStorageManagerIdentityKeyStoreCollection @"TSStorageManagerIdentityKeyStoreCollection"
#define TSStorageManagerTrustedKeysCollection @"TSStorageManagerTrustedKeysCollection"


@implementation TSStorageManager (IdentityKeyStore)

- (void)generateNewIdentityKey {
    [self setObject:[Curve25519 generateKeyPair]
              forKey:TSStorageManagerIdentityKeyStoreIdentityKey
        inCollection:TSStorageManagerIdentityKeyStoreCollection];
}


- (NSData *)identityKeyForRecipientId:(NSString *)recipientId {
    return [self dataForKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];
}


- (ECKeyPair *)identityKeyPair {
    return [self keyPairForKey:TSStorageManagerIdentityKeyStoreIdentityKey
                  inCollection:TSStorageManagerIdentityKeyStoreCollection];
}

- (int)localRegistrationId {
    return (int)[TSAccountManager getOrGenerateRegistrationId];
}

- (void)saveRemoteIdentity:(NSData *)identityKey recipientId:(NSString *)recipientId {
    NSData *existingKey = [self identityKeyForRecipientId:recipientId];
    if ([existingKey isEqual:identityKey]) {
        // Since we need to clear existing sessions when identity changes, we have to exit early
        // when the identity key hasn't changed, lest we blow away valid sessions.
        DDLogDebug(@"%s no-op since identity hasn't changed for recipient: %@", __PRETTY_FUNCTION__, recipientId);
        return;
    }

    DDLogInfo(@"%s invalidating any pre-existing sessions for recipientId: %@", __PRETTY_FUNCTION__, recipientId);
    [self deleteAllSessionsForContact:recipientId];

    DDLogInfo(@"%s saving new identity key for recipientId: %@", __PRETTY_FUNCTION__, recipientId);
    [self setObject:identityKey forKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey recipientId:(NSString *)recipientId {
    NSData *existingKey = [self identityKeyForRecipientId:recipientId];

    if (!existingKey) {
        return YES;
    }

    if ([existingKey isEqualToData:identityKey]) {
        return YES;
    }

    if (self.privacyPreferences.shouldBlockOnIdentityChange) {
        return NO;
    }

    DDLogInfo(@"Updating identity key for recipient:%@", recipientId);
    [self createIdentityChangeInfoMessageForRecipientId:recipientId];
    [self saveRemoteIdentity:identityKey recipientId:recipientId];
    return YES;
}

- (void)removeIdentityKeyForRecipient:(NSString *)receipientId {
    [self removeObjectForKey:receipientId inCollection:TSStorageManagerTrustedKeysCollection];
}

- (void)createIdentityChangeInfoMessageForRecipientId:(NSString *)recipientId
{
    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    [[TSErrorMessage nonblockingIdentityChangeInThread:contactThread recipientId:recipientId] save];

    for (TSGroupThread *groupThread in [TSGroupThread groupThreadsWithRecipientId:recipientId]) {
        [[TSErrorMessage nonblockingIdentityChangeInThread:groupThread recipientId:recipientId] save];
    }
}

@end
