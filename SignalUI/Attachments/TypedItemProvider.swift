//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UniformTypeIdentifiers
public import SignalServiceKit

// MARK: - ItemProviderError

private enum ItemProviderError: Error {
    case unsupportedMedia
    case cannotLoadUIImageObject
    case loadUIImageObjectFailed
    case uiImageMissingOrCorruptImageData
    case cannotLoadURLObject
    case loadURLObjectFailed
    case cannotLoadStringObject
    case loadStringObjectFailed
    case loadDataRepresentationFailed
    case loadInPlaceFileRepresentationFailed
    case fileUrlWasBplist
}

// MARK: - TypedItem

public enum TypedItem {
    case text(MessageText)
    case contact(Data)
    case other(PreviewableAttachment)

    public struct MessageText {
        public let filteredValue: FilteredString
        public init?(filteredValue: FilteredString) {
            guard filteredValue.rawValue.utf8.count <= OWSMediaUtils.kMaxOversizeTextMessageSendSizeBytes else {
                return nil
            }
            self.filteredValue = filteredValue
        }
    }

    public var isVisualMedia: Bool {
        switch self {
        case .text, .contact: false
        case .other(let attachment): attachment.isVisualMedia
        }
    }

    public var isStoriesCompatible: Bool {
        switch self {
        case .text: true
        case .contact: false
        case .other(let attachment): attachment.isVisualMedia
        }
    }
}

// MARK: - TypedItemProvider

public struct TypedItemProvider {

    // MARK: ItemType

    public enum ItemType {
        case movie
        case image
        case webUrl
        case fileUrl
        case contact
        // Apple docs and runtime checks seem to imply "public.plain-text"
        // should be able to be loaded from an NSItemProvider as
        // "public.text", but in practice it fails with:
        // "A string could not be instantiated because of an unknown error."
        case plainText
        case text
        case pdf
        case pkPass
        case json
        case data

        public var typeIdentifier: String {
            switch self {
            case .movie:
                return UTType.movie.identifier
            case .image:
                return UTType.image.identifier
            case .webUrl:
                return UTType.url.identifier
            case .fileUrl:
                return UTType.fileURL.identifier
            case .contact:
                return UTType.vCard.identifier
            case .plainText:
                return UTType.plainText.identifier
            case .text:
                return UTType.text.identifier
            case .pdf:
                return UTType.pdf.identifier
            case .pkPass:
                return "com.apple.pkpass"
            case .json:
                return UTType.json.identifier
            case .data:
                return UTType.data.identifier
            }
        }
    }

    // MARK: Properties

    public let itemProvider: NSItemProvider
    public let itemType: ItemType

    public init(itemProvider: NSItemProvider, itemType: ItemType) {
        self.itemProvider = itemProvider
        self.itemType = itemType
    }

    public var isWebUrl: Bool {
        itemType == .webUrl
    }

    public var isVisualMedia: Bool {
        itemType == .image || itemType == .movie
    }

    public var isStoriesCompatible: Bool {
        switch itemType {
        case .movie, .image, .webUrl, .plainText, .text:
            return true
        case .fileUrl, .contact, .pdf, .pkPass, .json, .data:
            return false
        }
    }

    // MARK: Creating typed item providers

    /// For some data types, the OS is just awful and apparently
    /// says they conform to something else but then returns
    /// useless versions of the information
    ///
    /// - `com.topografix.gpx`
    ///     conforms to `public.text`, but when asking the OS for text,
    ///     it returns a file URL instead
    private static let forcedDataTypeIdentifiers: [String] = ["com.topografix.gpx"]

    /// Due to UT conformance fallbacks, the order these
    /// are checked is important; more specific types need
    /// to come earlier in the list than their fallbacks.
    private static let itemTypeOrder: [TypedItemProvider.ItemType] = [.movie, .image, .contact, .json, .plainText, .text, .pdf, .pkPass, .fileUrl, .webUrl, .data]

    public static func buildVisualMediaAttachment(forItemProvider itemProvider: NSItemProvider) async throws -> PreviewableAttachment {
        let typedItem = try await make(for: itemProvider).buildAttachment()
        switch typedItem {
        case .other(let attachment) where attachment.isVisualMedia:
            return attachment
        case .text, .contact, .other:
            throw SignalAttachmentError.invalidFileFormat
        }
    }

    public static func make(for itemProvider: NSItemProvider) throws -> TypedItemProvider {
        for typeIdentifier in forcedDataTypeIdentifiers {
            if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                return TypedItemProvider(itemProvider: itemProvider, itemType: .data)
            }
        }

        for itemType in itemTypeOrder {
            if itemProvider.hasItemConformingToTypeIdentifier(itemType.typeIdentifier) {
                return TypedItemProvider(itemProvider: itemProvider, itemType: itemType)
            }
        }

