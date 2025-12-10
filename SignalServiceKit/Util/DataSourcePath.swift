//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DataSourcePath {
    public init(fileUrl: URL, shouldDeleteOnDeallocation: Bool) {
        owsPrecondition(fileUrl.isFileURL)
        self.fileUrl = fileUrl
        self.shouldDeleteOnDeallocation = shouldDeleteOnDeallocation
    }

    public convenience init(filePath: String, shouldDeleteOnDeallocation: Bool) {
        let fileUrl = URL(fileURLWithPath: filePath)
        self.init(fileUrl: fileUrl, shouldDeleteOnDeallocation: shouldDeleteOnDeallocation)
    }

    public convenience init(writingTempFileData: Data, fileExtension: String) throws {
        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
        try writingTempFileData.write(to: fileUrl, options: .completeFileProtectionUntilFirstUserAuthentication)
        self.init(fileUrl: fileUrl, shouldDeleteOnDeallocation: true)
    }

    public convenience init(writingSyncMessageData: Data) throws {
        try self.init(writingTempFileData: writingSyncMessageData, fileExtension: MimeTypeUtil.syncMessageFileExtension)
    }

    deinit {
        if shouldDeleteOnDeallocation && !isConsumed.get() {
            // In the ObjC code this would fire into a dispatch queue
            do {
                try FileManager.default.removeItem(at: fileUrl)
            } catch {
                owsFailDebug("DataSourcePath could not delete file: \(fileUrl), \(error)")
            }
        }
    }

    public let fileUrl: URL
    private let shouldDeleteOnDeallocation: Bool
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

    public func consumeAndDelete() throws {
        owsAssertDebug(isConsumed.tryToSetFlag())
        try OWSFileSystem.deleteFileIfExists(url: fileUrl)
    }

    public func imageSource() throws -> any OWSImageSource {
        return try DataImageSource.forPath(self.fileUrl.path)
    }
}
