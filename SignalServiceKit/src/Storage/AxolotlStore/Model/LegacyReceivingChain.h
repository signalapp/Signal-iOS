//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>

@class LegacyChainKey;

@interface LegacyReceivingChain : NSObject <NSSecureCoding>

- (instancetype)initWithChainKey:(LegacyChainKey*)chainKey senderRatchetKey:(NSData*)senderRatchet;

@property NSMutableArray *messageKeysList;
@property NSData *senderRatchetKey;
@property(readonly,nonatomic) LegacyChainKey *chainKey;

@end
