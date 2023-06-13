//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol VideoTimelineViewDataSource: VideoEditorDataSource, VideoPlaybackState {

    var videoThumbnails: [UIImage]? { get }

    var videoAspectRatio: CGSize { get }
}

protocol VideoTimelineViewDelegate: AnyObject {

    func videoTimelineViewDidBeginTrimming(_ view: VideoTimelineView)
    func videoTimelineView(_ view: VideoTimelineView, didTrimBeginningTo seconds: TimeInterval)
    func videoTimelineView(_ view: VideoTimelineView, didTrimEndTo seconds: TimeInterval)
    func videoTimelineViewDidEndTrimming(_ view: VideoTimelineView)

    func videoTimelineViewWillBeginScrubbing(_ view: VideoTimelineView)
    func videoTimelineView(_ view: VideoTimelineView, didScrubTo seconds: TimeInterval)
    func videoTimelineViewDidEndScrubbing(_ view: VideoTimelineView)
}

class VideoTimelineView: UIView {

    weak var dataSource: VideoTimelineViewDataSource?
    weak var delegate: VideoTimelineViewDelegate?

    private let thumbnailLayerView = OWSLayerView()
    private let thumbnailOverlayLayer = CAShapeLayer()
    private let trimLayerView = OWSLayerView()

    private let trimHandleLeft = TrimHandleView(position: .left)
    private let trimHandleRight = TrimHandleView(position: .right)
    private var trimGestureLocationOffset: CGFloat = 0

    private let cursorView = TimelineCursorView(frame: CGRect(origin: .zero, size: Constants.cursorSize))
    private var isCursorHidden: Bool {
        get {
            cursorView.alpha == 0
        }
        set {
            cursorView.alpha = newValue ? 0 : 1
        }
    }

    private enum Mode {
        case none
        case trimmingStart
        case trimmingEnd
        case scrubbing
    }
    private var mode: Mode = .none

    fileprivate enum Constants {
        static let timelineHeight: CGFloat = 40
        static let extraHotArea: CGFloat = 10
        static let cursorSize = CGSize(width: 4, height: timelineHeight + 4)
        static let cornerRadius: CGFloat = 4
    }
    static let preferredHeight = Constants.timelineHeight

