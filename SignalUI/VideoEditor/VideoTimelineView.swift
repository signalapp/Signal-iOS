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
    private let thumbnailDimmingLayer = CAShapeLayer()
    private let trimFrameView = TrimFrameView()

    private var trimGestureLocationOffset: CGFloat = 0

    private let cursorView = TimelineCursorView()
    private var isCursorHidden: Bool {
        get { cursorView.alpha == 0 }
        set { cursorView.alpha = newValue ? 0 : 1 }
    }

    /// Type of user interaction with the view.
    private enum UserInteraction {
        /// User is not doing anything.
        case none
        /// User is trimming beginning of the video.
        case trimmingStart
        /// User is trimming end of the video.
        case trimmingEnd
        /// User is scrubbing along the video timeline.
        case scrubbing
    }

    private var userInteraction = UserInteraction.none

    private enum Constants {
        static let timelineHeight: CGFloat = 40
        static let extraHotArea: CGFloat = 10
        static let cornerRadius: CGFloat = if #available(iOS 26, *) { 8 } else { 4 }
    }

    static let thumbnailStripHeight = Constants.timelineHeight

    private lazy var timeBubbleTextLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeCaption1.medium()
        return label
    }()

    private lazy var timeBubbleView: UIView = {
        let visualEffect: UIVisualEffect
        if #available(iOS 26, *) {
            visualEffect = UIGlassEffect(style: .regular)
        } else {
            visualEffect = UIBlurEffect(style: .regular)
        }
        let view = UIVisualEffectView(effect: visualEffect)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 4)
        timeBubbleTextLabel.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.addSubview(timeBubbleTextLabel)
        NSLayoutConstraint.activate([
            timeBubbleTextLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            timeBubbleTextLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            timeBubbleTextLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            timeBubbleTextLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
        if #available(iOS 26, *) {
            view.cornerConfiguration = .capsule()
        } else {
            view.layer.cornerRadius = 6
        }

        return view
    }()

    private var timeBubbleViewPositionConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)

        backgroundColor = .ows_gray65

        // Don't clip this view; the time bubble is drawn above it.
        trimFrameView.clipsToBounds = true
        if #available(iOS 26, *) {
            let cornerConfig = UICornerConfiguration.uniformCorners(radius: .fixed(Constants.cornerRadius))
            cornerConfiguration = cornerConfig
            trimFrameView.cornerConfiguration = cornerConfig
        } else {
            layer.cornerRadius = Constants.cornerRadius
            trimFrameView.layer.cornerRadius = Constants.cornerRadius
        }

        // Thumbnail strip.
        thumbnailLayerView.backgroundColor = backgroundColor
        thumbnailLayerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailLayerView)
        NSLayoutConstraint.activate([
            thumbnailLayerView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: TrimFrameView.horizontalEdgeThickness,
            ),
            thumbnailLayerView.leftAnchor.constraint(
                equalTo: leftAnchor,
                constant: TrimFrameView.verticalEdgeThickness,
            ),
            thumbnailLayerView.rightAnchor.constraint(
                equalTo: rightAnchor,
                constant: -TrimFrameView.verticalEdgeThickness,
            ),
            thumbnailLayerView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -TrimFrameView.horizontalEdgeThickness,
            ),
        ])

        // This layer dims thumbnail strip outside of trimmed area.
        // TODO: check if it is possible to change opacity on thumbnailLayerView instead.
        thumbnailDimmingLayer.fillColor = UIColor.ows_blackAlpha50.cgColor
        thumbnailDimmingLayer.fillRule = .evenOdd
        thumbnailDimmingLayer.zPosition = 10000
        thumbnailLayerView.layer.addSublayer(thumbnailDimmingLayer)

        // Layout callback that sets dimming frame.
        thumbnailLayerView.layoutCallback = { [weak self] view in
            guard let self else { return }

            let overlayPath = UIBezierPath()
            overlayPath.append(UIBezierPath(rect: self.thumbnailStripOverlayRectLeft))
            overlayPath.append(UIBezierPath(rect: self.thumbnailStripOverlayRectRight))
            self.thumbnailDimmingLayer.path = overlayPath.cgPath
            self.thumbnailDimmingLayer.frame = view.bounds

            updateThumbnailStrip()
        }

        // Trim frame
        trimFrameView.frame = bounds
        addSubview(trimFrameView)

        // Cursor
        addSubview(cursorView)

        addGestureRecognizer(PermissiveGestureRecognizer(target: self, action: #selector(gestureDidChange)))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: Constants.timelineHeight + 2 * TrimFrameView.horizontalEdgeThickness,
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTrimFrame()
        updateThumbnailStrip()
        updateCursorPosition()
    }

    // MARK: - Updates

    private var lastKnownThumbnailStripWidth: CGFloat?

    func updateThumbnailStrip() {
        guard thumbnailLayerView.frame.isEmpty == false else { return }

        let thumbnailStripRect = thumbnailLayerView.bounds
        guard thumbnailStripRect.width != lastKnownThumbnailStripWidth else { return }

        if let sublayers = thumbnailLayerView.layer.sublayers {
            for sublayer in sublayers {
                guard sublayer != thumbnailDimmingLayer else { continue }
                sublayer.removeFromSuperlayer()
            }
        }

        guard let dataSource, let videoThumbnails = dataSource.videoThumbnails else { return }

        // We want thumbnails to have the same aspect ratio as the video,
        // but also fill the entire thumbnail strip with a whole number of thumbnails.
        // Therefore the number of thumbnails of preferred width is rounded ("schoolbook rounding")
        // to minimize the difference between video and thumbnail aspect ratios.
        let videoAspectRatio = dataSource.videoAspectRatio
        let thumbnailHeight = thumbnailStripRect.height
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
            imageLayer.frame = CGRect(
                x: thumbnailStripRect.minX + CGFloat(index) * thumbnailWidth,
                y: thumbnailStripRect.minY,
                width: thumbnailWidth,
                height: thumbnailHeight,
            )
            thumbnailLayerView.layer.addSublayer(imageLayer)
        }

        lastKnownThumbnailStripWidth = thumbnailStripRect.width
    }

    func updateContents() {
        thumbnailLayerView.updateContent() // triggers `thumbnailLayerView.layoutCallback`
        updateTrimFrame()
        updateCursorPosition()
        updateTimeBubble()
    }

    private func updateTrimFrame() {
        trimFrameView.frame = trimFrameRect
        trimFrameView.frameColor = isTrimmedOrBeingTrimmed ? .Signal.yellow : .clear
    }

    func updateCursorPosition() {
        cursorView.center = cursorPosition
    }

    private var trimFrameRect: CGRect {
        innerTrimRect.insetBy(
            dx: -TrimFrameView.verticalEdgeThickness,
            dy: -TrimFrameView.horizontalEdgeThickness,
        )
    }

    /// - Returns Frame for the trimmed video fragment's thumbnail strip, in `VideoTimelineView` coordinate space.
    private var innerTrimRect: CGRect {
        let untrimmedRect = thumbnailLayerView.frame

        guard let dataSource else { return untrimmedRect }

        let untrimmedDurationSeconds = CGFloat(dataSource.untrimmedDurationSeconds)
        let startSeconds = CGFloat(dataSource.trimmedStartSeconds)
        let endSeconds = CGFloat(dataSource.trimmedEndSeconds)

        var result = untrimmedRect
        result.origin.x += startSeconds / untrimmedDurationSeconds * untrimmedRect.width
        result.size.width *= (endSeconds - startSeconds) / untrimmedDurationSeconds
        return result
    }

    /// - Returns Center coordinates for the `cursorView`, in `VideoTimelineView` coordinate space.
    private var cursorPosition: CGPoint {
        guard let dataSource else { return bounds.center }

        let startSeconds = CGFloat(dataSource.trimmedStartSeconds)
        let endSeconds = CGFloat(dataSource.trimmedEndSeconds)
        let currentTimeSeconds = CGFloat(dataSource.currentTimeSeconds)
        // alpha = 0 when playback is at start of trimmed clip.
        // alpha = 1 when playback is at end of trimmed clip.
        let playbackAlpha = currentTimeSeconds.inverseLerp(startSeconds, endSeconds, shouldClamp: true)

        let innerTrimRect = innerTrimRect
        let cursorPositionX = playbackAlpha.lerp(innerTrimRect.minX, innerTrimRect.maxX)
        return CGPoint(x: cursorPositionX, y: innerTrimRect.midY)
    }

    /**
     * - Returns Left part of `thumbnailLayerView` that is outside of the trim frame and should be dimmed,
     * in coordinates of `thumbnailLayerView`.
     */
    private var thumbnailStripOverlayRectLeft: CGRect {
        let adjustedInnerTrimRect = thumbnailLayerView.convert(innerTrimRect, from: self)
        var result = thumbnailLayerView.bounds
        // Left part has always the same origin as thumbnail strip, but shorter length.
        result.size.width = adjustedInnerTrimRect.minX - result.minX
        return result
    }

    /**
     * - Returns Right part of `thumbnailLayerView` that is outside of the trim frame and should be dimmed,
     * in coordinates of `thumbnailLayerView`.
     */
    private var thumbnailStripOverlayRectRight: CGRect {
        let adjustedInnerTrimRect = thumbnailLayerView.convert(innerTrimRect, from: self)
        var result = thumbnailLayerView.bounds
        // Right part has always the same maxX as thumbnailLayerView, but shorter length.
        result.size.width = result.maxX - adjustedInnerTrimRect.maxX
        result.origin.x = adjustedInnerTrimRect.maxX
        return result
    }

    private var isTrimmedOrBeingTrimmed: Bool {
        switch userInteraction {
        case .trimmingStart, .trimmingEnd:
            return true

        default:
            break
        }
        if let dataSource {
            return dataSource.isTrimmed
        }
        return false
    }

    // MARK: - Gestures

    @objc
    private func gestureDidChange(gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            userInteraction = interactionForNewGesture(gesture)
        }
        guard userInteraction != .none else {
            return
        }

        switch gesture.state {
        case .began:
            switch userInteraction {
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

    private func interactionForNewGesture(_ gesture: UIGestureRecognizer) -> UserInteraction {
        guard let dataSource else {
            return .none
        }

        let location = gesture.location(in: self)
        let innerTrimRect = innerTrimRect
        let outerTrimRect = innerTrimRect.insetBy(dx: -TrimFrameView.verticalEdgeThickness, dy: 0)

        // Our gesture handling is permissive, trim gestures can start
        // a little bit outside the visible "trim handles".
        let couldBeTrimStart = (
            dataSource.canBeTrimmed &&
                location.x >= (outerTrimRect.minX - Constants.extraHotArea) &&
                location.x <= (innerTrimRect.minX + Constants.extraHotArea),
        )
        let couldBeTrimEnd = (
            dataSource.canBeTrimmed &&
                location.x >= (innerTrimRect.maxX - Constants.extraHotArea) &&
                location.x <= (outerTrimRect.maxX + Constants.extraHotArea),
        )
        let couldBeScrub = (
            location.x >= innerTrimRect.minX &&
                location.x <= innerTrimRect.maxX,
        )

        // Prefer trimming to scrubbing.
        if couldBeTrimStart, couldBeTrimEnd {
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
        guard let dataSource, let delegate else {
            return
        }

        let adjustedHorizontalPosition = gesture.location(in: self).x - trimGestureLocationOffset
        let thumbnailStripRect = thumbnailLayerView.frame
        // alpha = 0 when gesture is at start of untrimmed clip.
        // alpha = 1 when gesture is at end of untrimmed clip.
        let untrimmedAlpha = Double(adjustedHorizontalPosition.inverseLerp(thumbnailStripRect.minX, thumbnailStripRect.maxX, shouldClamp: true))

        let startSeconds = dataSource.trimmedStartSeconds
        let endSeconds = dataSource.trimmedEndSeconds
        let untrimmedDurationSeconds = dataSource.untrimmedDurationSeconds
        let untrimmedSeconds = untrimmedDurationSeconds * untrimmedAlpha

        switch userInteraction {
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
        let previousMode = userInteraction
        userInteraction = .none

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

        let location = gesture.location(in: self)
        let thumbnailStripRect = thumbnailLayerView.frame
        if thumbnailStripRect.contains(location) == false {
            switch userInteraction {
            case .trimmingStart:
                trimGestureLocationOffset = min(0, location.x - thumbnailStripRect.minX)

            case .trimmingEnd:
                trimGestureLocationOffset = max(0, location.x - thumbnailStripRect.maxX)

            default:
                owsFailDebug("Invalid mode. [\(userInteraction)]")
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

    // MARK: - Time Bubble

    private enum TimeBubbleAlignment {
        case left
        case center
        case right
    }

    func updateTimeBubble() {
        guard let dataSource else {
            hideTimeBubble(animated: false)
            return
        }
        switch userInteraction {
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
            timeBubbleView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(timeBubbleView)
            NSLayoutConstraint.activate([
                timeBubbleView.bottomAnchor.constraint(equalTo: topAnchor, constant: -12),
            ])
        }

        var timeBubbleViewPositionConstraint: NSLayoutConstraint
        if let existingConstraint = self.timeBubbleViewPositionConstraint {
            timeBubbleViewPositionConstraint = existingConstraint
        } else {
            timeBubbleViewPositionConstraint = timeBubbleView.centerXAnchor.constraint(equalTo: leftAnchor)
            addConstraint(timeBubbleViewPositionConstraint)
            self.timeBubbleViewPositionConstraint = timeBubbleViewPositionConstraint
        }

        timeBubbleViewPositionConstraint.constant = {
            switch alignment {
            case .left:
                // Position strictly above left trim handle.
                return trimFrameView.frame.minX + 0.5 * TrimFrameView.verticalEdgeThickness
            case .right:
                // Position strictly above right trim handle.
                return trimFrameView.frame.maxX - 0.5 * TrimFrameView.verticalEdgeThickness
            case .center:
                // Position where current video playback is.
                return cursorView.center.x
            }
        }()

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

    private class TrimFrameView: UIView {

        static let horizontalEdgeThickness: CGFloat = 6
        static let verticalEdgeThickness: CGFloat = 16

        var frameColor: UIColor = .clear {
            didSet { shapeLayer.fillColor = frameColor.cgColor }
        }

        private let shapeLayer = CAShapeLayer()
        private let leftHandle = UIImageView(image: UIImage(imageLiteralResourceName: "video-trim-handle"))
        private let rightHandle = UIImageView(
            image: UIImage(imageLiteralResourceName: "video-trim-handle").withHorizontallyFlippedOrientation(),
        )

        override init(frame: CGRect) {
            super.init(frame: frame)

            isOpaque = false

            // Frame
            shapeLayer.fillRule = .evenOdd
            shapeLayer.fillColor = frameColor.cgColor
            layer.addSublayer(shapeLayer)

            // Handles
            leftHandle.tintColor = .white
            leftHandle.translatesAutoresizingMaskIntoConstraints = false
            addSubview(leftHandle)

            rightHandle.tintColor = .white
            rightHandle.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rightHandle)

            NSLayoutConstraint.activate([
                leftHandle.centerXAnchor.constraint(
                    equalTo: leftAnchor,
                    constant: Self.verticalEdgeThickness / 2,
                ),
                leftHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
                rightHandle.centerXAnchor.constraint(
                    equalTo: rightAnchor,
                    constant: -Self.verticalEdgeThickness / 2,
                ),
                rightHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            shapeLayer.frame = bounds
            shapeLayer.path = framePath(in: bounds)
        }

        private func framePath(in rect: CGRect) -> CGPath {
            let path = UIBezierPath(rect: rect)

            let innerRect = rect.insetBy(dx: Self.verticalEdgeThickness, dy: Self.horizontalEdgeThickness)
            if innerRect.isEmpty == false {
                path.append(UIBezierPath(rect: innerRect))
            }

            return path.cgPath
        }

        override var intrinsicContentSize: CGSize {
            CGSize(
                width: UIView.noIntrinsicMetric,
                height: Constants.timelineHeight + 2 * Self.horizontalEdgeThickness,
            )
        }
    }

    private class TimelineCursorView: UIView {

        private static let preferredSize = CGSize(
            width: 4,
            height: Constants.timelineHeight + TrimFrameView.horizontalEdgeThickness,
        )

        init() {
            super.init(frame: CGRect(origin: .zero, size: TimelineCursorView.preferredSize))

            isUserInteractionEnabled = false
            clipsToBounds = true
            backgroundColor = .white

            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = 4
            layer.shadowOpacity = 0.25
            layer.cornerRadius = Self.preferredSize.smallerAxis * 0.5
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            TimelineCursorView.preferredSize
        }
    }
}
