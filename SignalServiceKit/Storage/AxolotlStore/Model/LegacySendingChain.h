//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

@class ECKeyPair;
@class LegacyChainKey;

@interface LegacySendingChain : NSObject <NSSecureCoding>

-(instancetype)initWithChainKey:(LegacyChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;
@property(readonly,nonatomic) LegacyChainKey *chainKey;

@end
