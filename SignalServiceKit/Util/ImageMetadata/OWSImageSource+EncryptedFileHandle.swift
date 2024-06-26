//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct EncryptedFileHandleImageSource: OWSImageSource {

    private let fileHandle: EncryptedFileHandle

    public init(fileHandle: EncryptedFileHandle) {
        self.fileHandle = fileHandle
    }

    public init(
        encryptedFileUrl: URL,
        encryptionKey: Data,
        plaintextLength: UInt32
    ) throws {
        let fileHandle = try Cryptography.encryptedAttachmentFileHandle(
            at: encryptedFileUrl,
            plaintextLength: plaintextLength,
            encryptionKey: encryptionKey
        )
        self.init(fileHandle: fileHandle)
    }

    public var byteLength: Int { return Int(fileHandle.plaintextLength) }

    public func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        if fileHandle.offset() != byteOffset {
            try fileHandle.seek(toOffset: UInt32(byteOffset))
        }
        return try fileHandle.read(upToCount: UInt32(byteLength))
    }

    public func readIntoMemory() throws -> Data {
        if fileHandle.offset() != 0 {
            try fileHandle.seek(toOffset: 0)
        }
        return try fileHandle.read(upToCount: fileHandle.plaintextLength)
    }

    // Class-bound wrapper around FileHandle
    class FileHandleWrapper {
        let fileHandle: FileHandle

        init(_ fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }
    }

    public func cgImageSource() throws -> CGImageSource? {
        let dataProvider = try CGDataProvider.from(fileHandle: fileHandle)
        return CGImageSourceCreateWithDataProvider(dataProvider, nil)
    }
}
