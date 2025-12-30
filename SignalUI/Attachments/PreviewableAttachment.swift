//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
public import SignalServiceKit

/// Represents an attachment the user *might* choose to send.
///
/// See also ``SendableAttachment``.
///
/// These are attachments that are valid enough that we believe we can make
/// them fully valid if the user chooses to send them.
///
/// For example, if the user selects an image we can't decode, we can't make
/// a `PreviewableAttachment`. However, if the user selects an image whose
/// file size is too large, we *can* make a `PreviewableAttachment`. If the
/// user chooses to send it, we can re-encode the image with lower quality
/// and/or dimensions to fit within the limit.
///
/// On the other hand, if the user selects a PDF document that's too large,
/// we can't make it valid (e.g., we don't delete or re-encode pages), so we
/// can't make a `PreviewableAttachment` for it.
public struct PreviewableAttachment {
    public let rawValue: SignalAttachment

    public var dataSource: DataSourcePath { self.rawValue.dataSource }

    public var dataUTI: String { self.rawValue.dataUTI }
    public var mimeType: String { self.rawValue.mimeType }
    public var renderingFlag: AttachmentReference.RenderingFlag { self.rawValue.renderingFlag }

    public var isImage: Bool { self.rawValue.isImage }
    public var isAnimatedImage: Bool { self.rawValue.isAnimatedImage }
    public var isVideo: Bool { self.rawValue.isVideo }
    public var isVisualMedia: Bool { self.rawValue.isVisualMedia }
    public var isAudio: Bool { self.rawValue.isAudio }

