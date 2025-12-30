//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import Foundation

/// Computes (and un-computes) attachment padding.
///
/// In order to obsfucate attachment size on the wire, we round up
/// attachment plaintext bytes to the nearest power of 1.05. This number was
/// selected as it provides a good balance between number of buckets and
/// wasted bytes on the wire.
///
/// This type can compute that padding, and it can also "reverse" the
/// process and determine the maximum plaintext size that will fit within a
/// particular encrypted size limit.
struct PaddingBucket {
    private enum Constants {
        static let paddingMultiplier = 1.05
        static let smallestBucketNumber: Int = 129 // => 541 bytes

        static let ivLength = UInt64(Cryptography.Constants.aescbcIVLength)
        static let hmacLength = UInt64(Cryptography.Constants.hmac256OutputLength)
        static let blockLength = UInt64(kCCBlockSizeAES128)
    }

    let bucketNumber: Int

    /// The plaintext size with padding.
    let plaintextSize: UInt64

    /// The encrypted size with padding & encryption overhead.
    let encryptedSize: UInt64

    init?(bucketNumber: Int) {
        self.bucketNumber = max(bucketNumber, Constants.smallestBucketNumber)
        let plaintextSize = UInt64(exactly: floor(pow(Constants.paddingMultiplier, Double(self.bucketNumber))))
        guard let plaintextSize else {
            return nil
        }
        self.plaintextSize = plaintextSize
        let encryptedSize = Self.addingEncryptionOverhead(to: plaintextSize)
        guard let encryptedSize else {
            return nil
        }
        self.encryptedSize = encryptedSize
    }

    static func addingEncryptionOverhead(to paddedValue: UInt64) -> UInt64? {
        let result = paddedValue.addingReportingOverflow(
            Constants.ivLength
                + Constants.blockLength
                - paddedValue % Constants.blockLength
                + Constants.hmacLength,
        )
        if result.overflow {
            return nil
        }
        return result.partialValue
    }

    static func forUnpaddedPlaintextSize(_ unpaddedPlaintextSize: UInt64) -> PaddingBucket? {
        let bucketNumber: Int
        if unpaddedPlaintextSize == 0 {
            bucketNumber = 0
        } else {
            bucketNumber = Int(ceil(log(Double(unpaddedPlaintextSize)) / log(Constants.paddingMultiplier)))
        }
        return PaddingBucket(bucketNumber: bucketNumber)
    }

    static func forEncryptedSizeLimit(_ encryptedSize: UInt64) -> PaddingBucket {
        let worstCasePlaintextLimit = encryptedSize.subtractingReportingOverflow(
            Constants.ivLength
                // When computing the `encryptedSize`, we add 1 to 16 bytes of
                // `blockLength` padding. We always subtract 16 here (as a worst case) and
                // then check the next bucket to handle values near the boundary.
                + Constants.blockLength
                + Constants.hmacLength,
        )
        if worstCasePlaintextLimit.overflow || worstCasePlaintextLimit.partialValue == 0 {
            return PaddingBucket(bucketNumber: 0)!
        }
        // Taking the `floor(...)` here may cause us to pick a bucket one smaller
        // than we should when `encryptedSize` is exactly the size of a bucket.
        // (This happens when `plaintextSize` has a fractional component that gets
        // floored.) We already need to check the next bucket to handle the PKCS7
        // padding, so we rely on that check to handle this off-by-one as well.
        let worstCaseBucketNumber = floor(log(Double(worstCasePlaintextLimit.partialValue)) / log(Constants.paddingMultiplier))
        // We check one optimistic bucket because the minimum spacing is 27 bytes
        // (which is larger than the 15 + 1 worst-case bytes mentioned above).
        let optimisticPaddingBucket = PaddingBucket(bucketNumber: Int(worstCaseBucketNumber) + 1)
        if let optimisticPaddingBucket, optimisticPaddingBucket.encryptedSize <= encryptedSize {
            return optimisticPaddingBucket
        }
        // By definition, this bucket can't overflow the encrypted size limit.
        return PaddingBucket(bucketNumber: Int(worstCaseBucketNumber))!
    }
}
