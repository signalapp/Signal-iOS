//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A base class that abstracts away a source of NSData
/// and allows us to:
///
/// * Lazy-load if possible.
/// * Avoid duplicate reads & writes.
public protocol DataSource: AnyObject {

    var sourceFilename: String? { get set }

    //// Should not be called unless necessary as it can involve an expensive read.
    var data: Data { get }

    /// The URL for the data.  Should always be a File URL.
    ///
    /// Should not be called unless necessary as it can involve an expensive write.
    ///
    /// Will only return nil in the error case.
    var dataUrl: URL? { get }

    /// Will return zero in the error case.
    var dataLength: UInt { get }
    var isValidImage: Bool { get }
    var isValidVideo: Bool { get }
    var hasStickerLikeProperties: Bool { get }
    var imageMetadata: ImageMetadata? { get }

    func writeTo(_ dstUrl: URL) throws

    func consumeAndDelete() throws
}

// MARK: -

public class DataSourceValue: DataSource {
    public init(_ data: Data, fileExtension: String) {
        self.data = data
        self.fileExtension = fileExtension
        self._isConsumed = false

        // TODO: Figure out if it's actually necessary to write to disk here; objc was triggering background write to disk so we kept this behavior, but it may not be necessary.
        DispatchQueue.global().async { [weak self] in
            // relies on the side effect of this computed property writing to disk; don't shoot the messenger...
            _ = self?.dataUrl
        }
    }

    public convenience init?(_ data: Data, utiType: String) {
        guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(utiType) else {
            return nil
        }
        self.init(data, fileExtension: fileExtension)
    }

    public convenience init?(_ data: Data, mimeType: String) {
        guard let fileExtension = MimeTypeUtil.fileExtensionForMimeType(mimeType) else {
            return nil
        }
        self.init(data, fileExtension: fileExtension)
    }

    public convenience init(oversizeText: String) {
        let data = Data(oversizeText.filterForDisplay.utf8)
        self.init(data, fileExtension: MimeTypeUtil.oversizeTextAttachmentFileExtension)
    }

    deinit {
        if let _dataUrl {
            try? OWSFileSystem.deleteFileIfExists(url: _dataUrl)
        }
    }

    public let data: Data
    private let fileExtension: String

    private let lock = NSRecursiveLock()

    /// Should only be accessed while holding `lock`.
    private var _isConsumed: Bool
    private var isConsumed: Bool {
        get {
            return lock.withLock {
                return _isConsumed
            }
        }
        set {
            lock.withLock {
                _isConsumed = newValue
            }
        }
    }

    /// This property is lazily-populated.
    /// Should only be accessed while holding `lock`.
    private var _imageMetadata: ImageMetadata??
    public var imageMetadata: ImageMetadata? {
        return lock.withLock { () -> ImageMetadata? in
            owsAssertDebug(!_isConsumed)
            if let _imageMetadata {
                return _imageMetadata
            }
            let cachedImageMetadata = DataImageSource(data).imageMetadata(ignorePerTypeFileSizeLimits: true)
            _imageMetadata = cachedImageMetadata
            return cachedImageMetadata
        }
    }

    private var _sourceFilename: String?
    public var sourceFilename: String? {
        get {
            return _sourceFilename
        }
        set {
            owsAssertDebug(!isConsumed)
            _sourceFilename = newValue?.filterFilename()
        }
    }

    /// This property is lazily-populated.
    /// Should only be accessed while holding `lock`.
    private var _dataUrl: URL?
    public var dataUrl: URL? {
        lock.withLock {
            owsAssertDebug(!_isConsumed)
            if let _dataUrl {
                return _dataUrl
            }
            let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
            if (try? writeTo(fileUrl)) != nil {
                _dataUrl = fileUrl
            } else {
                owsFailDebug("Could not write data to disk.")
            }
            return _dataUrl
        }
    }

    public var dataLength: UInt {
        owsAssertDebug(!isConsumed)
        return UInt(data.count)
    }

    public func writeTo(_ dstUrl: URL) throws {
        owsAssertDebug(!isConsumed)

        do {
            try data.write(to: dstUrl, options: .atomic)
        } catch {
            owsFailDebug("Could not write data to disk: \(error)")
            throw error
        }
    }

    public func consumeAndDelete() throws {
        try lock.withLock {
            owsAssertDebug(!_isConsumed)
            _isConsumed = true
            guard let _dataUrl else { return }
            try OWSFileSystem.deleteFileIfExists(url: _dataUrl)
        }
    }

    public var isValidImage: Bool {
        owsAssertDebug(!isConsumed)
        return DataImageSource(data).ows_isValidImage
    }

