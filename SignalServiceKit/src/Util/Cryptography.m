//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>

// CommonCryptorSPI.h is a local copy of a private APple header fetched: Fri Aug 11 18:33:25 EDT 2017
// from https://opensource.apple.com/source/CommonCrypto/CommonCrypto-60074/include/CommonCryptorSPI.h
// We use it to provide the not-yet-public AES128-GCM cryptor
#import "CommonCryptorSPI.h"

#import "Cryptography.h"
#import "NSData+Base64.h"
#import "NSData+OWSConstantTimeCompare.h"

#define HMAC256_KEY_LENGTH 32
#define HMAC256_OUTPUT_LENGTH 32
#define AES_CBC_IV_LENGTH 16
#define AES_KEY_SIZE 32

NS_ASSUME_NONNULL_BEGIN

// length of initialization nonce
static const NSUInteger kAESGCM128_IVLength = 12;

// length of authentication tag for AES128-GCM
static const NSUInteger kAESGCM128_TagLength = 16;

const NSUInteger kAES128_KeyByteLength = 16;

@implementation OWSAES128Key

+ (nullable instancetype)keyWithData:(NSData *)data
{
    if (data.length != kAES128_KeyByteLength) {
        OWSFail(@"Invalid key length for AES128: %lu", (unsigned long)data.length);
        return nil;
    }
    
    return [[self alloc] initWithData:data];
}

+ (instancetype)generateRandomKey
{
    return [self new];
}

- (instancetype)init
{
    return [self initWithData:[Cryptography generateRandomBytes:kAES128_KeyByteLength]];
}

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _keyData = data;
    
    return self;
}

#pragma mark - SecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    NSData *keyData = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"keyData"];
    if (keyData.length != kAES128_KeyByteLength) {
        OWSFail(@"Invalid key length for AES128: %lu", (unsigned long)keyData.length);
        return nil;
    }
    
    _keyData = keyData;
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_keyData forKey:@"keyData"];
}

@end

@implementation Cryptography

#pragma mark random bytes methods