    private lazy var timeBubbleTextLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .dynamicTypeCaption1.medium()
        return label
    }()
    private lazy var timeBubbleView: UIView = {
        let view = OWSLayerView()
        view.alpha = 0
        view.backgroundColor = .ows_blackAlpha60
        view.isUserInteractionEnabled = false
        view.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 4)
        view.addSubview(timeBubbleTextLabel)
        timeBubbleTextLabel.autoPinEdgesToSuperviewMargins()

        view.layoutCallback = { view in
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: view.bounds, cornerRadius: 6).cgPath
            view.layer.mask = maskLayer
        }

        return view
    }()
    private var timeBubbleViewPositionConstraint: NSLayoutConstraint?

    required init() {
        super.init(frame: .zero)

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createContents() {

        // Thumbnail strip.
        addSubview(thumbnailLayerView)
        thumbnailLayerView.backgroundColor = .ows_gray65 // This value matches color of a trim handle in default state.
        thumbnailLayerView.clipsToBounds = true
        thumbnailLayerView.autoPinEdgesToSuperviewEdges()

        // This layer dims thumbnail strip outside of trimmed area.
        // TODO: check if it is possible to change opacity on thumbnailLayerView instead.
        thumbnailOverlayLayer.fillColor = UIColor.ows_blackAlpha50.cgColor
        thumbnailOverlayLayer.fillRule = .evenOdd
        thumbnailOverlayLayer.zPosition = 10000
        thumbnailLayerView.layer.addSublayer(thumbnailOverlayLayer)

        thumbnailLayerView.layoutCallback = { [weak self] view in
            guard let self = self else { return }

            // Rounded corners for thumbnailLayerView.
            // Even though actual thumbnail area is inset on both ends
            // it is necessary to apply rounded corners because thumbnailLayerView's background
            // becomes exposed when either trim handle is moved from their default position.
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: view.bounds, cornerRadius: Constants.cornerRadius).cgPath
            view.layer.mask = maskLayer

            // Dimming overlays.
            let overlayPath = UIBezierPath()
            overlayPath.append(UIBezierPath(rect: self.thumbnailStripOverlayRectLeft))
            overlayPath.append(UIBezierPath(rect: self.thumbnailStripOverlayRectRight))
            self.thumbnailOverlayLayer.path = overlayPath.cgPath
            self.thumbnailOverlayLayer.frame = view.bounds

            self.updateThumbnailView()
        }

        // View that contains trim handles and playback cursor.
        trimLayerView.shouldAnimate = false
        addSubview(trimLayerView)
        trimLayerView.autoPinEdgesToSuperviewEdges()

        trimLayerView.addSubview(trimHandleLeft)
        trimLayerView.addSubview(trimHandleRight)
        trimLayerView.addSubview(cursorView)
        trimLayerView.layoutCallback = { [weak self] view in
            guard let self = self else {
                return
            }

            self.trimHandleLeft.center = self.leftTrimHandleCenter
            self.trimHandleRight.center = self.rightTrimHandleCenter

            // Repurpose `UIImageView.isHighlighted` to show different image (yellow handles) when video is trimmed.
            let shouldHighlightHandles = self.isTrimmedOrBeingTrimmed
            self.trimHandleLeft.isHighlighted = shouldHighlightHandles
            self.trimHandleRight.isHighlighted = shouldHighlightHandles

            self.updateCursorPosition()
        }

        addGestureRecognizer(PermissiveGestureRecognizer(target: self, action: #selector(gestureDidChange)))
    }

    func updateThumbnailView() {
        if let sublayers = thumbnailLayerView.layer.sublayers {
            for sublayer in sublayers {
                if sublayer != thumbnailOverlayLayer {
                    sublayer.removeFromSuperlayer()
                }
            }
        }

        guard let dataSource = dataSource,
              let videoThumbnails = dataSource.videoThumbnails else {
            return
        }

        // Lengthwise thumbnails fill the entire space within trim handles in their default state.
        let thumbnailStripRect = thumbnailStripRect
        let thumbnailHeight = thumbnailStripRect.height
        guard thumbnailHeight > 0 else {
            return
        }

        // We want thumbnails to have the same aspect ratio as the video,
        // but also fill the entire thumbnail strip with a whole number of thumbnails.
        // Therefore the number of thumbnails of preferred width is rounded ("schoolbook rounding")
        // to minimize the difference between video and thumbnail aspect ratios.
        let videoAspectRatio = dataSource.videoAspectRatio
        let preferredThumbnailWidth = floor(thumbnailHeight * videoAspectRatio.width / videoAspectRatio.height)
        let thumbnailCount = UInt(round(thumbnailStripRect.width / preferredThumbnailWidth))
        let thumbnailWidth = thumbnailStripRect.width / CGFloat(thumbnailCount)

        for index in 0..<thumbnailCount {
            // The timeline shows a series of thumbnails reflecting the video
            // content at the point. It's ambiguous whether each thumbnail
            // should reflect the content at the thumbnail's left edge or
            // center. I've chosen to use the center.
            let thumbnailAlpha = (Double(index) + 0.5) / Double(thumbnailCount - 1)
            let thumbnailIndex = Int(round(thumbnailAlpha * Double(videoThumbnails.count))).clamp(0, videoThumbnails.count - 1)
            let thumbnail: UIImage = videoThumbnails[thumbnailIndex]
            let imageLayer = CALayer()
            imageLayer.contents = thumbnail.cgImage
            imageLayer.frame = CGRect(x: thumbnailStripRect.minX + CGFloat(index) * thumbnailWidth,
                                      y: thumbnailStripRect.minY,
                                      width: thumbnailWidth,
                                      height: thumbnailHeight)
            thumbnailLayerView.layer.addSublayer(imageLayer)
        }
    }

    // There's a few reasons we use this approach to extending the hot area
    // for this control.
    //
    // * It allows the frame/bounds of this view to coincide with its visible bounds.
    // * It allows our layout to honor the root view's margins in a simple way.
    // * It simplifies much of the geometry math done in this class.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Extend the hot area for this control.
        let extendedBounds = bounds.inset(by: UIEdgeInsets(margin: -Constants.extraHotArea))
        return extendedBounds.contains(point)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Constants.timelineHeight)
    }

    // We need to ensure that "trim rect" always reflects the
    // trim state in a coherent way.
    //
    // * When the video is untrimmed, the trim rect should fully
    //   fully occupy the timeline.
    // * When the video is trimmed down to the shortest valid
    //   snippet, the trim rect should be proportionally "small".
    //
    // Therefore we scale in _inner_ trim rect to reflect the
    // ratio of the trimmed video length to the original,
    // untrimmed video length.
    private var innerTrimRect: CGRect {
        guard let dataSource = dataSource else {
            return bounds
        }
        let untrimmedDurationSeconds = CGFloat(dataSource.untrimmedDurationSeconds)
        let startSeconds = CGFloat(dataSource.trimmedStartSeconds)
        let endSeconds = CGFloat(dataSource.trimmedEndSeconds)

        let maxTrimRect = convert(thumbnailStripRect, from: thumbnailLayerView)
        var result = maxTrimRect
        result.origin.x += startSeconds / untrimmedDurationSeconds * maxTrimRect.width
        result.size.width *= (endSeconds - startSeconds) / untrimmedDurationSeconds
        return result
    }

    private var cursorPosition: CGPoint {
        guard let dataSource = dataSource else {
            return bounds.center
        }
        let startSeconds = CGFloat(dataSource.trimmedStartSeconds)
        let endSeconds = CGFloat(dataSource.trimmedEndSeconds)
        let currentTimeSeconds = CGFloat(dataSource.currentTimeSeconds)
        // alpha = 0 when playback is at start of trimmed clip.
        // alpha = 1 when playback is at end of trimmed clip.
        let playbackAlpha = currentTimeSeconds.inverseLerp(startSeconds, endSeconds, shouldClamp: true)

        let innerTrimRect = innerTrimRect
        let cursorPositionX = playbackAlpha.lerp(innerTrimRect.minX, innerTrimRect.maxX)
        let cursorPositionXInTrimLayerView = trimLayerView.convert(CGPoint(x: cursorPositionX, y: 0), from: self).x
        return CGPoint(x: cursorPositionXInTrimLayerView, y: trimLayerView.bounds.midY)
    }

    /**
     * Returns the area within `thumbnailLayerView` that should be filled with video thumbnails.
     */
    private var thumbnailStripRect: CGRect {
        let insets = UIEdgeInsets(top: 0, left: trimHandleLeft.width, bottom: 0, right: trimHandleRight.width)
        return thumbnailLayerView.bounds.inset(by: insets)
    }

    /**
     * Returns left part of `thumbnailLayerView` that should be dimmed because it is outside of trim handles.
     */
    private var thumbnailStripOverlayRectLeft: CGRect {
        let adjustedInnerTrimRect = thumbnailLayerView.convert(innerTrimRect, from: self)
        var result = thumbnailStripRect
        result.size.width = adjustedInnerTrimRect.minX - result.minX
        return result
    }

    /**
     * Returns right part of `thumbnailLayerView` that should be dimmed because it is outside of trim handles.
     */
    private var thumbnailStripOverlayRectRight: CGRect {
        let adjustedInnerTrimRect = thumbnailLayerView.convert(innerTrimRect, from: self)
        var result = thumbnailStripRect
        result.size.width = result.maxX - adjustedInnerTrimRect.maxX
        result.origin.x = adjustedInnerTrimRect.maxX
        return result
    }

    private var leftTrimHandleCenter: CGPoint {
        let point = CGPoint(x: innerTrimRect.minX - 0.5 * trimHandleLeft.width, y: bounds.midY)
        return trimLayerView.convert(point, from: self)
    }

    private var rightTrimHandleCenter: CGPoint {
        let point = CGPoint(x: innerTrimRect.maxX + 0.5 * trimHandleRight.width, y: bounds.midY)
        return trimLayerView.convert(point, from: self)
    }

    private var isTrimmedOrBeingTrimmed: Bool {
        switch mode {
        case .trimmingStart, .trimmingEnd:
            return true

        default:
            break
        }
        if let dataSource = dataSource {
            return dataSource.isTrimmed
        }
        return false
    }

    func updateContents() {
        thumbnailLayerView.updateContent()
        trimLayerView.updateContent()
        updateCursorPosition()
        updateTimeBubble()
    }

    func updateCursorPosition() {
        cursorView.center = cursorPosition
    }
}

