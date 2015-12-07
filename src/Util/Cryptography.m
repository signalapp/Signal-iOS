//
//  Cryptography.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 3/26/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>

#import "Cryptography.h"

#import "NSData+Base64.h"

#define HMAC256_KEY_LENGTH 32
#define HMAC256_OUTPUT_LENGTH 32
#define AES_CBC_IV_LENGTH 16
#define AES_KEY_SIZE 32

@implementation Cryptography


#pragma mark random bytes methods
+ (NSMutableData *)generateRandomBytes:(NSUInteger)numberBytes {
    /* used to generate db master key, and to generate signaling key, both at install */
    NSMutableData *randomBytes = [NSMutableData dataWithLength:numberBytes];
    int err                    = 0;
    err                        = SecRandomCopyBytes(kSecRandomDefault, numberBytes, [randomBytes mutableBytes]);
    if (err != noErr) {
        @throw [NSException exceptionWithName:@"random problem" reason:@"problem generating the random " userInfo:nil];
    }
    return randomBytes;
}

#pragma mark SHA1

+ (NSString *)truncatedSHA1Base64EncodedWithoutPadding:(NSString *)string {
    /* used by TSContactManager to send hashed/truncated contact list to server */
    NSMutableData *hashData = [NSMutableData dataWithLength:20];

    CC_SHA1([string dataUsingEncoding:NSUTF8StringEncoding].bytes,
            (unsigned int)[string dataUsingEncoding:NSUTF8StringEncoding].length,
            hashData.mutableBytes);

    NSData *truncatedData = [hashData subdataWithRange:NSMakeRange(0, 10)];

    return [[truncatedData base64EncodedString] stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

+ (NSString *)computeSHA1DigestForString:(NSString *)input {
    // Here we are taking in our string hash, placing that inside of a C Char Array, then parsing it through the SHA1
    // encryption method.
    const char *cstr = [input cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data     = [NSData dataWithBytes:cstr length:input.length];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];

    CC_SHA1(data.bytes, (unsigned int)data.length, digest);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];

    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }

    return output;
}

#pragma mark SHA256
+ (NSData *)computeSHA256:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (unsigned int)data.length, digest);
    return
        [[NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH] subdataWithRange:NSMakeRange(0, truncatedBytes)];
}


#pragma mark HMAC/SHA256
+ (NSData *)computeSHA256HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey {
    uint8_t ourHmac[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA256, [HMACKey bytes], [HMACKey length], [dataToHMAC bytes], [dataToHMAC length], ourHmac);
    return [NSData dataWithBytes:ourHmac length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)computeSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey {
    uint8_t ourHmac[CC_SHA256_DIGEST_LENGTH] = {0};
    CCHmac(kCCHmacAlgSHA1, [HMACKey bytes], [HMACKey length], [dataToHMAC bytes], [dataToHMAC length], ourHmac);
    return [NSData dataWithBytes:ourHmac length:CC_SHA256_DIGEST_LENGTH];
}


+ (NSData *)truncatedSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey truncation:(NSUInteger)bytes {
    return [[Cryptography computeSHA1HMAC:dataToHMAC withHMACKey:HMACKey] subdataWithRange:NSMakeRange(0, bytes)];
}

+ (NSData *)truncatedSHA256HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey truncation:(NSUInteger)bytes {
    return [[Cryptography computeSHA256HMAC:dataToHMAC withHMACKey:HMACKey] subdataWithRange:NSMakeRange(0, bytes)];
}


#pragma mark AES CBC Mode
+ (NSData *)encryptCBCMode:(NSData *)dataToEncrypt
                   withKey:(NSData *)key
                    withIV:(NSData *)iv
               withVersion:(NSData *)version
               withHMACKey:(NSData *)hmacKey
              withHMACType:(TSMACType)hmacType
              computedHMAC:(NSData **)hmac {
    /* AES256 CBC encrypt then mac
     Returns nil if encryption fails
     */
    size_t bufferSize = [dataToEncrypt length] + kCCBlockSizeAES128;
    void *buffer      = malloc(bufferSize);

    size_t bytesEncrypted       = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
                                          kCCAlgorithmAES128,
                                          kCCOptionPKCS7Padding,
                                          [key bytes],
                                          [key length],
                                          [iv bytes],
                                          [dataToEncrypt bytes],
                                          [dataToEncrypt length],
                                          buffer,
                                          bufferSize,
                                          &bytesEncrypted);

    if (cryptStatus == kCCSuccess) {
        NSData *encryptedData = [NSData dataWithBytesNoCopy:buffer length:bytesEncrypted];
        // compute hmac of version||encrypted data||iv
        NSMutableData *dataToHmac = [NSMutableData data];
        if (version != nil) {
            [dataToHmac appendData:version];
        }
        [dataToHmac appendData:iv];
        [dataToHmac appendData:encryptedData];

        if (hmacType == TSHMACSHA1Truncated10Bytes) {
            *hmac = [Cryptography truncatedSHA1HMAC:dataToHmac withHMACKey:hmacKey truncation:10];
        } else if (hmacType == TSHMACSHA256Truncated10Bytes) {
            *hmac = [Cryptography truncatedSHA256HMAC:dataToHmac withHMACKey:hmacKey truncation:10];
        } else if (hmacType == TSHMACSHA256AttachementType) {
            *hmac = [Cryptography truncatedSHA256HMAC:dataToHmac withHMACKey:hmacKey truncation:HMAC256_OUTPUT_LENGTH];
        }

        return encryptedData;
    }
    free(buffer);
    return nil;
}


