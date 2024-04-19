//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class DecryptingStreamTransform: StreamTransform, FinalizableStreamTransform {

    public enum Error: Swift.Error {
        case invalidFooter
        case invalidHmac
        case notInitialized
    }

    private enum Constants {
        static let HeaderSize = 16
        static let FooterSize = 32
    }

    private var cipherContext: CipherContext?
    private var hmacContext: HmacContext

    private let encryptionKey: Data
    private let hmacKey: Data

    /// Because the HMAC footer is at the end of the input data, the input
    /// needs to be buffered to always keep the latest 32 bytes around as
    /// the provisional footer in case `finalize()` is called.
    private var inputBuffer = Data()

    private var finalized = false
    public var hasFinalized: Bool { finalized }
    /// If there is data in excess of the footer size, return true.
    public var hasPendingBytes: Bool { return inputBuffer.count > Constants.FooterSize }

    public var hasInitialized = false

    init(encryptionKey: Data, hmacKey: Data) throws {
        self.encryptionKey = encryptionKey
        self.hmacKey = hmacKey
        self.hmacContext = try HmacContext(key: hmacKey)
    }

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
        if !hasInitialized {
            guard inputBuffer.count > Constants.HeaderSize else { return Data() }
            // read the IV
            let iv = inputBuffer.subdata(in: 0..<Constants.HeaderSize)
            inputBuffer = inputBuffer.subdata(in: Constants.HeaderSize..<inputBuffer.count)

            try hmacContext.update(iv)

            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: encryptionKey,
                iv: iv
            )
            hasInitialized = true
        }
        guard var cipherContext else { throw Error.notInitialized }

        let targetData = try readBufferedData()
        if targetData.count > 0 {
            // Update the hmac with the new block
            try hmacContext.update(targetData)
        }

        // Return the next blocks of decrypted data
        return try cipherContext.update(targetData)
    }

    public func finalize() throws -> Data {
        guard var cipherContext else { throw Error.notInitialized }
        guard !finalized else { return Data() }
        finalized = true

        if inputBuffer.count < Constants.FooterSize {
            throw Error.invalidFooter
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
            throw Error.invalidHmac
        }
        return finalDecryptedData
    }
}
