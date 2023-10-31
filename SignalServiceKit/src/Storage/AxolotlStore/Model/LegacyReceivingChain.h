//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

@class LegacyChainKey;

@interface LegacyReceivingChain : NSObject <NSSecureCoding>

- (instancetype)initWithChainKey:(LegacyChainKey*)chainKey senderRatchetKey:(NSData*)senderRatchet;

@property NSMutableArray *messageKeysList;
@property NSData *senderRatchetKey;
@property(readonly,nonatomic) LegacyChainKey *chainKey;

@end
