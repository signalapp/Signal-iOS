//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI
import UIKit

// MARK: - Camera Controls

protocol CameraCaptureControlDelegate: AnyObject {

    // MARK: Photo

    func cameraCaptureControlDidRequestCapturePhoto(_ control: CameraCaptureControl)

    // MARK: Video

    func cameraCaptureControlDidRequestStartVideoRecording(_ control: CameraCaptureControl)
    func cameraCaptureControlDidRequestFinishVideoRecording(_ control: CameraCaptureControl)
    func cameraCaptureControlDidRequestCancelVideoRecording(_ control: CameraCaptureControl)

    // MARK: Zoom

    var zoomScaleReferenceDistance: CGFloat? { get }
    func cameraCaptureControl(_ control: CameraCaptureControl, didUpdateZoomLevel zoomLevel: CGFloat)
}

final class CameraCaptureControl: UIControl {

    typealias Axis = NSLayoutConstraint.Axis
    var axis: Axis = .horizontal {
        didSet {
            if oldValue != axis {
                reactivateConstraintsForCurrentAxis()
                invalidateIntrinsicContentSize()
            }
        }
    }

    private var horizontalAxisConstraints = [NSLayoutConstraint]()
    private var verticalAxisConstraints = [NSLayoutConstraint]()

    // When locking video recording is in progress this view has unconventional bounds,
    // with shutter button not being centered within its bounds.
    // This layout guide allows owner to position this control using shutter button as the anchor.
    let shutterButtonLayoutGuide = UILayoutGuide()

