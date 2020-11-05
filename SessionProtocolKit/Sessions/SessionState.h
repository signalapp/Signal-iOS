//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ECKeyPair;
#import "RKCK.h"
#import "MessageKeys.h"
#import "Chain.h"
#import "RootKey.h"

/**
 *  Pending PreKeys
 */

@interface PendingPreKey : NSObject <NSSecureCoding>

@property (readonly) int preKeyId;
@property (readonly) int signedPreKeyId;
@property (readonly) NSData *baseKey;

-(instancetype)initWithBaseKey:(NSData*)baseKey preKeyId:(int)preKeyId signedPreKeyId:(int)signedPrekeyId;

@end

@interface SessionState : NSObject <NSSecureCoding>

/**
 *  AxolotlSessions are either retreived from the database or initiated on new discussions. They are serialized before being stored to make storing abstractions significantly simpler. Because we propose no abstraction for a contact and TextSecure has multi-device (multiple sessions with same identity key) support, the identityKeys need to be added manually.
 */

@property(nonatomic) int  version;
@property(nonatomic, copy) NSData *aliceBaseKey;
@property(nonatomic) NSData *remoteIdentityKey;
@property(nonatomic) NSData *localIdentityKey;
@property(nonatomic) int previousCounter;
@property(nonatomic) RootKey *rootKey;

@property(nonatomic)int remoteRegistrationId;
@property(nonatomic)int localRegistrationId;

- (NSData*)senderRatchetKey;
- (ECKeyPair*)senderRatchetKeyPair;

- (BOOL)hasReceiverChain:(NSData *)senderEphemeral;
- (BOOL)hasSenderChain;

- (ChainKey *)receiverChainKey:(NSData *)senderEphemeral;

- (void)setReceiverChainKey:(NSData*)senderEphemeral chainKey:(ChainKey*)chainKey;

- (void)addReceiverChain:(NSData*)senderRatchetKey chainKey:(ChainKey*)chainKey;

- (void)setSenderChain:(ECKeyPair*)senderRatcherKeyPair chainKey:(ChainKey*)chainKey;

- (ChainKey*)senderChainKey;

- (void)setSenderChainKey:(ChainKey*)nextChainKey;

- (BOOL)hasMessageKeys:(NSData*)senderRatchetKey counter:(int)counter;

- (MessageKeys*)removeMessageKeys:(NSData*)senderRatcherKey counter:(int)counter;

- (void)setMessageKeys:(NSData*)senderRatchetKey messageKeys:(MessageKeys*)messageKeys;

- (void)setUnacknowledgedPreKeyMessage:(int)preKeyId signedPreKey:(int)signedPreKeyId baseKey:(NSData*)baseKey;
- (BOOL)hasUnacknowledgedPreKeyMessage;
- (PendingPreKey*)unacknowledgedPreKeyMessageItems;
- (void)clearUnacknowledgedPreKeyMessage;

@end