        owsFailDebug("unexpected share item: \(itemProvider)")
        throw ItemProviderError.unsupportedMedia
    }

    // MARK: Methods

    public nonisolated func buildAttachment(progress: Progress? = nil) async throws -> TypedItem {
        // Whenever this finishes, mark its progress as fully complete. This
        // handles item providers that can't provide partial progress updates.
        defer {
            if let progress {
                progress.completedUnitCount = progress.totalUnitCount
            }
        }

        let attachment: PreviewableAttachment
        switch itemType {
        case .image:
            // some apps send a usable file to us and some throw a UIImage at us, the UIImage can come in either directly
            // or as a bplist containing the NSKeyedArchiver output of a UIImage. the code below executes the following
            // order of attempts to load the input in the right way:
            //   1) try attaching the image from a file so we don't have to load the image into RAM in the common case
            //   2) try to load a UIImage directly in the case that is what was sent over
            //   3) try to NSKeyedUnarchive NSData directly into a UIImage
            do {
                attachment = try await buildFileAttachment(mustBeVisualMedia: true, progress: progress)
            } catch SignalAttachmentError.couldNotParseImage, ItemProviderError.fileUrlWasBplist {
                Logger.warn("failed to parse image directly from file; checking for loading UIImage directly")
                let image: UIImage = try await loadObjectWithKeyedUnarchiverFallback(
                    cannotLoadError: .cannotLoadUIImageObject,
                    failedLoadError: .loadUIImageObjectFailed,
                )
                attachment = try Self.createAttachment(withImage: image)
            }
        case .movie:
            attachment = try await self.buildFileAttachment(mustBeVisualMedia: true, progress: progress)
        case .pdf, .data:
            attachment = try await self.buildFileAttachment(mustBeVisualMedia: false, progress: progress)
        case .fileUrl, .json:
            let url: NSURL = try await loadObjectWithKeyedUnarchiverFallback(
                overrideTypeIdentifier: TypedItemProvider.ItemType.fileUrl.typeIdentifier,
                cannotLoadError: .cannotLoadURLObject,
                failedLoadError: .loadURLObjectFailed,
            )
            let (dataSource, dataUTI) = try Self.copyFileUrl(
                fileUrl: url as URL,
                defaultTypeIdentifier: UTType.data.identifier,
            )
            attachment = try await _buildFileAttachment(
                dataSource: dataSource,
                dataUTI: dataUTI,
                mustBeVisualMedia: false,
                progress: progress,
            )
        case .webUrl:
            let url: NSURL = try await loadObjectWithKeyedUnarchiverFallback(
                cannotLoadError: .cannotLoadURLObject,
                failedLoadError: .loadURLObjectFailed,
            )
            return try Self.createAttachment(withText: (url as URL).absoluteString)
        case .contact:
            let contactData = try await loadDataRepresentation()
            return .contact(contactData)
        case .plainText, .text:
            let text: NSString = try await loadObjectWithKeyedUnarchiverFallback(
                cannotLoadError: .cannotLoadStringObject,
                failedLoadError: .loadStringObjectFailed,
            )
            return try Self.createAttachment(withText: text as String)
        case .pkPass:
            let pkPass = try await loadDataRepresentation()
            let fileExtension = MimeTypeUtil.fileExtensionForUtiType(itemType.typeIdentifier)
            guard let fileExtension else {
                throw SignalAttachmentError.missingData
            }
            let dataSource = try DataSourcePath(writingTempFileData: pkPass, fileExtension: fileExtension)
            attachment = try PreviewableAttachment.genericAttachment(dataSource: dataSource, dataUTI: itemType.typeIdentifier)
        }
        return .other(attachment)
    }

    private nonisolated func buildFileAttachment(mustBeVisualMedia: Bool, progress: Progress?) async throws -> PreviewableAttachment {
        let (dataSource, dataUTI): (DataSourcePath, String) = try await withCheckedThrowingContinuation { continuation in
            let typeIdentifier = itemType.typeIdentifier
            _ = itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { fileUrl, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileUrl {
                    if Self.isBplist(url: fileUrl) {
                        continuation.resume(throwing: ItemProviderError.fileUrlWasBplist)
                    } else {
                        do {
                            continuation.resume(returning: try Self.copyFileUrl(fileUrl: fileUrl, defaultTypeIdentifier: typeIdentifier))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(throwing: ItemProviderError.loadInPlaceFileRepresentationFailed)
                }
            }
        }

        return try await _buildFileAttachment(dataSource: dataSource, dataUTI: dataUTI, mustBeVisualMedia: mustBeVisualMedia, progress: progress)
    }

    private nonisolated func loadDataRepresentation(
        overrideTypeIdentifier: String? = nil,
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadDataRepresentation(
                forTypeIdentifier: overrideTypeIdentifier ?? itemType.typeIdentifier,
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ItemProviderError.loadDataRepresentationFailed)
                }
            }
        }
    }

    private nonisolated func loadObjectWithKeyedUnarchiverFallback<T>(
        overrideTypeIdentifier: String? = nil,
        cannotLoadError: ItemProviderError,
        failedLoadError: ItemProviderError,
    ) async throws -> T where T: NSItemProviderReading, T: NSCoding, T: NSObject {
        do {
            guard itemProvider.canLoadObject(ofClass: T.self) else {
                throw cannotLoadError
            }
            return try await withCheckedThrowingContinuation { continuation in
                _ = itemProvider.loadObject(ofClass: T.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let typedObject = object as? T {
                        continuation.resume(returning: typedObject)
                    } else {
                        continuation.resume(throwing: failedLoadError)
                    }
                }
            }
        } catch {
            let data = try await loadDataRepresentation(overrideTypeIdentifier: overrideTypeIdentifier)
            if let result = try? NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data) {
                return result
            } else {
                throw error
            }
        }
    }

    // MARK: Static helpers

    private nonisolated static func isBplist(url: URL) -> Bool {
        if let handle = try? FileHandle(forReadingFrom: url) {
            let data = handle.readData(ofLength: 6)
            return data == Data("bplist".utf8)
        } else {
            return false
        }
    }

    private nonisolated static func createAttachment(withText text: String) throws -> TypedItem {
        let filteredText = FilteredString(rawValue: text)
        if let messageText = TypedItem.MessageText(filteredValue: filteredText) {
            return .text(messageText)
        } else {
            // If this is too large to send as a message, fall back to treating it as a
            // generic attachment that happens to contain text.
            let dataSource = try DataSourcePath(
                writingTempFileData: Data(filteredText.rawValue.utf8),
                fileExtension: MimeTypeUtil.oversizeTextAttachmentFileExtension,
            )
            return .other(try PreviewableAttachment.genericAttachment(
                dataSource: dataSource,
                dataUTI: UTType.plainText.identifier,
            ))
        }
    }

    private nonisolated static func createAttachment(withImage image: UIImage) throws -> PreviewableAttachment {
        guard let imagePng = image.pngData() else {
            throw ItemProviderError.uiImageMissingOrCorruptImageData
        }
        let containerType = SignalAttachment.ContainerType.png
        let dataSource = try DataSourcePath(writingTempFileData: imagePng, fileExtension: containerType.fileExtension)
        return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: containerType.dataType.identifier)
    }

    private nonisolated static func copyFileUrl(
        fileUrl: URL,
        defaultTypeIdentifier: String,
    ) throws -> (DataSourcePath, dataUTI: String) {
        guard fileUrl.isFileURL else {
            throw OWSAssertionError("Unexpectedly not a file URL: \(fileUrl)")
        }

        let copiedUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileUrl.pathExtension)
        try FileManager.default.copyItem(at: fileUrl, to: copiedUrl)

        let dataSource = DataSourcePath(fileUrl: copiedUrl, ownership: .owned)
        dataSource.sourceFilename = fileUrl.lastPathComponent

        let dataUTI = MimeTypeUtil.utiTypeForFileExtension(fileUrl.pathExtension) ?? defaultTypeIdentifier

        return (dataSource, dataUTI)
    }

    private nonisolated func _buildFileAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        mustBeVisualMedia: Bool,
        progress: Progress?,
    ) async throws -> PreviewableAttachment {
        if SignalAttachment.videoUTISet.contains(dataUTI) {
            // TODO: Move waiting for this export to the end of the share flow rather than up front
            var progressPoller: ProgressPoller?
            defer {
                progressPoller?.stopPolling()
            }
            return try await PreviewableAttachment.compressVideoAsMp4(
                dataSource: dataSource,
                sessionCallback: { exportSession in
                    guard let progress else { return }
                    progressPoller = ProgressPoller(progress: progress, pollInterval: 0.1, fractionCompleted: { return exportSession.progress })
                    progressPoller?.startPolling()
                },
            )
        } else if mustBeVisualMedia {
            // If it's not a video but must be visual media, then we must parse it as
            // an image or throw an error.
            return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        } else {
            return try PreviewableAttachment.buildAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
    }
}

// MARK: - ProgressPoller

/// Exposes a Progress object, whose progress is updated by polling the return of a given block
private class ProgressPoller: NSObject {
    private let progress: Progress
    private let pollInterval: TimeInterval
    private let fractionCompleted: () -> Float

    init(progress: Progress, pollInterval: TimeInterval, fractionCompleted: @escaping () -> Float) {
        self.progress = progress
        self.pollInterval = pollInterval
        self.fractionCompleted = fractionCompleted
    }

    private var timer: Timer?

    func stopPolling() {
        timer?.invalidate()
    }

    func startPolling() {
        guard self.timer == nil else {
            owsFailDebug("already started timer")
            return
        }

        self.timer = WeakTimer.scheduledTimer(timeInterval: pollInterval, target: self, userInfo: nil, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let fractionCompleted = self.fractionCompleted()
            self.progress.completedUnitCount = Int64(fractionCompleted * Float(self.progress.totalUnitCount))
        }
    }
}
