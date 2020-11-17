//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Chain.h"
#import <Curve25519Kit/Curve25519.h>

@interface ReceivingChain : NSObject <Chain, NSSecureCoding>

- (instancetype)initWithChainKey:(ChainKey*)chainKey senderRatchetKey:(NSData*)senderRatchet;

@property NSMutableArray *messageKeysList;
@property NSData *senderRatchetKey;

@end
