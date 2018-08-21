//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProvisioningCipher.h"
#import <RelayServiceKit/Cryptography.h>
#import <CommonCrypto/CommonCrypto.h>
#import "OWSProvisioningProtos.pb.h"

@import AxolotlKit;
@import Curve25519Kit;
@import HKDFKit;

NS_ASSUME_NONNULL_BEGIN

@interface OWSProvisioningCipher ()

@property (nonatomic, readonly) NSData *theirPublicKey;
@property (nonatomic, readonly) ECKeyPair *ourKeyPair;
@property (nonatomic, readonly) NSData *initializationVector;

@end

@implementation OWSProvisioningCipher

- (instancetype)initWithTheirPublicKey:(NSData *)theirPublicKey
{
    return [self initWithTheirPublicKey:theirPublicKey
                             ourKeyPair:[Curve25519 generateKeyPair]
                   initializationVector:[Cryptography generateRandomBytes:kCCBlockSizeAES128]];
}

// Private method which exposes dependencies for testing
- (instancetype)initWithTheirPublicKey:(NSData *)theirPublicKey
                            ourKeyPair:(ECKeyPair *)ourKeyPair
                  initializationVector:(NSData *)initializationVector
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _theirPublicKey = theirPublicKey;
    _ourKeyPair = ourKeyPair;
    _initializationVector = initializationVector;
    
    return self;
}

- (NSData *)ourPublicKey
{
    return self.ourKeyPair.publicKey;
}

- (nullable NSData *)encrypt:(NSData *)dataToEncrypt
{
    NSData *sharedSecret =
        [Curve25519 generateSharedSecretFromPublicKey:self.theirPublicKey andKeyPair:self.ourKeyPair];

    NSData *infoData = [@"TextSecure Provisioning Message" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *nullSalt = [[NSMutableData dataWithLength:32] copy];
    NSData *derivedSecret = [HKDFKit deriveKey:sharedSecret info:infoData salt:nullSalt outputSize:64];
    NSData *cipherKey = [derivedSecret subdataWithRange:NSMakeRange(0, 32)];
    NSData *macKey = [derivedSecret subdataWithRange:NSMakeRange(32, 32)];
    NSAssert(cipherKey.length == 32, @"Cipher Key must be 32 bytes");
    NSAssert(macKey.length == 32, @"Mac Key must be 32 bytes");

    u_int8_t versionByte[] = { 0x01 };
    NSMutableData *message = [NSMutableData dataWithBytes:&versionByte length:1];

    NSData *_Nullable cipherText = [self encrypt:dataToEncrypt withKey:cipherKey];
    if (cipherText == nil) {
        OWSFail(@"Provisioning cipher failed.");
        return nil;
    }
    
    [message appendData:cipherText];

    NSData *mac = [self macForMessage:message withKey:macKey];
    [message appendData:mac];

    return [message copy];
}

- (nullable NSData *)encrypt:(NSData *)dataToEncrypt withKey:(NSData *)cipherKey
{
    NSData *iv = self.initializationVector;
    if (iv.length != kCCBlockSizeAES128) {
        OWSFail(@"Unexpected length for iv");
        return nil;
    }

    // allow space for message + padding any incomplete block. PKCS7 padding will always add at least one byte.
    size_t ciphertextBufferSize = dataToEncrypt.length + kCCBlockSizeAES128;

    // message format is (iv || ciphertext)
    NSMutableData *encryptedMessage = [NSMutableData dataWithLength:iv.length + ciphertextBufferSize];
    
    // write the iv
    [encryptedMessage replaceBytesInRange:NSMakeRange(0, iv.length) withBytes:iv.bytes];
    
    // cipher text follows iv
    char *ciphertextBuffer = encryptedMessage.mutableBytes + iv.length;

    size_t bytesEncrypted = 0;

    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
        kCCAlgorithmAES,
        kCCOptionPKCS7Padding,
        cipherKey.bytes,
        cipherKey.length,
        iv.bytes,
        dataToEncrypt.bytes,
        dataToEncrypt.length,
        ciphertextBuffer,
        ciphertextBufferSize,
        &bytesEncrypted);

    if (cryptStatus != kCCSuccess) {
        DDLogError(@"Encryption failed with status: %d", cryptStatus);
        return nil;
    }

    return [encryptedMessage subdataWithRange:NSMakeRange(0, iv.length + bytesEncrypted)];
}

-(nullable NSData *)decrypt:(nonnull OWSProvisioningProtosProvisionEnvelope *)envelopeProto
{
    NSData *publicKeyData = envelopeProto.publicKey;
    NSData *message = envelopeProto.body;
    
    NSData *keyData = [publicKeyData removeKeyType];
    
    NSData *versionData = [message subdataWithRange:NSMakeRange(0, 1)];
    int version = *(int *)(versionData.bytes);
    if (version != 1) {
        DDLogError(@"Invalid Provision Message version: %d", version);
        return nil;
    }
    
    NSData *iv = [message subdataWithRange:NSMakeRange(1, kCCBlockSizeAES128)];
    
    NSData *mac = [message subdataWithRange:NSMakeRange(message.length - 32, 32)];
    
    NSData *ivAndCiphertext = [message subdataWithRange:NSMakeRange(0, message.length - mac.length)];
    NSData *ciphertext = [message subdataWithRange:NSMakeRange(kCCBlockSizeAES128 + 1, message.length - (kCCBlockSizeAES128 + mac.length + 1))];
    
    NSData *sharedSecret = [Curve25519 generateSharedSecretFromPublicKey:keyData
                                                              andKeyPair:self.ourKeyPair];
    
    NSData *infoData = [@"TextSecure Provisioning Message" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *nullSalt = [[NSMutableData dataWithLength:32] copy];
    
    NSData *derivedSecret = [HKDFKit deriveKey:sharedSecret info:infoData salt:nullSalt outputSize:64];
    
    NSData *cipherKey = [derivedSecret subdataWithRange:NSMakeRange(0, 32)];
    NSData *macKey = [derivedSecret subdataWithRange:NSMakeRange(32, 32)];
    NSAssert(cipherKey.length == 32, @"Cipher Key must be 32 bytes");
    NSAssert(macKey.length == 32, @"Mac Key must be 32 bytes");
    
    [self verifyMac:mac fromMessage:ivAndCiphertext withMCCKey:macKey];
    
    NSData *returnData = [AES_CBC decryptCBCMode:ciphertext withKey:cipherKey withIV:iv];
    return returnData;
    
}


- (NSData *)macForMessage:(NSData *)message withKey:(NSData *)macKey
{
    NSMutableData *hmac = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA256, macKey.bytes, macKey.length, message.bytes, message.length, hmac.mutableBytes);

    return [hmac copy];
}

- (void)verifyMac:(NSData *)mac fromMessage:(NSData *)messageData withMCCKey:(NSData *)macKey
{
    NSData *calculatedMAC = [self macForMessage:messageData withKey:macKey];
    
    if (![calculatedMAC isEqualToData:mac]) {
        @throw [NSException exceptionWithName:InvalidMessageException reason:@"Bad Mac!" userInfo:@{}];
    }
}


@end

NS_ASSUME_NONNULL_END