    private let shutterButtonOuterCircle: UIVisualEffectView = {
        guard #available(iOS 26, *) else {
            return CircleBlurView(effect: UIBlurEffect(style: .light))
        }
        let view = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        view.clipsToBounds = true
        view.cornerConfiguration = .capsule()
        return view
    }()

    private lazy var shutterButtonOuterCircleWidthConstraint = shutterButtonOuterCircle.widthAnchor.constraint(
        equalToConstant: LayoutMetrics.outerCircleDefaultSize,
    )

    private let shutterButtonInnerCircle: UIView = {
        let view = CircleView()
        view.backgroundColor = .white
        return view
    }()

    private lazy var shutterButtonInnerCircleWidthConstraint = shutterButtonInnerCircle.widthAnchor.constraint(
        equalToConstant: LayoutMetrics.innerCircleSize,
    )

    private enum LayoutMetrics {
        static let innerCircleSize: CGFloat = 68

        static let outerCircleDefaultSize: CGFloat = 80
        static let outerCircleRecordingSize: CGFloat = 122

        static let stopButtonSize: CGFloat = 36
        static let recordingLockControlSize: CGFloat = 48
    }

    private lazy var slidingCircleView: CircleView = {
        let view = CircleView()
        view.bounds = CGRect(origin: .zero, size: .square(LayoutMetrics.stopButtonSize))
        view.backgroundColor = .Signal.red
        return view
    }()

    private lazy var lockIconView = LockView(frame: CGRect(origin: .zero, size: .square(LayoutMetrics.recordingLockControlSize)))

    private lazy var stopButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.background.backgroundColor = .Signal.red
        configuration.background.cornerRadius = 8
        configuration.cornerStyle = .fixed
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                self?.didTapStopButton()
            },
        )
    }()

    weak var delegate: CameraCaptureControlDelegate?

    init(axis: Axis) {
        super.init(frame: CGRect(origin: .zero, size: CameraCaptureControl.intrinsicContentSize(forAxis: axis)))

        self.axis = axis

        // Layout guide for the shutter button.
        addLayoutGuide(shutterButtonLayoutGuide)
        NSLayoutConstraint.activate([
            shutterButtonLayoutGuide.widthAnchor.constraint(
                equalToConstant: LayoutMetrics.outerCircleDefaultSize,
            ),
            shutterButtonLayoutGuide.heightAnchor.constraint(
                equalToConstant: LayoutMetrics.outerCircleDefaultSize,
            ),
        ])

        // Per-axis constraints for the layout guide.
        horizontalAxisConstraints = [
            shutterButtonLayoutGuide.centerXAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 0.5 * LayoutMetrics.outerCircleDefaultSize,
            ),
            shutterButtonLayoutGuide.topAnchor.constraint(
                equalTo: topAnchor,
            ),
            shutterButtonLayoutGuide.bottomAnchor.constraint(
                equalTo: bottomAnchor,
            ),
        ]
        verticalAxisConstraints = [
            shutterButtonLayoutGuide.leadingAnchor.constraint(
                equalTo: leadingAnchor,
            ),
            shutterButtonLayoutGuide.trailingAnchor.constraint(
                equalTo: trailingAnchor,
            ),
            shutterButtonLayoutGuide.centerYAnchor.constraint(
                equalTo: topAnchor,
                constant: 0.5 * LayoutMetrics.outerCircleDefaultSize,
            ),
        ]

        // Outer circle.
        shutterButtonOuterCircle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shutterButtonOuterCircle)
        NSLayoutConstraint.activate([
            shutterButtonOuterCircleWidthConstraint,
            shutterButtonOuterCircle.heightAnchor.constraint(equalTo: shutterButtonOuterCircle.widthAnchor),
            shutterButtonOuterCircle.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor),
            shutterButtonOuterCircle.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor),
        ])

        // Inner circle - placed on top of outer circle.
        shutterButtonInnerCircle.translatesAutoresizingMaskIntoConstraints = false
        shutterButtonOuterCircle.contentView.addSubview(shutterButtonInnerCircle)
        NSLayoutConstraint.activate([
            shutterButtonInnerCircleWidthConstraint,
            shutterButtonInnerCircle.heightAnchor.constraint(equalTo: shutterButtonInnerCircle.widthAnchor),
            shutterButtonInnerCircle.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor),
            shutterButtonInnerCircle.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor),
        ])

        // Stop Button
        stopButton.alpha = 0
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stopButton)
        NSLayoutConstraint.activate([
            stopButton.widthAnchor.constraint(equalToConstant: LayoutMetrics.stopButtonSize),
            stopButton.heightAnchor.constraint(equalTo: stopButton.widthAnchor),
            stopButton.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor),
            stopButton.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor),
        ])

        // The long press handles both the tap and the hold interaction, as well as the animation
        // the presents as the user begins to hold (and the button begins to grow prior to recording)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0
        shutterButtonOuterCircle.isUserInteractionEnabled = true
        shutterButtonInnerCircle.isUserInteractionEnabled = false
        shutterButtonOuterCircle.addGestureRecognizer(longPressGesture)

        reactivateConstraintsForCurrentAxis()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI State

    enum RecordingState {
        case notRecording
        case maybeStartingRecording
        case recording
        case recordingLocked
        case recordingUsingVoiceOver
    }

    private var _recordingState: RecordingState = .notRecording
    var recordingState: RecordingState {
        get { _recordingState }
        set { setRecordingState(newValue, animationDuration: 0) }
    }

    private var sliderTrackingProgress: CGFloat = 0 {
        willSet {
            if newValue > 0 {
                // Prepare "slide to lock" UI in case user swipes right too fast
                // and animation for setState(.recording) isn't finished yet.
                prepareLongPressVideoRecordingControlsIfNecessary()
            }
        }
        didSet {
            guard isRecordingWithLongPress else { return }

            // Update size of the inner circle, that contracts with `sliderTrackingProgress` increasing.
            // Fully reveal stop button when sliderTrackingProgress == 0.5.
            let sizeChangeProgress = 2 * min(0.5, sliderTrackingProgress)
            shutterButtonOuterCircleWidthConstraint.constant = sizeChangeProgress.lerp(
                LayoutMetrics.outerCircleRecordingSize,
                LayoutMetrics.outerCircleDefaultSize,
            )
            shutterButtonInnerCircleWidthConstraint.constant = sizeChangeProgress.lerp(
                LayoutMetrics.innerCircleSize,
                LayoutMetrics.recordingLockControlSize,
            )
            // Hide the inner circle so that it is not visible when stop button is pressed.
            if sliderTrackingProgress > 0.5 {
                shutterButtonInnerCircle.alpha = 0
                slidingCircleView.backgroundColor = .white
            } else {
                shutterButtonInnerCircle.alpha = 1
                slidingCircleView.backgroundColor = .Signal.red
            }
        }
    }

    func setRecordingState(
        _ recordingState: RecordingState,
        isRecordingWithLongPress: Bool = false,
        animationDuration: TimeInterval = 0,
    ) {
        guard _recordingState != recordingState else { return }

        _recordingState = recordingState
        self.isRecordingWithLongPress = isRecordingWithLongPress

        if recordingState == .notRecording {
            // Hide "slide to lock" controls momentarily before animating the rest of the UI to "not recording" state.
            hideLongPressVideoRecordingControls()
        }
        if recordingState == .recordingUsingVoiceOver {
            stopButton.alpha = 1
        }

        if animationDuration > 0 {
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                options: [.beginFromCurrentState],
                animations: {
                    self.updateShutterButtonAppearanceForCurrentState()
                    self.setNeedsLayout()
                    self.layoutIfNeeded()
                },
                completion: { _ in
                    // When switching to "recording" state we want to prepare "slide to lock" UI elements
                    // in the completion handler because none of those elements are needed yet a this point.
                    // Adding the controls to the view hierarchy outside of the animation block
                    // also fixes an issue where stop button would be visible briefly during shutter button animations.
                    self.prepareLongPressVideoRecordingControlsIfNecessary()
                },
            )
        } else {
            updateShutterButtonAppearanceForCurrentState()
            prepareLongPressVideoRecordingControlsIfNecessary()
        }

        sendActions(for: .valueChanged)
    }

    private func updateShutterButtonAppearanceForCurrentState() {
        switch recordingState {
        case .notRecording, .maybeStartingRecording:
            shutterButtonInnerCircle.alpha = 1
            shutterButtonInnerCircle.backgroundColor = .white

            shutterButtonOuterCircleWidthConstraint.constant = LayoutMetrics.outerCircleDefaultSize
            shutterButtonInnerCircleWidthConstraint.constant = LayoutMetrics.innerCircleSize

        case .recording:
            shutterButtonInnerCircle.backgroundColor = .Signal.red
            shutterButtonOuterCircleWidthConstraint.constant = LayoutMetrics.outerCircleRecordingSize
            // Inner circle stays the same size initially and might get smaller as user moves the slider.

        case .recordingLocked:
            // This should already by at the correct size so this assignment is "just in case".
            shutterButtonInnerCircleWidthConstraint.constant = LayoutMetrics.stopButtonSize

        case .recordingUsingVoiceOver:
            shutterButtonOuterCircleWidthConstraint.constant = LayoutMetrics.outerCircleRecordingSize
            shutterButtonInnerCircleWidthConstraint.constant = LayoutMetrics.stopButtonSize
        }
    }

    private func initializeVideoRecordingControlsIfNecessary() {
        guard lockIconView.superview == nil else { return }

        // 1. Slider.
        addSubview(slidingCircleView)

        // 2. Lock Icon
        addSubview(lockIconView)
        lockIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lockIconView.widthAnchor.constraint(equalToConstant: LayoutMetrics.recordingLockControlSize),
            lockIconView.heightAnchor.constraint(equalTo: lockIconView.widthAnchor),
        ])
        // Centered vertically, pinned to trailing edge.
        let horizontalConstraints = [
            lockIconView.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor),
            lockIconView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        // Centered horizontally, pinned to bottom edge.
        let verticalConstraints = [
            lockIconView.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor),
            lockIconView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]

        // 3. Activate current constraints.
        horizontalAxisConstraints.append(contentsOf: horizontalConstraints)
        if axis == .horizontal {
            NSLayoutConstraint.activate(horizontalConstraints)
        }

        verticalAxisConstraints.append(contentsOf: verticalConstraints)
        if axis == .vertical {
            NSLayoutConstraint.activate(verticalConstraints)
        }

        setNeedsLayout()
        UIView.performWithoutAnimation {
            self.layoutIfNeeded()
        }
    }

    private func reactivateConstraintsForCurrentAxis() {
        switch axis {
        case .horizontal:
            NSLayoutConstraint.deactivate(verticalAxisConstraints)
            NSLayoutConstraint.activate(horizontalAxisConstraints)

        case .vertical:
            NSLayoutConstraint.deactivate(horizontalAxisConstraints)
            NSLayoutConstraint.activate(verticalAxisConstraints)

        @unknown default:
            owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
        }
    }

    override var intrinsicContentSize: CGSize {
        return Self.intrinsicContentSize(forAxis: axis)
    }

    private static func intrinsicContentSize(forAxis axis: Axis) -> CGSize {
        switch axis {
        case .horizontal:
            return CGSize(
                width: LayoutMetrics.outerCircleDefaultSize + 64 + LayoutMetrics.recordingLockControlSize,
                height: LayoutMetrics.outerCircleDefaultSize,
            )

        case .vertical:
            return CGSize(
                width: LayoutMetrics.outerCircleDefaultSize,
                height: LayoutMetrics.outerCircleDefaultSize + 64 + LayoutMetrics.recordingLockControlSize,
            )

        @unknown default:
            owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
            return CGSize(square: UIView.noIntrinsicMetric)
        }
    }

    // MARK: - Photo / Video Capture

    private func capturePhoto() {
        delegate?.cameraCaptureControlDidRequestCapturePhoto(self)
    }

    private func startVideoRecording() {
        delegate?.cameraCaptureControlDidRequestStartVideoRecording(self)
    }

    private func cancelVideoRecording() {
        delegate?.cameraCaptureControlDidRequestCancelVideoRecording(self)
    }

    private func finishVideoRecording() {
        delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
    }

    // MARK: - Gestures

    private let animationDuration: TimeInterval = 0.2
    private var isRecordingWithLongPress = false
    private static let longPressDurationThreshold = 0.5
    private var initialTouchLocation: CGPoint?
    private var initialZoomPosition: CGFloat?
    private var touchTimer: Timer?

    private var initialSlidingCircleViewCenter: CGPoint {
        shutterButtonOuterCircle.center
    }

    private var finalSlidingCircleViewCenter: CGPoint {
        lockIconView.center
    }

    @objc
    private func handleLongPress(gesture: UILongPressGestureRecognizer) {

        let currentLocation = gesture.location(in: self)

        switch gesture.state {
        case .possible:
            break

        case .began:
            guard recordingState == .notRecording else { break }

            recordingState = .maybeStartingRecording
            sliderTrackingProgress = 0
            initialTouchLocation = currentLocation
            initialZoomPosition = nil

            touchTimer?.invalidate()
            touchTimer = WeakTimer.scheduledTimer(
                timeInterval: CameraCaptureControl.longPressDurationThreshold,
                target: self,
                userInfo: nil,
                repeats: false,
            ) { [weak self] _ in
                guard let self else { return }

                self.setRecordingState(
                    .recording,
                    isRecordingWithLongPress: true,
                    animationDuration: 2 * self.animationDuration,
                )
                self.startVideoRecording()
            }

        case .changed:
            guard recordingState == .recording else { break }

            guard let referenceDistance = delegate?.zoomScaleReferenceDistance else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceDistance > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            // Zoom - only use if slide to lock hasn't been activated.
            var zoomLevel: CGFloat = 0
            if sliderTrackingProgress == 0 {
                let currentSlideOffset: CGFloat = {
                    switch axis {
                    case .horizontal:
                        if let initialZoomPosition {
                            return initialZoomPosition - currentLocation.y
                        } else {
                            initialZoomPosition = currentLocation.y
                            return 0
                        }

                    case .vertical:
                        if let initialZoomPosition {
                            if CurrentAppContext().isRTL {
                                return currentLocation.x - initialZoomPosition
                            } else {
                                return initialZoomPosition - currentLocation.x
                            }
                        } else {
                            initialZoomPosition = currentLocation.x
                            return 0
                        }

                    @unknown default:
                        owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
                        return 0
                    }
                }()

                let minDistanceBeforeActivatingZoom: CGFloat = 30
                let ratio = max(0, currentSlideOffset - minDistanceBeforeActivatingZoom) / (referenceDistance - minDistanceBeforeActivatingZoom)
                zoomLevel = ratio.clamp(0, 1)

                delegate?.cameraCaptureControl(self, didUpdateZoomLevel: zoomLevel)
            } else {
                initialZoomPosition = nil
            }

            // Video Recording Lock - only works if zoom level == 0
            if zoomLevel == 0 {
                switch axis {
                case .horizontal:
                    let xOffset = currentLocation.x - initialTouchLocation.x
                    updateHorizontalTracking(xOffset: xOffset)

                case .vertical:
                    let yOffset = currentLocation.y - initialTouchLocation.y
                    updateVerticalTracking(yOffset: yOffset)

                @unknown default:
                    owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
                }
            }

        case .ended:
            touchTimer?.invalidate()
            touchTimer = nil

            switch recordingState {
            case .recording:
                let shouldLockRecording = sliderTrackingProgress > 0.5

                // 1. Snap slider to one of the endpoints with the spring animation.
                let finalCenter = shouldLockRecording ? finalSlidingCircleViewCenter : initialSlidingCircleViewCenter
                UIView.animate(
                    withDuration: animationDuration,
                    delay: 0,
                    usingSpringWithDamping: 1,
                    initialSpringVelocity: 0,
                    options: [.beginFromCurrentState],
                ) {
                    self.slidingCircleView.center = finalCenter
                }

                // 2. Simultaneously with animating the slider animate the rest of the UI.
                if shouldLockRecording {
                    sliderTrackingProgress = 1
                    lockIconView.setState(.locked, animated: true)
                    setRecordingState(.recordingLocked, animationDuration: animationDuration)
                } else {
                    // Animate change of inner (white) circle back to normal...
                    sliderTrackingProgress = 0
                    UIView.animate(
                        withDuration: animationDuration,
                        animations: {
                            self.layoutIfNeeded()
                        },
                        completion: { _ in
                            // ...and only then animate the rest of the shutter button to its initial state.
                            self.setRecordingState(.notRecording, animationDuration: self.animationDuration)
                        },
                    )

                    finishVideoRecording()
                }

            case .notRecording, .maybeStartingRecording:
                if recordingState == .maybeStartingRecording {
                    recordingState = .notRecording
                }
                capturePhoto()

            case .recordingLocked, .recordingUsingVoiceOver:
                break
            }

        case .cancelled, .failed:
            if recordingState == .recording {
                sliderTrackingProgress = 0
                setRecordingState(.notRecording, animationDuration: animationDuration)
                cancelVideoRecording()
            }

            touchTimer?.invalidate()
            touchTimer = nil

        @unknown default:
            owsFailDebug("unexpected gesture state: \(gesture.state.rawValue)")
        }
    }

    private static let minDistanceBeforeActivatingLockSlider: CGFloat = 30

    private func updateHorizontalTracking(xOffset: CGFloat) {
        // RTL: Slider should be moved to the left and xOffset would be negative.
        let effectiveOffset = CurrentAppContext().isRTL ? min(0, xOffset + Self.minDistanceBeforeActivatingLockSlider) : max(0, xOffset - Self.minDistanceBeforeActivatingLockSlider)
        slidingCircleView.center = initialSlidingCircleViewCenter.plusX(effectiveOffset)

        let distanceToLock = abs(lockIconView.center.x - initialSlidingCircleViewCenter.x)
        sliderTrackingProgress = abs(effectiveOffset / distanceToLock).clamp(0, 1)
        updateLockStateAndPlayHapticFeedbackIfNecessary()

        Logger.debug("xOffset: \(xOffset), effectiveOffset: \(effectiveOffset),  distanceToLock: \(distanceToLock), progress: \(sliderTrackingProgress)")
    }

    private func updateVerticalTracking(yOffset: CGFloat) {
        let effectiveOffset = max(0, yOffset - Self.minDistanceBeforeActivatingLockSlider)
        slidingCircleView.center = initialSlidingCircleViewCenter.plusY(effectiveOffset)

        let distanceToLock = abs(lockIconView.center.y - initialSlidingCircleViewCenter.y)
        sliderTrackingProgress = (effectiveOffset / distanceToLock).clamp(0, 1)
        updateLockStateAndPlayHapticFeedbackIfNecessary()

        Logger.debug("yOffset: \(yOffset), effectiveOffset: \(effectiveOffset),  distanceToLock: \(distanceToLock), progress: \(sliderTrackingProgress)")
    }

    private func updateLockStateAndPlayHapticFeedbackIfNecessary() {
        let newLockState: LockView.State = sliderTrackingProgress > 0.5 ? .locking : .unlocked
        if lockIconView.state != newLockState {
            lockIconView.setState(newLockState, animated: true)
        }
    }

    private func prepareLongPressVideoRecordingControlsIfNecessary() {
        guard recordingState == .recording, sliderTrackingProgress == 0, isRecordingWithLongPress else { return }

        initializeVideoRecordingControlsIfNecessary()

        stopButton.alpha = 1

        slidingCircleView.alpha = 1
        slidingCircleView.center = initialSlidingCircleViewCenter

        lockIconView.alpha = 1
        lockIconView.state = .unlocked
    }

    private func hideLongPressVideoRecordingControls() {
        // Hide these two without animation because they're in the shutter button
        // and will interfere with circles animating.
        stopButton.alpha = 0
        slidingCircleView.alpha = 0

        // Fade out the lock icon because it is separated visually from the rest of the UI.
        UIView.animate(withDuration: animationDuration) {
            self.lockIconView.alpha = 0
        }
    }

    // MARK: - Button Actions

    private func didTapStopButton() {
        finishVideoRecording()
    }

    // MARK: - Recording lock indicator.

    private class LockView: UIView {
        private let imageViewLock = UIImageView(image: UIImage(resource: .lock))

        private let visualEffectBackgroundView: UIVisualEffectView = {
            guard #available(iOS 26, *) else {
                return CircleBlurView(effect: UIBlurEffect(style: .dark))
            }
            let view = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            view.cornerConfiguration = .capsule()
            return view
        }()

        private let whiteBackgroundView: UIView = {
            let view: UIView
            if #available(iOS 26, *) {
                view = UIView()
                view.cornerConfiguration = .capsule()
            } else {
                view = CircleView()
            }
            view.backgroundColor = .white
            return view
        }()

        private let whiteCircleView: UIView = {
            let view: UIView
            if #available(iOS 26, *) {
                view = UIView()
                view.cornerConfiguration = .capsule()
            } else {
                view = CircleView()
            }
            view.backgroundColor = .clear
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.borderWidth = 3
            return view
        }()

        enum State {
            case unlocked
            case locking
            case locked
        }

        private var _state: State = .unlocked
        var state: State {
            get {
                _state
            }
            set {
                guard _state != newValue else { return }
                setState(newValue, animated: false)
            }
        }

        func setState(_ state: State, animated: Bool) {
            _state = state
            if animated {
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    options: [.beginFromCurrentState],
                ) {
                    self.updateAppearance()
                }
            } else {
                updateAppearance()
            }
        }

        private func updateAppearance() {
            switch state {
            case .unlocked:
                visualEffectBackgroundView.alpha = 1
                whiteCircleView.alpha = 0
                whiteBackgroundView.alpha = 0
                imageViewLock.alpha = 1
                imageViewLock.tintColor = .white

            case .locking:
                visualEffectBackgroundView.alpha = 1
                whiteCircleView.alpha = 1
                whiteBackgroundView.alpha = 0
                imageViewLock.alpha = 0

            case .locked:
                visualEffectBackgroundView.alpha = 0
                whiteCircleView.alpha = 0
                whiteBackgroundView.alpha = 1
                imageViewLock.alpha = 1
                imageViewLock.tintColor = .black
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            isUserInteractionEnabled = false

            addSubview(visualEffectBackgroundView)
            visualEffectBackgroundView.contentView.addSubview(whiteCircleView)
            addSubview(whiteBackgroundView)
            addSubview(imageViewLock)

            visualEffectBackgroundView.translatesAutoresizingMaskIntoConstraints = false
            whiteCircleView.translatesAutoresizingMaskIntoConstraints = false
            whiteBackgroundView.translatesAutoresizingMaskIntoConstraints = false
            imageViewLock.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                visualEffectBackgroundView.topAnchor.constraint(equalTo: topAnchor),
                visualEffectBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffectBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffectBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

                whiteCircleView.topAnchor.constraint(equalTo: visualEffectBackgroundView.topAnchor),
                whiteCircleView.leadingAnchor.constraint(equalTo: visualEffectBackgroundView.leadingAnchor),
                whiteCircleView.trailingAnchor.constraint(equalTo: visualEffectBackgroundView.trailingAnchor),
                whiteCircleView.bottomAnchor.constraint(equalTo: visualEffectBackgroundView.bottomAnchor),

                whiteBackgroundView.topAnchor.constraint(equalTo: topAnchor),
                whiteBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                whiteBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                whiteBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

                imageViewLock.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageViewLock.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])

            updateAppearance()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            .square(LayoutMetrics.recordingLockControlSize)
        }
    }
}

