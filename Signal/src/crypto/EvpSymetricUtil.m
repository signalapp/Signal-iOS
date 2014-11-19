#import "EvpSymetricUtil.h"

#import "Constraints.h"
#import "EvpUtil.h"
#import "NumberUtil.h"

@implementation EvpSymetricUtil

+ (NSData*)encryptMessage:(NSData*)message usingCipher:(const EVP_CIPHER*)cipher andKey:(NSData*)key andIV:(NSData*)iv {
    [self assertKey:key andIV:iv lengthsAgainstCipher:cipher];
    
    int messageLength       = [NumberUtil assertConvertNSUIntegerToInt:message.length];
    int cipherBlockSize     = EVP_CIPHER_block_size(cipher);
    int cipherTextLength    = 0;
    int paddingLength       = 0;

    int bufferLength = (messageLength + cipherBlockSize - 1);
    unsigned char cipherText[bufferLength];
    
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if(!ctx) { RAISE_EXCEPTION; }
    
    @try {
        RAISE_EXCEPTION_ON_FAILURE(  EVP_EncryptInit_ex(ctx, cipher, NULL,[key bytes], [iv bytes]))
        RAISE_EXCEPTION_ON_FAILURE(  EVP_EncryptUpdate(ctx, cipherText, &cipherTextLength, [message bytes], messageLength))
        RAISE_EXCEPTION_ON_FAILURE(  EVP_EncryptFinal_ex(ctx, cipherText + cipherTextLength, &paddingLength))
        
        cipherTextLength += paddingLength;
    }
    @finally {
        EVP_CIPHER_CTX_free(ctx);
    }
    
    require(cipherTextLength <= bufferLength);

    return [NSData dataWithBytes:cipherText length: [NumberUtil assertConvertIntToNSUInteger:cipherTextLength]];
}

+ (void)assertKey:(NSData*)key andIV:(NSData*)iv lengthsAgainstCipher:(const EVP_CIPHER*)cipher {
    int cipherKeyLength     = EVP_CIPHER_key_length(cipher);
    int cipherIvLength      = EVP_CIPHER_iv_length(cipher);
    
    require(key.length == [NumberUtil assertConvertIntToNSUInteger:cipherKeyLength]);
    require(iv.length  == [NumberUtil assertConvertIntToNSUInteger:cipherIvLength]);
}

+ (NSData*)decryptMessage:(NSData*)cipherText usingCipher:(const EVP_CIPHER*)cipher andKey:(NSData*)key andIV:(NSData*)iv {
 
    [self assertKey:key andIV:iv lengthsAgainstCipher:cipher];
    
    int cipherTextLength    = [NumberUtil assertConvertNSUIntegerToInt:cipherText.length];
    int cipherBlockSize     = EVP_CIPHER_block_size(cipher);
    int plainTextLength     = 0;
    int paddingLength       = 0;

    int bufferLength = (cipherTextLength + cipherBlockSize);
    unsigned char plainText[bufferLength];
    
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if(!ctx) { RAISE_EXCEPTION; }

    @try {
        RAISE_EXCEPTION_ON_FAILURE(EVP_DecryptInit_ex(  ctx, cipher, NULL, [key bytes], [iv bytes]))
        RAISE_EXCEPTION_ON_FAILURE(EVP_DecryptUpdate(   ctx, plainText, &plainTextLength, [cipherText bytes], cipherTextLength))
        RAISE_EXCEPTION_ON_FAILURE(EVP_DecryptFinal_ex( ctx, plainText + plainTextLength, &paddingLength))
        
        plainTextLength += paddingLength;
    }
    @finally {
        EVP_CIPHER_CTX_free(ctx);
    }
    
    require(plainTextLength <= bufferLength);
    
    return [NSData dataWithBytes:plainText length: [NumberUtil assertConvertIntToNSUInteger:plainTextLength]];
}

+ (NSData*)encryptMessage:(NSData*)message usingAES128WithCBCAndPaddingAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_cbc() andKey:key andIV:iv];
}

+ (NSData*)decryptMessage:(NSData*)message usingAES128WithCBCAndPaddingAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_cbc() andKey:key andIV:iv];
}

+ (NSData*)encryptMessage:(NSData*)message usingAES128WithCFBAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_cfb128() andKey:key andIV:iv];
}

+ (NSData*)decryptMessage:(NSData*)message usingAES128WithCFBAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_cfb128() andKey:key andIV:iv];
}

+ (NSData*)encryptMessage:(NSData*)message usingAES128InCounterModeAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self encryptMessage:message usingCipher:EVP_aes_128_ctr() andKey:key andIV:iv];
}

+ (NSData*)decryptMessage:(NSData*)message usingAES128InCounterModeAndKey:(NSData*)key andIV:(NSData*)iv {
    return [self decryptMessage:message usingCipher:EVP_aes_128_ctr() andKey:key andIV:iv];
}

@end;
