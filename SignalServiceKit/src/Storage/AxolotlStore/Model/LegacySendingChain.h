//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>

@class LegacyChainKey;

@interface LegacySendingChain : NSObject <NSSecureCoding>

-(instancetype)initWithChainKey:(LegacyChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;
@property(readonly,nonatomic) LegacyChainKey *chainKey;

@end