    // Factory method for an image attachment.
    public static func imageAttachment(dataSource: DataSourcePath, dataUTI: String, canBeBorderless: Bool = false) throws -> Self {
        assert(!dataUTI.isEmpty)

        guard SignalAttachment.inputImageUTISet.contains(dataUTI) else {
            throw SignalAttachmentError.invalidFileFormat
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            owsFailDebug("imageData was empty")
            throw SignalAttachmentError.invalidData
        }

        let imageMetadata = try? dataSource.imageSource().imageMetadata(ignorePerTypeFileSizeLimits: true)

        let newDataSource: DataSourcePath
        let newDataUTI: String

        let isAnimated = imageMetadata?.isAnimated ?? false
        // Never re-encode animated images (i.e. GIFs) as JPEGs.
        if isAnimated {
            guard fileSize <= OWSMediaUtils.kMaxFileSizeAnimatedImage else {
                throw SignalAttachmentError.fileSizeTooLarge
            }

            if dataUTI == UTType.png.identifier {
                let strippedData = try SignalAttachment.removeImageMetadata(fromPngData: dataSource.readData())
                guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
                    throw SignalAttachmentError.couldNotRemoveMetadata
                }
                newDataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: fileExtension)
                newDataUTI = dataUTI
            } else {
                newDataSource = dataSource
                newDataUTI = dataUTI
            }
        } else {
            if
                let sourceFilename = dataSource.sourceFilename,
                ["heic", "heif"].contains((sourceFilename as NSString).pathExtension.lowercased()),
                dataUTI == UTType.jpeg.identifier as String
            {

                // If a .heic file actually contains jpeg data, update the extension to match.
                //
                // Here's how that can happen:
                // In iOS11, the Photos.app records photos with HEIC UTIType, with the .HEIC extension.
                // Since HEIC isn't a valid output format for Signal, we'll detect that and convert to JPEG,
                // updating the extension as well. No problem.
                // However the problem comes in when you edit an HEIC image in Photos.app - the image is saved
                // in the Photos.app as a JPEG, but retains the (now incongruous) HEIC extension in the filename.

                let baseFilename = (sourceFilename as NSString).deletingPathExtension
                dataSource.sourceFilename = (baseFilename as NSString).appendingPathExtension("jpg") ?? baseFilename
            }

            // When preparing an attachment, we always prepare it in the max quality for the current
            // context. The user can choose during sending whether they want the final send to be in
            // standard or high quality. We will do the final convert and compress before uploading.

            let isOriginalValid = SignalAttachment.isOriginalImageValid(
                forImageQuality: .maximumForCurrentAppContext(),
                fileSize: fileSize,
                dataUTI: dataUTI,
                imageMetadata: imageMetadata,
            )

            // If the original is valid and we can remove the metadata, go that route.
            if isOriginalValid, let strippedData = try? SignalAttachment.removeImageMetadata(fromData: dataSource.readData(), dataUti: dataUTI) {
                guard let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI) else {
                    throw SignalAttachmentError.couldNotRemoveMetadata
                }
                newDataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: fileExtension)
                newDataUTI = dataUTI
            } else {
                // Otherwise, resize & convert to a PNG or JPG before previewing it.
                let containerType: SignalAttachment.ContainerType
                (newDataSource, containerType) = try SignalAttachment.convertAndCompressImage(
                    toImageQuality: .maximumForCurrentAppContext(),
                    dataSource: dataSource,
                    imageMetadata: imageMetadata,
                )
                newDataUTI = containerType.dataType.identifier
            }
        }
        let result = SignalAttachment(dataSource: newDataSource, dataUTI: newDataUTI)
        result.isBorderless = canBeBorderless && (imageMetadata?.hasStickerLikeProperties ?? false)
        result.isAnimatedImage = isAnimated
        return Self(rawValue: result)
    }

    // Factory method for video attachments.
    public static func videoAttachment(dataSource: DataSourcePath, dataUTI: String) throws -> Self {
        try OWSMediaUtils.validateVideoExtension(ofPath: dataSource.fileUrl.path)
        try OWSMediaUtils.validateVideoAsset(atPath: dataSource.fileUrl.path)
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SignalAttachment.videoUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeVideo,
        )
    }

    private static var videoTempPath: URL {
        let videoDir = URL(fileURLWithPath: OWSTemporaryDirectory()).appendingPathComponent("video")
        OWSFileSystem.ensureDirectoryExists(videoDir.path)
        return videoDir
    }

    @MainActor
    public static func compressVideoAsMp4(dataSource: DataSourcePath, sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil) async throws -> Self {
        return try await compressVideoAsMp4(
            asset: AVAsset(url: dataSource.fileUrl),
            baseFilename: dataSource.sourceFilename,
            sessionCallback: sessionCallback,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(asset: AVAsset, baseFilename: String?, sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil) async throws -> Self {
        let startTime = MonotonicDate()

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            throw SignalAttachmentError.couldNotConvertToMpeg4
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

        if let sessionCallback {
            sessionCallback(exportSession)
        }

        let exportURL = videoTempPath.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        try await exportSession.exportAsync(to: exportURL, as: .mp4)

        switch exportSession.status {
        case .unknown:
            throw OWSAssertionError("Unknown export status.")
        case .waiting:
            throw OWSAssertionError("Export status: .waiting.")
        case .exporting:
            throw OWSAssertionError("Export status: .exporting.")
        case .completed:
            break
        case .failed:
            if let error = exportSession.error {
                owsFailDebug("Error: \(error)")
                throw error
            } else {
                throw OWSAssertionError("Export failed without error.")
            }
        case .cancelled:
            throw CancellationError()
        @unknown default:
            throw OWSAssertionError("Unknown export status: \(exportSession.status.rawValue)")
        }

        let mp4Filename: String?
        if let baseFilename {
            let baseFilenameWithoutExtension = (baseFilename as NSString).deletingPathExtension
            mp4Filename = (baseFilenameWithoutExtension as NSString).appendingPathExtension("mp4") ?? baseFilenameWithoutExtension
        } else {
            mp4Filename = nil
        }

        let dataSource = DataSourcePath(fileUrl: exportURL, ownership: .owned)
        dataSource.sourceFilename = mp4Filename

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("transcoded video in \(formattedDuration)s")

        return try videoAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Movie.identifier)
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    public static func audioAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> Self {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SignalAttachment.audioUTISet,
            maxFileSize: OWSMediaUtils.kMaxFileSizeAudio,
        )
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    public static func genericAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> Self {
        // [15M] TODO: Enforce this at compile-time rather than runtime.
        owsPrecondition(!SignalAttachment.videoUTISet.contains(dataUTI))
        owsPrecondition(!SignalAttachment.inputImageUTISet.contains(dataUTI))
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: nil,
            maxFileSize: OWSMediaUtils.kMaxFileSizeGeneric,
        )
    }

    // MARK: Voice Messages

    public static func voiceMessageAttachment(dataSource: DataSourcePath, dataUTI: String) throws(SignalAttachmentError) -> Self {
        let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        attachment.rawValue.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    public struct AttachmentType: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let image = Self(rawValue: 1 << 0)
        public static let video = Self(rawValue: 1 << 1)
        public static let audio = Self(rawValue: 1 << 2)
        public static let other = Self(rawValue: 1 << 3)

        public static let all: Self = [.image, .video, .audio, .other]
    }

    public struct BuildOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public static func buildAttachment(
        ofType type: AttachmentType = .all,
        dataSource: DataSourcePath,
        dataUTI: String,
        options: BuildOptions = [],
    ) throws -> Self {
        if SignalAttachment.inputImageUTISet.contains(dataUTI) {
            guard type.contains(.image) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
        if SignalAttachment.videoUTISet.contains(dataUTI) {
            guard type.contains(.video) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try videoAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
        if SignalAttachment.audioUTISet.contains(dataUTI) {
            guard type.contains(.audio) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
        guard type.contains(.other) else {
            throw SignalAttachmentError.invalidFileFormat
        }
        return try genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
    }

    // MARK: Helper Methods

    private static func newAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        validUTISet: Set<String>?,
        maxFileSize: UInt,
    ) throws(SignalAttachmentError) -> Self {
        assert(!dataUTI.isEmpty)

        let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)

        if let validUTISet {
            guard validUTISet.contains(dataUTI) else {
                throw .invalidFileFormat
            }
        }

        // [15M] TODO: Allow sending empty attachments?
        guard let fileSize = try? dataSource.readLength(), fileSize > 0 else {
            owsFailDebug("Empty attachment")
            throw .invalidData
        }

        guard fileSize <= maxFileSize else {
            throw .fileSizeTooLarge
        }

        // Attachment is valid
        return Self(rawValue: attachment)
    }
}
