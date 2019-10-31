//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import AVFoundation
import PromiseKit
import Photos

@objc
public protocol VideoEditorViewDelegate: class {
        func videoEditorViewController() -> UIViewController
}

// MARK: -

// A view for editing outgoing video attachments.
@objc
public class VideoEditorView: UIView {

    weak var delegate: VideoEditorViewDelegate?

    private let model: VideoEditorModel

    private let playerView: VideoPlayerView
    private let playButton = UIButton()

    private let timelineView = TrimVideoTimelineView()

    internal var isPlaying: Bool {
        return playerView.isPlaying
    }

    internal var currentTimeSeconds: Double {
        return playerView.currentTimeSeconds
    }

    internal var untrimmedDurationSeconds: Double {
        return model.untrimmedDurationSeconds
    }

    internal var trimmedStartSeconds: Double {
        return model.trimmedStartSeconds
    }

    internal var trimmedEndSeconds: Double {
        return model.trimmedEndSeconds
    }

    internal var displaySize: CGSize {
        return model.displaySize
    }

    internal var canBeTrimmed: Bool {
        return model.canBeTrimmed
    }

    internal var isTrimmed: Bool {
        return model.isTrimmed
    }

    private let timelineHeight: CGFloat = 40

    @objc
    public required init(model: VideoEditorModel, delegate: VideoEditorViewDelegate) {
        self.model = model
        self.delegate = delegate
        playerView = VideoPlayerView()
        playerView.videoPlayer = OWSVideoPlayer(url: URL(fileURLWithPath: model.srcVideoPath))

        super.init(frame: .zero)

        model.add(observer: self)

        backgroundColor = .black

        playerView.delegate = self
        timelineView.delegate = self
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    @objc
    public func configureSubviews() {
        let aspectRatio: CGFloat = model.displaySize.width / model.displaySize.height
        addSubviewWithScaleAspectFitLayout(view: playerView, aspectRatio: aspectRatio)
        playerView.setContentHuggingLow()
        playerView.setCompressionResistanceLow()

        let pauseGesture = UITapGestureRecognizer(target: self, action: #selector(didTapPlayerView(_:)))
        playerView.addGestureRecognizer(pauseGesture)

        addSubview(timelineView)
        timelineView.autoPinEdge(toSuperviewMargin: .leading)
        timelineView.autoPinEdge(toSuperviewMargin: .trailing)
        timelineView.autoPinEdge(toSuperviewMargin: .top)
        timelineView.autoSetDimension(.height, toSize: timelineHeight)

        playButton.accessibilityLabel = NSLocalizedString("PLAY_BUTTON_ACCESSABILITY_LABEL", comment: "Accessibility label for button to start media playback")
        playButton.setBackgroundImage(#imageLiteral(resourceName: "play_button"), for: .normal)
        playButton.contentMode = .scaleAspectFit

        let playButtonWidth = ScaleFromIPhone5(70)
        playButton.autoSetDimensions(to: CGSize(width: playButtonWidth, height: playButtonWidth))
        addSubview(playButton)

        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        playButton.autoAlignAxis(.horizontal, toSameAxisOf: playerView)
        playButton.autoAlignAxis(.vertical, toSameAxisOf: playerView)

        timelineView.updateContents()

        ensureSeekReflectsTrimming()

        generateThumbnailsAsync()
    }

    // MARK: -

    internal var videoThumbnails: [UIImage]?

    private func generateThumbnailsAsync() {
        let model = self.model
        let displaySize = self.displaySize
        let timelineHeight = self.timelineHeight
        let untrimmedDurationSeconds = self.untrimmedDurationSeconds

        VideoEditorView.thumbnails(forVideoAtPath: model.srcVideoPath,
                                   displaySize: displaySize,
                                   timelineHeight: timelineHeight,
                                   untrimmedDurationSeconds: untrimmedDurationSeconds)
            .done { [weak self] (thumbnails: [UIImage]) -> Void in
                guard let self = self else {
                    return
                }
                self.videoThumbnails = thumbnails
                self.timelineView.updateThumbnailView()
            }.catch { error in
                owsFailDebug("Error: \(error)")
        }.retainUntilComplete()
    }

    private class func thumbnails(forVideoAtPath videoPath: String,
                                  displaySize: CGSize,
                                  timelineHeight: CGFloat,
                                  untrimmedDurationSeconds: Double) -> Promise<[UIImage]> {
        AssertIsOnMainThread()

        let contextSize = CurrentAppContext().frame.size

        return DispatchQueue.global().async(.promise) {
            // We generate enough thumbnails for the worst case (full-screen landscape)
            // to avoid the complexity of regeneration.
            let contextMaxDimension = max(contextSize.width, contextSize.height)
            let thumbnailCount = UInt(ceil(contextMaxDimension / timelineHeight))

            let url = URL(fileURLWithPath: videoPath)
            let asset = AVURLAsset(url: url, options: nil)
            let generator = AVAssetImageGenerator(asset: asset)
            // We generate square thumbnails.
            generator.maximumSize = CGSize(width: timelineHeight, height: timelineHeight)
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
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        addSubview(view)
        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        view.autoCenterInSuperview()
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .equal)
            view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .equal)
        }
    }

    // MARK: - Event Handlers

    @objc
    public func didTapPlayerView(_ gestureRecognizer: UIGestureRecognizer) {
        togglePlayback()
    }

    @objc
    public func playButtonTapped() {
        togglePlayback()
    }

    private func togglePlayback() {
        if isPlaying {
            pauseVideo()
        } else {
            playVideo()
        }
    }

    // MARK: - Video

    private func playVideo() {
        ensureSeekReflectsTrimming()

        playerView.play()
    }

    private func ensureSeekReflectsTrimming() {
        var shouldSeekToStart = false
        if currentTimeSeconds < trimmedStartSeconds {
            // If playback cursor is before the start of the clipping,
            // restart playback.
            shouldSeekToStart = true
        } else {
            // If playback cursor is very near the end of the clipping,
            // restart playback.
            let toleranceSeconds: Double = 0.1
            if currentTimeSeconds > trimmedEndSeconds - toleranceSeconds {
                shouldSeekToStart = true
            }
        }

        if shouldSeekToStart {
            playerView.seek(to: CMTime(seconds: trimmedStartSeconds, preferredTimescale: model.untrimmedDuration.timescale))
        }
    }

    private func pauseVideo() {
        playerView.pause()
    }

    private var isShowingPlayButton = true

    private func updateControls() {
        AssertIsOnMainThread()

        if isPlaying {
            if isShowingPlayButton {
                isShowingPlayButton = false
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 0.0
                }
            }
        } else {
            if !isShowingPlayButton {
                isShowingPlayButton = true
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 1.0
                }
            }
        }
    }

    // MARK: - Navigation Bar

    public func navigationBarItems() -> [UIView] {
        guard !shouldHideControls else {
            return []
        }

        let saveButton = navigationBarButton(imageName: Theme.iconName(.messageActionSave),
                                             selector: #selector(didTapSave(sender:)))
        return [saveButton]
    }

    public var shouldHideControls: Bool {
        return false
    }

    // MARK: - Actions

    @objc
    func didTapSave(sender: UIButton) {
        playerView.stop()

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        let viewController = delegate.videoEditorViewController()
        viewController.ows_askForMediaLibraryPermissions { isGranted in
            AssertIsOnMainThread()

            guard isGranted else {
                return
            }

        }

        ModalActivityIndicatorViewController.present(fromViewController: viewController, canCancel: false) { modalVC in
            self.saveVideoPromise()
                .done { _ in
                    modalVC.dismiss {
                        // Do nothing.
                    }
                }.catch { error in
                    owsFailDebug("Error: \(error)")

                    modalVC.dismiss {
                        OWSActionSheets.showErrorAlert(message: NSLocalizedString("ERROR_COULD_NOT_SAVE_VIDEO", comment: "Error indicating that 'save video' failed."))
                    }
            }.retainUntilComplete()
        }
    }

    private func saveVideoPromise() -> Promise<Void> {
        return videoForSavePromise().then(on: .global()) { (videoFilePath: String) -> Promise<Void> in
            let videoUrl = URL(fileURLWithPath: videoFilePath)

            let (promise, resolver) = Promise<Void>.pending()
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl)
            }) { didSucceed, error in
                if let error = error {
                    resolver.reject(error)
                    return
                }
                guard didSucceed else {
                    resolver.reject(OWSErrorMakeAssertionError("Video export failed."))
                    return
                }
                resolver.fulfill(())
            }
            return promise
        }
    }

    private func videoForSavePromise() -> Promise<String> {
        guard model.isTrimmed else {
            // Video editor has no changes.
            return Promise.value(model.srcVideoPath)
        }
        return model.exportOutput()
    }
}

