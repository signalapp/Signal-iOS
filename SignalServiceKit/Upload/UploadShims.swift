//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Upload {
    public enum Shims {
        public typealias AttachmentEncrypter = _Upload_AttachmentEncrypterShim
        public typealias FileSystem = _Upload_FileSystemShim
        public typealias SleepTimer = _Upload_SleepTimerShim
    }

    public enum Wrappers {
        public typealias AttachmentEncrypter = _Upload_AttachmentEncrypterWrapper
        public typealias FileSystem = _Upload_FileSystemWrapper
        public typealias SleepTimer = _Upload_SleepTimerWrapper
    }
}

// MARK: - Shims

public protocol _Upload_AttachmentEncrypterShim {
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata

    func decryptAttachment(at encryptedUrl: URL, metadata: DecryptionMetadata, output: URL) throws
}

public protocol _Upload_FileSystemShim {
    func temporaryFileUrl() -> URL

    func fileOrFolderExists(url: URL) -> Bool

    func deleteFile(url: URL) throws

    func maxFileChunkSizeBytes() -> Int

    func readMemoryMappedFileData(url: URL) throws -> Data
}

public protocol _Upload_SleepTimerShim {
    func sleep(for delay: TimeInterval) async throws
}

// MARK: - Wrappers

public struct _Upload_AttachmentEncrypterWrapper: Upload.Shims.AttachmentEncrypter {
    public func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        try Cryptography.encryptAttachment(at: unencryptedUrl, output: encryptedUrl)
    }

    public func decryptAttachment(at encryptedUrl: URL, metadata: DecryptionMetadata, output: URL) throws {
        try Cryptography.decryptAttachment(at: encryptedUrl, metadata: metadata, output: output)
    }
}

public struct _Upload_FileSystemWrapper: Upload.Shims.FileSystem {
    public func temporaryFileUrl() -> URL {
        return OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
    }

    public func fileOrFolderExists(url: URL) -> Bool {
        return OWSFileSystem.fileOrFolderExists(url: url)
    }

    public func deleteFile(url: URL) throws {
        try OWSFileSystem.deleteFile(url: url)
    }

    public func maxFileChunkSizeBytes() -> Int {
        return 32 * 1024 * 1024
    }

    public func readMemoryMappedFileData(url: URL) throws -> Data {
        return try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
    }
}

public struct _Upload_SleepTimerWrapper: Upload.Shims.SleepTimer {
    public func sleep(for delay: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: delay.clampedNanoseconds)
    }
}
