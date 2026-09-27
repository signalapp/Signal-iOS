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

    override var canSaveMedia: Bool {
        if model.needsRender {
            return true
        }
        return super.canSaveMedia
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
        var thumbnails = [UIImage]()
        for index in 0..<thumbnailCount {
            let thumbnailAlpha = Double(index) / Double(thumbnailCount - 1)
            let thumbnailTimeSeconds = thumbnailAlpha * untrimmedDurationSeconds
            let thumbnailCMTime = CMTime(seconds: thumbnailTimeSeconds, preferredTimescale: 1000)
            let cgImage = try generator.copyCGImage(at: thumbnailCMTime, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            thumbnails.append(thumbnail)
        }
        return thumbnails
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
    }

    // MARK: - VideoEditorViewControllerProviding

    func viewController(forVideoEditorView videoEditorView: VideoEditorView) -> UIViewController {
        return self
    }
}
