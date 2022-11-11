//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "LegacyMessageKeys.h"

static NSString* const kCoderMessageKeysCipherKey = @"kCoderMessageKeysCipherKey";
static NSString* const kCoderMessageKeysMacKey    = @"kCoderMessageKeysMacKey";
static NSString* const kCoderMessageKeysIVKey     = @"kCoderMessageKeysIVKey";
static NSString* const kCoderMessageKeysIndex     = @"kCoderMessageKeysIndex";


@implementation LegacyMessageKeys

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self initWithCipherKey:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderMessageKeysCipherKey]
                            macKey:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderMessageKeysMacKey]
                                iv:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderMessageKeysIVKey]
                             index:[aDecoder decodeIntForKey:kCoderMessageKeysIndex]];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.cipherKey forKey:kCoderMessageKeysCipherKey];
    [aCoder encodeObject:self.macKey forKey:kCoderMessageKeysMacKey];
    [aCoder encodeObject:self.iv forKey:kCoderMessageKeysIVKey];
    [aCoder encodeInt:self.index forKey:kCoderMessageKeysIndex];
}


- (instancetype)initWithCipherKey:(NSData*)cipherKey macKey:(NSData*)macKey iv:(NSData *)data index:(int)index{

    OWSAssert(cipherKey);
    OWSAssert(macKey);
    OWSAssert(data);

    self = [super init];
    
    if (self) {
        _cipherKey = cipherKey;
        _macKey    = macKey;
        _iv        = data;
        _index     = index;
    }

    return self;
}

-(NSString*) debugDescription {
    return [NSString stringWithFormat:@"cipherKey: %@\n macKey %@\n",self.cipherKey,self.macKey];
}

@end
