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

    public nonisolated func buildAttachment(progress: Progress? = nil) async throws -> SignalAttachment {
        // Whenever this finishes, mark its progress as fully complete. This
        // handles item providers that can't provide partial progress updates.
        defer {
            if let progress {
                progress.completedUnitCount = progress.totalUnitCount
            }
        }

        switch itemType {
        case .image:
            // some apps send a usable file to us and some throw a UIImage at us, the UIImage can come in either directly
            // or as a bplist containing the NSKeyedArchiver output of a UIImage. the code below executes the following
            // order of attempts to load the input in the right way:
            //   1) try attaching the image from a file so we don't have to load the image into RAM in the common case
            //   2) try to load a UIImage directly in the case that is what was sent over
            //   3) try to NSKeyedUnarchive NSData directly into a UIImage
            do {
                return try await buildFileAttachment(progress: progress)
            } catch SignalAttachmentError.couldNotParseImage, ItemProviderError.fileUrlWasBplist {
                Logger.warn("failed to parse image directly from file; checking for loading UIImage directly")
                let image: UIImage = try await loadObjectWithKeyedUnarchiverFallback(
                    cannotLoadError: .cannotLoadUIImageObject,
                    failedLoadError: .loadUIImageObjectFailed
                )
                return try Self.createAttachment(withImage: image)
            }
        case .movie, .pdf, .data:
            return try await self.buildFileAttachment(progress: progress)
        case .fileUrl, .json:
            let url: NSURL = try await loadObjectWithKeyedUnarchiverFallback(
                overrideTypeIdentifier: TypedItemProvider.ItemType.fileUrl.typeIdentifier,
                cannotLoadError: .cannotLoadURLObject,
                failedLoadError: .loadURLObjectFailed
            )

            let (dataSource, dataUTI) = try Self.copyFileUrl(
                fileUrl: url as URL,
                defaultTypeIdentifier: UTType.data.identifier
            )

            return try await compressVideoIfNecessary(
                dataSource: dataSource,
                dataUTI: dataUTI,
                progress: progress
            )
        case .webUrl:
            let url: NSURL = try await loadObjectWithKeyedUnarchiverFallback(
                cannotLoadError: .cannotLoadURLObject,
                failedLoadError: .loadURLObjectFailed
            )
            return try Self.createAttachment(withText: (url as URL).absoluteString)
        case .contact:
            let contactData = try await loadDataRepresentation()
            let dataSource = DataSourceValue(contactData, utiType: itemType.typeIdentifier)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: itemType.typeIdentifier)
            attachment.isConvertibleToContactShare = true
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        case .plainText, .text:
            let text: NSString = try await loadObjectWithKeyedUnarchiverFallback(
                cannotLoadError: .cannotLoadStringObject,
                failedLoadError: .loadStringObjectFailed
            )
            return try Self.createAttachment(withText: text as String)
        case .pkPass:
            let pkPass = try await loadDataRepresentation()
            let dataSource = DataSourceValue(pkPass, utiType: itemType.typeIdentifier)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: itemType.typeIdentifier)
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        }
    }

    private nonisolated func buildFileAttachment(progress: Progress?) async throws -> SignalAttachment {
        let (dataSource, dataUTI): (DataSource, String) = try await withCheckedThrowingContinuation { continuation in
            let typeIdentifier = itemType.typeIdentifier
            _ = itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier)  { fileUrl, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileUrl {
                    if Self.isBplist(url: fileUrl) {
                        continuation.resume(throwing: ItemProviderError.fileUrlWasBplist)
                    } else {
                        do {
                            // NOTE: Compression here rather than creating an additional temp file would be nice but blocking this completion handler for video encoding is probably not a good way to go.
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

        return try await compressVideoIfNecessary(dataSource: dataSource, dataUTI: dataUTI, progress: progress)
    }

    private nonisolated func loadDataRepresentation(
        overrideTypeIdentifier: String? = nil,
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadDataRepresentation(
                forTypeIdentifier: overrideTypeIdentifier ?? itemType.typeIdentifier
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
        failedLoadError: ItemProviderError
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

    private nonisolated static func createAttachment(withText text: String) throws -> SignalAttachment {
        let dataSource = DataSourceValue(oversizeText: text)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: UTType.text.identifier)
        if let attachmentError = attachment.error {
            throw attachmentError
        }
        attachment.isConvertibleToTextMessage = true
        return attachment
    }

    private nonisolated static func createAttachment(withImage image: UIImage) throws -> SignalAttachment {
        guard let imagePng = image.pngData() else {
            throw ItemProviderError.uiImageMissingOrCorruptImageData
        }
        let type = UTType.png
        let dataSource = DataSourceValue(imagePng, utiType: type.identifier)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: type.identifier)
        if let attachmentError = attachment.error {
            throw attachmentError
        }
        return attachment
    }

    private nonisolated static func copyFileUrl(
        fileUrl: URL,
        defaultTypeIdentifier: String
    ) throws -> (DataSource, dataUTI: String) {
        guard fileUrl.isFileURL else {
            throw OWSAssertionError("Unexpectedly not a file URL: \(fileUrl)")
        }

        let copiedUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileUrl.pathExtension)
        try FileManager.default.copyItem(at: fileUrl, to: copiedUrl)

        let dataSource = try DataSourcePath(fileUrl: copiedUrl, shouldDeleteOnDeallocation: true)
        dataSource.sourceFilename = fileUrl.lastPathComponent

        let dataUTI = MimeTypeUtil.utiTypeForFileExtension(fileUrl.pathExtension) ?? defaultTypeIdentifier

        return (dataSource, dataUTI)
    }

    private nonisolated func compressVideoIfNecessary(
        dataSource: DataSource,
        dataUTI: String,
        progress: Progress?
    ) async throws -> SignalAttachment {
        if SignalAttachment.isVideoThatNeedsCompression(
            dataSource: dataSource,
            dataUTI: dataUTI
        ) {
            // TODO: Move waiting for this export to the end of the share flow rather than up front
            var progressPoller: ProgressPoller?
            defer {
                progressPoller?.stopPolling()
            }
            let compressedAttachment = try await SignalAttachment.compressVideoAsMp4(
                dataSource: dataSource,
                dataUTI: dataUTI,
                sessionCallback: { exportSession in
                    guard let progress else { return }
                    progressPoller = ProgressPoller(progress: progress, pollInterval: 0.1, fractionCompleted: { return exportSession.progress })
                    progressPoller?.startPolling()
                }
            )

            if let attachmentError = compressedAttachment.error {
                throw attachmentError
            }

            return compressedAttachment
        } else {
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI)

            if let attachmentError = attachment.error {
                throw attachmentError
            }

            return attachment
        }
    }
}

// MARK: - ProgressPoller

/// Exposes a Progress object, whose progress is updated by polling the return of a given block
final private class ProgressPoller: NSObject {
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

        self.timer = WeakTimer.scheduledTimer(timeInterval: pollInterval, target: self, userInfo: nil, repeats: true) { [weak self] (timer) in
            guard let self else {
                timer.invalidate()
                return
            }

            let fractionCompleted = self.fractionCompleted()
            self.progress.completedUnitCount = Int64(fractionCompleted * Float(self.progress.totalUnitCount))
        }
    }
}
