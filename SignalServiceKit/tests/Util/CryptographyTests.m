//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Cryptography.h"
#import "NSData+OWS.h"
#import "SSKBaseTest.h"

NS_ASSUME_NONNULL_BEGIN

@interface CryptographyTests : SSKBaseTest

@end

#pragma mark -

@interface Cryptography (Test)

+ (NSData *)truncatedSHA256HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey truncation:(int)bytes;
+ (NSData *)encryptCBCMode:(NSData *)dataToEncrypt
                   withKey:(NSData *)key
                    withIV:(NSData *)iv
               withVersion:(NSData *)version
               withHMACKey:(NSData *)hmacKey
              withHMACType:(TSMACType)hmacType
              computedHMAC:(NSData **)hmac;

+ (NSData *)decryptCBCMode:(NSData *)dataToDecrypt
                       key:(NSData *)key
                        IV:(NSData *)iv
                   version:(NSData *)version
                   HMACKey:(NSData *)hmacKey
                  HMACType:(TSMACType)hmacType
              matchingHMAC:(NSData *)hmac;

@end

@implementation CryptographyTests

- (void)testEncryptAttachmentData
{
    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];

    // Sanity
    XCTAssertNotNil(plainTextData);

    NSData *generatedKey;
    NSData *generatedDigest;

    NSData *cipherText =
        [Cryptography encryptAttachmentData:plainTextData outKey:&generatedKey outDigest:&generatedDigest];

    NSError *error;
    NSData *decryptedData = [Cryptography decryptAttachment:cipherText
                                                    withKey:generatedKey
                                                     digest:generatedDigest
                                               unpaddedSize:(UInt32)plainTextData.length
                                                      error:&error];
    XCTAssertNil(error);

    XCTAssertEqualObjects(plainTextData, decryptedData);
}

- (void)testEncryptAttachmentDataWithBadUnpaddedSize
{

    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];

    // Sanity
    XCTAssertNotNil(plainTextData);

    NSData *generatedKey;
    NSData *generatedDigest;

    NSData *cipherText =
        [Cryptography encryptAttachmentData:plainTextData outKey:&generatedKey outDigest:&generatedDigest];


    NSError *error;
    NSData *decryptedData = [Cryptography decryptAttachment:cipherText
                                                    withKey:generatedKey
                                                     digest:generatedDigest
                                               unpaddedSize:(UInt32)cipherText.length + 1
                                                      error:&error];
    XCTAssertNotNil(error);
    XCTAssertNil(decryptedData);
}

- (void)testDecryptAttachmentWithBadKey
{
    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];

    // Sanity
    XCTAssertNotNil(plainTextData);

    NSData *generatedKey;
    NSData *generatedDigest;

    NSData *cipherText =
        [Cryptography encryptAttachmentData:plainTextData outKey:&generatedKey outDigest:&generatedDigest];

    NSData *badKey = [Cryptography generateRandomBytes:64];

    NSError *error;
    XCTAssertThrows([Cryptography decryptAttachment:cipherText
                                            withKey:badKey
                                             digest:generatedDigest
                                       unpaddedSize:(UInt32)plainTextData.length
                                              error:&error]);
}

- (void)testDecryptAttachmentWithBadDigest
{
    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];

    // Sanity
    XCTAssertNotNil(plainTextData);

    NSData *generatedKey;
    NSData *generatedDigest;

    NSData *cipherText =
        [Cryptography encryptAttachmentData:plainTextData outKey:&generatedKey outDigest:&generatedDigest];

    NSData *badDigest = [Cryptography generateRandomBytes:32];

    NSError *error;
    XCTAssertThrows([Cryptography decryptAttachment:cipherText
                                            withKey:generatedKey
                                             digest:badDigest
                                       unpaddedSize:(UInt32)plainTextData.length
                                              error:&error]);
}

