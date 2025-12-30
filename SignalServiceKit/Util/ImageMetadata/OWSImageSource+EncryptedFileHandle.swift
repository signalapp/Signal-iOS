//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct EncryptedFileHandleImageSource: OWSImageSource {

    private let fileHandle: EncryptedFileHandle

    init(fileHandle: EncryptedFileHandle) {
        self.fileHandle = fileHandle
    }

    init(
        encryptedFileUrl: URL,
        attachmentKey: AttachmentKey,
        plaintextLength: UInt64,
    ) throws {
        let fileHandle = try Cryptography.encryptedAttachmentFileHandle(
            at: encryptedFileUrl,
            plaintextLength: plaintextLength,
            attachmentKey: attachmentKey,
        )
        self.init(fileHandle: fileHandle)
    }

    var byteLength: Int { return Int(fileHandle.plaintextLength) }

    func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        if fileHandle.offset() != byteOffset {
            try fileHandle.seek(toOffset: UInt64(byteOffset))
        }
        return try fileHandle.read(upToCount: byteLength)
    }

    func readIntoMemory() throws -> Data {
        if fileHandle.offset() != 0 {
            try fileHandle.seek(toOffset: 0)
        }
        return try fileHandle.read(upToCount: Int(fileHandle.plaintextLength))
    }

    // Class-bound wrapper around FileHandle
    class FileHandleWrapper {
        let fileHandle: FileHandle

        init(_ fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }
    }

    func cgImageSource() throws -> CGImageSource? {
        let dataProvider = try CGDataProvider.from(fileHandle: fileHandle)
        return CGImageSourceCreateWithDataProvider(dataProvider, nil)
    }
}
