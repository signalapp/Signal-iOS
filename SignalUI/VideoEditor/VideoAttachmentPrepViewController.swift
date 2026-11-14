//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit

protocol VideoPlaybackState {
    var isPlaying: Bool { get }
    var currentTimeSeconds: TimeInterval { get }
}

protocol VideoEditorDataSource: AnyObject {
    var untrimmedDurationSeconds: TimeInterval { get }
    var trimmedStartSeconds: TimeInterval { get }
    var trimmedEndSeconds: TimeInterval { get }
    var canBeTrimmed: Bool { get }
    var isTrimmed: Bool { get }
}

/**
 * Coordinate data transfer between VideoEditorView and VideoTimelineView
 */
class VideoAttachmentPrepViewController: AttachmentPrepViewController, VideoEditorDataSource, VideoEditorModelObserver,
    VideoEditorViewDelegate, VideoPlaybackState, VideoTimelineViewDataSource, VideoTimelineViewDelegate,
    VideoEditorViewControllerProviding
{

    private let model: VideoEditorModel

    private lazy var editorView = VideoEditorView(model: model, delegate: self, dataSource: self, viewControllerProvider: self)

    private lazy var timelineView: VideoTimelineView = {
        let timelineView = VideoTimelineView()
        timelineView.dataSource = self
        timelineView.delegate = self
        return timelineView
    }()

    override init?(attachmentApprovalItem: AttachmentApprovalItem) {
        guard let videoEditorModel = attachmentApprovalItem.videoEditorModel else {
            owsFailDebug("videoEditorModel is empty.")
            return nil
        }

        self.model = videoEditorModel

        super.init(attachmentApprovalItem: attachmentApprovalItem)

        model.add(observer: self)
    }

    override var contentView: UIView {
        editorView
    }

    override var toolbarSupplementaryView: UIView? {
        timelineView
    }

    override func prepareContentView() {
        editorView.hasRoundedCorners = true
        editorView.configureSubviews()
        generateThumbnailsAsync()
    }

    override func prepareToMoveOffscreen() {
        editorView.pauseIfPlaying()
    }

    private(set) var videoThumbnails: [UIImage]?

    private var shouldResumeVideoPlaybackOnScrubbingEnd = false

    // MARK: - VideoEditorViewDelegate

    func videoEditorViewPlaybackTimeDidChange(_ videoEditorView: VideoEditorView) {
        timelineView.updateCursorPosition()
        timelineView.updateTimeBubble()
    }

    // MARK: - VideoEditorDataSource

    var untrimmedDurationSeconds: TimeInterval {
        return model.untrimmedDurationSeconds
    }

    var trimmedStartSeconds: TimeInterval {
        return model.trimmedStartSeconds
    }

    var trimmedEndSeconds: TimeInterval {
        return model.trimmedEndSeconds
    }

    var canBeTrimmed: Bool {
        return model.canBeTrimmed
    }

    var isTrimmed: Bool {
        return model.isTrimmed
    }

    // MARK: - VideoPlaybackState

    var isPlaying: Bool {
        return editorView.isPlaying
    }

    var currentTimeSeconds: TimeInterval {
        return editorView.currentTimeSeconds
    }

    // MARK: - VideoTimelineViewDataSource

    var videoAspectRatio: CGSize {
        return model.displaySize
    }

    private func generateThumbnailsAsync() {
        let model = self.model
        let videoAspectRatio = videoAspectRatio
        let untrimmedDurationSeconds = self.untrimmedDurationSeconds
        let contextSize = CurrentAppContext().frame.size
        let displayScale = traitCollection.displayScale

        Task { [weak self] in
            do {
                let thumbnails = try await VideoAttachmentPrepViewController.thumbnails(
                    forVideoAtPath: model.srcVideoPath,
                    aspectRatio: videoAspectRatio,
                    thumbnailHeight: VideoTimelineView.thumbnailStripHeight,
                    contextSize: contextSize,
                    screenScale: displayScale,
                    untrimmedDurationSeconds: untrimmedDurationSeconds,
                )
                self?.videoThumbnails = thumbnails
                self?.timelineView.updateThumbnailStrip()
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    @concurrent
    private static func thumbnails(
        forVideoAtPath videoPath: String,
        aspectRatio: CGSize,
        thumbnailHeight: CGFloat,
        contextSize: CGSize,
        screenScale: CGFloat,
        untrimmedDurationSeconds: TimeInterval,
    ) async throws -> [UIImage] {
        // We generate enough thumbnails for the worst case (full-screen landscape)
        // to avoid the complexity of regeneration.
        let contextMaxDimension = max(contextSize.width, contextSize.height)
        let thumbnailWidth = floor(thumbnailHeight * aspectRatio.width / aspectRatio.height)
        let thumbnailCount = UInt(ceil(contextMaxDimension / thumbnailWidth))

        let maxThumbnailSize = max(thumbnailWidth, thumbnailHeight) * screenScale

        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url, options: nil)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(square: maxThumbnailSize)
        generator.appliesPreferredTrackTransform = true

        let times: [CMTime] = (0..<thumbnailCount).map { index in
            let thumbnailAlpha = Double(index) / Double(thumbnailCount - 1)
            let thumbnailTimeSeconds = thumbnailAlpha * untrimmedDurationSeconds
            return CMTime(seconds: thumbnailTimeSeconds, preferredTimescale: 1000)
        }

        let cgImages = try await generateCGImages(generator: generator, times: times)
        return cgImages.map { cgImage in
            UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }
    }

    /// Requests every image at once, so they can be generated concurrently
    /// rather than one decode at a time.
    @concurrent
    private static func generateCGImages(
        generator: AVAssetImageGenerator,
        times: [CMTime],
    ) async throws -> [CGImage] {
        guard !times.isEmpty else {
            return []
        }

        struct Results {
            var cgImages: [CGImage?]
            var remainingCount: Int
            var error: Error?

            /// Returns `self` once every requested image has been reported.
            mutating func record(
                index: Int?,
                cgImage: CGImage?,
                result: AVAssetImageGenerator.Result,
                error: Error?,
            ) -> Results? {
                switch result {
                case .succeeded:
                    if let index {
                        cgImages[index] = cgImage
                    }
                case .failed, .cancelled:
                    fallthrough
                @unknown default:
                    self.error = self.error ?? error ?? OWSAssertionError("image generation failed")
                }
                remainingCount -= 1
                return remainingCount == 0 ? self : nil
            }
        }
        let results = AtomicValue(
            Results(
                cgImages: Array(repeating: nil, count: times.count),
                remainingCount: times.count,
            ),
            lock: UnfairLock(),
        )

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(
                forTimes: times.map { NSValue(time: $0) },
            ) { requestedTime, cgImage, _, result, error in
                let finishedResults = results.update { results in
                    results.record(
                        index: times.firstIndex(of: requestedTime),
                        cgImage: cgImage,
                        result: result,
                        error: error,
                    )
                }
                guard let finishedResults else {
                    return
                }
                if let error = finishedResults.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: finishedResults.cgImages.compacted())
                }
            }
        }
    }

    // MARK: - VideoTimelineViewDelegate

    func videoTimelineViewDidBeginTrimming(_ view: VideoTimelineView) {
        editorView.pauseIfPlaying()
        editorView.isTrimmingVideo = true
    }

    func videoTimelineView(_ view: VideoTimelineView, didTrimBeginningTo seconds: TimeInterval) {
        model.trimToStartSeconds(seconds)
        editorView.seek(toSeconds: seconds)
    }

    func videoTimelineView(_ view: VideoTimelineView, didTrimEndTo seconds: TimeInterval) {
        model.trimToEndSeconds(seconds)
        editorView.seek(toSeconds: seconds)
    }

    func videoTimelineViewDidEndTrimming(_ view: VideoTimelineView) {
        editorView.isTrimmingVideo = false
        editorView.ensureSeekReflectsTrimming()
    }

    func videoTimelineViewWillBeginScrubbing(_ view: VideoTimelineView) {
        // Pause playback during scrubbing.
        shouldResumeVideoPlaybackOnScrubbingEnd = editorView.pauseIfPlaying()
    }

    func videoTimelineView(_ view: VideoTimelineView, didScrubTo seconds: TimeInterval) {
        editorView.seek(toSeconds: seconds)
    }

    func videoTimelineViewDidEndScrubbing(_ view: VideoTimelineView) {
        if shouldResumeVideoPlaybackOnScrubbingEnd {
            editorView.playVideo()
        }
    }

    // MARK: - VideoEditorModelObserver

    func videoEditorModelDidChange(_ model: VideoEditorModel) {
        timelineView.updateContents()
        editorView.updateIsMuted()
    }

    // MARK: - VideoEditorViewControllerProviding

    func viewController(forVideoEditorView videoEditorView: VideoEditorView) -> UIViewController {
        return self
    }
}
