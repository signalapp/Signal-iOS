//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import AVFoundation
import PromiseKit

@objc
public protocol VideoEditorModelObserver: class {
    func videoEditorModelDidChange(_ model: VideoEditorModel)
}

// MARK: -

@objc
public class VideoEditorModel: NSObject {

    @objc
    public let srcVideoPath: String

    @objc
    public let untrimmedDuration: CMTime

    @objc
    public var untrimmedDurationSeconds: TimeInterval {
        return untrimmedDuration.seconds
    }

    @objc
    public var trimmedDurationSeconds: TimeInterval {
        return max(0, trimmedEndSeconds - trimmedStartSeconds)
    }

    @objc
    public private(set) var trimmedStartSeconds: TimeInterval = 0

    @objc
    public private(set) var trimmedEndSeconds: TimeInterval = 0

    @objc
    public let naturalSize: CGSize

    @objc
    public let displaySize: CGSize

    @objc
    public static let minimumDurationSeconds: TimeInterval = 1

    private var minimumDurationSeconds: TimeInterval {
        return VideoEditorModel.minimumDurationSeconds
    }

    @objc
    public var canBeTrimmed: Bool {
        return untrimmedDurationSeconds > minimumDurationSeconds
    }

    @objc
    public var isTrimmed: Bool {
        return trimmedStartSeconds > 0 || trimmedEndSeconds < untrimmedDurationSeconds
    }

    // We don't want to allow editing of videos if:
    //
    // * They are invalid.
    // * We can't determine their size / aspect-ratio.
    public init(srcVideoPath: String) throws {
        self.srcVideoPath = srcVideoPath

        guard OWSMediaUtils.isValidVideo(path: srcVideoPath) else {
            throw OWSAssertionError("Invalid video content type or size.")
        }

        let mediaUrl = URL(fileURLWithPath: srcVideoPath)
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

        guard asset.isPlayable,
            asset.isExportable,
            asset.isReadable,
            !asset.hasProtectedContent else {
                throw OWSAssertionError("Invalid content.")
        }

        self.untrimmedDuration = duration
        self.naturalSize = naturalSize
        self.displaySize = displaySize
        self.trimmedStartSeconds = 0
        self.trimmedEndSeconds = duration.seconds

        super.init()
    }

    @objc
    public func trimToStartSeconds(_ value: TimeInterval) {
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

    @objc
    public func trimToEndSeconds(_ value: TimeInterval) {
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

    @objc
    public func add(observer: VideoEditorModelObserver) {
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

    public func exportOutput() -> Promise<String> {
        assert(isTrimmed)

        let asset = AVURLAsset(url: URL(fileURLWithPath: srcVideoPath))

        // AVAssetExportPresetPassthrough maintains the source quality.
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return Promise(error: OWSAssertionError("Could not create export session."))
        }

        let dstFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: "mp4")
        exportSession.outputURL = URL(fileURLWithPath: dstFilePath)
        // This will ensure that the MP4 moov atom (movie atom)
        // is located at the beginning of the file. That may help
        // recipients validate incoming videos.
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.outputFileType = AVFileType.mp4
        // Preserve the original timescale.
        let cmStart: CMTime = CMTime(seconds: trimmedStartSeconds, preferredTimescale: untrimmedDuration.timescale)
        let cmDuration: CMTime = CMTime(seconds: trimmedDurationSeconds, preferredTimescale: untrimmedDuration.timescale)
        let cmRange: CMTimeRange = CMTimeRange(start: cmStart, duration: cmDuration)
        exportSession.timeRange = cmRange

        let (promise, resolver) = Promise<String>.pending()
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                resolver.fulfill(dstFilePath)
            default:
                resolver.reject(OWSAssertionError("Status: \(exportSession.status)"))
            }
        }
        return promise
    }
}
