//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "LegacyReceivingChain.h"

@interface LegacyReceivingChain ()

@property (nonatomic)LegacyChainKey *chainKey;

@end

@implementation LegacyReceivingChain

static NSString* const kCoderChainKey      = @"kCoderChainKey";
static NSString* const kCoderSenderRatchet = @"kCoderSenderRatchet";
static NSString* const kCoderMessageKeys   = @"kCoderMessageKeys";

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self initWithChainKey:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderChainKey]
                 senderRatchetKey:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderSenderRatchet]];
    if (self) {
        self.messageKeysList = [aDecoder decodeObjectOfClass:[NSMutableArray class] forKey:kCoderMessageKeys];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.chainKey forKey:kCoderChainKey];
    [aCoder encodeObject:self.senderRatchetKey forKey:kCoderSenderRatchet];
    [aCoder encodeObject:self.messageKeysList forKey:kCoderMessageKeys];
}

- (instancetype)initWithChainKey:(LegacyChainKey *)chainKey senderRatchetKey:(NSData *)senderRatchet{
    OWSAssert(chainKey);
    OWSAssert(senderRatchet);

    self = [super init];

    self.chainKey         = chainKey;
    self.senderRatchetKey = senderRatchet;
    self.messageKeysList  = [NSMutableArray array];

    return self;
}

@end
