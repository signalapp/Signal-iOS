//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <Foundation/Foundation.h>
#import <SignalServiceKit/Chain.h>

@interface ReceivingChain : NSObject <Chain, NSSecureCoding>

- (instancetype)initWithChainKey:(ChainKey*)chainKey senderRatchetKey:(NSData*)senderRatchet;

@property NSMutableArray *messageKeysList;
@property NSData *senderRatchetKey;

@end