- (void)testComputeSHA256Digest
{
    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];
    NSData *digest = [Cryptography computeSHA256Digest:plainTextData];

    const uint8_t expectedBytes[] = {
        0xba, 0x5f, 0xf1, 0x26,
        0x82, 0xbb, 0xb2, 0x51,
        0x8b, 0xe6, 0x06, 0x48,
        0xc5, 0x53, 0xd0, 0xa2,
        0xbf, 0x71, 0xf1, 0xec,
        0xb4, 0xdb, 0x02, 0x12,
        0x5f, 0x80, 0xea, 0x34,
        0xc9, 0x8d, 0xee, 0x1f
    };

    NSData *expectedDigest = [NSData dataWithBytes:expectedBytes length:32];
    XCTAssertEqualObjects(expectedDigest, digest);

    NSData *expectedTruncatedDigest = [NSData dataWithBytes:expectedBytes length:10];
    NSData *truncatedDigest = [Cryptography computeSHA256Digest:plainTextData truncatedToBytes:10];
    XCTAssertEqualObjects(expectedTruncatedDigest, truncatedDigest);
}

- (void)testGCMRoundTrip
{
    NSData *plainTextData = [@"Super🔥secret🔥test🔥data🏁🏁" dataUsingEncoding:NSUTF8StringEncoding];
    // Sanity Check
    XCTAssertEqual(39, plainTextData.length);

    OWSAES256Key *key = [OWSAES256Key new];
    NSData *_Nullable encryptedData = [Cryptography encryptAESGCMWithProfileData:plainTextData key:key];

    const NSUInteger ivLength = 12;
    const NSUInteger tagLength = 16;
    
    XCTAssertEqual(ivLength + plainTextData.length + tagLength, encryptedData.length);

    NSData *_Nullable decryptedData = [Cryptography decryptAESGCMWithProfileData:encryptedData key:key];
    XCTAssert(decryptedData != nil);
    XCTAssertEqual(39, decryptedData.length);
    XCTAssertEqualObjects(plainTextData, decryptedData);
    XCTAssertEqualObjects(@"Super🔥secret🔥test🔥data🏁🏁", [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding]);
}

- (void)testGCMWithBadTag
{
    NSData *plainTextData = [@"Super🔥secret🔥test🔥data🏁🏁" dataUsingEncoding:NSUTF8StringEncoding];
    // Sanity Check
    XCTAssertEqual(39, plainTextData.length);

    OWSAES256Key *key = [OWSAES256Key new];
    NSData *_Nullable encryptedData = [Cryptography encryptAESGCMWithProfileData:plainTextData key:key];

    const NSUInteger ivLength = 12;
    const NSUInteger tagLength = 16;

    XCTAssertEqual(ivLength + plainTextData.length + tagLength, encryptedData.length);

    // Logic to slice up encryptedData copied from `[Cryptography decryptAESGCMWithData:key:]`

    // encryptedData layout: initializationVector || cipherText || authTag
    NSUInteger cipherTextLength = encryptedData.length - ivLength - tagLength;

    NSData *initializationVector = [encryptedData subdataWithRange:NSMakeRange(0, ivLength)];
    NSData *cipherText = [encryptedData subdataWithRange:NSMakeRange(ivLength, cipherTextLength)];
    NSData *authTag = [encryptedData subdataWithRange:NSMakeRange(ivLength + cipherTextLength, tagLength)];

    NSData *_Nullable decryptedData = [Cryptography decryptAESGCMWithInitializationVector:initializationVector
                                                                               ciphertext:cipherText
                                                              additionalAuthenticatedData:nil
                                                                                  authTag:authTag
                                                                                      key:key];

    // Before we corrupt the tag, make sure we can decrypt the text as a sanity check to ensure we divided up the
    // encryptedData correctly.
    XCTAssert(decryptedData != nil);
    XCTAssertEqualObjects(
        @"Super🔥secret🔥test🔥data🏁🏁", [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding]);

    // Now that we know it decrypts, try again with a bogus authTag
    NSMutableData *bogusAuthTag = [authTag mutableCopy];

    // Corrupt one byte in the bogusAuthTag
    uint8_t flippedByte;
    [bogusAuthTag getBytes:&flippedByte length:1];
    flippedByte = flippedByte ^ 0xff;
    [bogusAuthTag replaceBytesInRange:NSMakeRange(0, 1) withBytes:&flippedByte];

    decryptedData = [Cryptography decryptAESGCMWithInitializationVector:initializationVector
                                                             ciphertext:cipherText
                                            additionalAuthenticatedData:nil
                                                                authTag:bogusAuthTag
                                                                    key:key];

    XCTAssertNil(decryptedData, @"Should have failed to decrypt");
}

@end

NS_ASSUME_NONNULL_END
