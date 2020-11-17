//
//  ReceivingChain.m
//  AxolotlKit
//
//  Created by Frederic Jacobs on 02/09/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import "ReceivingChain.h"
#import <SignalCoreKit/OWSAsserts.h>

@interface ReceivingChain ()

@property (nonatomic)ChainKey *chainKey;

@end

@implementation ReceivingChain

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

- (instancetype)initWithChainKey:(ChainKey *)chainKey senderRatchetKey:(NSData *)senderRatchet{
    OWSAssert(chainKey);
    OWSAssert(senderRatchet);

    self = [super init];

    self.chainKey         = chainKey;
    self.senderRatchetKey = senderRatchet;
    self.messageKeysList  = [NSMutableArray array];

    return self;
}

@end