// MARK: -

extension VideoEditorView: VideoEditorModelObserver {

    public func videoEditorModelDidChange(_ model: VideoEditorModel) {
        timelineView.updateContents()
    }
}

// MARK: -

extension VideoEditorView: VideoPlayerViewDelegate {
    public func videoPlayerViewStatusDidChange(_ view: VideoPlayerView) {
        updateControls()
    }

    public func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
        // Prevent playback past the end of the trimming.
        guard currentTimeSeconds <= trimmedEndSeconds else {
            playerView.stop()
            return
        }

        timelineView.updateCursor()
        timelineView.updateTimeBubble()
    }
}

// MARK: -

extension VideoEditorView: TrimVideoTimelineViewDelegate {

    func setTrimStart(_ seconds: Double) {
        // Stop playback during trim gestures.
        playerView.stop()

        model.trimToStartSeconds(seconds)
    }

    func setTrimEnd(_ seconds: Double) {
        // Stop playback during trim gestures.
        playerView.stop()

        model.trimToEndSeconds(seconds)
    }

    func scrubToTime(_ seconds: Double) {
        // Stop playback during scrubbing.
        playerView.stop()

        playerView.seek(to: CMTime(seconds: seconds, preferredTimescale: model.untrimmedDuration.timescale))
    }

