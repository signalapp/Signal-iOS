//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProvisioningCipher.h"
#import <25519/Curve25519.h>
#import <HKDFKit/HKDFKit.h>
#import <SignalServiceKit/Cryptography.h>

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

- (NSData *)encrypt:(NSData *)dataToEncrypt
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

    NSData *cipherText = [self encrypt:dataToEncrypt withKey:cipherKey];
    [message appendData:cipherText];

    NSData *mac = [self macForMessage:message withKey:macKey];
    [message appendData:mac];

    return [message copy];
}

- (NSData *)encrypt:(NSData *)dataToEncrypt withKey:(NSData *)cipherKey
{
    NSData *iv = self.initializationVector;
    OWSAssert(iv.length == kCCBlockSizeAES128);

    // allow space for message + padding any incomplete block
    size_t bufferSize = dataToEncrypt.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t bytesEncrypted = 0;

    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt,
        kCCAlgorithmAES,
        kCCOptionPKCS7Padding,
        cipherKey.bytes,
        cipherKey.length,
        iv.bytes,
        dataToEncrypt.bytes,
        dataToEncrypt.length,
        buffer,
        bufferSize,
        &bytesEncrypted);

    if (cryptStatus != kCCSuccess) {
        DDLogError(@"Encryption failed with status: %d", cryptStatus);
    }

    NSMutableData *encryptedMessage = [[NSMutableData alloc] initWithData:iv];
    [encryptedMessage appendBytes:buffer length:bytesEncrypted];

    return [encryptedMessage copy];
}

- (NSData *)macForMessage:(NSData *)message withKey:(NSData *)macKey
{
    uint8_t hmacBytes[CC_SHA256_DIGEST_LENGTH] = { 0 };
    CCHmac(kCCHmacAlgSHA256, macKey.bytes, macKey.length, message.bytes, message.length, hmacBytes);

    return [NSData dataWithBytes:hmacBytes length:CC_SHA256_DIGEST_LENGTH];
}


@end

NS_ASSUME_NONNULL_END
