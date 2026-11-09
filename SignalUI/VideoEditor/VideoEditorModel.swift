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

    let normalizedVideo: NormalizedVideo

    var srcVideoPath: String {
        return normalizedVideo.dataSource.fileUrl.path
    }

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
    init(normalizedVideo: NormalizedVideo) throws {
        self.normalizedVideo = normalizedVideo

        let asset = normalizedVideo.sourceAsset

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

    // MARK: - Editing

    var isEdited: Bool { isTrimmed }

    /// The source video with all edits applied.
    @MainActor
    func editedAsset() async throws -> AVAsset {
        let source = self.normalizedVideo.sourceAsset

        // Preserve the original timescale.
        let timescale = self.untrimmedDuration.timescale
        let timeRange = CMTimeRange(
            start: CMTime(seconds: self.trimmedStartSeconds, preferredTimescale: timescale),
            duration: CMTime(seconds: self.trimmedDurationSeconds, preferredTimescale: timescale),
        )

        let composition = AVMutableComposition()
        let videoTracks = try await source.loadTracks(withMediaType: .video)
        let audioTracks = try await source.loadTracks(withMediaType: .audio)
        let sourceTracks = videoTracks + audioTracks
        for sourceTrack in sourceTracks {
            guard
                let track = composition.addMutableTrack(
                    withMediaType: sourceTrack.mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid,
                )
            else {
                throw OWSAssertionError("couldn't add composition track")
            }
            try track.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
            let (transform, naturalTimeScale) = try await sourceTrack.load(
                .preferredTransform,
                .naturalTimeScale,
            )
            track.preferredTransform = transform
            track.naturalTimeScale = naturalTimeScale
        }
        return composition
    }
}
