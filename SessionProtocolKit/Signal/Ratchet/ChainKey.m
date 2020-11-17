//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ChainKey.h"
#import "TSDerivedSecrets.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ChainKey

static NSString *const kCoderKey = @"kCoderKey";
static NSString *const kCoderIndex = @"kCoderIndex";

#define kTSKeySeedLength 1

static uint8_t kMessageKeySeed[kTSKeySeedLength] = { 01 };
static uint8_t kChainKeySeed[kTSKeySeedLength] = { 02 };

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable id)initWithCoder:(NSCoder *)aDecoder
{
    NSData *key = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderKey];
    int index = [aDecoder decodeIntForKey:kCoderIndex];

    return [self initWithData:key index:index];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_key forKey:kCoderKey];
    [aCoder encodeInt:_index forKey:kCoderIndex];
}

- (instancetype)initWithData:(NSData *)chainKey index:(int)index
{
    OWSAssert(chainKey.length == 32);
    OWSAssert(index >= 0);

    self = [super init];

    if (self) {
        _key = chainKey;
        _index = index;
    }

    return self;
}

- (instancetype)nextChainKey
{
    NSData *nextCK = [self baseMaterial:[NSData dataWithBytes:kChainKeySeed length:kTSKeySeedLength]];
    OWSAssert(nextCK.length == 32);

    int nextIndex;
    ows_add_overflow(self.index, 1, &nextIndex);
    return [[ChainKey alloc] initWithData:nextCK index:nextIndex];
}

- (MessageKeys *)throws_messageKeys
{
    NSData *inputKeyMaterial = [self baseMaterial:[NSData dataWithBytes:kMessageKeySeed length:kTSKeySeedLength]];
    TSDerivedSecrets *derivedSecrets = [TSDerivedSecrets throws_derivedMessageKeysWithData:inputKeyMaterial];
    return [[MessageKeys alloc] initWithCipherKey:derivedSecrets.cipherKey
                                           macKey:derivedSecrets.macKey
                                               iv:derivedSecrets.iv
                                            index:self.index];
}

- (NSData *)baseMaterial:(NSData *)seed
{
    OWSAssert(self.key);
    OWSAssert(self.key.length == 32);
    OWSAssert(seed);
    OWSAssert(seed.length == kTSKeySeedLength);

    NSMutableData *_Nullable bufferData = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    OWSAssert(bufferData);

    CCHmacContext ctx;
    CCHmacInit(&ctx, kCCHmacAlgSHA256, [self.key bytes], [self.key length]);
    CCHmacUpdate(&ctx, [seed bytes], [seed length]);
    CCHmacFinal(&ctx, bufferData.mutableBytes);
    return [bufferData copy];
}

@end

NS_ASSUME_NONNULL_END
