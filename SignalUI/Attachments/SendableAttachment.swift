//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
public import SignalServiceKit

/// Represents an attachment that's fully valid and ready to send.
///
/// See also ``PreviewableAttachment``.
///
/// These are attachments that have been fully processed and are ready to
/// send as-is. The bytes representing these attachments meet the criteria
/// for sending via Signal.
public struct SendableAttachment {
    public let dataSource: DataSourcePath
    public let dataUTI: String
    public let sourceFilename: FilteredFilename?
    public let mimeType: String
    public let renderingFlag: AttachmentReference.RenderingFlag

    private init(
        dataSource: DataSourcePath,
        dataUTI: String,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
    ) {
        self.dataSource = dataSource
        self.dataUTI = dataUTI
        self.sourceFilename = dataSource.sourceFilename.map(FilteredFilename.init(rawValue:))
        self.mimeType = mimeType
        self.renderingFlag = renderingFlag
    }

    private init(nonImagePreviewableAttachment previewableAttachment: PreviewableAttachment) {
        self.init(
            dataSource: previewableAttachment.dataSource,
            dataUTI: previewableAttachment.dataUTI,
            mimeType: previewableAttachment.mimeType,
            renderingFlag: previewableAttachment.renderingFlag,
        )
    }

    @concurrent
    public static func forPreviewableAttachment(
        _ attachment: PreviewableAttachment,
        imageQualityLevel: ImageQualityLevel,
    ) async throws -> Self {
        switch attachment.attachmentType {
        case .animatedImage where attachment.dataUTI == UTType.png.identifier:
            let strippedData = try NormalizedImage.removeImageMetadata(fromPngData: attachment.dataSource.readData())
            let dataSource = try DataSourcePath(writingTempFileData: strippedData, fileExtension: "png")
            return SendableAttachment(
                dataSource: dataSource,
                dataUTI: attachment.dataUTI,
                mimeType: attachment.mimeType,
                renderingFlag: attachment.renderingFlag,
            )
        case .animatedImage:
            // Other animated images aren't re-encoded.
            break
        case .image(let normalizedImage):
            let finalizedImage = try normalizedImage.finalizeImage(imageQuality: imageQualityLevel)
            return SendableAttachment(
                dataSource: finalizedImage.dataSource,
                dataUTI: finalizedImage.dataUTI,
                mimeType: MimeTypeUtil.mimeTypeForDataSource(finalizedImage.dataSource, dataUTI: finalizedImage.dataUTI),
                renderingFlag: attachment.renderingFlag,
            )
        case .normalizedVideo:
            throw OWSAssertionError("Videos must be finalized before sending.")
        case .other:
            break
        }
        return Self(nonImagePreviewableAttachment: attachment)
    }

    /// A default filename to use if one isn't provided by the user.
    var defaultFilename: String {
        let kDefaultAttachmentName = "signal"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let dateString = dateFormatter.string(from: Date())

        var defaultFilename = "\(kDefaultAttachmentName)-\(dateString)"
        if let fileExtension = MimeTypeUtil.fileExtensionForUtiType(self.dataUTI) {
            defaultFilename += ".\(fileExtension)"
        }
        return defaultFilename
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
    public func segmentedIfNecessary(
        segmentDuration: TimeInterval,
        attachmentLimits: OutgoingAttachmentLimits,
    ) async throws -> SegmentAttachmentResult {
        guard SignalAttachment.videoUTISet.contains(self.dataUTI) else {
            return SegmentAttachmentResult(self, segmented: nil)
        }
        let asset = AVURLAsset(url: self.dataSource.fileUrl)
        let cmDuration = asset.duration
        let duration = cmDuration.seconds
        guard duration > segmentDuration else {
            // No need to segment, we are done.
            return SegmentAttachmentResult(self, segmented: nil)
        }

        var startTime: TimeInterval = 0
        var segmentFileUrls = [URL]()
        while startTime < duration {
            segmentFileUrls.append(try await Self.trimAsset(
                asset,
                from: startTime,
                duration: segmentDuration,
                totalDuration: cmDuration,
            ))
            startTime += segmentDuration
        }

        let segments = try segmentFileUrls.map { url in
            let dataSource = DataSourcePath(fileUrl: url, ownership: .owned)
            // [15M] TODO: This doesn't transfer all SignalAttachment fields.
            let attachment = try PreviewableAttachment.finalizedVideoAttachment(
                dataSource: dataSource,
                dataUTI: self.dataUTI,
                attachmentLimits: attachmentLimits,
            )
            return Self(nonImagePreviewableAttachment: attachment)
        }
        return SegmentAttachmentResult(self, segmented: segments)
    }

    fileprivate static func trimAsset(
        _ asset: AVURLAsset,
        from startTime: TimeInterval,
        duration: TimeInterval,
        totalDuration: CMTime,
    ) async throws -> URL {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw OWSAssertionError("Failed to start export session for segmentation")
        }

        // tmp url is ok, it gets moved when converted to a Attachment later anyway.
        let outputUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: asset.url.pathExtension,
            isAvailableWhileDeviceLocked: true,
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

    // MARK: - ForSending

    public struct ForSending {
        public let dataSource: AttachmentDataSource
        public let renderingFlag: AttachmentReference.RenderingFlag

        public init(dataSource: AttachmentDataSource, renderingFlag: AttachmentReference.RenderingFlag) {
            self.dataSource = dataSource
            self.renderingFlag = renderingFlag
        }
    }

    public func forSending(attachmentContentValidator: any AttachmentContentValidator) async throws -> ForSending {
        let dataSource = try await attachmentContentValidator.validateSendableAttachmentContents(self, shouldUseDefaultFilename: true)
        return ForSending(
            dataSource: dataSource,
            renderingFlag: self.renderingFlag,
        )
    }
}

extension AttachmentContentValidator {
    public func validateSendableAttachmentContents(
        _ sendableAttachment: SendableAttachment,
        shouldUseDefaultFilename: Bool,
    ) async throws -> AttachmentDataSource {
        let pendingAttachment = try await validateDataSourceContents(
            sendableAttachment.dataSource,
            mimeType: sendableAttachment.mimeType,
            renderingFlag: sendableAttachment.renderingFlag,
            sourceFilename: sendableAttachment.sourceFilename?.rawValue ?? (shouldUseDefaultFilename ? sendableAttachment.defaultFilename : nil),
        )
        return .pendingAttachment(pendingAttachment)
    }
}
