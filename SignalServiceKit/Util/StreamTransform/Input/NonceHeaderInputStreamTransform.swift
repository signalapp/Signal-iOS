//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class NonceHeaderInputStreamTransform: StreamTransform, BufferedStreamTransform {

    private var buffer = Data()
    private var headerLength: Int?
    private var hasFinishedReadingHeader: Bool
    private var needMoreData: Bool = true

    public var hasPendingBytes: Bool { return !needMoreData && (headerLength == nil || buffer.count > headerLength!) }
    public func readBufferedData() throws -> Data {
        let returnedData = try skipPastMetadataHeader()
        buffer = Data()
        return returnedData
    }

    init(source: BackupImportSource) {
        switch source {
        case .remote:
            // Remote backups have the header,
            // we have to finish reading it first
            self.hasFinishedReadingHeader = false
        case .linkNsync:
            // Link'N'Sync backups have no header; finish immediately.
            self.hasFinishedReadingHeader = true
        }
    }

    public func transform(data: Data) throws -> Data {
        if hasFinishedReadingHeader {
            return data
        }

        if data.count > 0 {
            needMoreData = false
            buffer.append(data)
        }
        return try skipPastMetadataHeader()
    }

    /// Decode the next chunk of data, if enough data is present in the buffer.
    private func skipPastMetadataHeader() throws -> Data {
        guard buffer.count > BackupNonce.magicFileSignature.count else {
            // We dont have enough data to decode the signature, return for now.
            needMoreData = true
            return Data()
        }

        // decode the next variable length int
        let (dataSize, intLength) = ChunkedInputStreamTransform.decodeVariableLengthInteger(
            buffer: buffer,
            start: BackupNonce.magicFileSignature.count,
        )

        guard dataSize > 0 else {
            needMoreData = true
            // Don't have enough data to decode an int, so return for now
            return Data()
        }

        guard let intDataSize = Int(exactly: dataSize) else {
            // The decoded integer is to large to fit into an Int
            // The Data operations all require Int Ranges, so
            owsFailDebug("Decoded data size too large")
            return Data()
        }

        // Only advance if there is enough data present to both
        // decode the variable length integer and skip past the specified
        // number of bytes.
        let endOfHeader = BackupNonce.magicFileSignature.count + intDataSize + intLength
        guard buffer.count >= endOfHeader else {
            needMoreData = true
            return Data()
        }

        // Return any data past the header, skipping the header portion.
        let returnBuffer = buffer.dropFirst(endOfHeader)

        headerLength = endOfHeader
        hasFinishedReadingHeader = true
        needMoreData = false
        buffer = Data()

        return returnBuffer
    }
}