// MARK: - Gestures

extension VideoTimelineView {

    private var outerTrimRect: CGRect {
        let trimRectInset = UIEdgeInsets(top: 0, leading: -trimHandleLeft.width, bottom: 0, trailing: -trimHandleRight.width)
        return innerTrimRect.inset(by: trimRectInset)
    }

    @objc
    private func gestureDidChange(gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            mode = modeForNewGesture(gesture)
        }
        guard mode != .none else {
            return
        }

        switch gesture.state {
        case .began:
            switch mode {
            case .trimmingStart, .trimmingEnd:
                beginTrimming(withGesture: gesture)

            case .scrubbing:
                delegate?.videoTimelineViewWillBeginScrubbing(self)
                applyGestureInProgress(gesture)

            default:
                break
            }

            updateContents()

        case .changed:
            applyGestureInProgress(gesture)

        case .ended:
            applyGestureInProgress(gesture)
            completeGestureProcessing()

        default:
            completeGestureProcessing()
            return
        }
    }

    private func modeForNewGesture(_ gesture: UIGestureRecognizer) -> Mode {
        guard let dataSource = dataSource else {
            return .none
        }

        let location = gesture.location(in: self)
        let outerTrimRect = outerTrimRect
        let innerTrimRect = innerTrimRect

        // Our gesture handling is permissive, trim gestures can start
        // a little bit outside the visible "trim handles".
        let couldBeTrimStart = (dataSource.canBeTrimmed &&
                                location.x >= (outerTrimRect.minX - Constants.extraHotArea) &&
                                location.x <= (innerTrimRect.minX + Constants.extraHotArea))
        let couldBeTrimEnd = (dataSource.canBeTrimmed &&
                              location.x >= (innerTrimRect.maxX - Constants.extraHotArea) &&
                              location.x <= (outerTrimRect.maxX + Constants.extraHotArea))
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
            return .none
        }
    }

    private func applyGestureInProgress(_ gesture: UIGestureRecognizer) {
        guard let dataSource = dataSource, let delegate = delegate else {
            return
        }

        let adjustedHorizontalPosition = gesture.location(in: trimLayerView).x - trimGestureLocationOffset
        let thumbnailStripRect = thumbnailStripRect
        // alpha = 0 when gesture is at start of untrimmed clip.
        // alpha = 1 when gesture is at end of untrimmed clip.
        let untrimmedAlpha = Double(adjustedHorizontalPosition.inverseLerp(thumbnailStripRect.minX, thumbnailStripRect.maxX, shouldClamp: true))

        let startSeconds = dataSource.trimmedStartSeconds
        let endSeconds = dataSource.trimmedEndSeconds
        let untrimmedDurationSeconds = dataSource.untrimmedDurationSeconds
        let untrimmedSeconds = untrimmedDurationSeconds * untrimmedAlpha

        switch mode {
        case .trimmingStart:
            // Don't let users trim clip to less than the minimum duration.
            let maxValue = max(0, endSeconds - VideoEditorModel.minimumDurationSeconds)
            let seconds = min(maxValue, untrimmedSeconds)
            delegate.videoTimelineView(self, didTrimBeginningTo: seconds)

        case .trimmingEnd:
            // Don't let users trim clip to less than the minimum duration.
            let minValue = min(untrimmedDurationSeconds, startSeconds + VideoEditorModel.minimumDurationSeconds)
            let seconds = max(minValue, untrimmedSeconds)
            delegate.videoTimelineView(self, didTrimEndTo: seconds)

        case .scrubbing:
            // Clamp to the trimmed clip.
            let seconds = untrimmedSeconds.clamp(startSeconds, endSeconds)
            delegate.videoTimelineView(self, didScrubTo: seconds)

        case .none:
            owsFailDebug("Unexpected mode.")
        }
    }

    private func completeGestureProcessing() {
        let previousMode = mode
        mode = .none

        switch previousMode {
        case .trimmingStart, .trimmingEnd:
            endTrimming()

        case .scrubbing:
            delegate?.videoTimelineViewDidEndScrubbing(self)

        default:
            break
        }
        updateContents()
    }

    private func beginTrimming(withGesture gesture: UIGestureRecognizer) {
        UIView.animate(withDuration: 0.2) {
            self.isCursorHidden = true
        }

        let location = gesture.location(in: trimLayerView)
        let thumbnailStripRect = thumbnailStripRect
        if !thumbnailStripRect.contains(location) {
            switch mode {
            case .trimmingStart:
                trimGestureLocationOffset = min(0, location.x - thumbnailStripRect.minX)

            case .trimmingEnd:
                trimGestureLocationOffset = max(0, location.x - thumbnailStripRect.maxX)

            default:
                owsFailDebug("Invalid mode. [\(mode)]")
            }
        }

        delegate?.videoTimelineViewDidBeginTrimming(self)
    }

    private func endTrimming() {
        UIView.animate(withDuration: 0.2) {
            self.isCursorHidden = false
        }

        trimGestureLocationOffset = 0

        delegate?.videoTimelineViewDidEndTrimming(self)
    }
}

