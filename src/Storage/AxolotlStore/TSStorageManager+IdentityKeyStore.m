//
//  TSStorageManager+IdentityKeyStore.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "TSStorageManager+IdentityKeyStore.h"

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
    [self setObject:identityKey forKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];
}

- (BOOL)isTrustedIdentityKey:(NSData *)identityKey recipientId:(NSString *)recipientId {
    NSData *trusted = [self dataForKey:recipientId inCollection:TSStorageManagerTrustedKeysCollection];

    return (trusted == nil || [trusted isEqualToData:identityKey]);
}

- (void)removeIdentityKeyForRecipient:(NSString *)receipientId {
    [self removeObjectForKey:receipientId inCollection:TSStorageManagerTrustedKeysCollection];
}

@end
