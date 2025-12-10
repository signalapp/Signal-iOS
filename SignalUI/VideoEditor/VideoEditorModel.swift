//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit

protocol VideoEditorModelObserver: AnyObject {
    func videoEditorModelDidChange(_ model: VideoEditorModel)
}

// MARK: -

// Should be @MainActor.
class VideoEditorModel: NSObject {

    let srcVideoPath: String

    let untrimmedDuration: CMTime

    var untrimmedDurationSeconds: TimeInterval {
        return untrimmedDuration.seconds
    }

    var trimmedDurationSeconds: TimeInterval {
        return max(0, trimmedEndSeconds - trimmedStartSeconds)
    }

    private(set) var trimmedStartSeconds: TimeInterval = 0

    private(set) var trimmedEndSeconds: TimeInterval = 0

    let naturalSize: CGSize

    let displaySize: CGSize

    static let minimumDurationSeconds: TimeInterval = 1

    private var minimumDurationSeconds: TimeInterval {
        return VideoEditorModel.minimumDurationSeconds
    }

    var canBeTrimmed: Bool {
        return untrimmedDurationSeconds > minimumDurationSeconds
    }

    var isTrimmed: Bool {
        return trimmedStartSeconds > 0 || trimmedEndSeconds < untrimmedDurationSeconds
    }

    // We don't want to allow editing of videos if:
    //
    // * They are invalid.
    // * We can't determine their size / aspect-ratio.
    init?(_ attachment: PreviewableAttachment) throws {
        guard attachment.rawValue.isVideo, !attachment.rawValue.isLoopingVideo else {
            return nil
        }
        let mediaUrl = attachment.rawValue.dataSource.fileUrl
        self.srcVideoPath = mediaUrl.path

        let asset = AVURLAsset(url: mediaUrl)

        let duration: CMTime = asset.duration
        guard duration.seconds > 0 else {
            throw OWSAssertionError("Invalid duration: \(duration).")
        }

        let videoTracks = asset.tracks(withMediaType: .video)
        guard let firstVideoTrack: AVAssetTrack = videoTracks.first else {
            throw OWSAssertionError("Missing video track.")
        }

        let naturalSize: CGSize = firstVideoTrack.naturalSize
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            throw OWSAssertionError("Invalid naturalSize: \(naturalSize).")
        }
        let preferredTransform: CGAffineTransform = firstVideoTrack.preferredTransform
        let displaySize = naturalSize.applying(preferredTransform).abs
        guard displaySize.width > 0, displaySize.height > 0 else {
            throw OWSAssertionError("Invalid displaySize: \(displaySize).")
        }

        guard
            asset.isPlayable,
            asset.isExportable,
            asset.isReadable,
            !asset.hasProtectedContent
        else {
            throw OWSAssertionError("Invalid content.")
        }

        self.untrimmedDuration = duration
        self.naturalSize = naturalSize
        self.displaySize = displaySize
        self.trimmedStartSeconds = 0
        self.trimmedEndSeconds = duration.seconds

        super.init()
    }

    func trimToStartSeconds(_ value: TimeInterval) {
        // Ensure:
        //
        // * Trimmed start > 0
        // * Trimmed start < video duration - minimum duration
        // * Trimmed start < trimmed end - minimum duration
        let minValue: TimeInterval = 0
        let maxValue: TimeInterval = min(untrimmedDurationSeconds, trimmedEndSeconds) - minimumDurationSeconds
        trimmedStartSeconds = max(minValue, min(maxValue, value))

        fireModelDidChange()
    }

    func trimToEndSeconds(_ value: TimeInterval) {
        // Ensure:
        //
        // * Trimmed end > 0 + minimum duration
        // * Trimmed end > trimmed start + minimum duration
        // * Trimmed end < video duration
        let minValue: TimeInterval = max(0, trimmedStartSeconds) + minimumDurationSeconds
        let maxValue: TimeInterval = untrimmedDurationSeconds
        trimmedEndSeconds = max(minValue, min(maxValue, value))

        fireModelDidChange()
    }

    // MARK: - Observers

    private var observers = [Weak<VideoEditorModelObserver>]()

    func add(observer: VideoEditorModelObserver) {
        observers.append(Weak(value: observer))
    }

    private func fireModelDidChange() {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.videoEditorModelDidChange(self)
        }
    }

    // MARK: - Rendering

    var needsRender: Bool { isTrimmed }

    @MainActor
    func render() async throws -> URL {
        owsPrecondition(self.needsRender)

        let startTime = MonotonicDate()

        let asset = AVURLAsset(url: URL(fileURLWithPath: self.srcVideoPath))
        let exportUrl = OWSFileSystem.temporaryFileUrl(fileExtension: "mp4")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw OWSAssertionError("couldn't create export session")
        }

        // This will ensure that the MP4 moov atom (movie atom)
        // is located at the beginning of the file. That may help
        // recipients validate incoming videos.
        session.shouldOptimizeForNetworkUse = true
        // Preserve the original timescale.
        let cmStart: CMTime = CMTime(seconds: self.trimmedStartSeconds, preferredTimescale: self.untrimmedDuration.timescale)
        let cmDuration: CMTime = CMTime(seconds: self.trimmedDurationSeconds, preferredTimescale: self.untrimmedDuration.timescale)
        let cmRange: CMTimeRange = CMTimeRange(start: cmStart, duration: cmDuration)
        session.timeRange = cmRange

        try await session.exportAsync(to: exportUrl, as: .mp4)

        let endTime = MonotonicDate()
        let formattedDuration = OWSOperation.formattedNs((endTime - startTime).nanoseconds)
        Logger.info("trimmed video in \(formattedDuration)s")

        switch session.status {
        case .completed:
            return exportUrl
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? OWSAssertionError("status \(session.status)")
        }
    }
}
