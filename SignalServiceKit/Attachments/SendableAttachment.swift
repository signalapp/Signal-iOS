//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment that's fully valid and ready to send.
///
/// See also ``PreviewableAttachment``.
///
/// These are attachments that have been fully processed and are ready to
/// send as-is. The bytes representing these attachments meet the criteria
/// for sending via Signal.
public struct SendableAttachment {
    private let rawValue: SignalAttachment

    private init(rawValue: SignalAttachment) {
        self.rawValue = rawValue
    }

    @concurrent
    public static func forPreviewableAttachment(
        _ previewableAttachment: PreviewableAttachment,
        imageQuality: ImageQualityLevel? = nil,
    ) async throws(SignalAttachmentError) -> Self {
        // We only bother converting/compressing non-animated images
        if let imageQuality, previewableAttachment.isImage, !previewableAttachment.rawValue.isAnimatedImage {
            let dataSource = previewableAttachment.rawValue.dataSource
            guard let imageMetadata = try? dataSource.imageSource().imageMetadata(ignorePerTypeFileSizeLimits: true) else {
                throw .invalidData
            }
            let isValidOriginal = SignalAttachment.isOriginalImageValid(
                forImageQuality: imageQuality,
                fileSize: UInt64(safeCast: dataSource.dataLength),
                dataUTI: previewableAttachment.rawValue.dataUTI,
                imageMetadata: imageMetadata,
            )
            if !isValidOriginal {
                return SendableAttachment(
                    rawValue: try SignalAttachment.convertAndCompressImage(
                        toImageQuality: imageQuality,
                        dataSource: dataSource,
                        attachment: previewableAttachment.rawValue,
                        imageMetadata: imageMetadata,
                    ),
                )
            }
        }
        return Self(rawValue: previewableAttachment.rawValue)
    }

    public var mimeType: String { self.rawValue.mimeType }
    public var renderingFlag: AttachmentReference.RenderingFlag { self.rawValue.renderingFlag }
    public var sourceFilename: FilteredFilename? {
        return self.rawValue.dataSource.sourceFilename.map(FilteredFilename.init(rawValue:))
    }

    public var dataSource: any DataSource { self.rawValue.dataSource }

    public func buildAttachmentDataSource(attachmentContentValidator: any AttachmentContentValidator) async throws -> AttachmentDataSource {
        return try await attachmentContentValidator.validateContents(
            dataSource: rawValue.dataSource,
            shouldConsume: true,
            mimeType: mimeType,
            renderingFlag: renderingFlag,
            sourceFilename: filenameOrDefault,
        )
    }

    /// The user-provided filename, if known. Otherwise, we'll generate a
    /// filename similar to "signal-2017-04-24-095918.zip".
    private var filenameOrDefault: String {
        if let sourceFilename {
            return sourceFilename.rawValue
        } else {
            let kDefaultAttachmentName = "signal"

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let dateString = dateFormatter.string(from: Date())

            var defaultFilename = "\(kDefaultAttachmentName)-\(dateString)"
            if let fileExtension = MimeTypeUtil.fileExtensionForUtiType(self.rawValue.dataUTI) {
                defaultFilename += ".\(fileExtension)"
            }
            return defaultFilename
        }
    }

    // MARK: - Video Segmenting

    public struct SegmentAttachmentResult {
        public let original: SendableAttachment
        public let segmented: [SendableAttachment]?

        public init(_ original: SendableAttachment, segmented: [SendableAttachment]? = nil) {
            assert(segmented?.isEmpty != true)
            self.original = original
            self.segmented = segmented
        }
    }

    /// If the attachment is a video longer than `storyVideoSegmentMaxDuration`,
    /// segments into separate attachments under that duration.
    /// Otherwise returns a result with only the original and nil segmented attachments.
    public func segmentedIfNecessary(segmentDuration: TimeInterval) async throws -> SegmentAttachmentResult {
        guard let dataSource = self.rawValue.dataSourceIfVideo else {
            return SegmentAttachmentResult(self, segmented: nil)
        }

        let asset = AVURLAsset(url: dataSource.fileUrl)
        let cmDuration = asset.duration
        let duration = cmDuration.seconds
        guard duration > segmentDuration else {
            // No need to segment, we are done.
            return SegmentAttachmentResult(self, segmented: nil)
        }

        let dataUTI = self.rawValue.dataUTI

        var startTime: TimeInterval = 0
        var segmentFileUrls = [URL]()
        while startTime < duration {
            segmentFileUrls.append(try await Self.trimAsset(
                asset,
                from: startTime,
                duration: segmentDuration,
                totalDuration: cmDuration
            ))
            startTime += segmentDuration
        }
        let segments = try segmentFileUrls.map { url in
            return try SendableAttachment(rawValue: SignalAttachment.videoAttachment(
                dataSource: try DataSourcePath(
                    fileUrl: url,
                    shouldDeleteOnDeallocation: true
                ),
                dataUTI: dataUTI
            ))
        }
        return SegmentAttachmentResult(self, segmented: segments)
    }

    fileprivate static func trimAsset(
        _ asset: AVURLAsset,
        from startTime: TimeInterval,
        duration: TimeInterval,
        totalDuration: CMTime
    ) async throws -> URL {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw OWSAssertionError("Failed to start export session for segmentation")
        }

        // tmp url is ok, it gets moved when converted to a Attachment later anyway.
        let outputUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: asset.url.pathExtension,
            isAvailableWhileDeviceLocked: true
        )
        exportSession.outputURL = outputUrl
        /// This is hardcoded here and in our media editor. That's in signalUI, so hard to link the two.
        exportSession.outputFileType = AVFileType.mp4
        // Puts file metadata in the right place for streaming validation.
        exportSession.shouldOptimizeForNetworkUse = true

        let cmStart = CMTime(seconds: startTime, preferredTimescale: totalDuration.timescale)
        let endTime = min(startTime + duration, totalDuration.seconds)
        let cmEnd = CMTime(seconds: endTime, preferredTimescale: totalDuration.timescale)
        exportSession.timeRange = CMTimeRange(start: cmStart, end: cmEnd)

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputUrl
        case .cancelled, .failed:
            throw OWSAssertionError("Video segmentation export session failed")
        case .unknown, .waiting, .exporting:
            fallthrough
        @unknown default:
            throw OWSAssertionError("Video segmentation failed with unknown status: \(exportSession.status)")
        }
    }
}
