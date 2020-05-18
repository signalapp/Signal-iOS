//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import AVFoundation
import PromiseKit

public enum VideoEditorError: Error {
    case cancelled
}

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

        clearRender()

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

        clearRender()

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

    // MARK: - Rendering

    // Represents an attempt to render the output.
    // Contains a copy of the model state at the
    // time the render is enqueued.
    public class Render {
        fileprivate let srcVideoPath: String
        fileprivate let untrimmedDuration: CMTime
        fileprivate let trimmedStartSeconds: TimeInterval
        fileprivate let trimmedDurationSeconds: TimeInterval
        fileprivate let isTrimmed: Bool

        fileprivate let promise: Promise<String>
        fileprivate let resolver: Resolver<String>

        // This property should only be accessed on VideoEditorModel.serialQueue.
        private var exportSession: AVAssetExportSession?

        // Until the render is consumed, it is the responsibility of this
        // class to clean up its temp files.
        private let isConsumed = AtomicBool(false)

        required init(model: VideoEditorModel) {
            self.srcVideoPath = model.srcVideoPath
            self.untrimmedDuration = model.untrimmedDuration
            self.trimmedStartSeconds = model.trimmedStartSeconds
            self.trimmedDurationSeconds = model.trimmedDurationSeconds
            self.isTrimmed = model.isTrimmed

            let (promise, resolver) = Promise<String>.pending()
            self.promise = promise
            self.resolver = resolver
        }

        deinit {
            guard !isConsumed.get() else {
                return
            }

            promise.done(on: DispatchQueue.global()) { filePath in
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: filePath))
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }

        // consumableFilePromise

        // Returns a promise that yields a file path
        // for the output video file path.  The caller
        // has responsibility for cleaning up this file.
        public func consumingFilePromise() -> Promise<String> {
            if isConsumed.get() {
                owsFailDebug("File is already consumed.")
            }
            isConsumed.set(true)
            return promise
        }

        // Returns a promise that yields a file path
        // for the output video file path.  The caller
        // does not have responsibility for cleaning up this file.
        public func nonconsumingFilePromise() -> Promise<String> {
            if isConsumed.get() {
                owsFailDebug("File is already consumed.")
            }
            return promise
        }

        fileprivate func set(exportSession: AVAssetExportSession) {
            assertOnQueue(VideoEditorModel.serialQueue)

            self.exportSession = exportSession
        }

        // This method should only be accessed on VideoEditorModel.serialQueue.
        fileprivate func cancel() {
            assertOnQueue(VideoEditorModel.serialQueue)

            guard let exportSession = self.exportSession else {
                return
            }
            exportSession.cancelExport()
        }
    }

    fileprivate static let serialQueue: DispatchQueue = DispatchQueue(label: "VideoEditorModel.serialQueue")
    // This property should only be accessed on serialQueue.
    fileprivate var currentRender: Render?
    // This operation queue ensures that only one render operation is
    // running at a given time.
    private static let renderOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "VideoEditorModel.renderOperationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    // Whenever the model state changes, we need to discard any ongoing render.
    private func clearRender() {
        VideoEditorModel.serialQueue.sync {
            guard let render = self.currentRender else {
                return
            }
            render.cancel()
            self.currentRender = nil
        }
    }

    // This method can be used to access the rendered output.
    // It can also be used to eagerly initiate a render (if
    // necessary) to reduce perceived render time.
    public func ensureCurrentRender() -> Render {
        return VideoEditorModel.serialQueue.sync {
            if let currentRender = self.currentRender {
                return currentRender
            }
            let render = Render(model: self)
            self.currentRender = render

            // Enqueue an operation to process the render.
            let operationQueue = VideoEditorModel.renderOperationQueue
            let operation = TrimVideoOperation(model: self, render: render)
            operationQueue.addOperation(operation)

            return render
        }
    }
}

// MARK: -

private class TrimVideoOperation: OWSOperation {

    private let model: VideoEditorModel
    private let render: VideoEditorModel.Render

    fileprivate required init(model: VideoEditorModel,
                              render: VideoEditorModel.Render) {
        self.model = model
        self.render = render
    }

    public override func run() {
        Logger.debug("")

        let (promise, resolver) = Promise<String>.pending()
        DispatchQueue.global().async {
            let currentRender = VideoEditorModel.serialQueue.sync {
                return self.model.currentRender
            }
            guard self.render === currentRender else {
                // Renders can take quite a while, so it's important to skip
                // renders that are no longer necessary.
                resolver.reject(OWSAssertionError("Skipping stale render."))
                return
            }
            let render = self.render
            guard render.isTrimmed else {
                // Video editor has no changes.
                owsFailDebug("calling no-op render. Instead copy the file.")
                // When rendering a new file, the caller is given a URL that they "own" - that is the
                // caller can then `consume` it, and must delete on deallocation if they don't.
                //
                // However here we return the existing URL, which violates that contract - two entities
                // now own the original file. In practice, I think we're no longer hitting this code
                // path, but I'm leaving this here for resiliency.
                resolver.fulfill(render.srcVideoPath)
                return
            }

            let asset = AVURLAsset(url: URL(fileURLWithPath: render.srcVideoPath))
            let dstFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: "mp4")

            // AVAssetExportPresetPassthrough maintains the source quality.
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                resolver.reject(OWSAssertionError("Could not create export session."))
                return
            }
            VideoEditorModel.serialQueue.sync {
                render.set(exportSession: exportSession)
            }

            exportSession.outputURL = URL(fileURLWithPath: dstFilePath)
            // This will ensure that the MP4 moov atom (movie atom)
            // is located at the beginning of the file. That may help
            // recipients validate incoming videos.
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.outputFileType = AVFileType.mp4
            // Preserve the original timescale.
            let cmStart: CMTime = CMTime(seconds: render.trimmedStartSeconds, preferredTimescale: render.untrimmedDuration.timescale)
            let cmDuration: CMTime = CMTime(seconds: render.trimmedDurationSeconds, preferredTimescale: render.untrimmedDuration.timescale)
            let cmRange: CMTimeRange = CMTimeRange(start: cmStart, duration: cmDuration)
            exportSession.timeRange = cmRange

            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    resolver.fulfill(dstFilePath)
                case .cancelled:
                    resolver.reject(VideoEditorError.cancelled)
                default:
                    resolver.reject(OWSAssertionError("Status: \(exportSession.status)"))
                }
            }
        }
        promise.done { filePath in
            self.render.resolver.fulfill(filePath)
            self.reportSuccess()
        }.catch { error in
            if case VideoEditorError.cancelled = error {
                // operation was cancelled - this is normal.
            } else {
                owsFailDebug("Error: \(error)")
            }
            self.render.resolver.reject(error)
            VideoEditorModel.serialQueue.sync {
                // Discard failed render.
                if self.model.currentRender === self.render {
                    self.model.currentRender = nil
                }
            }
            self.reportError(withUndefinedRetry: error)
        }
    }
}
