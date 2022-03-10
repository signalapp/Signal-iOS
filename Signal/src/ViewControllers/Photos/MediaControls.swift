//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalUI

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

class CameraCaptureControl: UIView {

    var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            if oldValue != axis {
                reactivateConstraintsForCurrentAxis()
                invalidateIntrinsicContentSize()
            }
        }
    }
    private var horizontalAxisConstraints = [NSLayoutConstraint]()
    private var verticalAxisConstraints = [NSLayoutConstraint]()

    let shutterButtonLayoutGuide = UILayoutGuide() // allows view controller to align to shutter button.
    private let shutterButtonOuterCircle = CircleBlurView(effect: UIBlurEffect(style: .light))
    private let shutterButtonInnerCircle = CircleView()

    fileprivate static let recordingLockControlSize: CGFloat = 36   // Stop button, swipe tracking circle, lock icon
    private static let shutterButtonDefaultSize: CGFloat = 72
    private static let shutterButtonRecordingSize: CGFloat = 122

    private let outerCircleSizeConstraint: NSLayoutConstraint
    private let innerCircleSizeConstraint: NSLayoutConstraint

    private lazy var slidingCircleView: CircleView = {
        let view = CircleView()
        view.bounds = CGRect(origin: .zero, size: .square(CameraCaptureControl.recordingLockControlSize))
        view.backgroundColor = .ows_white
        return view
    }()
    private lazy var lockIconView = LockView(frame: CGRect(origin: .zero, size: .square(CameraCaptureControl.recordingLockControlSize)))
    private lazy var stopButton: UIButton = {
        let button = OWSButton { [weak self] in
            guard let self = self else { return }
            self.didTapStopButton()
        }
        button.backgroundColor = .white
        button.dimsWhenHighlighted = true
        button.layer.masksToBounds = true
        button.layer.cornerRadius = 4
        return button
    }()

    weak var delegate: CameraCaptureControlDelegate?

    required init(axis: NSLayoutConstraint.Axis) {
        innerCircleSizeConstraint = shutterButtonInnerCircle.autoSetDimension(.width, toSize: CameraCaptureControl.shutterButtonDefaultSize)
        outerCircleSizeConstraint = shutterButtonOuterCircle.autoSetDimension(.width, toSize: CameraCaptureControl.shutterButtonDefaultSize)

        super.init(frame: CGRect(origin: .zero, size: CameraCaptureControl.intrinsicContentSize(forAxis: axis)))

        self.axis = axis

        // Round Shutter Button
        addLayoutGuide(shutterButtonLayoutGuide)
        shutterButtonLayoutGuide.widthAnchor.constraint(equalToConstant: CameraCaptureControl.shutterButtonDefaultSize).isActive = true
        shutterButtonLayoutGuide.heightAnchor.constraint(equalToConstant: CameraCaptureControl.shutterButtonDefaultSize).isActive = true
        horizontalAxisConstraints.append(contentsOf: [
            shutterButtonLayoutGuide.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 0.5*CameraCaptureControl.shutterButtonDefaultSize),
            shutterButtonLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            shutterButtonLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor)

        ])
        verticalAxisConstraints.append(contentsOf: [
            shutterButtonLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            shutterButtonLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            shutterButtonLayoutGuide.centerYAnchor.constraint(equalTo: topAnchor, constant: 0.5*CameraCaptureControl.shutterButtonDefaultSize)
        ])

        addSubview(shutterButtonOuterCircle)
        shutterButtonOuterCircle.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor).isActive = true
        shutterButtonOuterCircle.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor).isActive = true
        shutterButtonOuterCircle.autoPin(toAspectRatio: 1)

        addSubview(shutterButtonInnerCircle)
        shutterButtonInnerCircle.autoPin(toAspectRatio: 1)
        shutterButtonInnerCircle.isUserInteractionEnabled = false
        shutterButtonInnerCircle.backgroundColor = .clear
        shutterButtonInnerCircle.layer.borderColor = UIColor.ows_white.cgColor
        shutterButtonInnerCircle.layer.borderWidth = 5
        shutterButtonInnerCircle.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor).isActive = true
        shutterButtonInnerCircle.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor).isActive = true

        // The long press handles both the tap and the hold interaction, as well as the animation
        // the presents as the user begins to hold (and the button begins to grow prior to recording)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0
        shutterButtonOuterCircle.addGestureRecognizer(longPressGesture)

        reactivateConstraintsForCurrentAxis()
    }

    @available(*, unavailable, message: "Use init(axis:) instead")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    // MARK: - UI State

    enum State {
        case initial
        case recording
        case recordingLocked
    }

    private var _internalState: State = .initial
    var state: State {
        get {
            _internalState
        }
        set {
            setState(newValue)
        }
    }

    private var sliderTrackingProgress: CGFloat = 0 {
        didSet {
            guard isRecordingWithLongPress else { return }

            // Update size of the inner circle, that contracts with `sliderTrackingProgress` increasing.
            // Fully reveal stop button when sliderTrackingProgress == 0.5.
            let circleSizeOffset = 2 * min(0.5, sliderTrackingProgress) * (CameraCaptureControl.shutterButtonDefaultSize - CameraCaptureControl.recordingLockControlSize)
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize - circleSizeOffset
            // Hide the inner circle so that it is not visible when stop button is pressed.
            shutterButtonInnerCircle.alpha = sliderTrackingProgress > 0.5 ? 0 : 1
        }
    }

    func setState(_ state: State, isRecordingWithLongPress: Bool = false, animationDuration: TimeInterval = 0) {
        guard _internalState != state else { return }

        _internalState = state
        self.isRecordingWithLongPress = isRecordingWithLongPress

        if state == .initial {
            // Hide "slide to lock" controls momentarily before animating the rest of the UI to "not recording" state.
            hideLongPressVideoRecordingControls()
        }

        if animationDuration > 0 {
            UIView.animate(withDuration: animationDuration,
                           delay: 0,
                           options: [ .beginFromCurrentState ],
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
                if state == .recording && isRecordingWithLongPress {
                    self.prepareLongPressVideoRecordingControls()
                }
            })
        } else {
            updateShutterButtonAppearanceForCurrentState()
            if state == .recording && isRecordingWithLongPress {
                prepareLongPressVideoRecordingControls()
            }
        }
    }

    private func updateShutterButtonAppearanceForCurrentState() {
        switch state {
        case .initial:
            shutterButtonInnerCircle.alpha = 1
            shutterButtonInnerCircle.backgroundColor = .clear

            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize

        case .recording:
            shutterButtonInnerCircle.backgroundColor = .ows_white
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            // Inner circle stays the same size initially and might get smaller as user moves the slider.

        case .recordingLocked:
            // This should already by at the correct size so this assignment is "just in case".
            innerCircleSizeConstraint.constant = CameraCaptureControl.recordingLockControlSize
        }
    }

    private func initializeVideoRecordingControlsIfNecessary() {
        guard stopButton.superview == nil else { return }

        // 1. Stop button.
        addSubview(stopButton)
        stopButton.autoPin(toAspectRatio: 1)
        stopButton.autoSetDimension(.width, toSize: CameraCaptureControl.recordingLockControlSize)
        stopButton.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor).isActive = true
        stopButton.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor).isActive = true

        // 2. Slider.
        insertSubview(slidingCircleView, belowSubview: shutterButtonInnerCircle)

        // 3. Lock Icon
        addSubview(lockIconView)
        lockIconView.translatesAutoresizingMaskIntoConstraints = false
        // Centered vertically, pinned to trailing edge.
        let horizontalConstraints = [ lockIconView.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor),
                                      lockIconView.trailingAnchor.constraint(equalTo: trailingAnchor) ]
        // Centered horizontally, pinned to bottom edge.
        let verticalConstraints = [ lockIconView.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor),
                                    lockIconView.bottomAnchor.constraint(equalTo: bottomAnchor) ]

        // 4. Activate current constraints.
        horizontalAxisConstraints.append(contentsOf: horizontalConstraints)
        if axis == .horizontal {
            addConstraints(horizontalConstraints)
        }

        verticalAxisConstraints.append(contentsOf: verticalConstraints)
        if axis == .vertical {
            addConstraints(verticalConstraints)
        }

        setNeedsLayout()
        UIView.performWithoutAnimation {
            self.layoutIfNeeded()
        }
    }

    private func reactivateConstraintsForCurrentAxis() {
        switch axis {
        case .horizontal:
            removeConstraints(verticalAxisConstraints)
            addConstraints(horizontalAxisConstraints)

        case .vertical:
            removeConstraints(horizontalAxisConstraints)
            addConstraints(verticalAxisConstraints)

        @unknown default:
            owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
        }
    }

    override var intrinsicContentSize: CGSize {
        return Self.intrinsicContentSize(forAxis: axis)
    }

    private static func intrinsicContentSize(forAxis axis: NSLayoutConstraint.Axis) -> CGSize {
        switch axis {
        case .horizontal:
            return CGSize(width: CameraCaptureControl.shutterButtonDefaultSize + 64 + CameraCaptureControl.recordingLockControlSize,
                          height: CameraCaptureControl.shutterButtonDefaultSize)

        case .vertical:
            return CGSize(width: CameraCaptureControl.shutterButtonDefaultSize,
                          height: CameraCaptureControl.shutterButtonDefaultSize + 64 + CameraCaptureControl.recordingLockControlSize)

        @unknown default:
            owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
            return CGSize(square: UIView.noIntrinsicMetric)
        }
    }

    // MARK: - Gestures

    private let animationDuration: TimeInterval = 0.2
    private var isRecordingWithLongPress = false
    private static let longPressDurationThreshold = 0.5
    private var initialTouchLocation: CGPoint?
    private var initialZoomPosition: CGFloat?
    private var touchTimer: Timer?

    private var initialSlidingCircleViewCenter: CGPoint {
        shutterButtonInnerCircle.center
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
            guard state == .initial else { break }

            initialTouchLocation = currentLocation
            initialZoomPosition = nil

            touchTimer?.invalidate()
            touchTimer = WeakTimer.scheduledTimer(
                timeInterval: CameraCaptureControl.longPressDurationThreshold,
                target: self,
                userInfo: nil,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }

                self.setState(.recording, isRecordingWithLongPress: true, animationDuration: 2*self.animationDuration)
                self.delegate?.cameraCaptureControlDidRequestStartVideoRecording(self)
            }

        case .changed:
            guard state == .recording else { break }

            guard let referenceDistance = delegate?.zoomScaleReferenceDistance else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceDistance > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation = initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            // Zoom - only use if slide to lock hasn't been activated.
            var zoomLevel: CGFloat = 0
            if sliderTrackingProgress == 0 {
                let currentSlideOffset: CGFloat = {
                    switch axis {
                    case .horizontal:
                        if let initialZoomPosition = initialZoomPosition {
                            return initialZoomPosition - currentLocation.y
                        } else {
                            initialZoomPosition = currentLocation.y
                            return 0
                        }

                    case .vertical:
                        if let initialZoomPosition = initialZoomPosition {
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

            if state == .recording {
                let shouldLockRecording = sliderTrackingProgress > 0.5

                // 1. Snap slider to one of the endpoints with the spring animation.
                let finalCenter = shouldLockRecording ? finalSlidingCircleViewCenter : initialSlidingCircleViewCenter
                UIView.animate(withDuration: animationDuration,
                               delay: 0,
                               usingSpringWithDamping: 1,
                               initialSpringVelocity: 0,
                               options: [ .beginFromCurrentState ]) {
                    self.slidingCircleView.center = finalCenter
                }

                // 2. Simultaneously with animating the slider animate the rest of the UI.
                if shouldLockRecording {
                    sliderTrackingProgress = 1
                    lockIconView.setState(.locked, animated: true)
                    setState(.recordingLocked, animationDuration: animationDuration)
                } else {
                    // Animate change of inner (white) circle back to normal...
                    sliderTrackingProgress = 0
                    UIView.animate(withDuration: animationDuration,
                                   animations: {
                        self.layoutIfNeeded()
                    },
                                   completion: { _ in
                        // ...and only then animate the rest of the shutter button to its initial state.
                        self.setState(.initial, animationDuration: self.animationDuration)
                    })

                    delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
                }
            } else {
                delegate?.cameraCaptureControlDidRequestCapturePhoto(self)
            }

        case .cancelled, .failed:
            if state == .recording {
                sliderTrackingProgress = 0
                setState(.initial, animationDuration: animationDuration)
                delegate?.cameraCaptureControlDidRequestCancelVideoRecording(self)
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

    private func prepareLongPressVideoRecordingControls() {
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
        delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
    }
}

private class LockView: UIView {

    private let imageViewLock = UIImageView(image: UIImage(named: "media-composer-lock-outline-24"))
    private let blurBackgroundView = CircleBlurView(effect: UIBlurEffect(style: .dark))
    private let whiteBackgroundView = CircleView()
    private let whiteCircleView = CircleView()

    enum State {
        case unlocked
        case locking
        case locked
    }
    private var _internalState: State = .unlocked
    var state: State {
        get {
            _internalState
        }
        set {
            guard _internalState != newValue else { return }
            setState(newValue)
        }
    }

    func setState(_ state: State, animated: Bool = false) {
        _internalState = state
        if animated {
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           options: [ .beginFromCurrentState ]) {
                self.updateAppearance()
            }
        } else {
            updateAppearance()
        }
    }

    private func updateAppearance() {
        switch state {
        case .unlocked:
            blurBackgroundView.alpha = 1
            whiteCircleView.alpha = 0
            whiteBackgroundView.alpha = 0
            imageViewLock.alpha = 1
            imageViewLock.tintColor = .ows_white

        case .locking:
            blurBackgroundView.alpha = 1
            whiteCircleView.alpha = 1
            whiteBackgroundView.alpha = 0
            imageViewLock.alpha = 0

        case .locked:
            blurBackgroundView.alpha = 0
            whiteCircleView.alpha = 0
            whiteBackgroundView.alpha = 1
            imageViewLock.alpha = 1
            imageViewLock.tintColor = .ows_black
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        addSubview(whiteCircleView)
        whiteCircleView.backgroundColor = .clear
        whiteCircleView.layer.borderColor = UIColor.ows_white.cgColor
        whiteCircleView.layer.borderWidth = 3
        whiteCircleView.autoPinEdgesToSuperviewEdges()

        addSubview(whiteBackgroundView)
        whiteBackgroundView.backgroundColor = .ows_white
        whiteBackgroundView.autoPinEdgesToSuperviewEdges()

        addSubview(imageViewLock)
        imageViewLock.tintColor = .ows_white
        imageViewLock.autoCenterInSuperview()

        updateAppearance()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CameraCaptureControl.recordingLockControlSize, height: CameraCaptureControl.recordingLockControlSize)
    }
}

@available(iOS, deprecated: 13.0, message: "Use `overrideUserInterfaceStyle` instead.")
private protocol UserInterfaceStyleOverride {

    var userInterfaceStyleOverride: UIUserInterfaceStyle { get set }

    var effectiveUserInterfaceStyle: UIUserInterfaceStyle { get }

}

private extension UserInterfaceStyleOverride {

    var effectiveUserInterfaceStyle: UIUserInterfaceStyle {
        if userInterfaceStyleOverride != .unspecified {
            return userInterfaceStyleOverride
        }
        if let uiView = self as? UIView {
            return uiView.traitCollection.userInterfaceStyle
        }
        return .unspecified
    }

    static func blurEffectStyle(for userInterfaceStyle: UIUserInterfaceStyle) -> UIBlurEffect.Style {
        switch userInterfaceStyle {
        case .dark:
            return .dark
        case .light:
            return .extraLight
        default:
            fatalError("It is an error to pass UIUserInterfaceStyleUnspecified.")
        }
    }

    static func tintColor(for userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
        switch userInterfaceStyle {
        case .dark:
            return Theme.darkThemePrimaryColor
        case .light:
            return .ows_gray60
        default:
            fatalError("It is an error to pass UIUserInterfaceStyleUnspecified.")
        }
    }
}

class CameraOverlayButton: UIButton, UserInterfaceStyleOverride {

    fileprivate var userInterfaceStyleOverride: UIUserInterfaceStyle = .unspecified {
        didSet {
            if oldValue != userInterfaceStyleOverride {
                updateStyle()
            }
        }
    }

    enum BackgroundStyle {
        case solid
        case blur
    }

    let backgroundStyle: BackgroundStyle
    let backgroundView: UIView
    private static let visibleButtonSize: CGFloat = 36  // both height and width
    private static let defaultInset: CGFloat = 8

    var contentInsets: UIEdgeInsets = UIEdgeInsets(margin: CameraOverlayButton.defaultInset) {
        didSet {
            layoutMargins = contentInsets
        }
    }

    required init(image: UIImage?, backgroundStyle: BackgroundStyle = .blur, userInterfaceStyleOverride: UIUserInterfaceStyle = .unspecified) {
        self.backgroundStyle = backgroundStyle
        self.backgroundView = {
            switch backgroundStyle {
            case .solid:
                return CircleView()

            case .blur:
                return CircleBlurView(effect: UIBlurEffect(style: .regular))
            }
        }()

        super.init(frame: CGRect(origin: .zero, size: .square(Self.visibleButtonSize + 2*Self.defaultInset)))

        self.userInterfaceStyleOverride = userInterfaceStyleOverride

        layoutMargins = contentInsets

        addSubview(backgroundView)
        backgroundView.isUserInteractionEnabled = false
        backgroundView.autoPinEdgesToSuperviewMargins()

        setImage(image, for: .normal)
        updateStyle()
    }

    @available(*, unavailable, message: "Use init(image:userInterfaceStyleOverride:) instead")
    override init(frame: CGRect) {
        notImplemented()
    }

    @available(*, unavailable, message: "Use init(image:userInterfaceStyleOverride:) instead")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sendSubviewToBack(backgroundView)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: Self.visibleButtonSize + layoutMargins.leading + layoutMargins.trailing,
                      height: Self.visibleButtonSize + layoutMargins.top + layoutMargins.bottom)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle, userInterfaceStyleOverride == .unspecified {
            updateStyle()
        }
    }

    private static func backgroundColor(for userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
        switch userInterfaceStyle {
        case .dark:
            return .ows_gray80
        case .light:
            return .ows_gray20
        default:
            fatalError("It is an error to pass UIUserInterfaceStyleUnspecified.")
        }
    }

    private func updateStyle() {
        switch backgroundStyle {
        case .solid:
            backgroundView.backgroundColor = CameraOverlayButton.backgroundColor(for: effectiveUserInterfaceStyle)
        case .blur:
            if let circleBlurView = backgroundView as? CircleBlurView {
                circleBlurView.effect = UIBlurEffect(style: CameraOverlayButton.blurEffectStyle(for: effectiveUserInterfaceStyle))
            }
        }
        tintColor = CameraOverlayButton.tintColor(for: effectiveUserInterfaceStyle)
    }
}

class MediaDoneButton: UIButton, UserInterfaceStyleOverride {

    var badgeNumber: Int = 0 {
        didSet {
            textLabel.text = numberFormatter.string(for: badgeNumber)
            invalidateIntrinsicContentSize()
        }
    }

    var userInterfaceStyleOverride: UIUserInterfaceStyle = .unspecified {
        didSet {
            if oldValue != userInterfaceStyleOverride {
                updateStyle()
            }
        }
    }

    private static var font: UIFont {
        return UIFont.ows_dynamicTypeSubheadline.ows_monospaced
    }

    private let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_white
        label.textAlignment = .center
        label.font = MediaDoneButton.font
        return label
    }()
    private let pillView: PillView = {
        let pillView = PillView(frame: .zero)
        pillView.isUserInteractionEnabled = false
        pillView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 7)
        return pillView
    }()
    private let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let chevronImageView: UIImageView = {
        let image: UIImage?
        if #available(iOS 13, *) {
            image = CurrentAppContext().isRTL ? UIImage(systemName: "chevron.backward") : UIImage(systemName: "chevron.right")
        } else {
            image = CurrentAppContext().isRTL ? UIImage(named: "chevron-left-20") : UIImage(named: "chevron-right-20")
        }
        let chevronImageView = UIImageView(image: image!.withRenderingMode(.alwaysTemplate))
        chevronImageView.contentMode = .center
        if #available(iOS 13, *) {
            chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: MediaDoneButton.font.pointSize)
        }
        return chevronImageView
    }()
    private var dimmerView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(pillView)
        pillView.autoPinEdgesToSuperviewEdges()

        pillView.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        let blueBadgeView = PillView(frame: bounds)
        blueBadgeView.backgroundColor = .ows_accentBlue
        blueBadgeView.layoutMargins = UIEdgeInsets(margin: 4)
        blueBadgeView.addSubview(textLabel)
        textLabel.autoPinEdgesToSuperviewMargins()

        let hStack = UIStackView(arrangedSubviews: [blueBadgeView, chevronImageView])
        hStack.spacing = 6
        pillView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()

        updateStyle()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            textLabel.font = .ows_dynamicTypeSubheadline.ows_monospaced
            if #available(iOS 13, *) {
                chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: textLabel.font.pointSize)
            }
        }
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateStyle()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                if dimmerView == nil {
                    let dimmerView = UIView(frame: bounds)
                    dimmerView.isUserInteractionEnabled = false
                    dimmerView.backgroundColor = .ows_black
                    pillView.addSubview(dimmerView)
                    dimmerView.autoPinEdgesToSuperviewEdges()
                    self.dimmerView = dimmerView
                }
                dimmerView?.alpha = 0.5
            } else if let dimmerView = dimmerView {
                dimmerView.alpha = 0
            }
        }
    }

    private func updateStyle() {
        let userInterfaceStyle = effectiveUserInterfaceStyle
        // ".unspecified" is present during initialization on iOS 12.
        guard userInterfaceStyle != .unspecified else { return }
        blurBackgroundView.effect = UIBlurEffect(style: MediaDoneButton.blurEffectStyle(for: userInterfaceStyle))
        chevronImageView.tintColor = MediaDoneButton.tintColor(for: userInterfaceStyle)
    }
}
