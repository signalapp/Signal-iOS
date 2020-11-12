//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Chain.h"

#import <Curve25519Kit/Curve25519.h>

@interface SendingChain : NSObject <Chain, NSSecureCoding>

-(instancetype)initWithChainKey:(ChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;

@end
