//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "SendingChain.h"
#import "ChainKey.h"

@interface SendingChain ()

@property (nonatomic)ChainKey *chainKey;

@end

@implementation SendingChain

static NSString* const kCoderChainKey      = @"kCoderChainKey";
static NSString* const kCoderSenderRatchet = @"kCoderSenderRatchet";

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self initWithChainKey:[aDecoder decodeObjectOfClass:[ChainKey class] forKey:kCoderChainKey]
             senderRatchetKeyPair:[aDecoder decodeObjectOfClass:[ECKeyPair class] forKey:kCoderSenderRatchet]];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.chainKey forKey:kCoderChainKey];
    [aCoder encodeObject:self.senderRatchetKeyPair forKey:kCoderSenderRatchet];
}

- (instancetype)initWithChainKey:(ChainKey *)chainKey senderRatchetKeyPair:(ECKeyPair *)keyPair{
    self = [super init];

    OWSAssert(chainKey.key.length == 32);
    OWSAssert(keyPair);

    if (self) {
        _chainKey             = chainKey;
        _senderRatchetKeyPair = keyPair;
    }

    return self;
}

-(ChainKey *)chainKey{
    return _chainKey;
}

@end
