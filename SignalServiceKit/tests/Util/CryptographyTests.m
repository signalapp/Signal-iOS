//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "Cryptography.h"
#import "NSData+Base64.h"

NS_ASSUME_NONNULL_BEGIN

@interface CryptographyTests : XCTestCase

@end

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

    NSData *decryptedData = [Cryptography decryptAttachment:cipherText withKey:generatedKey digest:generatedDigest];

    XCTAssertEqualObjects(plainTextData, decryptedData);
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

    NSData *decryptedData = [Cryptography decryptAttachment:cipherText withKey:badKey digest:generatedDigest];

    XCTAssertNil(decryptedData);
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

    NSData *decryptedData = [Cryptography decryptAttachment:cipherText withKey:generatedKey digest:badDigest];

    XCTAssertNil(decryptedData);
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


@end

NS_ASSUME_NONNULL_END
