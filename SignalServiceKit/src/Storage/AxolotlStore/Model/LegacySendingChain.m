//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "LegacySendingChain.h"
#import "LegacyChainKey.h"

@interface LegacySendingChain ()

@property (nonatomic)LegacyChainKey *chainKey;

@end

@implementation LegacySendingChain

static NSString* const kCoderChainKey      = @"kCoderChainKey";
static NSString* const kCoderSenderRatchet = @"kCoderSenderRatchet";

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self initWithChainKey:[aDecoder decodeObjectOfClass:[LegacyChainKey class] forKey:kCoderChainKey]
             senderRatchetKeyPair:[aDecoder decodeObjectOfClass:[ECKeyPair class] forKey:kCoderSenderRatchet]];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.chainKey forKey:kCoderChainKey];
    [aCoder encodeObject:self.senderRatchetKeyPair forKey:kCoderSenderRatchet];
}

- (instancetype)initWithChainKey:(LegacyChainKey *)chainKey senderRatchetKeyPair:(ECKeyPair *)keyPair{
    self = [super init];

    OWSAssert(chainKey.key.length == 32);
    OWSAssert(keyPair);

    if (self) {
        _chainKey             = chainKey;
        _senderRatchetKeyPair = keyPair;
    }

    return self;
}

-(LegacyChainKey *)chainKey{
    return _chainKey;
}

@end
