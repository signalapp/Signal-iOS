//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Cryptography.h"
#import "Randomness.h"
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface CryptographyTests : XCTestCase

@end

#pragma mark -

@implementation CryptographyTests

- (void)testComputeSHA256Digest
{
    NSString *plainText = @"SGF3YWlpIGlzIEF3ZXNvbWUh";
    NSData *plainTextData = [NSData dataFromBase64String:plainText];
    NSData *digest = [Cryptography computeSHA256Digest:plainTextData];

    const uint8_t expectedBytes[] = { 0xba,
        0x5f,
        0xf1,
        0x26,
        0x82,
        0xbb,
        0xb2,
        0x51,
        0x8b,
        0xe6,
        0x06,
        0x48,
        0xc5,
        0x53,
        0xd0,
        0xa2,
        0xbf,
        0x71,
        0xf1,
        0xec,
        0xb4,
        0xdb,
        0x02,
        0x12,
        0x5f,
        0x80,
        0xea,
        0x34,
        0xc9,
        0x8d,
        0xee,
        0x1f };

    NSData *expectedDigest = [NSData dataWithBytes:expectedBytes length:32];
    XCTAssertEqualObjects(expectedDigest, digest);

    NSData *expectedTruncatedDigest = [NSData dataWithBytes:expectedBytes length:10];
    NSData *_Nullable truncatedDigest = [Cryptography computeSHA256Digest:plainTextData truncatedToBytes:10];
    XCTAssertNotNil(truncatedDigest);
    XCTAssertEqualObjects(expectedTruncatedDigest, truncatedDigest);
}

@end

NS_ASSUME_NONNULL_END
