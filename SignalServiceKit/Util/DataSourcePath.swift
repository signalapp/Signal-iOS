//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DataSourcePath {
    public enum Ownership {
        /// The `DataSourcePath` owns this URL and may consume it.
        case owned

        /// The `DataSourcePath` is borrowing a reference to this file and must not
        /// touch it.
        case borrowed
    }

    public init(fileUrl: URL, ownership: Ownership) {
        owsPrecondition(fileUrl.isFileURL)
        self.fileUrl = fileUrl
        self.ownership = ownership
    }

    public convenience init(filePath: String, ownership: Ownership) {
        let fileUrl = URL(fileURLWithPath: filePath)
        self.init(fileUrl: fileUrl, ownership: ownership)
    }

    public convenience init(writingTempFileData: Data, fileExtension: String) throws {
        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
        try writingTempFileData.write(to: fileUrl, options: .completeFileProtectionUntilFirstUserAuthentication)
        self.init(fileUrl: fileUrl, ownership: .owned)
    }

    public convenience init(writingSyncMessageData: Data) throws {
        try self.init(writingTempFileData: writingSyncMessageData, fileExtension: MimeTypeUtil.syncMessageFileExtension)
    }

    deinit {
        if ownership == .owned, !isConsumed.get() {
            do {
                try OWSFileSystem.deleteFileIfExists(url: fileUrl)
            } catch {
                owsFailDebug("DataSourcePath could not delete file: \(fileUrl), \(error)")
            }
        }
    }

    public let fileUrl: URL
    private let ownership: Ownership
    private let isConsumed = AtomicBool(false, lock: .init())

    private var _sourceFilename: String?
    public var sourceFilename: String? {
        get {
            return _sourceFilename
        }
        set {
            owsAssertDebug(!isConsumed.get())
            _sourceFilename = newValue?.filterFilename()
        }
    }

    public func readData() throws -> Data {
        owsAssertDebug(!isConsumed.get())
        return try Data(contentsOf: fileUrl, options: [.mappedIfSafe])
    }

    public func readLength() throws -> UInt64 {
        owsAssertDebug(!isConsumed.get())
        return UInt64(try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    public func consumeAndDeleteIfNecessary() throws {
        owsAssertDebug(isConsumed.tryToSetFlag())
        if ownership == .owned {
            try OWSFileSystem.deleteFileIfExists(url: fileUrl)
        }
    }

    public func imageSource() throws -> any OWSImageSource {
        return try DataImageSource.forPath(self.fileUrl.path)
    }
}