+ (NSData *)decryptCBCMode:(NSData *)dataToDecrypt
                       key:(NSData *)key
                        IV:(NSData *)iv
                   version:(NSData *)version
                   HMACKey:(NSData *)hmacKey
                  HMACType:(TSMACType)hmacType
              matchingHMAC:(NSData *)hmac {
    /* AES256 CBC encrypt then mac

     Returns nil if hmac invalid or decryption fails
     */
    // verify hmac of version||encrypted data||iv
    NSMutableData *dataToHmac = [NSMutableData data];
    if (version != nil) {
        [dataToHmac appendData:version];
    }

    [dataToHmac appendData:iv];
    [dataToHmac appendData:dataToDecrypt];

    NSData *ourHmacData;

    if (hmacType == TSHMACSHA1Truncated10Bytes) {
        ourHmacData = [Cryptography truncatedSHA1HMAC:dataToHmac withHMACKey:hmacKey truncation:10];
    } else if (hmacType == TSHMACSHA256Truncated10Bytes) {
        ourHmacData = [Cryptography truncatedSHA256HMAC:dataToHmac withHMACKey:hmacKey truncation:10];
    } else if (hmacType == TSHMACSHA256AttachementType) {
        ourHmacData =
            [Cryptography truncatedSHA256HMAC:dataToHmac withHMACKey:hmacKey truncation:HMAC256_OUTPUT_LENGTH];
    }

    if (hmac == nil || ![ourHmacData isEqualToData:hmac]) {
        DDLogError(@"Bad HMAC on decrypting payload");
        return nil;
    }

    // decrypt
    size_t bufferSize = [dataToDecrypt length] + kCCBlockSizeAES128;
    void *buffer      = malloc(bufferSize);

    size_t bytesDecrypted       = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt,
                                          kCCAlgorithmAES128,
                                          kCCOptionPKCS7Padding,
                                          [key bytes],
                                          [key length],
                                          [iv bytes],
                                          [dataToDecrypt bytes],
                                          [dataToDecrypt length],
                                          buffer,
                                          bufferSize,
                                          &bytesDecrypted);
    if (cryptStatus == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:buffer length:bytesDecrypted];
    } else {
        DDLogError(@"Failed CBC decryption");
        free(buffer);
    }

    return nil;
}

