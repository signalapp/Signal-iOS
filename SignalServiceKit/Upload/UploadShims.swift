//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Upload {
    public enum Shims {
        public typealias FileSystem = _Upload_FileSystemShim
    }

    public enum Wrappers {
        public typealias FileSystem = _Upload_FileSystemWrapper
    }
}

// MARK: - Shims

public protocol _Upload_FileSystemShim {
    func temporaryFileUrl() -> URL

    func deleteFile(url: URL) throws

    func createTempFileSlice(url: URL, start: Int) throws -> (URL, Int)
}

// MARK: - Wrappers

public struct _Upload_FileSystemWrapper: Upload.Shims.FileSystem {
    public func temporaryFileUrl() -> URL {
        return OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
    }

    public func deleteFile(url: URL) throws {
        try OWSFileSystem.deleteFile(url: url)
    }

    public func createTempFileSlice(url: URL, start: Int) throws -> (URL, Int) {
        return try OWSFileSystem.createTempFileSlice(url: url, start: start)
    }
}
