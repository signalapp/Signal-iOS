#import "EVPMessageDigest.h"

#import <evp.h>
#import <hmac.h>

#import "Constraints.h"
#import "EVPUtil.h"
#import "NumberUtil.h"

@implementation EVPMessageDigest

+ (NSData*)hash:(NSData*)data withDigest:(const EVP_MD*)digest {
    NSUInteger expectedDigestLength = [NumberUtil assertConvertIntToNSUInteger:EVP_MD_size(digest)];
    unsigned int digestLength = 0;
    unsigned char digestBuffer[expectedDigestLength];
    
    EVP_MD_CTX* ctx = EVP_MD_CTX_create();
    require(NULL != ctx);
    @try {
        RAISE_EXCEPTION_ON_FAILURE(EVP_DigestInit_ex(ctx, digest, NULL));
        RAISE_EXCEPTION_ON_FAILURE(EVP_DigestUpdate(ctx, data.bytes, data.length));
        RAISE_EXCEPTION_ON_FAILURE(EVP_DigestFinal_ex(ctx, digestBuffer, &digestLength));
    }
    @finally {
        EVP_MD_CTX_destroy(ctx);
    }
   
    require(digestLength == expectedDigestLength);
    return [NSData dataWithBytes:digestBuffer length:digestLength];
}

+ (NSData*)hmacWithData:(NSData*)data andKey:(NSData*)key andDigest:(const EVP_MD*)md {
    NSUInteger digestLength = [NumberUtil assertConvertIntToNSUInteger:EVP_MD_size(md)];
    
    unsigned char* digest = HMAC(md,
                                 [key bytes], [NumberUtil assertConvertNSUIntegerToInt:key.length],
                                 [data bytes], data.length,
                                 NULL, NULL);
    
    return [NSData  dataWithBytes:digest length:digestLength];
}

+ (NSData*)hashWithSHA256:(NSData*)data {
    return [self hash:data withDigest:EVP_sha256()];
}

+ (NSData*)hmacUsingSHA1Data:(NSData*)data withKey:(NSData*)key {
    return [self hmacWithData:data andKey:key andDigest:EVP_sha1()];
}

+ (NSData*)hmacUsingSHA256Data:(NSData*)data withKey:(NSData*)key {
    return [self hmacWithData:data andKey:key andDigest:EVP_sha256()];
}

@end