// MARK: - Time Bubble

extension VideoTimelineView {

    private enum TimeBubbleAlignment {
        case left
        case center
        case right
    }

    func updateTimeBubble() {
        guard let dataSource = dataSource else {
            hideTimeBubble(animated: false)
            return
        }
        switch mode {
        case .none:
            hideTimeBubble(animated: true)
        case .trimmingStart:
            showTimeBubble(time: dataSource.trimmedStartSeconds, alignment: .left)
        case .trimmingEnd:
            showTimeBubble(time: dataSource.trimmedEndSeconds, alignment: .right)
        case .scrubbing:
            showTimeBubble(time: dataSource.currentTimeSeconds, alignment: .center)
        }
    }

    private func showTimeBubble(time: TimeInterval, alignment: TimeBubbleAlignment) {
        if timeBubbleView.superview == nil {
            addSubview(timeBubbleView)
            timeBubbleView.autoPinEdge(.bottom, to: .top, of: self, withOffset: -24)
        }

        var timeBubbleViewPositionConstraint: NSLayoutConstraint
        if let existingConstraint = self.timeBubbleViewPositionConstraint {
            timeBubbleViewPositionConstraint = existingConstraint
        } else {
            timeBubbleViewPositionConstraint =
            NSLayoutConstraint(item: timeBubbleView, attribute: .centerX, relatedBy: .equal,
                               toItem: self, attribute: .left, multiplier: 1, constant: 0)
            addConstraint(timeBubbleViewPositionConstraint)
            self.timeBubbleViewPositionConstraint = timeBubbleViewPositionConstraint
        }

        timeBubbleViewPositionConstraint.constant = {
            switch alignment {
            case .left:
                // Position strictly above left trim handle.
                return convert(trimHandleLeft.center, from: trimLayerView).x
            case .right:
                // Position strictly above right trim handle.
                return convert(trimHandleRight.center, from: trimLayerView).x
            case .center:
                // Position where current video playback is.
                return convert(cursorView.center, from: trimLayerView).x
            }}()

        timeBubbleTextLabel.text = OWSFormat.localizedDurationString(from: round(time))

        if timeBubbleView.alpha < 1 {
            UIView.performWithoutAnimation {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
            UIView.animate(withDuration: 0.2) {
                self.timeBubbleView.alpha = 1
            }
        }
    }

    private func hideTimeBubble(animated: Bool = false) {
        guard animated else {
            timeBubbleView.alpha = 0
            return
        }
        UIView.animate(withDuration: 0.2) {
            self.timeBubbleView.alpha = 0
        }
    }
}

private class TrimHandleView: UIImageView {

