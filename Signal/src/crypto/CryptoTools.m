#import "CryptoTools.h"

#import "Constraints.h"
#import "Conversions.h"
#import "EvpMessageDigest.h"
#import "EvpSymetricUtil.h"
#import "Util.h"

@implementation CryptoTools

+ (NSData *)generateSecureRandomData:(NSUInteger)length {
    NSMutableData *d = [NSMutableData dataWithLength:length];
    int err          = SecRandomCopyBytes(kSecRandomDefault, length, [d mutableBytes]);
    if (err != 0) {
        [SecurityFailure raise:@"SecRandomCopyBytes failed"];
    }
    return d;
}

+ (uint16_t)generateSecureRandomUInt16 {
    return [[self generateSecureRandomData:sizeof(uint16_t)] bigEndianUInt16At:0];
}

+ (uint32_t)generateSecureRandomUInt32 {
    return [[self generateSecureRandomData:sizeof(uint32_t)] bigEndianUInt32At:0];
}

+ (NSString *)computeOtpWithPassword:(NSString *)password andCounter:(int64_t)counter {
    ows_require(password != nil);

    NSData *d = [[@(counter) stringValue] encodedAsUtf8];
    NSData *h = [d hmacWithSha1WithKey:password.encodedAsUtf8];
    return h.encodedAsBase64;
}

@end

@implementation NSData (CryptoTools)

- (NSData *)hmacWithSha1WithKey:(NSData *)key {
    return [EvpMessageDigest hmacUsingSha1Data:self withKey:key];
}

- (NSData *)hmacWithSha256WithKey:(NSData *)key {
    return [EvpMessageDigest hmacUsingSha256Data:self withKey:key];
}

- (NSData *)encryptWithAesInCipherFeedbackModeWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil encryptMessage:self usingAes128WithCfbAndKey:key andIv:iv];
}
- (NSData *)encryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil encryptMessage:self usingAes128WithCbcAndPaddingAndKey:key andIv:iv];
}
- (NSData *)encryptWithAesInCounterModeWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil encryptMessage:self usingAes128InCounterModeAndKey:key andIv:iv];
}

- (NSData *)decryptWithAesInCipherFeedbackModeWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil decryptMessage:self usingAes128WithCfbAndKey:key andIv:iv];
}
- (NSData *)decryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil decryptMessage:self usingAes128WithCbcAndPaddingAndKey:key andIv:iv];
}
- (NSData *)decryptWithAesInCounterModeWithKey:(NSData *)key andIv:(NSData *)iv {
    return [EvpSymetricUtil decryptMessage:self usingAes128InCounterModeAndKey:key andIv:iv];
}

- (NSData *)hashWithSha256 {
    return [EvpMessageDigest hashWithSha256:self];
}
- (bool)isEqualToData_TimingSafe:(NSData *)other {
    if (other == nil)
        return false;
    NSUInteger n = self.length;
    if (other.length != n)
        return false;
    bool equal = true;
    for (NSUInteger i = 0; i < n; i++)
        equal &= [self uint8At:i] == [other uint8At:i];
    return equal;
}
@end
