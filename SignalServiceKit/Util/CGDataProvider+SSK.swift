//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol CGDataProviderFileHandle {
    func offset() throws -> UInt64
    func seek(toOffset offset: UInt64) throws
    func readNonOptional(upToCount count: Int) throws -> Data
}

extension FileHandle: CGDataProviderFileHandle {
    public func readNonOptional(upToCount count: Int) throws -> Data {
        return try self.read(upToCount: count) ?? Data()
    }
}

extension CGDataProvider {
    // Class-bound wrapper around a FileHandle
    private class FileHandleWrapper {
        let fileHandle: any CGDataProviderFileHandle

        init(_ fileHandle: any CGDataProviderFileHandle) {
            self.fileHandle = fileHandle
        }
    }

    public static func from(fileHandle: any CGDataProviderFileHandle, fileSize: Int64) -> CGDataProvider? {
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: nil,
            releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, offset, byteCount in
                guard let info else {
                    return 0
                }
                let fileHandle = Unmanaged<FileHandleWrapper>.fromOpaque(info).takeUnretainedValue().fileHandle
                do {
                    if offset != (try fileHandle.offset()) {
                        try fileHandle.seek(toOffset: UInt64(offset))
                    }
                    let data = try fileHandle.readNonOptional(upToCount: byteCount)
                    data.withUnsafeBytes { bytes in
                        buffer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                    }
                    return data.count
                } catch {
                    return 0
                }
            },
            releaseInfo: { info in
                guard let info else {
                    return
                }
                Unmanaged<FileHandleWrapper>.fromOpaque(info).release()
            },
        )

        let fileHandleWrapper = FileHandleWrapper(fileHandle)
        let unmanagedFileHandle = Unmanaged.passRetained(fileHandleWrapper)

        return CGDataProvider(
            directInfo: unmanagedFileHandle.toOpaque(),
            size: fileSize,
            callbacks: &callbacks,
        )
    }
}
