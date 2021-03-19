//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "RKCK.h"
#import <Curve25519Kit/Curve25519.h>

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