    public var isValidVideo: Bool {
        owsAssertDebug(!isConsumed)
        guard let path = dataUrl?.path else {
            return false
        }
        owsFailDebug("Are we calling this anywhere? It seems quite inefficient.")
        do {
            try OWSMediaUtils.validateVideoExtension(ofPath: path)
            try OWSMediaUtils.validateVideoSize(atPath: path)
            try OWSMediaUtils.validateVideoAsset(atPath: path)
            return true
        } catch {
            return false
        }
    }

    public var hasStickerLikeProperties: Bool {
        owsAssertDebug(!isConsumed)
        return imageMetadata?.hasStickerLikeProperties ?? false
    }
}

// MARK: -

public class DataSourcePath: DataSource {
    public init(fileUrl: URL, shouldDeleteOnDeallocation: Bool) throws {
        guard fileUrl.isFileURL else {
            throw OWSAssertionError("unexpected fileUrl: \(fileUrl)")
        }

        self.fileUrl = fileUrl
        self.shouldDeleteOnDeallocation = shouldDeleteOnDeallocation
        self._isConsumed = false
    }

    public convenience init(filePath: String, shouldDeleteOnDeallocation: Bool) throws {
        let fileUrl = URL.init(fileURLWithPath: filePath)
        try self.init(fileUrl: fileUrl, shouldDeleteOnDeallocation: shouldDeleteOnDeallocation)
    }

    public convenience init(writingTempFileData: Data, fileExtension: String) throws {
        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
        try writingTempFileData.write(to: fileUrl, options: .completeFileProtectionUntilFirstUserAuthentication)
        try self.init(fileUrl: fileUrl, shouldDeleteOnDeallocation: true)
    }

    public convenience init(writingSyncMessageData: Data) throws {
        try self.init(writingTempFileData: writingSyncMessageData, fileExtension: MimeTypeUtil.syncMessageFileExtension)
    }

    deinit {
        if shouldDeleteOnDeallocation && !_isConsumed {
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
    private let lock = NSRecursiveLock()

    private var _isConsumed: Bool
    private var isConsumed: Bool {
        get {
            return lock.withLock {
                return _isConsumed
            }
        }
        set {
            lock.withLock {
                _isConsumed = newValue
            }
        }
    }

    private var _sourceFilename: String?
    public var sourceFilename: String? {
        get {
            return _sourceFilename
        }
        set {
            owsAssertDebug(!isConsumed)
            _sourceFilename = newValue?.filterFilename()
        }
    }

    private var _data: Data?
    public var data: Data {
        lock.withLock {
            owsAssertDebug(!_isConsumed)
            if _data == nil {
                _data = NSData(contentsOfFile: fileUrl.path) as Data?
            }
            if _data == nil {
                owsFailDebug("Could not read data from disk.")
                _data = Data()
            }
            return _data!
        }
    }

    public var dataLength: UInt {
        owsAssertDebug(!isConsumed)
        do {
            let values = try fileUrl.resourceValues(forKeys: [.fileSizeKey])
            return UInt(values.fileSize!)
        } catch {
            owsFailDebug("Could not read data length from disk with error: \(error)")
            return 0
        }
    }

    public var dataUrl: URL? {
        owsAssertDebug(!isConsumed)
        return fileUrl
    }

    public var isValidImage: Bool {
        owsAssertDebug(!isConsumed)
        return (try? DataImageSource.forPath(fileUrl.path))?.ows_isValidImage ?? false
    }

    public var isValidVideo: Bool {
        owsAssertDebug(!isConsumed)
        do {
            try OWSMediaUtils.validateVideoExtension(ofPath: fileUrl.path)
            try OWSMediaUtils.validateVideoSize(atPath: fileUrl.path)
            try OWSMediaUtils.validateVideoAsset(atPath: fileUrl.path)
            return true
        } catch {
            return false
        }
    }

    public var hasStickerLikeProperties: Bool {
        owsAssertDebug(!isConsumed)
        return imageMetadata?.hasStickerLikeProperties ?? false
    }

    private var _imageMetadata: ImageMetadata??
    public var imageMetadata: ImageMetadata? {
        lock.withLock { () -> ImageMetadata? in
            owsAssertDebug(!_isConsumed)
            if let _imageMetadata {
                return _imageMetadata
            }
            let imageMetadata = (try? DataImageSource.forPath(fileUrl.path))?.imageMetadata(ignorePerTypeFileSizeLimits: true)
            _imageMetadata = imageMetadata
            return imageMetadata
        }
    }

    public func writeTo(_ dstUrl: URL) throws {
        owsAssertDebug(!isConsumed)
        do {
            try FileManager.default.copyItem(at: fileUrl, to: dstUrl)
        } catch {
            owsFailDebug("Could not write data with error: \(error)")
        }
    }

    public func consumeAndDelete() throws {
        try lock.withLock {
            owsAssertDebug(!_isConsumed)
            _isConsumed = true

            try OWSFileSystem.deleteFileIfExists(url: fileUrl)
        }
    }
}
