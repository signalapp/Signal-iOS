//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>

@class LegacyChainKey;

@interface LegacySendingChain : NSObject <NSSecureCoding>

-(instancetype)initWithChainKey:(LegacyChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;
@property(readonly,nonatomic) LegacyChainKey *chainKey;

@end
