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
    public let attachmentType: AttachmentType

    public enum AttachmentType {
        case image(NormalizedImage)
        case animatedImage
        case other
    }

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

        let imageMetadata = try? dataSource.imageSource().imageMetadata()
        let isBorderless = canBeBorderless && (imageMetadata?.hasStickerLikeProperties ?? false)

        let isAnimated = imageMetadata?.isAnimated ?? false
        // Never re-encode animated images (i.e. GIFs) as JPEGs.
        if isAnimated {
            guard fileSize <= OWSMediaUtils.kMaxFileSizeAnimatedImage else {
                throw SignalAttachmentError.fileSizeTooLarge
            }

            let rawValue = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)
            rawValue.isBorderless = isBorderless
            rawValue.isAnimatedImage = true
            return Self(
                rawValue: rawValue,
                attachmentType: .animatedImage,
            )
        } else {
            if
                let sourceFilename = dataSource.sourceFilename,
                ["heic", "heif"].contains((sourceFilename as NSString).pathExtension.lowercased()),
                dataUTI == UTType.jpeg.identifier as String
            {

                // If a .heic file actually contains jpeg data, update the extension to
                // match.
                //
                // Here's how that can happen:
                //
                // In iOS11, the Photos.app records photos with HEIC UTIType, with the
                // .HEIC extension. Since HEIC isn't a valid output format for Signal,
                // we'll detect that and convert to JPEG, updating the extension as well.
                // No problem. However the problem comes in when you edit an HEIC image in
                // Photos.app - the image is saved in the Photos.app as a JPEG, but retains
                // the (now incongruous) HEIC extension in the filename.

                let baseFilename = (sourceFilename as NSString).deletingPathExtension
                dataSource.sourceFilename = (baseFilename as NSString).appendingPathExtension("jpg") ?? baseFilename
            }

            let normalizedImage = try NormalizedImage.forDataSource(dataSource, dataUTI: dataUTI)
            return imageAttachmentForNormalizedImage(normalizedImage, isBorderless: isBorderless)
        }
    }

    public static func imageAttachmentForNormalizedImage(_ normalizedImage: NormalizedImage, isBorderless: Bool = false) -> Self {
        let rawValue = SignalAttachment(dataSource: normalizedImage.dataSource, dataUTI: normalizedImage.dataUTI)
        rawValue.isBorderless = isBorderless
        return Self(
            rawValue: rawValue,
            attachmentType: .image(normalizedImage),
        )
    }

    // Factory method for video attachments.
    public static func videoAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws -> Self {
        try OWSMediaUtils.validateVideoExtension(ofPath: dataSource.fileUrl.path)
        try OWSMediaUtils.validateVideoAsset(atPath: dataSource.fileUrl.path)
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SignalAttachment.videoUTISet,
            maxFileSize: attachmentLimits.maxPlaintextVideoBytes,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(
        dataSource: DataSourcePath,
        attachmentLimits: OutgoingAttachmentLimits,
        sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil,
    ) async throws -> Self {
        return try await compressVideoAsMp4(
            asset: AVAsset(url: dataSource.fileUrl),
            baseFilename: dataSource.sourceFilename,
            attachmentLimits: attachmentLimits,
            sessionCallback: sessionCallback,
        )
    }

    @MainActor
    public static func compressVideoAsMp4(
        asset: AVAsset,
        baseFilename: String?,
        attachmentLimits: OutgoingAttachmentLimits,
        sessionCallback: (@MainActor (AVAssetExportSession) -> Void)? = nil,
    ) async throws -> Self {
        let imageQuality = SSKEnvironment.shared.databaseStorageRef.read(block: ImageQuality.fetchValue(tx:))
        let qualityLevel = ImageQualityLevel.resolvedValue(
            imageQuality: imageQuality,
            standardQualityLevel: attachmentLimits.standardQualityLevel,
        )
        let exportTiers = videoExportTiers(
            forQualityLevel: qualityLevel,
            videoDuration: asset.duration,
            maxFileSize: attachmentLimits.maxPlaintextVideoBytes,
        )

        // Export at the highest acceptable quality. If the resulting file
        // is too large to send, try again at the next tier down.
        for exportTier in exportTiers.dropLast() {
            do {
                return try await compressVideoAsMp4(
                    asset: asset,
                    presetName: exportTier.presetName,
                    baseFilename: baseFilename,
                    attachmentLimits: attachmentLimits,
                    sessionCallback: sessionCallback,
                )
            } catch SignalAttachmentError.fileSizeTooLarge {
                Logger.warn("Video exported with \(exportTier.presetName) exceeded the attachment size limit; retrying at a lower quality.")
            }
        }

        // The last tier is always attempted; if even it is too large, the
        // error propagates to the caller (same as the historical behavior).
        let lastResortTier = exportTiers[exportTiers.count - 1]
        return try await compressVideoAsMp4(
            asset: asset,
            presetName: lastResortTier.presetName,
            baseFilename: baseFilename,
            attachmentLimits: attachmentLimits,
            sessionCallback: sessionCallback,
        )
    }

    @MainActor
    private static func compressVideoAsMp4(
        asset: AVAsset,
        presetName: String,
        baseFilename: String?,
        attachmentLimits: OutgoingAttachmentLimits,
        sessionCallback: (@MainActor (AVAssetExportSession) -> Void)?,
    ) async throws -> Self {
        let startTime = MonotonicDate()

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw SignalAttachmentError.couldNotConvertToMpeg4
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()

        if let sessionCallback {
            sessionCallback(exportSession)
        }

        let exportURL = OWSFileSystem.temporaryFileUrl(fileExtension: "mp4", isAvailableWhileDeviceLocked: false)

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
        Logger.info("transcoded video in \(formattedDuration)s (preset: \(presetName))")

        return try videoAttachment(dataSource: dataSource, dataUTI: UTType.mpeg4Movie.identifier, attachmentLimits: attachmentLimits)
    }

    // MARK: Video Quality

    /// An `AVAssetExportSession` preset paired with a conservative estimate
    /// of the bitrate of the file it produces.
    struct VideoExportTier {
        let presetName: String

        /// Estimated size of the exported output, in bytes per second of
        /// video (video and audio combined). Deliberately conservative
        /// (higher than typical output) so that tiers are only skipped when
        /// their output would very likely exceed the attachment size limit.
        /// Exported files are always re-validated against the size limit.
        let estimatedBytesPerSecond: UInt64
    }

    /// The quality tiers to attempt when compressing a video, from highest
    /// to lowest quality.
    ///
    /// Which tiers are offered depends on the user's "Sent Media Quality"
    /// preference: standard quality exports at up to 720p and high quality
    /// at up to 1080p. (Previously, all videos were crushed to 640x480,
    /// regardless of the preference.) Tiers whose estimated output size
    /// exceeds `maxFileSize` are omitted, unless no lower tier remains.
    static func videoExportTiers(
        forQualityLevel qualityLevel: ImageQualityLevel,
        videoDuration: CMTime,
        maxFileSize: UInt64,
    ) -> [VideoExportTier] {
        let tiers: [VideoExportTier]
        switch qualityLevel {
        case .one:
            // Matches the historical behavior (640x480) for reduced-quality
            // contexts (app extensions, regions with lowered standard quality).
            tiers = [
                VideoExportTier(presetName: AVAssetExportPreset640x480, estimatedBytesPerSecond: 160_000),
            ]
        case .two:
            tiers = [
                VideoExportTier(presetName: AVAssetExportPreset1280x720, estimatedBytesPerSecond: 640_000),
                VideoExportTier(presetName: AVAssetExportPreset960x540, estimatedBytesPerSecond: 320_000),
                VideoExportTier(presetName: AVAssetExportPreset640x480, estimatedBytesPerSecond: 160_000),
            ]
        case .three:
            tiers = [
                VideoExportTier(presetName: AVAssetExportPreset1920x1080, estimatedBytesPerSecond: 1_280_000),
                VideoExportTier(presetName: AVAssetExportPreset1280x720, estimatedBytesPerSecond: 640_000),
                VideoExportTier(presetName: AVAssetExportPreset960x540, estimatedBytesPerSecond: 320_000),
                VideoExportTier(presetName: AVAssetExportPreset640x480, estimatedBytesPerSecond: 160_000),
            ]
        }

        let durationSeconds = CMTimeGetSeconds(videoDuration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return tiers
        }

        // Skip tiers whose estimated output size exceeds the limit, but
        // never drop the last tier: it serves as the last resort, and its
        // output is validated against the limit after export.
        var result = tiers
        while
            result.count > 1,
            let firstTier = result.first,
            UInt64(durationSeconds).multipliedReportingOverflow(by: firstTier.estimatedBytesPerSecond).partialValue > maxFileSize
        {
            result.removeFirst()
        }
        return result
    }

    // MARK: Audio Attachments

    // Factory method for audio attachments.
    public static func audioAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SignalAttachmentError) -> Self {
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: SignalAttachment.audioUTISet,
            maxFileSize: attachmentLimits.maxPlaintextAudioBytes,
        )
    }

    // MARK: Generic Attachments

    // Factory method for generic attachments.
    public static func genericAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SignalAttachmentError) -> Self {
        // [15M] TODO: Enforce this at compile-time rather than runtime.
        owsPrecondition(!SignalAttachment.videoUTISet.contains(dataUTI))
        owsPrecondition(!SignalAttachment.inputImageUTISet.contains(dataUTI))
        return try newAttachment(
            dataSource: dataSource,
            dataUTI: dataUTI,
            validUTISet: nil,
            maxFileSize: attachmentLimits.maxPlaintextBytes,
        )
    }

    // MARK: Voice Messages

    public static func voiceMessageAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
    ) throws(SignalAttachmentError) -> Self {
        let attachment = try audioAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        attachment.rawValue.isVoiceMessage = true
        return attachment
    }

    // MARK: Attachments

    public struct AttachmentTypes: OptionSet {
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
        ofTypes types: AttachmentTypes = .all,
        dataSource: DataSourcePath,
        dataUTI: String,
        attachmentLimits: OutgoingAttachmentLimits,
        options: BuildOptions = [],
    ) throws -> Self {
        if SignalAttachment.inputImageUTISet.contains(dataUTI) {
            guard types.contains(.image) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try imageAttachment(dataSource: dataSource, dataUTI: dataUTI)
        }
        if SignalAttachment.videoUTISet.contains(dataUTI) {
            guard types.contains(.video) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try videoAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        }
        if SignalAttachment.audioUTISet.contains(dataUTI) {
            guard types.contains(.audio) else {
                throw SignalAttachmentError.invalidFileFormat
            }
            return try audioAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
        }
        guard types.contains(.other) else {
            throw SignalAttachmentError.invalidFileFormat
        }
        return try genericAttachment(dataSource: dataSource, dataUTI: dataUTI, attachmentLimits: attachmentLimits)
    }

    // MARK: Helper Methods

    private static func newAttachment(
        dataSource: DataSourcePath,
        dataUTI: String,
        validUTISet: Set<String>?,
        maxFileSize: UInt64,
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
        return Self(rawValue: attachment, attachmentType: .other)
    }
}
