//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class DecryptingStreamTransform: StreamTransform, FinalizableStreamTransform {

    public enum Error: Swift.Error {
        case InvalidFooter
        case InvalidHmac
    }

    private enum Constants {
        static let FooterSize = 32
    }

    private var cipherContext: CipherContext
    private var hmacContext: HmacContext

    private let iv: Data
    private let encryptionKey: Data
    private let hmacKey: Data

    /// Because the HMAC footer is at the end of the input data, the input
    /// needs to be buffered to always keep the latest 32 bytes around as
    /// the provisional footer in case `finalize()` is called.
    private var inputBuffer = Data()

    private var finalized = false
    public var hasFinalized: Bool { finalized }

    init(iv: Data, encryptionKey: Data, hmacKey: Data) throws {
        self.iv = iv
        self.encryptionKey = encryptionKey
        self.hmacKey = hmacKey

        self.hmacContext = try HmacContext(key: hmacKey)
        self.cipherContext = try CipherContext(
            operation: .decrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: iv
        )
    }

    /// If there is data in excess of the footer size, return true.
    public var hasPendingBytes: Bool { return inputBuffer.count > Constants.FooterSize }

    /// Return any data in excess of the footer.
    public func readBufferedData() throws -> Data {
        guard inputBuffer.count > Constants.FooterSize else { return Data() }

        // Get the data up to the point reserved for the footer, and preserve
        // the provisional footer data in the input buffer.
        let remainingDataLength = inputBuffer.count - Constants.FooterSize
        let remainingData = inputBuffer.subdata(in: 0..<remainingDataLength)
        inputBuffer = inputBuffer.subdata(in: remainingDataLength..<inputBuffer.count)
        return remainingData
    }

    public func transform(data: Data) throws -> Data {
        inputBuffer.append(data)

        let targetData = try readBufferedData()
        if targetData.count > 0 {
            // Update the hmac with the new block
            try hmacContext.update(targetData)
        }

        // Return the next blocks of decrypted data
        return try cipherContext.update(targetData)
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        if inputBuffer.count < Constants.FooterSize {
            throw Error.InvalidFooter
        }

        // Fetch the remaining non-footer data
        let remainingData = try readBufferedData()

        // readBufferedData will result in inputBuffer having only
        // footerdata remaining in inputBuffer
        let footerData = inputBuffer

        // Finalize the decryption by transforming any data remaining in the
        // input buffer, and then finalizing the cipher context.
        var finalDecryptedData = try transform(data: remainingData)
        finalDecryptedData.append(try cipherContext.finalize())

        // Verify our HMAC of the encrypted data matches the one included.
        let hmac = try hmacContext.finalize()
        guard hmac.ows_constantTimeIsEqual(to: footerData) else {
            throw Error.InvalidHmac
        }
        return finalDecryptedData
    }
}