protocol CameraZoomSelectionControlDelegate: AnyObject {

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didSelect camera: CameraCaptureSession.CameraType)

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didChangeZoomFactor zoomFactor: CGFloat)
}

class CameraZoomSelectionControl: UIView {

    typealias Axis = NSLayoutConstraint.Axis

    weak var delegate: CameraZoomSelectionControlDelegate?

    private let availableCameras: [CameraCaptureSession.CameraType]

    var selectedCamera: CameraCaptureSession.CameraType

    var currentZoomFactor: CGFloat {
        didSet {
            var viewFound = false
            for selectionView in selectionViews.reversed() {
                if currentZoomFactor >= selectionView.defaultZoomFactor, !viewFound {
                    selectionView.isSelected = true
                    selectionView.currentZoomFactor = currentZoomFactor
                    selectionView.update(animated: true)
                    viewFound = true
                } else if selectionView.isSelected {
                    selectionView.isSelected = false
                    selectionView.update(animated: true)
                }
            }
        }
    }

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.spacing = 2
        stackView.axis = .horizontal
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

    private let selectionViews: [CameraSelectionCircleView]

    var cameraZoomLevelIndicators: [UIView] {
        selectionViews
    }

    var axis: Axis {
        get { stackView.axis }
        set { stackView.axis = newValue }
    }

