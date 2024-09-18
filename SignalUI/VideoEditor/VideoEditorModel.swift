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

class VideoEditorModel: NSObject {

    private let lock = UnfairLock()

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
    init(srcVideoPath: String) throws {
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

    func trimToStartSeconds(_ value: TimeInterval) {
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

    func trimToEndSeconds(_ value: TimeInterval) {
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
    fileprivate var currentRender: Render?

    // Whenever the model state changes, we need to discard any ongoing render.
    private func clearRender() {
        lock.withLock {
            currentRender?.cancel()
            currentRender = nil
        }
    }

    // This method can be used to access the rendered output.
    func ensureCurrentRender() -> Render {
        return lock.withLock {
            if let render = self.currentRender {
                return render
            } else {
                let render = Render(model: self)
                self.currentRender = render
                return render
            }
        }
    }
}

extension VideoEditorModel {
    // Represents an attempt to render the output.
    // Contains a copy of the model state at the
    // time the render is enqueued.
    class Render {
        private enum ExportState {
            case ready
            case exporting(Task<Result, any Error>)
            case failed(any Error)
            case finished(Result)

            mutating func cancel() -> Task<Result, any Error>? {
                switch self {
                case .exporting(let task):
                    self = .ready
                    return task
                case .ready, .failed, .finished:
                    return nil
                }
            }
        }

        fileprivate let srcVideoPath: String
        fileprivate let untrimmedDuration: CMTime
        fileprivate let trimmedStartSeconds: TimeInterval
        fileprivate let trimmedDurationSeconds: TimeInterval
        fileprivate let isTrimmed: Bool

        // Until the render is consumed, it is the responsibility of this
        // class to clean up its temp files.
        private var lock = UnfairLock()
        private var exportState = ExportState.ready

        class Result {
            private let lock = UnfairLock()
            private let path: String

            // While the Result owns the resulting file, it is its responsibility to clean
            // it up on deinit. Ownership can be relinquished to a caller of consumeResultPath()
            private var isOwned = false

            fileprivate init(path: String, owned: Bool = true) {
                self.path = path
                self.isOwned = owned
            }

            deinit {
                guard isOwned else { return }

                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }

            /// Returns an unowned reference to the render output file. This path is valid as long as the `Result`
            /// is valid and file has not been consumed by `consumeResultPath()`. Caller should make a copy
            /// of this file if they'd like the render result to outlive these events.
            func getResultPath() -> String {
                lock.withLock {
                    // Something else has already taken ownership of this file
                    // It's probably still valid, but worth flagging as an issue.
                    owsAssertDebug(isOwned, "Result file externally owned")
                }
                return path
            }

            /// Returns a path to the render result. Receiver is responsible for deleting the resulting file
            /// This should be called once at most
            func consumeResultPath() throws -> String {
                // Since the path is being consumed, we no longer own it.
                // If we didn't already own it, we should make a copy of the unowned filepath
                // It's incorrect and worthy of a failDebug, but it's also probably still valid.
                // In that case, we make a copy so that the receiver can take ownership
                let shouldCopy: Bool = lock.withLock {
                    owsAssertDebug(isOwned, "Result file externally owned")
                    let wasAlreadyOwned = isOwned
                    isOwned = false
                    return !wasAlreadyOwned
                }

                if shouldCopy {
                    let dstFilePath = OWSFileSystem.temporaryFilePath(fileExtension: "mp4")
                    try FileManager.default.copyItem(atPath: path, toPath: dstFilePath)
                    return dstFilePath
                } else {
                    return path
                }
            }
        }

        init(model: VideoEditorModel) {
            self.srcVideoPath = model.srcVideoPath
            self.untrimmedDuration = model.untrimmedDuration
            self.trimmedStartSeconds = model.trimmedStartSeconds
            self.trimmedDurationSeconds = model.trimmedDurationSeconds
            self.isTrimmed = model.isTrimmed
        }

        func render() async throws -> Result {
            enum CurrentExport {
                case exporting(Task<Result, any Error>)
                case finished(Swift.Result<Result, any Error>)

                var result: Result {
                    get async throws {
                        switch self {
                        case .exporting(let task):
                            return try await task.value
                        case .finished(let result):
                            return try result.get()
                        }
                    }
                }
            }

            let export = lock.withLock { () -> CurrentExport in
                switch exportState {
                case .finished(let result):
                    return .finished(.success(result))
                case .exporting(let task):
                    return .exporting(task)
                case .failed(let error):
                    return .finished(.failure(error))
                case .ready:
                    break
                }

                let task = Task {
                    do {
                        let result = try await _render()
                        lock.withLock { exportState = .finished(result) }
                        return result
                    } catch let error as CancellationError {
                        lock.withLock { exportState = .ready }
                        throw error
                    } catch {
                        owsFailDebug("Export failed: \(error)")
                        lock.withLock { exportState = .failed(error) }
                        throw error
                    }
                }
                self.exportState = .exporting(task)
                return .exporting(task)
            }

            return try await export.result
        }

        nonisolated private func _render() async throws -> Result {
            guard isTrimmed else {
                // Video editor has no changes.
                owsFailDebug("calling no-op render. Instead copy the file.")

                // Since we haven't trimmed, there's nothing to render. Callers shouldn't get here, but
                // just in case we'll return an unowned Result. The implementation of Result ensures that
                // a new copy of the srcVideoPath is made for any consume requests to maintain the ownership contract.
                return Result(path: srcVideoPath, owned: false)
            }

            let asset = AVURLAsset(url: URL(fileURLWithPath: self.srcVideoPath))
            let dstFilePath = OWSFileSystem.temporaryFilePath(fileExtension: "mp4")

            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw OWSAssertionError("Could not create export session.")
            }

            let exportURL = URL(fileURLWithPath: dstFilePath)

            // This will ensure that the MP4 moov atom (movie atom)
            // is located at the beginning of the file. That may help
            // recipients validate incoming videos.
            session.shouldOptimizeForNetworkUse = true
            // Preserve the original timescale.
            let cmStart: CMTime = CMTime(seconds: self.trimmedStartSeconds, preferredTimescale: self.untrimmedDuration.timescale)
            let cmDuration: CMTime = CMTime(seconds: self.trimmedDurationSeconds, preferredTimescale: self.untrimmedDuration.timescale)
            let cmRange: CMTimeRange = CMTimeRange(start: cmStart, duration: cmDuration)
            session.timeRange = cmRange

            try await session.exportAsync(to: exportURL, as: .mp4)

            switch (session.status, session.outputURL?.path) {
            case (.completed, let path?):
                return Result(path: path, owned: true)
            case (.cancelled, _):
                throw CancellationError()
            default:
                throw session.error ?? OWSAssertionError("Status \(session.status)")
            }
        }

        func cancel() {
            let currentExport = lock.withLock { exportState.cancel() }
            currentExport?.cancel()
        }
    }
}