+ (NSMutableData *)generateRandomBytes:(NSUInteger)numberBytes {
    /* used to generate db master key, and to generate signaling key, both at install */
    NSMutableData *randomBytes = [NSMutableData dataWithLength:numberBytes];
    int err = SecRandomCopyBytes(kSecRandomDefault, numberBytes, [randomBytes mutableBytes]);
    if (err != noErr) {
        DDLogError(@"Error in generateRandomBytes: %d", err);
        @throw
            [NSException exceptionWithName:@"random problem" reason:@"problem generating random bytes." userInfo:nil];
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

#pragma mark SHA256 Digest
+ (NSData *)computeSHA256Digest:(NSData *)data
{
    return [self computeSHA256Digest:(NSData *)data truncatedToBytes:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)computeSHA256Digest:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes
{
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

/**
 * AES256 CBC encrypt then mac. Used to decrypt both signal messages and attachment blobs
 *
 * @return decrypted data or nil if hmac invalid/decryption fails
 */
+ (NSData *)decryptCBCMode:(NSData *)dataToDecrypt
                       key:(NSData *)key
                        IV:(NSData *)iv
                   version:(nullable NSData *)version
                   HMACKey:(NSData *)hmacKey
                  HMACType:(TSMACType)hmacType
              matchingHMAC:(NSData *)hmac
                    digest:(nullable NSData *)digest
{
    // Verify hmac of: version? || iv || encrypted data
    NSMutableData *dataToAuth = [NSMutableData data];
    if (version != nil) {
        [dataToAuth appendData:version];
    }

    [dataToAuth appendData:iv];
    [dataToAuth appendData:dataToDecrypt];

    NSData *ourHmacData;

    if (hmacType == TSHMACSHA1Truncated10Bytes) {
        ourHmacData = [Cryptography truncatedSHA1HMAC:dataToAuth withHMACKey:hmacKey truncation:10];
    } else if (hmacType == TSHMACSHA256Truncated10Bytes) {
        ourHmacData = [Cryptography truncatedSHA256HMAC:dataToAuth withHMACKey:hmacKey truncation:10];
    } else if (hmacType == TSHMACSHA256AttachementType) {
        ourHmacData =
            [Cryptography truncatedSHA256HMAC:dataToAuth withHMACKey:hmacKey truncation:HMAC256_OUTPUT_LENGTH];
    }

    if (hmac == nil || ![ourHmacData ows_constantTimeIsEqualToData:hmac]) {
        DDLogError(@"%@ %s Bad HMAC on decrypting payload. Their MAC: %@, our MAC: %@", self.tag, __PRETTY_FUNCTION__, hmac, ourHmacData);
        return nil;
    }

    // Optionally verify digest of: version? || iv || encrypted data || hmac
    if (digest) {
        DDLogDebug(@"%@ %s verifying their digest: %@", self.tag, __PRETTY_FUNCTION__, digest);
        [dataToAuth appendData:ourHmacData];
        NSData *ourDigest = [Cryptography computeSHA256Digest:dataToAuth];
        if (!ourDigest || ![ourDigest ows_constantTimeIsEqualToData:digest]) {
            DDLogWarn(@"%@ Bad digest on decrypting payload. Their digest: %@, our digest: %@", self.tag, digest, ourDigest);
            return nil;
        }
    }

    // decrypt
    size_t bufferSize = [dataToDecrypt length] + kCCBlockSizeAES128;
    void *buffer      = malloc(bufferSize);
    
    if (buffer == NULL) {
        DDLogError(@"%@ Failed to allocate memory.", self.tag);
        return nil;
    }

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
        return [NSData dataWithBytesNoCopy:buffer length:bytesDecrypted freeWhenDone:YES];
    } else {
        DDLogError(@"%@ Failed CBC decryption", self.tag);
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
                        matchingHMAC:[NSData dataWithBytes:mac length:10]
                              digest:nil];
}

+ (NSData *)decryptAttachment:(NSData *)dataToDecrypt withKey:(NSData *)key digest:(nullable NSData *)digest
{
    if (([dataToDecrypt length] < AES_CBC_IV_LENGTH + HMAC256_OUTPUT_LENGTH) ||
        ([key length] < AES_KEY_SIZE + HMAC256_KEY_LENGTH)) {
        DDLogError(@"%@ Message shorter than crypto overhead!", self.tag);
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
                           matchingHMAC:hmac
                                 digest:digest];
}

+ (NSData *)encryptAttachmentData:(NSData *)attachmentData
                           outKey:(NSData *_Nonnull *_Nullable)outKey
                        outDigest:(NSData *_Nonnull *_Nullable)outDigest
{
    NSData *iv            = [Cryptography generateRandomBytes:AES_CBC_IV_LENGTH];
    NSData *encryptionKey = [Cryptography generateRandomBytes:AES_KEY_SIZE];
    NSData *hmacKey       = [Cryptography generateRandomBytes:HMAC256_KEY_LENGTH];

    // The concatenated key for storage
    NSMutableData *attachmentKey = [NSMutableData data];
    [attachmentKey appendData:encryptionKey];
    [attachmentKey appendData:hmacKey];
    *outKey = [attachmentKey copy];

    // Encrypt
    size_t bufferSize = [attachmentData length] + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);

    if (buffer == NULL) {
        DDLogError(@"%@ Failed to allocate memory.", self.tag);
        return nil;
    }

    size_t bytesEncrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
                                          kCCAlgorithmAES128,
                                          kCCOptionPKCS7Padding,
                                          [encryptionKey bytes],
                                          [encryptionKey length],
                                          [iv bytes],
                                          [attachmentData bytes],
                                          [attachmentData length],
                                          buffer,
                                          bufferSize,
                                          &bytesEncrypted);

    if (cryptStatus != kCCSuccess) {
        DDLogError(@"%@ %s CCCrypt failed with status: %d", self.tag, __PRETTY_FUNCTION__, (int32_t)cryptStatus);
        free(buffer);
        return nil;
    }

    NSData *cipherText = [NSData dataWithBytesNoCopy:buffer length:bytesEncrypted freeWhenDone:YES];

    NSMutableData *encryptedAttachmentData = [NSMutableData data];
    [encryptedAttachmentData appendData:iv];
    [encryptedAttachmentData appendData:cipherText];

    // compute hmac of: iv || encrypted data
    NSData *hmac =
        [Cryptography truncatedSHA256HMAC:encryptedAttachmentData withHMACKey:hmacKey truncation:HMAC256_OUTPUT_LENGTH];
    DDLogVerbose(@"%@ computed hmac: %@", self.tag, hmac);

    [encryptedAttachmentData appendData:hmac];

    // compute digest of: iv || encrypted data || hmac
    *outDigest = [self computeSHA256Digest:encryptedAttachmentData];
    DDLogVerbose(@"%@ computed digest: %@", self.tag, *outDigest);

    return [encryptedAttachmentData copy];
}

+ (nullable NSData *)encryptAESGCMWithData:(NSData *)plainTextData key:(OWSAES128Key *)key
{
    NSData *initializationVector = [Cryptography generateRandomBytes:kAESGCM128_IVLength];
    uint8_t *cipherTextBytes = malloc(plainTextData.length);
    if (cipherTextBytes == NULL) {
        OWSFail(@"%@ Failed to allocate encryptedBytes", self.tag);
        return nil;
    }
    
    uint8_t *authTagBytes = malloc(kAESGCM128_TagLength);
    if (authTagBytes == NULL) {
        free(cipherTextBytes);
        OWSFail(@"%@ Failed to allocate authTagBytes", self.tag);
        return nil;
    }
    
    // NOTE: Since `tagLength` is an input parameter, it seems weird that the signature for tagLength is a `size_t*` rather than just a `size_t`.
    //
    // I found a vague reference in the Safari repository implying that this may be a bug:
    // source: https://www.mail-archive.com/webkit-changes@lists.webkit.org/msg114561.html
    //
    // Comment was:
    //     tagLength is actual an input <rdar://problem/30660074>
    size_t tagLength = kAESGCM128_TagLength;

    CCCryptorStatus status
        = CCCryptorGCM(kCCEncrypt,       // CCOperation op, /* kCCEncrypt, kCCDecrypt */
            kCCAlgorithmAES128,          // CCAlgorithm alg,
            key.keyData.bytes,           // const void *key, /* raw key material */
            key.keyData.length,          // size_t keyLength,
            initializationVector.bytes,  // const void *iv,
            initializationVector.length, // size_t ivLen,
            NULL,                        // const void *aData,
            0,                           // size_t aDataLen,
            plainTextData.bytes,         // const void *dataIn,
            plainTextData.length,        // size_t dataInLength,
            cipherTextBytes,             // void *dataOut,
            authTagBytes,                // const void *tag,
            &tagLength                   // size_t *tagLength)
            );

    if (status != kCCSuccess) {
        OWSFail(@"CCCryptorGCM encrypt failed with status: %d", status);
        free(cipherTextBytes);
        free(authTagBytes);
        return nil;
    }
    
    // build up return value: initializationVector || cipherText || authTag
    NSMutableData *encryptedData = [initializationVector mutableCopy];
    [encryptedData appendBytes:cipherTextBytes length:plainTextData.length];
    [encryptedData appendBytes:authTagBytes length:tagLength];

    free(cipherTextBytes);
    free(authTagBytes);
    
    return [encryptedData copy];
}

+ (nullable NSData *)decryptAESGCMWithData:(NSData *)encryptedData key:(OWSAES128Key *)key
{
    OWSAssert(encryptedData.length > kAESGCM128_IVLength + kAESGCM128_TagLength);
    NSUInteger cipherTextLength = encryptedData.length - kAESGCM128_IVLength - kAESGCM128_TagLength;
    
    // encryptedData layout: initializationVector || cipherText || authTag
    NSData *initializationVector = [encryptedData subdataWithRange:NSMakeRange(0, kAESGCM128_IVLength)];
    NSData *cipherText = [encryptedData subdataWithRange:NSMakeRange(kAESGCM128_IVLength, cipherTextLength)];
    NSData *authTag =
        [encryptedData subdataWithRange:NSMakeRange(kAESGCM128_IVLength + cipherTextLength, kAESGCM128_TagLength)];

    return
        [self decryptAESGCMWithInitializationVector:initializationVector cipherText:cipherText authTag:authTag key:key];
}

+ (nullable NSData *)decryptAESGCMWithInitializationVector:(NSData *)initializationVector
                                                cipherText:(NSData *)cipherText
                                                   authTag:(NSData *)authTagFromEncrypt
                                                       key:(OWSAES128Key *)key
{
    void *plainTextBytes = malloc(cipherText.length);
    if (plainTextBytes == NULL) {
        OWSFail(@"Failed to malloc plainTextBytes");
        return nil;
    }

    void *decryptAuthTagBytes = malloc(kAESGCM128_TagLength);
    if (decryptAuthTagBytes == NULL) {
        OWSFail(@"Failed to malloc decryptAuthTagBytes");
        free(plainTextBytes);
        return nil;
    }

    // NOTE: Since `tagLength` is an input parameter, it seems weird that the signature for tagLength is a `size_t*` rather than just a `size_t`.
    //
    // I found a vague reference in the Safari repository implying that this may be a bug:
    // source: https://www.mail-archive.com/webkit-changes@lists.webkit.org/msg114561.html
    //
    // Comment was:
    //     tagLength is actual an input <rdar://problem/30660074>
    size_t tagLength = kAESGCM128_TagLength;

    CCCryptorStatus status
        = CCCryptorGCM(kCCDecrypt,       // CCOperation op, /* kCCEncrypt, kCCDecrypt */
            kCCAlgorithmAES128,          // CCAlgorithm alg,
            key.keyData.bytes,           // const void *key,	/* raw key material */
            key.keyData.length,          // size_t keyLength,
            initializationVector.bytes,  // const void *iv,
            initializationVector.length, // size_t ivLen,
            NULL,                        // const void *aData,
            0,                           // size_t aDataLen,
            cipherText.bytes,            // const void *dataIn,
            cipherText.length,           // size_t dataInLength,
            plainTextBytes,              // void *dataOut,
            decryptAuthTagBytes,         // const void *tag,
            &tagLength                   // size_t *tagLength
            );

    NSData *decryptAuthTag = [NSData dataWithBytesNoCopy:decryptAuthTagBytes length:tagLength freeWhenDone:YES];
    if (![decryptAuthTag ows_constantTimeIsEqualToData:authTagFromEncrypt]) {
        // This should only happen if the user has changed their profile key, which should only
        // happen currently if they re-register.
        DDLogError(@"Auth tags don't match given tag: %@ computed tag: %@", authTagFromEncrypt, decryptAuthTag);
        free(plainTextBytes);
        return nil;
    }

    if (status != kCCSuccess) {
        OWSFail(@"CCCryptorGCM decrypt failed with status: %d", status);
        free(plainTextBytes);
        return nil;
    }

    return [NSData dataWithBytesNoCopy:plainTextBytes length:cipherText.length freeWhenDone:YES];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
