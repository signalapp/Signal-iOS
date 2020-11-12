//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RKCK.h"
#import <Curve25519Kit/Curve25519.h>
#import "TSDerivedSecrets.h"
#import <SignalCoreKit/OWSAsserts.h>

@implementation RKCK

- (instancetype)initWithRK:(RootKey*)rootKey CK:(ChainKey*)chainKey{
    OWSAssert(rootKey);
    OWSAssert(chainKey);

    self = [super init];
    self.rootKey = rootKey;
    self.chainKey   = chainKey;
    return self;
}

@end
