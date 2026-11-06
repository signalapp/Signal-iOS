//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct PaddingBucketTest {
    @Test(arguments: [
        (0, 541),
        (540, 541),
        (541, 541),
        (542, 568),
        (3_400, 3_456),
        (20_000, 20_018),
        (50_000, 50_585),
        (100_000, 100_155),
        (500_000, 501_096),
        (1_000_000, 1_041_743),
        (10_000_000, 10_319_484),
        (100_000_000, 102_224_512),
        (1_000_000_000, 1_012_633_066),
    ])
    func testPaddedSize(testCase: (unpaddedSize: UInt64, paddedSize: UInt64)) {
        #expect(PaddingBucket.forUnpaddedPlaintextSize(testCase.unpaddedSize)?.plaintextSize == testCase.paddedSize)
    }

    @Test(arguments: [
        (0, 592),
        (540, 592),
        (541, 592),
        (542, 624),
        (3_400, 3_520),
        (20_000, 20_080),
        (50_000, 50_640),
        (100_000, 100_208),
        (500_000, 501_152),
        (1_000_000, 1_041_792),
        (10_000_000, 10_319_536),
        (100_000_000, 102_224_576),
        (1_000_000_000, 1_012_633_120),
    ])
    func testEncryptedSize(testCase: (unpaddedSize: UInt64, encryptedSize: UInt64)) {
        #expect(PaddingBucket.forUnpaddedPlaintextSize(testCase.unpaddedSize)?.encryptedSize == testCase.encryptedSize)
    }

    @Test(arguments: [
        (591, 129),
        (592, 129),
    ])
    func testForEncryptedSize(testCase: (encryptedSizeLimit: UInt64, bucketNumber: Int)) {
        #expect(PaddingBucket.forEncryptedSizeLimit(testCase.encryptedSizeLimit).bucketNumber == testCase.bucketNumber)
    }

    @Test(arguments: 130...483)
    func testAllInterestingLimits(bucketNumber: Int) {
        let encryptedSize = PaddingBucket(bucketNumber: bucketNumber)!.encryptedSize
        #expect(PaddingBucket.forEncryptedSizeLimit(encryptedSize).bucketNumber == bucketNumber)
        #expect(PaddingBucket.forEncryptedSizeLimit(encryptedSize - 1).bucketNumber == bucketNumber - 1)
    }

    @Test
    func testOverflow() {
        let largestBucket = PaddingBucket.forEncryptedSizeLimit(.max)
        #expect(largestBucket.bucketNumber == 909)
    }
}
