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
    private var slidingCircleHPositionConstraint: NSLayoutConstraint?
    private var slidingCircleVPositionConstraint: NSLayoutConstraint?

    private lazy var slidingCircleView: CircleView = {
        let view = CircleView(diameter: CameraCaptureControl.recordingLockControlSize)
        view.backgroundColor = .ows_white
        view.isHidden = true
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
        button.isHidden = true
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
            if sliderTrackingProgress == 1 && state == .recording {
                setState(.recordingLocked) // this will call updateUIForCurrentState()
            } else {
                updateUIForCurrentState()
            }
        }
    }

    func setState(_ state: State, isRecordingWithLongPress: Bool = false, animationDuration: TimeInterval = 0) {
        guard _internalState != state else { return }

        Logger.debug("New state: \(_internalState) -> \(state)")

        _internalState = state
        self.isRecordingWithLongPress = isRecordingWithLongPress
        if animationDuration > 0 {
            UIView.animate(withDuration: animationDuration,
                           delay: 0,
                           options: [ .beginFromCurrentState ],
                           animations: {
                self.updateUIForCurrentState()
            })
        } else {
            updateUIForCurrentState()
        }
    }

    private func updateUIForCurrentState() {
        switch state {
        case .initial:
            // element visibility
            if slidingCircleHPositionConstraint != nil {
                stopButton.isHidden = true
                slidingCircleView.isHidden = true
                lockIconView.isHidden = true
                lockIconView.state = .unlocked
            }
            shutterButtonInnerCircle.alpha = 1
            shutterButtonInnerCircle.backgroundColor = .clear
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize

        case .recording:
            prepareRecordingControlsIfNecessary()
            let sliderProgress = isRecordingWithLongPress ? sliderTrackingProgress : 0
            // element visibility
            stopButton.isHidden = sliderProgress == 0
            slidingCircleView.isHidden = sliderProgress == 0
            lockIconView.isHidden = !isRecordingWithLongPress
            lockIconView.setState(sliderProgress > 0.5 ? .locking : .unlocked, animated: true)
            shutterButtonInnerCircle.backgroundColor = .ows_white
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            // Inner (white) circle gets smaller as user drags the slider and reveals stop button when the slider is halfway to the lock icon.
            let circleSizeOffset = 2 * sliderProgress * (CameraCaptureControl.shutterButtonDefaultSize - CameraCaptureControl.recordingLockControlSize)
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize - circleSizeOffset

        case .recordingLocked:
            prepareRecordingControlsIfNecessary()
            // element visibility
            stopButton.isHidden = false
            slidingCircleView.isHidden = false
            lockIconView.isHidden = false
            lockIconView.setState(.locked, animated: true)
            shutterButtonInnerCircle.alpha = 0
            shutterButtonInnerCircle.backgroundColor = .ows_white
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.recordingLockControlSize
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    private func prepareRecordingControlsIfNecessary() {
        guard slidingCircleHPositionConstraint == nil else { return }

        // 1. Stop button.
        addSubview(stopButton)
        stopButton.autoPin(toAspectRatio: 1)
        stopButton.autoSetDimension(.width, toSize: CameraCaptureControl.recordingLockControlSize)
        stopButton.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor).isActive = true
        stopButton.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor).isActive = true

        // 2. Slider.
        insertSubview(slidingCircleView, belowSubview: shutterButtonInnerCircle)
        slidingCircleView.translatesAutoresizingMaskIntoConstraints = false
        let circleHPositionConstraint = slidingCircleView.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor)
        var horizontalConstraints: [NSLayoutConstraint] = [ circleHPositionConstraint ]
        horizontalConstraints.append(slidingCircleView.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor))
        slidingCircleHPositionConstraint = circleHPositionConstraint

        let circleVPositionConstraint = slidingCircleView.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor)
        var verticalConstraints: [NSLayoutConstraint] = [ circleVPositionConstraint ]
        verticalConstraints.append(slidingCircleView.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor))
        slidingCircleVPositionConstraint = circleVPositionConstraint

        // 3. Lock Icon
        addSubview(lockIconView)
        lockIconView.translatesAutoresizingMaskIntoConstraints = false
        // Centered vertically, pinned to trailing edge.
        horizontalConstraints.append(contentsOf: [ lockIconView.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor),
                                                   lockIconView.trailingAnchor.constraint(equalTo: trailingAnchor) ])
        // Centered horizontally, pinned to bottom edge.
        verticalConstraints.append(contentsOf: [ lockIconView.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor),
                                                 lockIconView.bottomAnchor.constraint(equalTo: bottomAnchor) ])

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

    private var isRecordingWithLongPress = false
    private static let longPressDurationThreshold = 0.5
    private static let minDistanceBeforeActivatingLockSlider: CGFloat = 30
    private var initialTouchLocation: CGPoint?
    private var initialZoomPosition: CGFloat?
    private var touchTimer: Timer?

    @objc
    private func handleLongPress(gesture: UILongPressGestureRecognizer) {
        guard let gestureView = gesture.view else {
            owsFailDebug("gestureView was unexpectedly nil")
            return
        }

        switch gesture.state {
        case .possible:
            break

        case .began:
            guard state == .initial else { break }

            initialTouchLocation = gesture.location(in: gesture.view)
            initialZoomPosition = nil

            touchTimer?.invalidate()
            touchTimer = WeakTimer.scheduledTimer(
                timeInterval: CameraCaptureControl.longPressDurationThreshold,
                target: self,
                userInfo: nil,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }

                self.setState(.recording, isRecordingWithLongPress: true, animationDuration: 0.4)

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

            let currentLocation = gesture.location(in: gestureView)

            // Zoom - only use if slide to lock hasn't been activated.
            var zoomLevel: CGFloat = 0
            if sliderTrackingProgress == 0 {
                let minDistanceBeforeActivatingZoom: CGFloat = 30
                let currentDistance: CGFloat = {
                    switch axis {
                    case .horizontal:
                        if initialZoomPosition == nil {
                            initialZoomPosition = currentLocation.y
                        }
                        return initialZoomPosition! - currentLocation.y - minDistanceBeforeActivatingZoom

                    case .vertical:
                        if initialZoomPosition == nil {
                            initialZoomPosition = currentLocation.x
                        }
                        return initialZoomPosition! - currentLocation.x - minDistanceBeforeActivatingZoom

                    @unknown default:
                        owsFailDebug("Unsupported `axis` value: \(axis.rawValue)")
                        return 0
                    }
                }()

                let distanceForFullZoom = referenceDistance / 4
                let ratio = currentDistance / distanceForFullZoom
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

            guard state != .recordingLocked else { return }

            if state == .recording {
                setState(.initial, animationDuration: 0.2)

                delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
            } else {
                delegate?.cameraCaptureControlDidRequestCapturePhoto(self)
            }

        case .cancelled, .failed:
            if state == .recording {
                setState(.initial, animationDuration: 0.2)

                delegate?.cameraCaptureControlDidRequestCancelVideoRecording(self)
            }

            touchTimer?.invalidate()
            touchTimer = nil

        @unknown default:
            owsFailDebug("unexpected gesture state: \(gesture.state.rawValue)")
        }
    }

    private func updateHorizontalTracking(xOffset: CGFloat) {
        let effectiveDistance = xOffset - Self.minDistanceBeforeActivatingLockSlider
        let distanceToLock = abs(lockIconView.center.x - stopButton.center.x)
        if let positionConstraint = slidingCircleHPositionConstraint {
            let trackingPosition = effectiveDistance.clamp(0, distanceToLock)
            positionConstraint.constant = trackingPosition
        }
        sliderTrackingProgress = (effectiveDistance / distanceToLock).clamp(0, 1)

        Logger.debug("xOffset: \(xOffset), effectiveDistance: \(effectiveDistance),  distanceToLock: \(distanceToLock), progress: \(sliderTrackingProgress)")
    }

    private func updateVerticalTracking(yOffset: CGFloat) {
        let effectiveDistance = yOffset - Self.minDistanceBeforeActivatingLockSlider
        let distanceToLock = abs(lockIconView.center.y - stopButton.center.y)
        if let positionConstraint = slidingCircleVPositionConstraint {
            let trackingPosition = effectiveDistance.clamp(0, distanceToLock)
            positionConstraint.constant = trackingPosition
        }
        sliderTrackingProgress = (effectiveDistance / distanceToLock).clamp(0, 1)

        Logger.debug("yOffset: \(yOffset), effectiveDistance: \(effectiveDistance),  distanceToLock: \(distanceToLock), progress: \(sliderTrackingProgress)")
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

    private let backgroundView: CircleBlurView = {
        let view = CircleBlurView(effect: UIBlurEffect(style: .regular))
        view.isUserInteractionEnabled = false
        return view
    }()

    private static let visibleButtonSize: CGFloat = 36  // both height and width
    private static let defaultInset: CGFloat = 4

    var contentInsets: UIEdgeInsets = UIEdgeInsets(margin: CameraOverlayButton.defaultInset) {
        didSet {
            layoutMargins = contentInsets
        }
    }

    required init(image: UIImage?, userInterfaceStyleOverride: UIUserInterfaceStyle = .unspecified) {
        super.init(frame: CGRect(origin: .zero, size: .square(Self.visibleButtonSize + 2*Self.defaultInset)))

        self.userInterfaceStyleOverride = userInterfaceStyleOverride

        layoutMargins = contentInsets

        addSubview(backgroundView)
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

    private func updateStyle() {
        backgroundView.effect = UIBlurEffect(style: CameraOverlayButton.blurEffectStyle(for: effectiveUserInterfaceStyle))
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
        blurBackgroundView.effect = UIBlurEffect(style: MediaDoneButton.blurEffectStyle(for: effectiveUserInterfaceStyle))
        chevronImageView.tintColor = MediaDoneButton.tintColor(for: effectiveUserInterfaceStyle)
    }
}