    init(availableCameras: [(cameraType: CameraCaptureSession.CameraType, defaultZoomFactor: CGFloat)]) {
        owsAssertDebug(!availableCameras.isEmpty, "availableCameras must not be empty.")

        self.availableCameras = availableCameras.map { $0.cameraType }

        let (wideAngleCamera, wideAngleCameraZoomFactor) = availableCameras.first(where: { $0.cameraType == .wideAngle }) ?? availableCameras.first!
        selectedCamera = wideAngleCamera
        currentZoomFactor = wideAngleCameraZoomFactor

        selectionViews = availableCameras.map {
            CameraSelectionCircleView(cameraType: $0.cameraType, defaultZoomFactor: $0.defaultZoomFactor)
        }

        super.init(frame: .zero)

        let extendBackground = selectionViews.count > 1
        layoutMargins = UIEdgeInsets(margin: extendBackground ? 2 : 0)

        selectionViews.forEach { view in
            view.isSelected = view.cameraType == selectedCamera
            view.update(animated: false)
        }
        stackView.addArrangedSubviews(selectionViews)

        // Background view is present even if there's just one zoom level.
        // If there's just one zoom level the background is the same size as the circle.
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)
        if #available(iOS 26, *) {
            backgroundView.cornerConfiguration = .capsule()
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Adding `stackView` to `backgroundView.contentView` causes infinite layout loop in UIKit.
        // Therefore add it to self which looks the same visually.
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(gesture:)))
        addGestureRecognizer(tapGestureRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if #unavailable(iOS 26) {
            backgroundView.layer.cornerRadius = 0.5 * bounds.size.smallerAxis
        }
    }

    // MARK: - Selection

    @objc
    private func handleTap(gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        var tappedView: CameraSelectionCircleView?
        for selectionView in selectionViews {
            if selectionView.point(inside: gesture.location(in: selectionView), with: nil) {
                tappedView = selectionView
                break
            }
        }

        if let selectedView = tappedView {
            selectionViews.forEach { view in
                if view.isSelected, view != selectedView {
                    view.isSelected = false
                    view.update(animated: true)
                } else if view == selectedView {
                    view.isSelected = true
                    view.update(animated: true)
                }
            }
            selectedCamera = selectedView.cameraType
            delegate?.cameraZoomControl(self, didSelect: selectedCamera)
        }
    }

    private class CameraSelectionCircleView: UIView {

        let cameraType: CameraCaptureSession.CameraType
        let defaultZoomFactor: CGFloat
        var currentZoomFactor: CGFloat = 1

        private let circleView: CircleView = {
            let circleView = CircleView()
            circleView.backgroundColor = .ows_blackAlpha20
            return circleView
        }()

        private let textLabel: UILabel = {
            let label = UILabel()
            label.textAlignment = .center
            label.textColor = .white
            label.font = .semiboldFont(ofSize: 11)
            return label
        }()

        init(cameraType: CameraCaptureSession.CameraType, defaultZoomFactor: CGFloat) {
            self.cameraType = cameraType
            self.defaultZoomFactor = defaultZoomFactor
            self.currentZoomFactor = defaultZoomFactor

            super.init(frame: .zero)

            addSubview(circleView)
            addSubview(textLabel)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            textLabel.frame = bounds

            let circleDiameter = isSelected ? Self.circleDiamererSelectedState : Self.circleDiameterDefaultState
            circleView.frame = CGRect(
                origin: CGPoint(
                    x: 0.5 * (bounds.width - circleDiameter),
                    y: 0.5 * (bounds.height - circleDiameter),
                ),
                size: CGSize(square: circleDiameter),
            )
        }

        var isSelected: Bool = false {
            didSet {
                if !isSelected {
                    currentZoomFactor = defaultZoomFactor
                }
            }
        }

        private static let circleDiamererSelectedState: CGFloat = 38
        private static let circleDiameterDefaultState: CGFloat = 24

        private static let numberFormatterNormal: NumberFormatter = {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumIntegerDigits = 0
            numberFormatter.maximumFractionDigits = 1
            return numberFormatter
        }()

        private static let numberFormatterSelected: NumberFormatter = {
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumIntegerDigits = 1
            numberFormatter.maximumFractionDigits = 1
            return numberFormatter
        }()

        private class func cameraLabel(forZoomFactor zoomFactor: CGFloat, isSelected: Bool) -> String {
            let numberFormatter = isSelected ? numberFormatterSelected : numberFormatterNormal
            // Don't allow 0.95 to be rounded to 1.
            let adjustedZoomFactor = floor(zoomFactor * 10) / 10
            guard var scaleString = numberFormatter.string(for: adjustedZoomFactor) else {
                return ""
            }
            if isSelected {
                scaleString.append("×")
            }
            return scaleString
        }

        private static let animationDuration: TimeInterval = 0.2

        func update(animated: Bool) {
            textLabel.text = Self.cameraLabel(forZoomFactor: currentZoomFactor, isSelected: isSelected)

            let animations = {
                if self.isSelected {
                    self.textLabel.layer.transform = CATransform3DMakeScale(1.2, 1.2, 1)
                } else {
                    self.textLabel.layer.transform = CATransform3DIdentity
                }

                self.setNeedsLayout()
                self.layoutIfNeeded()
            }

            if animated {
                UIView.animate(
                    withDuration: Self.animationDuration,
                    delay: 0,
                    options: [.curveEaseInOut],
                ) {
                    animations()
                }
            } else {
                animations()
            }
        }

        override var intrinsicContentSize: CGSize { .square(Self.circleDiamererSelectedState) }

        override var isAccessibilityElement: Bool {
            get { false }
            set { super.isAccessibilityElement = newValue }
        }
    }
}