#pragma mark methods which use AES CBC
+ (NSData *)decryptAppleMessagePayload:(NSData *)payload withSignalingKey:(NSString *)signalingKeyString {
    assert(payload);
    assert(signalingKeyString);

    unsigned char version[1];
    unsigned char iv[16];
    NSUInteger ciphertext_length = ([payload length] - 10 - 17) * sizeof(char);
    unsigned char *ciphertext    = (unsigned char *)malloc(ciphertext_length);
    unsigned char mac[10];
    [payload getBytes:version range:NSMakeRange(0, 1)];
    [payload getBytes:iv range:NSMakeRange(1, 16)];
    [payload getBytes:ciphertext range:NSMakeRange(17, [payload length] - 10 - 17)];
    [payload getBytes:mac range:NSMakeRange([payload length] - 10, 10)];

    NSData *signalingKey                = [NSData dataFromBase64String:signalingKeyString];
    NSData *signalingKeyAESKeyMaterial  = [signalingKey subdataWithRange:NSMakeRange(0, 32)];
    NSData *signalingKeyHMACKeyMaterial = [signalingKey subdataWithRange:NSMakeRange(32, 20)];
    return
        [Cryptography decryptCBCMode:[NSData dataWithBytesNoCopy:ciphertext length:ciphertext_length freeWhenDone:YES]
                                 key:signalingKeyAESKeyMaterial
                                  IV:[NSData dataWithBytes:iv length:16]
                             version:[NSData dataWithBytes:version length:1]
                             HMACKey:signalingKeyHMACKeyMaterial
                            HMACType:TSHMACSHA256Truncated10Bytes
                        matchingHMAC:[NSData dataWithBytes:mac length:10]];
}

+ (NSData *)decryptAttachment:(NSData *)dataToDecrypt withKey:(NSData *)key {
    if (([dataToDecrypt length] < AES_CBC_IV_LENGTH + HMAC256_OUTPUT_LENGTH) ||
        ([key length] < AES_KEY_SIZE + HMAC256_KEY_LENGTH)) {
        DDLogError(@"Message shorter than crypto overhead!");
        return nil;
    }

    // key: 32 byte AES key || 32 byte Hmac-SHA256 key.
    NSData *encryptionKey = [key subdataWithRange:NSMakeRange(0, AES_KEY_SIZE)];
    NSData *hmacKey       = [key subdataWithRange:NSMakeRange(AES_KEY_SIZE, HMAC256_KEY_LENGTH)];

    // dataToDecrypt: IV || Ciphertext || truncated MAC(IV||Ciphertext)
    NSData *iv                  = [dataToDecrypt subdataWithRange:NSMakeRange(0, AES_CBC_IV_LENGTH)];
    NSData *encryptedAttachment = [dataToDecrypt
        subdataWithRange:NSMakeRange(AES_CBC_IV_LENGTH,
                                     [dataToDecrypt length] - AES_CBC_IV_LENGTH - HMAC256_OUTPUT_LENGTH)];
    NSData *hmac = [dataToDecrypt
        subdataWithRange:NSMakeRange([dataToDecrypt length] - HMAC256_OUTPUT_LENGTH, HMAC256_OUTPUT_LENGTH)];

    return [Cryptography decryptCBCMode:encryptedAttachment
                                    key:encryptionKey
                                     IV:iv
                                version:nil
                                HMACKey:hmacKey
                               HMACType:TSHMACSHA256AttachementType
                           matchingHMAC:hmac];
}

+ (TSAttachmentEncryptionResult *)encryptAttachment:(NSData *)attachment
                                        contentType:(NSString *)contentType
                                         identifier:(NSString *)identifier {
    NSData *iv            = [Cryptography generateRandomBytes:AES_CBC_IV_LENGTH];
    NSData *encryptionKey = [Cryptography generateRandomBytes:AES_KEY_SIZE];
    NSData *hmacKey       = [Cryptography generateRandomBytes:HMAC256_KEY_LENGTH];

    // The concatenated key for storage
    NSMutableData *outKey = [NSMutableData data];
    [outKey appendData:encryptionKey];
    [outKey appendData:hmacKey];

    NSData *computedHMAC;
    NSData *ciphertext = [Cryptography encryptCBCMode:attachment
                                              withKey:encryptionKey
                                               withIV:iv
                                          withVersion:nil
                                          withHMACKey:hmacKey
                                         withHMACType:TSHMACSHA256AttachementType
                                         computedHMAC:&computedHMAC];

    NSMutableData *encryptedAttachment = [NSMutableData data];
    [encryptedAttachment appendData:iv];
    [encryptedAttachment appendData:ciphertext];
    [encryptedAttachment appendData:computedHMAC];

    TSAttachmentStream *pointer =
        [[TSAttachmentStream alloc] initWithIdentifier:identifier data:attachment key:outKey contentType:contentType];

    return [[TSAttachmentEncryptionResult alloc] initWithPointer:pointer body:encryptedAttachment];
}

@end
