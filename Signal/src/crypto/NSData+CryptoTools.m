#import "NSData+CryptoTools.h"
#import "EvpMessageDigest.h"
#import "EvpSymetricUtil.h"
#import "NSData+Util.h"

@implementation NSData (CryptoTools)

- (NSData*)hmacWithSHA1WithKey:(NSData*)key {
    return [EvpMessageDigest hmacUsingSHA1Data:self withKey:key];
}

- (NSData*)hmacWithSHA256WithKey:(NSData*)key {
    return [EvpMessageDigest hmacUsingSHA256Data:self withKey:key];
}

- (NSData*)encryptWithAESInCipherFeedbackModeWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil encryptMessage:self usingAES128WithCFBAndKey:key andIV:iv];
}

- (NSData*)encryptWithAESInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil encryptMessage:self usingAES128WithCBCAndPaddingAndKey:key andIV:iv];
}

- (NSData*)encryptWithAESInCounterModeWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil encryptMessage:self usingAES128InCounterModeAndKey:key andIV:iv];
}

- (NSData*)decryptWithAESInCipherFeedbackModeWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil decryptMessage:self usingAES128WithCFBAndKey:key andIV:iv];
}

- (NSData*)decryptWithAESInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil decryptMessage:self usingAES128WithCBCAndPaddingAndKey:key andIV:iv];
}

- (NSData*)decryptWithAESInCounterModeWithKey:(NSData*)key andIV:(NSData*)iv {
    return [EvpSymetricUtil decryptMessage:self usingAES128InCounterModeAndKey:key andIV:iv];
}

- (NSData*)hashWithSHA256 {
    return [EvpMessageDigest hashWithSHA256:self];
}

- (bool)isEqualToData_TimingSafe:(NSData*)other {
    if (other == nil) return false;
    NSUInteger n = self.length;
    if (other.length != n) return false;
    bool equal = true;
    for (NSUInteger i = 0; i < n; i++)
        equal &= [self uint8At:i] == [other uint8At:i];
    return equal;
}

@end