final class RecordingDurationView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        let backgroundView: UIView
        if #available(iOS 26, *) {
            directionalLayoutMargins = .init(hMargin: 15, vMargin: 10)

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = .Signal.red
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .capsule()
            addSubview(glassEffectView)
            glassEffectView.contentView.addSubview(label)

            backgroundView = glassEffectView
        } else {
            directionalLayoutMargins = .init(hMargin: 16, vMargin: 9)

            backgroundView = PillView()
            backgroundView.backgroundColor = .Signal.red
            addSubview(backgroundView)
            backgroundView.addSubview(label)
        }

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        updateDurationLabel()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var duration: TimeInterval = 0 {
        didSet {
            updateDurationLabel()
        }
    }

    // MARK: - Subviews

    private let label: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.textColor = .Signal.label
        return label
    }()

    // MARK: -

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter
    }()

    private func updateDurationLabel() {
        let durationDate = Date(timeIntervalSinceReferenceDate: duration)
        label.text = timeFormatter.string(from: durationDate)
    }
}

// MARK: - Buttons

final class BadgedProceedButton: UIButton {

    var badgeNumber: Int = 0 {
        didSet {
            textLabel.text = Self.numberFormatter.string(for: badgeNumber)
            badgeView.isHidden = badgeNumber == 0
        }
    }

    private static var badgeFont: UIFont {
        return UIFont.systemFont(ofSize: 13, weight: .bold).monospaced()
    }