    enum Position {
        case left
        case right
    }
    let position: Position

    private static func handleImage(forPosition position: Position, isHighlighted: Bool) -> UIImage? {
        let imageName = isHighlighted ? "media-editor-video-trim-yellow" : "media-editor-video-trim-gray"
        let image = UIImage(imageLiteralResourceName: imageName)
        if position == .left {
            return image.withHorizontallyFlippedOrientation()
        }
        return image
    }

    override var isHighlighted: Bool {
        willSet {
            if newValue && highlightedImage == nil {
                highlightedImage = TrimHandleView.handleImage(forPosition: position, isHighlighted: true)
            }
        }
    }

    required init(position: Position) {
        self.position = position
        super.init(image: TrimHandleView.handleImage(forPosition: position, isHighlighted: false))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class TimelineCursorView: UIView {

    override static var layerClass: AnyClass {
        CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer? {
        return layer as? CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        shapeLayer?.shadowColor = UIColor.black.cgColor
        shapeLayer?.shadowOffset = .zero
        shapeLayer?.shadowRadius = 4
        shapeLayer?.shadowOpacity = 0.25
        shapeLayer?.fillColor = UIColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        VideoTimelineView.Constants.cursorSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePath()
    }

    private func updatePath() {
        shapeLayer?.path = UIBezierPath(roundedRect: bounds, cornerRadius: width * 0.5).cgPath
    }
}
