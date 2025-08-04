//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class NonceHeaderOutputStreamTransform: StreamTransform {

    private let metadataHeader: BackupNonce.MetadataHeader

    public init(metadataHeader: BackupNonce.MetadataHeader) {
        self.metadataHeader = metadataHeader
    }

    private var hasWrittenHeader = false

    public func transform(data: Data) throws -> Data {
        if hasWrittenHeader { return data }
        defer { hasWrittenHeader = true }

        var result = Data()
        result.append(BackupNonce.magicFileSignature)
        let headerData = metadataHeader.data
        result.append(ChunkedOutputStreamTransform.writeVariableLengthUInt32(UInt32(headerData.count)))
        result.append(headerData)
        result.append(data)
        return result
    }
}