    private static let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.font = .dynamicTypeFootnoteClamped.bold()
        return label
    }()

    private lazy var badgeView: UIView = {
        let badgeView = PillView(frame: .zero)
        badgeView.backgroundColor = .Signal.accent
        badgeView.layoutMargins = UIEdgeInsets(margin: 2)
        badgeView.addSubview(textLabel)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: badgeView.layoutMarginsGuide.topAnchor),
            textLabel.leadingAnchor.constraint(equalTo: badgeView.layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: badgeView.layoutMarginsGuide.trailingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: badgeView.layoutMarginsGuide.bottomAnchor),
        ])
        return badgeView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        configuration = .roundMedia(image: UIImage(resource: .chevronRight26), size: 40)

        badgeView.isHidden = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeView)
        NSLayoutConstraint.activate([
            badgeView.widthAnchor.constraint(greaterThanOrEqualTo: badgeView.heightAnchor),
            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: -6),
            badgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 4),
        ])

        accessibilityLabel = OWSLocalizedString(
            "CAMERA_VO_ARROW_RIGHT_PROCEED",
            comment: "VoiceOver label for -> button in text story composer.",
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FlashModeButton: UIButton {

    typealias Mode = AVCaptureDevice.FlashMode

    private var _mode: Mode

    var mode: Mode {
        get { _mode }
        set { setMode(newValue, animated: false) }
    }

    private static func icon(for mode: Mode) -> UIImage {
        switch mode {
        case .off:
            return UIImage(resource: .flashSlash)
        case .on:
            return UIImage(resource: .flash)
        case .auto:
            return UIImage(resource: .flashAuto)
        @unknown default:
            owsFailBeta("Unexpected AVCaptureDevice.FlashMode: \(mode.rawValue)")
            return UIImage(resource: .flashAuto)
        }
    }

    init(mode: Mode, size: CGFloat, withBackground: Bool) {
        _mode = mode

        super.init(frame: .zero)

        configuration = .roundMedia(
            image: FlashModeButton.icon(for: mode),
            size: size,
            withBackground: withBackground,
        )
        configurationUpdateHandler = { button in
            guard
                let flashModeButton = button as? FlashModeButton,
                var configuration = flashModeButton.configuration
            else { return }

            configuration.image = FlashModeButton.icon(for: flashModeButton.mode)
            button.configuration = configuration
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode, animated: Bool) {
        _mode = mode

        guard animated else {
            setNeedsUpdateConfiguration()
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.setNeedsUpdateConfiguration()
        }
    }
}

final class CaptureModeButton: UIButton {

    typealias Mode = PhotoCaptureViewController.CaptureMode

    private var _mode: Mode

    var mode: Mode {
        get { _mode }
        set { setMode(newValue, animated: false) }
    }

    private static func icon(for mode: Mode) -> UIImage {
        switch mode {
        case .single: UIImage(resource: .multicaptureOff)
        case .multi: UIImage(resource: .multicaptureOn)
        }
    }

    init(mode: Mode, size: CGFloat, withBackground: Bool) {
        _mode = mode

        super.init(frame: .zero)

        configuration = .roundMedia(
            image: CaptureModeButton.icon(for: mode),
            size: size,
            withBackground: withBackground,
        )
        configurationUpdateHandler = { button in
            guard
                let captureModeButton = button as? CaptureModeButton,
                var configuration = captureModeButton.configuration
            else { return }

            configuration.image = CaptureModeButton.icon(for: captureModeButton.mode)
            button.configuration = configuration
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var captureMode = PhotoCaptureViewController.CaptureMode.single

    func setMode(_ mode: Mode, animated: Bool) {
        _mode = mode

        guard animated else {
            setNeedsUpdateConfiguration()
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.setNeedsUpdateConfiguration()
        }
    }
}

final class SwitchCameraButton: UIButton {

    fileprivate var isFrontCameraActive = false

    init(size: CGFloat, withBackground: Bool) {
        super.init(frame: .zero)

        configuration = .roundMedia(
            image: UIImage(resource: .switchCamera),
            size: size,
            withBackground: withBackground,
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func performSwitchAnimation() {
        UIView.animate(withDuration: 0.2) {
            let epsilonToForceCounterClockwiseRotation: CGFloat = 0.00001
            self.transform = self.transform.rotate(.pi + epsilonToForceCounterClockwiseRotation)
        }
    }
}

final class PhotoLibraryButton: UIButton {

    init(size: CGFloat, withBackground: Bool) {
        super.init(frame: .zero)

        configuration = .roundMedia(
            image: UIImage(resource: .albumTilt),
            size: size,
            withBackground: withBackground,
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Toolbars

final class CameraTopBar: MediaTopBar {

    // Leading edge.
    let closeButton: UIButton = {
        let button = UIButton(configuration: .roundMedia(image: UIImage(resource: .x), size: 44))
        // Other buttons have accessibility configured in extensions.
        button.accessibilityLabel = OWSLocalizedString(
            "CAMERA_VO_CLOSE_BUTTON",
            comment: "VoiceOver label for close (X) button in camera.",
        )
        return button
    }()

    // Middle.
    let recordingTimerView = RecordingDurationView(frame: .zero)

    // Trailing edge.
    let captureModeButton: CaptureModeButton
    let flashModeButton: FlashModeButton

    // Bundles `captureModeButton` and `flashModeButton` together.
    private lazy var cameraControlsContainerView: UIView = {
        let buttonStack = UIStackView(arrangedSubviews: [captureModeButton, flashModeButton])

        guard #available(iOS 26, *) else {
            buttonStack.spacing = 16
            return buttonStack
        }

        buttonStack.isLayoutMarginsRelativeArrangement = true
        // Glass panel slightly exceeds outside edges of the buttons.
        // Target size for the panel is 100 x 44.
        buttonStack.spacing = 4
        buttonStack.directionalLayoutMargins = .init(hMargin: 6, vMargin: 0)

        let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glassEffectView.cornerConfiguration = .capsule()
        glassEffectView.contentView.addSubview(buttonStack)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
        ])
        return glassEffectView
    }()

    override init(frame: CGRect) {
        // No individual background for buttons that would be placed on a shared glass pill.
        let buttonsHaveBackground: Bool = if #available(iOS 26, *) { false } else { true }
        let buttonSize: CGFloat = 44
        captureModeButton = CaptureModeButton(mode: .single, size: buttonSize, withBackground: buttonsHaveBackground)
        flashModeButton = FlashModeButton(mode: .auto, size: buttonSize, withBackground: buttonsHaveBackground)

        super.init(frame: frame)

        addSubview(closeButton)
        addSubview(recordingTimerView)
        addSubview(cameraControlsContainerView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        recordingTimerView.translatesAutoresizingMaskIntoConstraints = false
        cameraControlsContainerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: controlsLayoutGuide.leadingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor),

            recordingTimerView.centerYAnchor.constraint(equalTo: controlsLayoutGuide.centerYAnchor),
            recordingTimerView.centerXAnchor.constraint(equalTo: controlsLayoutGuide.centerXAnchor),

            cameraControlsContainerView.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor),
            cameraControlsContainerView.trailingAnchor.constraint(equalTo: controlsLayoutGuide.trailingAnchor),
            cameraControlsContainerView.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor),
        ])

        updateElementsVisibility(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Mode

    enum Mode {
        case cameraControls
        case closeButton
        case videoRecording
    }

    private var _mode: Mode = .cameraControls

    var mode: Mode {
        get { _mode }
        set { setMode(newValue, animated: false) }
    }

    func setMode(_ mode: Mode, animated: Bool) {
        guard _mode != mode else { return }

        _mode = mode
        updateElementsVisibility(animated: animated)
    }

    private func updateElementsVisibility(animated: Bool) {
        switch mode {
        case .cameraControls:
            closeButton.setIsHidden(false, animated: animated)
            cameraControlsContainerView.setIsHidden(false, animated: animated)
            recordingTimerView.setIsHidden(true, animated: animated)

        case .closeButton:
            closeButton.setIsHidden(false, animated: animated)
            cameraControlsContainerView.setIsHidden(true, animated: animated)
            recordingTimerView.setIsHidden(true, animated: animated)

        case .videoRecording:
            closeButton.setIsHidden(true, animated: animated)
            cameraControlsContainerView.setIsHidden(true, animated: animated)
            recordingTimerView.setIsHidden(false, animated: animated)
        }
    }
}

/// Contains Photo Library button, Shutter button and Switch Cameras button in horizontal layout.
/// Designed to be placed along the bottom of the screen.
final class CameraBottomBar: UIView {

    var _isRecordingVideo = false
    var isRecordingVideo: Bool {
        get { _isRecordingVideo }
        set { setIsRecordingVideo(newValue, animated: false) }
    }

    func setIsRecordingVideo(_ isRecording: Bool, animated: Bool) {
        _isRecordingVideo = isRecording
        photoLibraryButton.setIsHidden(isRecording, animated: animated)
        switchCameraButton.setIsHidden(isRecording, animated: animated)
    }

    private var _isFrontCameraActive = false
    var isFrontCameraActive: Bool {
        get { _isFrontCameraActive }
        set { setIsFrontCameraActive(newValue, animated: false) }
    }

    func setIsFrontCameraActive(_ isFrontCameraActive: Bool, animated: Bool) {
        _isFrontCameraActive = isFrontCameraActive

        switchCameraButton.isFrontCameraActive = isFrontCameraActive
    }

    let photoLibraryButton = PhotoLibraryButton(size: 48, withBackground: true)
    let switchCameraButton = SwitchCameraButton(size: 48, withBackground: true)
    let captureControl = CameraCaptureControl(axis: .horizontal)

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true

        addSubview(photoLibraryButton)
        addSubview(captureControl)
        addSubview(switchCameraButton)

        captureControl.translatesAutoresizingMaskIntoConstraints = false
        photoLibraryButton.translatesAutoresizingMaskIntoConstraints = false
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            photoLibraryButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            photoLibraryButton.centerYAnchor.constraint(equalTo: captureControl.centerYAnchor),

            captureControl.topAnchor.constraint(equalTo: topAnchor),
            captureControl.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            captureControl.shutterButtonLayoutGuide.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            captureControl.bottomAnchor.constraint(equalTo: bottomAnchor),

            switchCameraButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            switchCameraButton.centerYAnchor.constraint(equalTo: captureControl.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Override to allow touches that hit empty area of the toobar to pass through to views underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        guard view != self else { return nil }
        return view
    }
}

/// Contains Capture Mode, Flash, Switch Camera, Shutter, Choose Photo buttons in vertical layout.
/// Designed to be placed along the trailing edge of the screen on an iPad.
final class CameraSideBar: UIView {

    var _isRecordingVideo = false
    var isRecordingVideo: Bool {
        get { _isRecordingVideo }
        set { setIsRecordingVideo(newValue, animated: false) }
    }

    func setIsRecordingVideo(_ isRecording: Bool, animated: Bool) {
        _isRecordingVideo = isRecording
        cameraControlsContainerView.setIsHidden(isRecording, animated: animated)
        photoLibraryButton.setIsHidden(isRecording, animated: animated)
    }

    private var _isFrontCameraActive = false
    var isFrontCameraActive: Bool {
        get { _isFrontCameraActive }
        set { setIsFrontCameraActive(newValue, animated: false) }
    }

    func setIsFrontCameraActive(_ isFrontCameraActive: Bool, animated: Bool) {
        _isFrontCameraActive = isFrontCameraActive

        switchCameraButton.isFrontCameraActive = isFrontCameraActive
    }

    // Above the shutter button.
    let captureModeButton: CaptureModeButton
    let flashModeButton: FlashModeButton
    let switchCameraButton: SwitchCameraButton

    // Bundles `captureModeButton`, `flashModeButton` and `switchCameraButton` together.
    private lazy var cameraControlsContainerView: UIView = {
        let buttonStack = UIStackView(arrangedSubviews: [captureModeButton, flashModeButton, switchCameraButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 16
        return buttonStack
    }()

    // Below the shutter button.
    let photoLibraryButton: PhotoLibraryButton

    // Shutter button.
    private(set) var cameraCaptureControl = CameraCaptureControl(axis: .vertical)

    override init(frame: CGRect) {
        captureModeButton = CaptureModeButton(mode: .single, size: 48, withBackground: true)
        flashModeButton = FlashModeButton(mode: .auto, size: 48, withBackground: true)
        switchCameraButton = SwitchCameraButton(size: 48, withBackground: true)
        photoLibraryButton = PhotoLibraryButton(size: 48, withBackground: true)

        super.init(frame: frame)

        addSubview(cameraControlsContainerView)
        addSubview(cameraCaptureControl)
        addSubview(photoLibraryButton)

        cameraControlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        cameraCaptureControl.translatesAutoresizingMaskIntoConstraints = false
        photoLibraryButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            cameraControlsContainerView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            cameraControlsContainerView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),

            cameraCaptureControl.shutterButtonLayoutGuide.topAnchor.constraint(
                equalTo: cameraControlsContainerView.bottomAnchor,
                constant: 24,
            ),
            cameraCaptureControl.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            cameraCaptureControl.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            photoLibraryButton.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            photoLibraryButton.topAnchor.constraint(
                equalTo: cameraCaptureControl.shutterButtonLayoutGuide.bottomAnchor,
                constant: 24,
            ),
            photoLibraryButton.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Other Controls

final class CameraZoomControlsView: UIView {

    typealias Axis = NSLayoutConstraint.Axis

    var axis = Axis.horizontal {
        didSet {
            frontCameraZoomControl?.axis = axis
            rearCameraZoomControl?.axis = axis
        }
    }

    let frontCameraZoomControl: CameraZoomSelectionControl?
    let rearCameraZoomControl: CameraZoomSelectionControl?

    private var _isFrontCameraActive = false
    var isFrontCameraActive: Bool {
        get { _isFrontCameraActive }
        set { setIsFrontCameraActive(newValue, animated: false) }
    }

    func setIsFrontCameraActive(_ isFrontCameraActive: Bool, animated: Bool) {
        _isFrontCameraActive = isFrontCameraActive

        frontCameraZoomControl?.setIsHidden(!isFrontCameraActive, animated: animated)
        rearCameraZoomControl?.setIsHidden(isFrontCameraActive, animated: animated)
    }

    init?(cameraCaptureSession: CameraCaptureSession, axis: Axis) {
        let availableFrontCameras = cameraCaptureSession.cameraZoomFactorMap(forPosition: .front)
        let availableRearCameras = cameraCaptureSession.cameraZoomFactorMap(forPosition: .back)

        if availableFrontCameras.isEmpty, availableRearCameras.isEmpty { return nil }

        if availableFrontCameras.count > 0 {
            let cameras = availableFrontCameras.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1) }
            frontCameraZoomControl = CameraZoomSelectionControl(availableCameras: cameras)
        } else {
            frontCameraZoomControl = nil
        }

        if availableRearCameras.count > 0 {
            let cameras = availableRearCameras.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1) }
            rearCameraZoomControl = CameraZoomSelectionControl(availableCameras: cameras)
        } else {
            rearCameraZoomControl = nil
        }

        self.axis = axis

        super.init(frame: .zero)

        // TODO: controls can be of different size
        if let frontCameraZoomControl {
            frontCameraZoomControl.axis = axis
            frontCameraZoomControl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(frontCameraZoomControl)
            NSLayoutConstraint.activate([
                frontCameraZoomControl.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                frontCameraZoomControl.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                frontCameraZoomControl.centerXAnchor.constraint(equalTo: centerXAnchor),
                frontCameraZoomControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        if let rearCameraZoomControl {
            rearCameraZoomControl.axis = axis
            rearCameraZoomControl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(rearCameraZoomControl)
            NSLayoutConstraint.activate([
                rearCameraZoomControl.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                rearCameraZoomControl.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                rearCameraZoomControl.centerXAnchor.constraint(equalTo: centerXAnchor),
                rearCameraZoomControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ComposerTypeSelectionControl: UISegmentedControl {

    private static let titleCamera = OWSLocalizedString(
        "STORY_COMPOSER_CAMERA",
        comment: "One of two possible sources when composing a new story. Displayed at the bottom in in-app camera.",
    )
    private static let titleText = OWSLocalizedString(
        "STORY_COMPOSER_TEXT",
        comment: "One of two possible sources when composing a new story. Displayed at the bottom in in-app camera.",
    )

    init() {
        super.init(frame: .zero)

        insertSegment(withTitle: ComposerTypeSelectionControl.titleText.uppercased(), at: 0, animated: false)
        insertSegment(withTitle: ComposerTypeSelectionControl.titleCamera.uppercased(), at: 0, animated: false)

        // Use a clear image for the background and the dividers
        if #unavailable(iOS 26) {
            backgroundColor = .clear

            let tintColorImage = UIImage.image(color: .clear, size: CGSize(width: 1, height: 32))
            setBackgroundImage(tintColorImage, for: .normal, barMetrics: .default)
            setDividerImage(
                tintColorImage,
                forLeftSegmentState: .normal,
                rightSegmentState: .normal,
                barMetrics: .default,
            )
        }

        var fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        if #available(iOS 26, *), let rounded = fontDescriptor.withDesign(.rounded) {
            fontDescriptor = rounded
        }
        if #unavailable(iOS 26), let monospaced = fontDescriptor.withDesign(.monospaced) {
            fontDescriptor = monospaced
        }
        let normalFont = UIFont(descriptor: fontDescriptor, size: 14)
        let selectedFont = UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold)!, size: 14)

        setTitleTextAttributes(
            [.font: normalFont, .foregroundColor: UIColor.Signal.secondaryLabel],
            for: .normal,
        )
        setTitleTextAttributes(
            [.font: selectedFont, .foregroundColor: UIColor.Signal.label],
            for: .selected,
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard #available(iOS 26, *) else { return super.intrinsicContentSize }

        // Increase both dimensions to add padding around titles.
        let horizontalTitlePadding = 8
        var size = super.intrinsicContentSize
        size.width += CGFloat(horizontalTitlePadding * 2 * numberOfSegments)
        size.height = 40
        return size
    }
}

// MARK: - Accessibility

extension CameraCaptureControl {

    override var isAccessibilityElement: Bool {
        get { true }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.button] }
        set { super.accessibilityTraits = newValue }
    }

    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(shutterButtonLayoutGuide.layoutFrame, in: self) }
        set { super.accessibilityFrame = newValue }
    }

    override var accessibilityLabel: String? {
        get {
            switch recordingState {
            case .notRecording:
                return OWSLocalizedString(
                    "CAMERA_VO_TAKE_PICTURE",
                    comment: "VoiceOver label for the round capture button in in-app camera.",
                )

            case .recordingUsingVoiceOver:
                return OWSLocalizedString(
                    "CAMERA_VO_STOP_VIDEO_REC",
                    comment: "VoiceOver label for the round capture button in in-app camera during video recording.",
                )

            default:
                owsFailDebug("Invalid state")
                return nil
            }
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            guard recordingState == .notRecording else { return [] }
            let actionName = OWSLocalizedString(
                "CAMERA_VO_TAKE_VIDEO",
                comment: "VoiceOver label for other possible action for round capture button in in-app camera.",
            )
            return [UIAccessibilityCustomAction(name: actionName, target: self, selector: #selector(accessibilityStartVideoRecording))]
        }
        set { super.accessibilityCustomActions = newValue }
    }

    override func accessibilityActivate() -> Bool {
        switch recordingState {
        case .notRecording:
            capturePhoto()

        case .recordingUsingVoiceOver:
            accessibilityStopVideoRecording()

        default:
            owsFailDebug("Invalid state")
            return false
        }
        return true
    }

    @objc
    private func accessibilityStartVideoRecording() {
        startVideoRecording()
    }

    private func accessibilityStopVideoRecording() {
        finishVideoRecording()
    }
}

extension BadgedProceedButton {

    override var accessibilityLabel: String? {
        get { CommonStrings.doneButton }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            guard badgeNumber > 0 else { return nil }

            let format = OWSLocalizedString(
                "CAMERA_VO_N_ITEMS",
                tableName: "PluralAware",
                comment: "VoiceOver text for blue Done button in camera, describing how many items have already been captured.",
            )
            return String.localizedStringWithFormat(format, badgeNumber)
        }
        set {
            super.accessibilityValue = newValue
        }
    }
}

extension FlashModeButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_FLASH_BUTTON",
                comment: "VoiceOver label for Flash button in camera.",
            )
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            switch mode {
            case .auto:
                return OWSLocalizedString(
                    "CAMERA_VO_FLASH_AUTO",
                    comment: "VoiceOver description of current flash setting.",
                )

            case .on:
                return OWSLocalizedString(
                    "CAMERA_VO_FLASH_ON",
                    comment: "VoiceOver description of current flash setting.",
                )

            case .off:
                return OWSLocalizedString(
                    "CAMERA_VO_FLASH_OFF",
                    comment: "VoiceOver description of current flash setting.",
                )

            @unknown default:
                owsFailDebug("unexpected photoCapture.flashMode: \(mode.rawValue)")
                return nil
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension SwitchCameraButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_CAMERA_CHOOSER_BUTTON",
                comment: "VoiceOver label for Switch Camera button in in-app camera.",
            )
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityHint: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_CAMERA_CHOOSER_HINT",
                comment: "VoiceOver hint for Switch Camera button in in-app camera.",
            )
        }
        set { super.accessibilityHint = newValue }
    }

    override var accessibilityValue: String? {
        get {
            if isFrontCameraActive {
                return OWSLocalizedString(
                    "CAMERA_VO_CAMERA_FRONT_FACING",
                    comment: "VoiceOver value for Switch Camera button that tells which camera is currently active.",
                )
            } else {
                return OWSLocalizedString(
                    "CAMERA_VO_CAMERA_BACK_FACING",
                    comment: "VoiceOver value for Switch Camera button that tells which camera is currently active.",
                )
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension CaptureModeButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_CAMERA_ALBUM_MODE",
                comment: "VoiceOver label for Flash button in camera.",
            )
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            switch captureMode {
            case .single:
                return OWSLocalizedString(
                    "CAMERA_VO_CAMERA_ALBUM_MODE_OFF",
                    comment: "VoiceOver label for Switch Camera button in in-app camera.",
                )

            case .multi:
                return OWSLocalizedString(
                    "CAMERA_VO_CAMERA_ALBUM_MODE_ON",
                    comment: "VoiceOver label for Switch Camera button in in-app camera.",
                )
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension PhotoLibraryButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_PHOTO_LIBRARY_BUTTON",
                comment: "VoiceOver label for button to choose existing photo/video in in-app camera",
            )
        }
        set { super.accessibilityLabel = newValue }
    }
}

