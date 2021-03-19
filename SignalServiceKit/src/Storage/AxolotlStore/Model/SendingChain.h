//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/Chain.h>

@interface SendingChain : NSObject <Chain, NSSecureCoding>

-(instancetype)initWithChainKey:(ChainKey*)chainKey senderRatchetKeyPair:(ECKeyPair*)keyPair;

@property ECKeyPair *senderRatchetKeyPair;

@end