    func gestureDidComplete() {
        ensureSeekReflectsTrimming()
    }
}

// MARK: -

protocol TrimVideoTimelineViewDelegate: class {
    var isPlaying: Bool { get }
    var currentTimeSeconds: Double { get }
    var untrimmedDurationSeconds: Double { get }
    var trimmedStartSeconds: Double { get }
    var trimmedEndSeconds: Double { get }
    var displaySize: CGSize { get }
    var canBeTrimmed: Bool { get }
    var isTrimmed: Bool { get }

    var videoThumbnails: [UIImage]? { get }

    func setTrimStart(_ seconds: Double)
    func setTrimEnd(_ seconds: Double)
    func scrubToTime(_ seconds: Double)
    func gestureDidComplete()
}

// MARK: -

class TrimVideoTimelineView: UIView {
    fileprivate weak var delegate: TrimVideoTimelineViewDelegate?

    private let thumbnailLayerView = OWSLayerView()
    private let trimLayerView = OWSLayerView()
    private let cursorLayerView = OWSLayerView()

    private enum Mode {
        case trimmingStart
        case trimmingEnd
        case scrubbing
    }

    private var mode: Mode?

    private var timeBubbleView: UIView?

    @objc
    public required init() {
        super.init(frame: .zero)

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private func createContents() {
        self.backgroundColor = .black

        addSubview(thumbnailLayerView)
        thumbnailLayerView.clipsToBounds = true
        thumbnailLayerView.autoPinEdgesToSuperviewEdges()
        thumbnailLayerView.layoutCallback = { [weak self] view in
            self?.updateThumbnailView()
        }

        addSubview(trimLayerView)
        trimLayerView.autoPinEdgesToSuperviewEdges()
        let trimLayer = CAShapeLayer()
        trimLayerView.layer.addSublayer(trimLayer)
        trimLayerView.layoutCallback = { [weak self] view in
            guard let self = self else {
                return
            }
            let bezierPath = UIBezierPath()
            bezierPath.append(UIBezierPath(rect: self.outerTrimRect))
            bezierPath.append(UIBezierPath(rect: self.innerTrimRect))

            trimLayer.path = bezierPath.cgPath
            trimLayer.frame = view.bounds
            trimLayer.fillColor = self.outerPathColor.cgColor
            trimLayer.fillRule = .evenOdd
        }

        addSubview(cursorLayerView)
        cursorLayerView.autoPinEdgesToSuperviewEdges()
        let cursorLayer = CAShapeLayer()
                cursorLayer.shadowColor = UIColor.black.cgColor
                cursorLayer.shadowOffset = CGSize(width: 0, height: 2)
                cursorLayer.shadowRadius = 4
                cursorLayer.shadowOpacity = 0.5
        cursorLayerView.layer.addSublayer(cursorLayer)
        cursorLayerView.layoutCallback = { [weak self] view in
            guard let self = self else {
                return
            }
            guard self.shouldShowCursor else {
                view.isHidden = true
                return
            }
            view.isHidden = false
            let bezierPath = UIBezierPath()
            bezierPath.append(UIBezierPath(rect: self.cursorRect))
            cursorLayer.path = bezierPath.cgPath
            cursorLayer.frame = view.bounds
            cursorLayer.fillColor = self.cursorColor.cgColor
            cursorLayer.fillRule = .evenOdd
        }

        isUserInteractionEnabled = true
        addGestureRecognizer(PermissiveGestureRecognizer(target: self, action: #selector(gestureDidChange)))
    }

    fileprivate func updateThumbnailView() {
        if let sublayers = thumbnailLayerView.layer.sublayers {
            for sublayer in sublayers {
                sublayer.removeFromSuperlayer()
            }
        }
        guard let delegate = delegate else {
            return
        }
        guard let videoThumbnails = delegate.videoThumbnails else {
            return
        }

        let thumbnailSize: CGFloat = height()
        let thumbnailCount = UInt(ceil(width() / thumbnailSize))

        for index in 0..<thumbnailCount {
            // The timeline shows a series of thumbnails reflecting the video
            // content at the point.   It's ambiguous whether each thumbnail
            // should reflect the content at the thumbnail's left edge or
            // center. I've chosen to use the center.
            let thumbnailAlpha = (Double(index) + 0.5) / Double(thumbnailCount - 1)
            let thumbnailIndex = Int(round(thumbnailAlpha * Double(videoThumbnails.count))).clamp(0, videoThumbnails.count - 1)
            let thumbnail: UIImage = videoThumbnails[thumbnailIndex]
            let imageLayer = CALayer()
            imageLayer.contents = thumbnail.cgImage
            let x: CGFloat = CGFloat(index) * thumbnailSize
            imageLayer.frame = CGRect(x: x, y: 0, width: thumbnailSize, height: thumbnailSize)
            thumbnailLayerView.layer.addSublayer(imageLayer)
        }
    }

    private let extraHotArea: CGFloat = 10

    // There's a few reasons we use this approach to extending the hot area
    // for this control.
    //
    // * It allows the frame/bounds of this view to coincide with its visible bounds.
    // * It allows our layout to honor the root view's margins is a simple way.
    // * It simplifies much of the geometry math done in this class.
    @objc
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Extend the hot area for this control.
        let extendedBounds = bounds.inset(by: UIEdgeInsets(top: -extraHotArea, leading: -extraHotArea, bottom: -extraHotArea, trailing: -extraHotArea))
        return extendedBounds.contains(point)
    }

    private let trimRectVThickness: CGFloat = 2
    private let trimRectHThickness: CGFloat = 12
    private let cursorWidth: CGFloat = 3
    private let cursorHeight: CGFloat = 44

    private var outerTrimRect: CGRect {
        guard let delegate = delegate else {
            return bounds
        }
        let untrimmedDurationSeconds = CGFloat(delegate.untrimmedDurationSeconds)
        let startSeconds = CGFloat(delegate.trimmedStartSeconds)
        let endSeconds = CGFloat(delegate.trimmedEndSeconds)

        var result = bounds
        result.origin.x = startSeconds / untrimmedDurationSeconds * bounds.width
        result.size.width = (endSeconds - startSeconds) / untrimmedDurationSeconds * bounds.width
        return result
    }

    private var innerTrimRect: CGRect {
        return outerTrimRect.inset(by: UIEdgeInsets(top: trimRectVThickness, leading: trimRectHThickness, bottom: trimRectVThickness, trailing: trimRectHThickness))
    }

    private var cursorRect: CGRect {
        guard let delegate = delegate else {
            return bounds
        }
        let startSeconds = CGFloat(delegate.trimmedStartSeconds)
        let endSeconds = CGFloat(delegate.trimmedEndSeconds)
        let currentTimeSeconds = CGFloat(delegate.currentTimeSeconds)
        // alpha = 0 when playback is at start of trimmed clip.
        // alpha = 1 when playback is at end of trimmed clip.
        let playbackAlpha = currentTimeSeconds.inverseLerp(startSeconds, endSeconds, shouldClamp: true)

        let outerTrimRect = self.outerTrimRect
        var result = CGRect.zero
        result.origin.x = playbackAlpha.lerp(outerTrimRect.minX, outerTrimRect.maxX) - cursorWidth * 0.5
        result.origin.y = outerTrimRect.midY - cursorHeight * 0.5
        result.size.width = cursorWidth
        result.size.height = cursorHeight
        return result
    }

    fileprivate func updateContents() {
        trimLayerView.updateContent()
        cursorLayerView.updateContent()
        updateTimeBubble()
    }

    fileprivate func updateCursor() {
        cursorLayerView.updateContent()
    }

    private var outerPathColor: UIColor {
        if let mode = self.mode {
            switch mode {
            case .trimmingStart, .trimmingEnd:
                return .ows_accentYellow
            default:
                break
            }
        }
        if let delegate = delegate, delegate.isTrimmed {
            return .ows_accentYellow
        }
        return .ows_white
    }

    private var cursorColor: UIColor {
        return .ows_white
    }

    private var shouldShowCursor: Bool {
        if let mode = self.mode, mode == .scrubbing {
            return true
        }
        if let delegate = delegate, delegate.isPlaying {
            return true
        }
        return false
    }

    // MARK: Events

    @objc
    func gestureDidChange(gesture: UIGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            mode = modeForNewGesture(location: location)
            guard let mode = self.mode else {
                return
            }
            if shouldApplyGestureOnStart(mode: mode) {
                applyGestures(mode: mode, location: location)
            }
            updateContents()
        case .changed:
            guard let mode = self.mode else {
                return
            }
            applyGestures(mode: mode, location: location)
        case .ended:
            guard let mode = self.mode else {
                return
            }
            applyGestures(mode: mode, location: location)
            endGestures()
        default:
            endGestures()
            return
        }
    }

    private func modeForNewGesture(location: CGPoint) -> Mode? {
        guard let delegate = delegate else {
            return nil
        }

        let outerTrimRect = self.outerTrimRect
        let innerTrimRect = self.innerTrimRect

        // Our gesture handling is permissive, trim gestures can start
        // a little bit outside the visible "trim handles".
        let couldBeTrimStart = (delegate.canBeTrimmed &&
            location.x >= (outerTrimRect.minX - extraHotArea) &&
            location.x <= (innerTrimRect.minX + extraHotArea))
        let couldBeTrimEnd = (delegate.canBeTrimmed &&
            location.x >= (innerTrimRect.maxX - extraHotArea) &&
            location.x <= (outerTrimRect.maxX + extraHotArea))
        let couldBeScrub = (location.x >= innerTrimRect.minX &&
            location.x <= innerTrimRect.maxX)

        // Prefer trimming to scrubbing.
        if couldBeTrimStart && couldBeTrimEnd {
            // Because our gesture handling is permissive,
            // we need to disambiguate.
            let startDistance = abs(location.x - outerTrimRect.minX)
            let endDistance = abs(location.x - outerTrimRect.maxX)
            if startDistance < endDistance {
                return .trimmingStart
            } else {
                return .trimmingEnd
            }
        } else if couldBeTrimStart {
            return .trimmingStart
        } else if couldBeTrimEnd {
            return .trimmingEnd
        } else if couldBeScrub {
            return .scrubbing
        } else {
            return nil
        }
    }

    private func shouldApplyGestureOnStart(mode: Mode) -> Bool {
        return mode == .scrubbing
    }

    private func applyGestures(mode: Mode, location: CGPoint) {
        guard let delegate = delegate else {
            return
        }

        let untrimmedDurationSeconds = delegate.untrimmedDurationSeconds
        let startSeconds = delegate.trimmedStartSeconds
        let endSeconds = delegate.trimmedEndSeconds
        // alpha = 0 when gesture is at start of untrimmed clip.
        // alpha = 1 when gesture is at end of untrimmed clip.
        let untrimmedAlpha = Double(location.x.inverseLerp(0, bounds.width, shouldClamp: true))
        let untrimmedSeconds = untrimmedDurationSeconds * untrimmedAlpha

        switch mode {
        case .trimmingStart:
            // Don't let users trim clip to less than the minimum duration.
            let maxValue = max(0, endSeconds - VideoEditorModel.minimumDurationSeconds)
            let seconds = min(maxValue, untrimmedSeconds)
            delegate.setTrimStart(seconds)
        case .trimmingEnd:
            // Don't let users trim clip to less than the minimum duration.
            let minValue = min(untrimmedDurationSeconds, startSeconds + VideoEditorModel.minimumDurationSeconds)
            let seconds = max(minValue, untrimmedSeconds)
            delegate.setTrimEnd(seconds)
        case .scrubbing:
            // Clamp to the trimmed clip.
            let seconds = untrimmedSeconds.clamp(startSeconds, endSeconds)
            delegate.scrubToTime(seconds)
        }
    }

    private func endGestures() {
        self.mode = nil
        delegate?.gestureDidComplete()
        updateContents()
        updateTimeBubble()
    }

    private enum TimeBubbleAlignment {
        case left
        case center
        case right
    }

    fileprivate func updateTimeBubble() {
        guard let delegate = delegate else {
            hideTimeBubble()
            return
        }
        if let mode = mode {
            switch mode {
            case .trimmingStart:
                showTimeBubble(time: delegate.trimmedStartSeconds, alignment: .left)
            case .trimmingEnd:
                showTimeBubble(time: delegate.trimmedEndSeconds, alignment: .right)
            case .scrubbing:
                showTimeBubble(time: delegate.currentTimeSeconds, alignment: .center)
            }
        } else if delegate.isPlaying {
            showTimeBubble(time: delegate.currentTimeSeconds, alignment: .center)
        } else {
            hideTimeBubble()
        }
    }

    private func showTimeBubble(time: Double, alignment: TimeBubbleAlignment) {
        hideTimeBubble()

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }

        let timeBubbleView = OWSLayerView()
        timeBubbleView.backgroundColor = UIColor(white: 0, alpha: 0.6)
        timeBubbleView.layoutCallback = { view in
            view.layer.cornerRadius = min(view.width(), view.height()) * 0.5
        }
        addSubview(timeBubbleView)
        timeBubbleView.autoPinEdge(.top, to: .bottom, of: self, withOffset: 9)

        let bubbleAlpha: Double = time / delegate.untrimmedDurationSeconds
        let bubbleOffset: CGFloat = width() * CGFloat(bubbleAlpha)
        switch alignment {
        case .left:
            timeBubbleView.autoPinEdge(.left, to: .left, of: self, withOffset: bubbleOffset)
        case .right:
            timeBubbleView.autoPinEdge(.right, to: .left, of: self, withOffset: bubbleOffset)
        case .center:
            timeBubbleView.autoAlignAxis(.vertical, toSameAxisOf: self, withOffset: bubbleOffset - width() * 0.5)
        }

        let label = UILabel()
        label.text = OWSFormat.formatDurationSeconds(Int(round(time)))
        label.textColor = .ows_white
        label.font = .ows_dynamicTypeCaption1
        timeBubbleView.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 3)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 6)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)

        self.timeBubbleView = timeBubbleView
    }

    private func hideTimeBubble() {
        timeBubbleView?.removeFromSuperview()
        timeBubbleView = nil
    }
}