extension CameraZoomSelectionControl {

    override var isAccessibilityElement: Bool {
        get { true }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.button, .adjustable] }
        set { super.accessibilityTraits = newValue }
    }

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString("CAMERA_VO_ZOOM", comment: "VoiceOver label for camera zoom control.")
        }
        set { super.accessibilityLabel = newValue }
    }

    private static let voiceOverNumberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = 1
        return numberFormatter
    }()

    override var accessibilityValue: String? {
        get {
            guard let zoomValueString = CameraZoomSelectionControl.voiceOverNumberFormatter.string(for: currentZoomFactor) else { return nil }

            let formatString = OWSLocalizedString(
                "CAMERA_VO_ZOOM_LEVEL",
                comment: "VoiceOver description of current camera zoom level.",
            )
            return String.nonPluralLocalizedStringWithFormat(formatString, zoomValueString)
        }
        set { super.accessibilityValue = newValue }
    }

    override func accessibilityActivate() -> Bool {
        // Tapping on a single available camera switches between 1x and 2x.
        guard availableCameras.count > 1 else {
            delegate?.cameraZoomControl(self, didSelect: selectedCamera)
            return true
        }

        // Cycle through cameras.
        guard let selectedCameraIndex = availableCameras.firstIndex(of: selectedCamera) else { return false }
        var nextCameraIndex = availableCameras.index(after: selectedCameraIndex)
        if nextCameraIndex >= availableCameras.endIndex {
            nextCameraIndex = availableCameras.startIndex
        }
        let nextCamera = availableCameras[nextCameraIndex]
        selectedCamera = nextCamera
        delegate?.cameraZoomControl(self, didSelect: nextCamera)
        return true
    }

    override func accessibilityIncrement() {
        // Increment zoom by 0.1.
        currentZoomFactor = 0.1 * round(currentZoomFactor * 10 + 1)
        delegate?.cameraZoomControl(self, didChangeZoomFactor: currentZoomFactor)
    }

    override func accessibilityDecrement() {
        // Decrement zoom by 0.1.
        currentZoomFactor = 0.1 * round(currentZoomFactor * 10 - 1)
        delegate?.cameraZoomControl(self, didChangeZoomFactor: currentZoomFactor)
    }
}

extension ComposerTypeSelectionControl {

    override var isAccessibilityElement: Bool {
        get { true }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .adjustable }
        set { super.accessibilityTraits = newValue }
    }

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString(
                "CAMERA_VO_COMPOSER_MODE",
                comment: "VoiceOver label for composer mode (CAMERA|TEXT) selector at the bottom of in-app camera screen.",
            )
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { titleForSegment(at: selectedSegmentIndex) }
        set { super.accessibilityValue = newValue }
    }

    override func accessibilityIncrement() {
        if selectedSegmentIndex + 1 < numberOfSegments {
            selectedSegmentIndex += 1
        }
    }

    override func accessibilityDecrement() {
        if selectedSegmentIndex > 0 {
            selectedSegmentIndex -= 1
        }
    }
}
