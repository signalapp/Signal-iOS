//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>

@class ChainKey;

@interface SendingChain : NSObject <NSSecureCoding>

-(instancetype)initWithChainKey:(ChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;
@property(readonly,nonatomic) ChainKey *chainKey;

@end
