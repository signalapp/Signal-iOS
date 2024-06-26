//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct FileHandleImageSource: OWSImageSource {

    private let fileHandle: FileHandle
    public let byteLength: Int

    public init(fileHandle: FileHandle, byteLength: Int) {
        self.fileHandle = fileHandle
        self.byteLength = byteLength
    }

    public init(fileUrl: URL) throws {
        let byteLength = OWSFileSystem.fileSize(of: fileUrl)?.intValue ?? 0
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        self.init(fileHandle: fileHandle, byteLength: byteLength)
    }

    public func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        if try fileHandle.offset() != byteOffset {
            fileHandle.seek(toFileOffset: UInt64(byteOffset))
        }
        return try fileHandle.read(upToCount: byteLength) ?? Data()
    }

    public func readIntoMemory() throws -> Data {
        if try fileHandle.offset() != 0 {
            fileHandle.seek(toFileOffset: 0)
        }
        return try fileHandle.readToEnd() ?? Data()
    }

    // Class-bound wrapper around FileHandle
    class FileHandleWrapper {
        let fileHandle: FileHandle

        init(_ fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }
    }

    public func cgImageSource() throws -> CGImageSource? {
        let fileHandle = FileHandleWrapper(fileHandle)

        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: nil,
            releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, offset, byteCount in
                guard
                    let unmanagedFileHandle = info?.assumingMemoryBound(
                        to: Unmanaged<FileHandleWrapper>.self
                    ).pointee
                else {
                    return 0
                }
                let fileHandle = unmanagedFileHandle.takeUnretainedValue().fileHandle
                do {
                    if offset != (try fileHandle.offset()) {
                        try fileHandle.seek(toOffset: UInt64(offset))
                    }
                    let data = try fileHandle.read(upToCount: byteCount) ?? Data()
                    data.withUnsafeBytes { bytes in
                        buffer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                    }
                    return data.count
                } catch {
                    return 0
                }
            },
            releaseInfo: { info in
                guard
                    let unmanagedFileHandle = info?.assumingMemoryBound(
                        to: Unmanaged<FileHandleWrapper>.self
                    ).pointee
                else {
                    return
                }
                unmanagedFileHandle.release()
            }
        )

        var unmanagedFileHandle = Unmanaged.passRetained(fileHandle)

        guard let dataProvider = CGDataProvider(
            directInfo: &unmanagedFileHandle,
            size: Int64(byteLength),
            callbacks: &callbacks
        ) else {
            throw OWSAssertionError("Failed to create data provider")
        }
        return CGImageSourceCreateWithDataProvider(dataProvider, nil)
    }
}
