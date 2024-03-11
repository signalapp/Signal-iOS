//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AVFoundation

extension SignalAttachment {

    public struct SegmentAttachmentResult {
        public let original: SignalAttachment
        public let segmented: [SignalAttachment]?

        public init(_ original: SignalAttachment, segmented: [SignalAttachment]? = nil) {
            assert(segmented == nil || !(segmented?.isEmpty ?? true))
            self.original = original
            self.segmented = segmented
        }
    }

    /// If the attachment is a video longer than `storyVideoSegmentMaxDuration`,
    /// segments into separate attachments under that duration.
    /// Otherwise returns a result with only the original and nil segmented attachments.
    public func segmentedIfNecessary(
        on queue: DispatchQueue,
        segmentDuration: TimeInterval
    ) -> Promise<SegmentAttachmentResult> {
        owsAssertDebug(!Thread.isMainThread)

        guard isVideo else { return .value(.init(self, segmented: nil)) }

        // Write to disk  so we can edit with AVKit
        guard
            let url = dataSource.dataUrl,
            url.isFileURL
        else {
            // Nil URL means failure to write to disk.
            // This should almost never happens, but if it does we have to fail
            // because we don't know if the video is too long to send.
            return .init(error: OWSAssertionError("Failed to write video to disk for segmentation"))
        }

        let asset = AVURLAsset(url: url)
        let cmDuration = asset.duration
        let duration = cmDuration.seconds
        guard duration > segmentDuration else {
            // No need to segment, we are done.
            return .value(.init(self, segmented: nil))
        }

        let dataUTI = self.dataUTI

        var startTime: TimeInterval = 0
        var segmentFilePromises = [Promise<URL>]()
        while startTime < duration {
            segmentFilePromises.append(Self.trimAsset(
                asset,
                from: startTime,
                duration: segmentDuration,
                totalDuration: cmDuration
            ))
            startTime += segmentDuration
        }
        return Promise.when(fulfilled: segmentFilePromises)
            .map(on: queue) { (urls: [URL]) -> SegmentAttachmentResult in
                let segments = try urls.map { url in
                    return SignalAttachment.attachment(
                        dataSource: try DataSourcePath.dataSource(
                            with: url,
                            shouldDeleteOnDeallocation: true
                        ),
                        dataUTI: dataUTI
                    )
                }
                return .init(self, segmented: segments)
            }
    }

    fileprivate static func trimAsset(
        _ asset: AVURLAsset,
        from startTime: TimeInterval,
        duration: TimeInterval,
        totalDuration: CMTime
    ) -> Promise<URL> {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return .init(error: OWSAssertionError("Failed to start export session for segmentation"))
        }

        // tmp url is ok, it gets moved when converted to a TSAttachment later anyway.
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

        return Promise { future in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    future.resolve(outputUrl)
                case .cancelled, .failed:
                    future.reject(OWSAssertionError("Video segmentation export session failed"))
                default:
                    future.reject(OWSAssertionError("Video segmentation failed with unknown status: \(exportSession.status)"))
                }
            }
        }
    }
}
