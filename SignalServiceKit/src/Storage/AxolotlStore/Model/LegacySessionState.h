//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

@class ECKeyPair;
@class LegacyChainKey;
@class LegacyReceivingChain;

#import <SignalServiceKit/LegacyMessageKeys.h>
#import <SignalServiceKit/LegacyRootKey.h>

/**
 *  Pending PreKeys
 */

@interface LegacyPendingPreKey : NSObject <NSSecureCoding>

@property (readonly) int preKeyId;
@property (readonly) int signedPreKeyId;
@property (readonly) NSData *baseKey;

-(instancetype)initWithBaseKey:(NSData*)baseKey preKeyId:(int)preKeyId signedPreKeyId:(int)signedPrekeyId;

@end

@interface LegacySessionState : NSObject <NSSecureCoding>

/**
 *  AxolotlSessions are either retrieved from the database or initiated on new discussions. They are serialized before being stored to make storing abstractions significantly simpler. Because we propose no abstraction for a contact and TextSecure has multi-device (multiple sessions with same identity key) support, the identityKeys need to be added manually.
 */

@property(nonatomic) int  version;
@property(nonatomic, copy) NSData *aliceBaseKey;
@property(nonatomic) NSData *remoteIdentityKey;
@property(nonatomic) NSData *localIdentityKey;
@property(nonatomic) int previousCounter;
@property(nonatomic) LegacyRootKey *rootKey;

@property(nonatomic) NSArray<LegacyReceivingChain *> *receivingChains;

@property(nonatomic)int remoteRegistrationId;
@property(nonatomic)int localRegistrationId;

@property (nonatomic, readonly) BOOL isFresh;

- (NSData*)senderRatchetKey;
- (ECKeyPair*)senderRatchetKeyPair;

- (void)setSenderChain:(ECKeyPair*)senderRatcherKeyPair chainKey:(LegacyChainKey*)chainKey;

- (LegacyChainKey*)senderChainKey;

- (void)setUnacknowledgedPreKeyMessage:(int)preKeyId signedPreKey:(int)signedPreKeyId baseKey:(NSData*)baseKey;
- (LegacyPendingPreKey*)unacknowledgedPreKeyMessageItems;

@end
