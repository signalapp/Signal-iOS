//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

public class HmacStreamTransform: StreamTransform, FinalizableStreamTransform, BufferedStreamTransform {
    public enum Error: Swift.Error {
        case invalidHmac
        case invalidFooter
    }

    public enum Constants {
        static let FooterSize = 32
    }

    public enum Operation {
        case generate
        case validate
    }

    private var hmacState: HMAC<SHA256>
    private let hmacKey: Data
    private let operation: Operation

    private var finalized = false
    public var hasFinalized: Bool { finalized }

    /// Because the HMAC footer is at the end of the input data, the input
    /// needs to be buffered to always keep the latest 32 bytes around as
    /// the provisional footer in case `finalize()` is called.
    private var inputBuffer = Data()

    /// If there is data in excess of the footer size, return true.
    public var hasPendingBytes: Bool { inputBuffer.count > footerSize }

    private let footerSize: Int

    init(hmacKey: Data, operation: Operation) throws {
        self.hmacKey = hmacKey
        self.hmacState = HMAC(key: .init(data: hmacKey))
        self.operation = operation
        self.footerSize = {
            switch operation {
            case .generate: return 0
            case .validate: return Constants.FooterSize
            }
        }()
    }

    public func readBufferedData() throws -> Data {
        guard inputBuffer.count > self.footerSize else { return Data() }

        // Get the data up to the point reserved for the footer, and preserve
        // the provisional footer data in the input buffer.
        let remainingDataLength = inputBuffer.count - self.footerSize
        let remainingData = inputBuffer.subdata(in: 0..<remainingDataLength)
        inputBuffer = inputBuffer.subdata(in: remainingDataLength..<inputBuffer.count)
        return remainingData
    }

    public func transform(data: Data) throws -> Data {
        inputBuffer.append(data)
        let targetData = try readBufferedData()
        if targetData.count > 0 {
            // Update the hmac with the new block
            hmacState.update(data: targetData)
        }
        return targetData
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        if inputBuffer.count < self.footerSize {
            throw Error.invalidFooter
        }

        // Fetch the remaining non-footer data
        var remainingData = try readBufferedData()

        let hmac = Data(hmacState.finalize())
        switch operation {
        case .generate:
            remainingData.append(hmac)
        case .validate:
            // footerdata remaining in inputBuffer
            let footerData = inputBuffer
            guard hmac.ows_constantTimeIsEqual(to: footerData) else {
                throw Error.invalidHmac
            }
            inputBuffer = Data()
        }

        return remainingData
    }
}
