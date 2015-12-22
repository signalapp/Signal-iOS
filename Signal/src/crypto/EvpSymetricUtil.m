#import "EvpSymetricUtil.h"

#import "Constraints.h"
#import "EvpUtil.h"
#import "NumberUtil.h"

@implementation EvpSymetricUtil

+ (NSData *)encryptMessage:(NSData *)message
               usingCipher:(const EVP_CIPHER *)cipher
                    andKey:(NSData *)key
                     andIv:(NSData *)iv {
    [self assertKey:key andIv:iv lengthsAgainstCipher:cipher];

    int messageLength    = [NumberUtil assertConvertNSUIntegerToInt:message.length];
    int cipherBlockSize  = EVP_CIPHER_block_size(cipher);
    int cipherTextLength = 0;
    int paddingLength    = 0;

    int bufferLength = (messageLength + cipherBlockSize - 1);
    unsigned char cipherText[bufferLength];

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        RAISE_EXCEPTION;
    }

    @try {
        RAISE_EXCEPTION_ON_FAILURE(EVP_EncryptInit_ex(ctx, cipher, NULL, [key bytes], [iv bytes]))
        RAISE_EXCEPTION_ON_FAILURE(
            EVP_EncryptUpdate(ctx, cipherText, &cipherTextLength, [message bytes], messageLength))
        RAISE_EXCEPTION_ON_FAILURE(EVP_EncryptFinal_ex(ctx, cipherText + cipherTextLength, &paddingLength))

        cipherTextLength += paddingLength;
    } @finally {
        EVP_CIPHER_CTX_free(ctx);
    }

    ows_require(cipherTextLength <= bufferLength);

    return [NSData dataWithBytes:cipherText length:[NumberUtil assertConvertIntToNSUInteger:cipherTextLength]];
}

+ (void)assertKey:(NSData *)key andIv:(NSData *)iv lengthsAgainstCipher:(const EVP_CIPHER *)cipher {
    int cipherKeyLength = EVP_CIPHER_key_length(cipher);
    int cipherIvLength  = EVP_CIPHER_iv_length(cipher);

    ows_require(key.length == [NumberUtil assertConvertIntToNSUInteger:cipherKeyLength]);
    ows_require(iv.length == [NumberUtil assertConvertIntToNSUInteger:cipherIvLength]);
}

+ (NSData *)decryptMessage:(NSData *)cipherText
               usingCipher:(const EVP_CIPHER *)cipher
                    andKey:(NSData *)key
                     andIv:(NSData *)iv {
    [self assertKey:key andIv:iv lengthsAgainstCipher:cipher];

    int cipherTextLength = [NumberUtil assertConvertNSUIntegerToInt:cipherText.length];
    int cipherBlockSize  = EVP_CIPHER_block_size(cipher);
    int plainTextLength  = 0;
    int paddingLength    = 0;

    int bufferLength = (cipherTextLength + cipherBlockSize);
    unsigned char plainText[bufferLength];

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        RAISE_EXCEPTION;
    }

    @try {
        RAISE_EXCEPTION_ON_FAILURE(EVP_DecryptInit_ex(ctx, cipher, NULL, [key bytes], [iv bytes]))
        RAISE_EXCEPTION_ON_FAILURE(
            EVP_DecryptUpdate(ctx, plainText, &plainTextLength, [cipherText bytes], cipherTextLength))
        RAISE_EXCEPTION_ON_FAILURE(EVP_DecryptFinal_ex(ctx, plainText + plainTextLength, &paddingLength))

        plainTextLength += paddingLength;
    } @finally {
        EVP_CIPHER_CTX_free(ctx);
    }

    ows_require(plainTextLength <= bufferLength);

    return [NSData dataWithBytes:plainText length:[NumberUtil assertConvertIntToNSUInteger:plainTextLength]];
}

+ (NSData *)encryptMessage:(NSData *)message usingAes128WithCbcAndPaddingAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_cbc() andKey:key andIv:iv];
}
+ (NSData *)decryptMessage:(NSData *)message usingAes128WithCbcAndPaddingAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_cbc() andKey:key andIv:iv];
}

+ (NSData *)encryptMessage:(NSData *)message usingAes128WithCfbAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_cfb128() andKey:key andIv:iv];
}
+ (NSData *)decryptMessage:(NSData *)message usingAes128WithCfbAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_cfb128() andKey:key andIv:iv];
}

+ (NSData *)encryptMessage:(NSData *)message usingAes128InCounterModeAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_ctr() andKey:key andIv:iv];
}
+ (NSData *)decryptMessage:(NSData *)message usingAes128InCounterModeAndKey:(NSData *)key andIv:(NSData *)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_ctr() andKey:key andIv:iv];
}

@end
;
