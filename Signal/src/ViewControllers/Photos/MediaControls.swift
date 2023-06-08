//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalMessaging
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

    fileprivate static let recordingLockControlSize: CGFloat = 42   // Stop button, swipe tracking circle, lock icon
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

        // Stop Button
        stopButton.alpha = 0
        addSubview(stopButton)
        stopButton.autoPin(toAspectRatio: 1)
        stopButton.autoSetDimension(.width, toSize: CameraCaptureControl.recordingLockControlSize)
        stopButton.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor).isActive = true
        stopButton.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor).isActive = true

        // The long press handles both the tap and the hold interaction, as well as the animation
        // the presents as the user begins to hold (and the button begins to grow prior to recording)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0
        shutterButtonOuterCircle.addGestureRecognizer(longPressGesture)

        reactivateConstraintsForCurrentAxis()
    }

    @available(*, unavailable, message: "Use init(axis:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI State

    enum State {
        case initial
        case recording
        case recordingLocked
        case recordingUsingVoiceOver
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
        if state == .recordingUsingVoiceOver {
            stopButton.alpha = 1
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
                if self.state == .recording && isRecordingWithLongPress {
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

        case .recordingUsingVoiceOver:
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.recordingLockControlSize
        }
    }

    private func initializeVideoRecordingControlsIfNecessary() {
        guard lockIconView.superview == nil else { return }

        // 1. Slider.
        insertSubview(slidingCircleView, belowSubview: shutterButtonInnerCircle)

        // 2. Lock Icon
        addSubview(lockIconView)
        lockIconView.translatesAutoresizingMaskIntoConstraints = false
        // Centered vertically, pinned to trailing edge.
        let horizontalConstraints = [ lockIconView.centerYAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerYAnchor),
                                      lockIconView.trailingAnchor.constraint(equalTo: trailingAnchor) ]
        // Centered horizontally, pinned to bottom edge.
        let verticalConstraints = [ lockIconView.centerXAnchor.constraint(equalTo: shutterButtonLayoutGuide.centerXAnchor),
                                    lockIconView.bottomAnchor.constraint(equalTo: bottomAnchor) ]

        // 3. Activate current constraints.
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

            sliderTrackingProgress = 0
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
                self.startVideoRecording()
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

            switch state {
            case .recording:
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

                    finishVideoRecording()
                }

            case .initial:
                capturePhoto()

            case .recordingLocked, .recordingUsingVoiceOver:
                break
            }

        case .cancelled, .failed:
            if state == .recording {
                sliderTrackingProgress = 0
                setState(.initial, animationDuration: animationDuration)
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
        finishVideoRecording()
    }
}

protocol CameraZoomSelectionControlDelegate: AnyObject {

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didSelect camera: CameraCaptureSession.CameraType)

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didChangeZoomFactor zoomFactor: CGFloat)
}

class CameraZoomSelectionControl: UIView {

    weak var delegate: CameraZoomSelectionControlDelegate?

    private let availableCameras: [CameraCaptureSession.CameraType]

    var selectedCamera: CameraCaptureSession.CameraType
    var currentZoomFactor: CGFloat {
        didSet {
            var viewFound = false
            for selectionView in selectionViews.reversed() {
                if currentZoomFactor >= selectionView.defaultZoomFactor && !viewFound {
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
        stackView.axis = UIDevice.current.isIPad ? .vertical : .horizontal
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()
    private let selectionViews: [CameraSelectionCircleView]

    var cameraZoomLevelIndicators: [UIView] {
        selectionViews
    }

    var axis: NSLayoutConstraint.Axis {
        get {
            stackView.axis
        }
        set {
            stackView.axis = newValue
        }
    }

    required init(availableCameras: [(cameraType: CameraCaptureSession.CameraType, defaultZoomFactor: CGFloat)]) {
        owsAssertDebug(!availableCameras.isEmpty, "availableCameras must not be empty.")

        self.availableCameras = availableCameras.map { $0.cameraType }

        let (wideAngleCamera, wideAngleCameraZoomFactor) = availableCameras.first(where: { $0.cameraType == .wideAngle }) ?? availableCameras.first!
        selectedCamera = wideAngleCamera
        currentZoomFactor = wideAngleCameraZoomFactor

        selectionViews = availableCameras.map { CameraSelectionCircleView(camera: $0.cameraType, defaultZoomFactor: $0.defaultZoomFactor) }

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = selectionViews.count > 1 ? .ows_blackAlpha20 : .clear
        layoutMargins = UIEdgeInsets(margin: 2)

        selectionViews.forEach { view in
            view.isSelected = view.camera == selectedCamera
            view.autoSetDimensions(to: .square(38))
            view.update(animated: false)
        }
        stackView.addArrangedSubviews(selectionViews)
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(gesture:)))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @available(*, unavailable, message: "Use init(availableCameras:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Only do pill shape if background color is set (see initializer).
        if selectionViews.count > 1 {
            layer.cornerRadius = 0.5 * min(width, height)
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
                if view.isSelected && view != selectedView {
                    view.isSelected = false
                    view.update(animated: true)
                } else if view == selectedView {
                    view.isSelected = true
                    view.update(animated: true)
                }
            }
            selectedCamera = selectedView.camera
            delegate?.cameraZoomControl(self, didSelect: selectedCamera)
        }
    }

    private class CameraSelectionCircleView: UIView {

        let camera: CameraCaptureSession.CameraType
        let defaultZoomFactor: CGFloat
        var currentZoomFactor: CGFloat = 1

        private let circleView: CircleView = {
            let circleView = CircleView()
            circleView.backgroundColor = .ows_blackAlpha60
            return circleView
        }()

        private let textLabel: UILabel = {
            let label = UILabel()
            label.textAlignment = .center
            label.textColor = .ows_white
            label.font = .semiboldFont(ofSize: 11)
            return label
        }()

        required init(camera: CameraCaptureSession.CameraType, defaultZoomFactor: CGFloat) {
            self.camera = camera
            self.defaultZoomFactor = defaultZoomFactor
            self.currentZoomFactor = defaultZoomFactor

            super.init(frame: .zero)

            addSubview(circleView)
            addSubview(textLabel)
            textLabel.autoPinEdgesToSuperviewEdges()
        }

        @available(*, unavailable, message: "Use init(camera:defaultZoomFactor:) instead")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            circleView.bounds = CGRect(origin: .zero, size: CGSize(square: circleDiameter))
            circleView.center = bounds.center
        }

        var isSelected: Bool = false {
            didSet {
                if !isSelected {
                    currentZoomFactor = defaultZoomFactor
                }
            }
        }

        private var circleDiameter: CGFloat {
            let circleDiameter = isSelected ? bounds.width : bounds.width * 24 / 38
            return ceil(circleDiameter)
        }

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

        static private let animationDuration: TimeInterval = 0.2
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
                UIView.animate(withDuration: Self.animationDuration,
                               delay: 0,
                               options: [ .curveEaseInOut ]) {
                    animations()
                }
            } else {
                animations()
            }
        }

        override var isAccessibilityElement: Bool {
            get { false }
            set { super.isAccessibilityElement = newValue }
        }
    }
}

private class LockView: UIView {

    private let imageViewLock = UIImageView(image: UIImage(named: "media-composer-lock-outline"))
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
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CameraCaptureControl.recordingLockControlSize, height: CameraCaptureControl.recordingLockControlSize)
    }
}

class RecordingDurationView: PillView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 9)

        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        let stackView = UIStackView(arrangedSubviews: [icon, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        updateDurationLabel()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var duration: TimeInterval = 0 {
        didSet {
            updateDurationLabel()
        }
    }

    // If `true` red dot next to duration label will flash.
    var isRecordingInProgress: Bool = false {
        didSet {
            guard oldValue != isRecordingInProgress else { return }
            if isRecordingInProgress {
                startAnimatingRedDot()
            } else {
                stopAnimatingRedDot()
            }
        }
    }

    // MARK: - Subviews

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = UIColor.white
        return label
    }()

    private let icon: UIView = {
        let icon = CircleView()
        icon.backgroundColor = .red
        icon.autoSetDimensions(to: CGSize(square: 6))
        icon.alpha = 0
        return icon
    }()

    // MARK: -

    private func startAnimatingRedDot() {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [ .autoreverse, .repeat ],
            animations: { self.icon.alpha = 1 }
        )
    }

    private func stopAnimatingRedDot() {
        icon.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.4) {
            self.icon.alpha = 0
        }
    }

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

class MediaDoneButton: UIButton {

    var badgeNumber: Int = 0 {
        didSet {
            textLabel.text = numberFormatter.string(for: badgeNumber)
            invalidateIntrinsicContentSize()
        }
    }

    override var overrideUserInterfaceStyle: UIUserInterfaceStyle {
        didSet {
            if oldValue != overrideUserInterfaceStyle {
                updateStyle()
            }
        }
    }

    private static var font: UIFont {
        return UIFont.dynamicTypeSubheadline.monospaced()
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
        pillView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 8)
        return pillView
    }()
    private let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let chevronImageView: UIImageView = {
        let image = UIImage(systemName: "chevron.right")
        let chevronImageView = UIImageView(image: image!.withRenderingMode(.alwaysTemplate).imageFlippedForRightToLeftLayoutDirection())
        chevronImageView.contentMode = .center
        chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: MediaDoneButton.font.pointSize)
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
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            textLabel.font = .dynamicTypeSubheadline.monospaced()
            chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: textLabel.font.pointSize)
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
        let blurStyle: UIBlurEffect.Style
        let tintColor: UIColor
        switch overrideUserInterfaceStyle {
        case .dark:
            blurStyle = .dark
            tintColor = Theme.darkThemePrimaryColor
        case .light:
            blurStyle = .extraLight
            tintColor = .ows_gray60
        default:
            blurStyle = .regular
            tintColor = .ows_accentBlue
        }
        blurBackgroundView.effect = UIBlurEffect(style: blurStyle)
        chevronImageView.tintColor = tintColor
    }
}

class FlashModeButton: RoundMediaButton {

    private static let flashOn = UIImage(named: "media-composer-flash-filled")
    private static let flashOff = UIImage(named: "media-composer-flash-outline")
    private static let flashAuto = UIImage(named: "media-composer-flash-auto")

    private var flashMode: AVCaptureDevice.FlashMode = .auto

    required init() {
        super.init(image: FlashModeButton.flashAuto, backgroundStyle: .blur, customView: nil)
    }

    func setFlashMode(_ flashMode: AVCaptureDevice.FlashMode, animated: Bool) {
        guard self.flashMode != flashMode else { return }

        let image: UIImage? = {
            switch flashMode {
            case .auto:
                return FlashModeButton.flashAuto
            case .on:
                return FlashModeButton.flashOn
            case .off:
                return FlashModeButton.flashOff
            @unknown default:
                owsFailDebug("unexpected photoCapture.flashMode: \(flashMode.rawValue)")
                return FlashModeButton.flashAuto
            }
        }()
        setImage(image, animated: animated)
        self.flashMode = flashMode
    }
}

class CameraChooserButton: RoundMediaButton {

    var isFrontCameraActive = false

    init(backgroundStyle: RoundMediaButton.BackgroundStyle) {
        super.init(image: UIImage(named: "media-composer-switch-camera"), backgroundStyle: backgroundStyle, customView: nil)
    }

    func performSwitchAnimation() {
        UIView.animate(withDuration: 0.2) {
            let epsilonToForceCounterClockwiseRotation: CGFloat = 0.00001
            self.transform = self.transform.rotate(.pi + epsilonToForceCounterClockwiseRotation)
        }
    }
}

class CaptureModeButton: RoundMediaButton {

    private static let batchModeOn = UIImage(named: "media-composer-create-album-solid")
    private static let batchModeOff = UIImage(named: "media-composer-create-album-outline")

    init() {
        super.init(image: CaptureModeButton.batchModeOff, backgroundStyle: .blur, customView: nil)
    }

    private var captureMode = PhotoCaptureViewController.CaptureMode.single

    func setCaptureMode(_ captureMode: PhotoCaptureViewController.CaptureMode, animated: Bool) {
        guard self.captureMode != captureMode else { return }

        let image: UIImage? = {
            switch captureMode {
            case .single:
                return CaptureModeButton.batchModeOff
            case .multi:
                return CaptureModeButton.batchModeOn
            }
        }()
        setImage(image, animated: animated)
        self.captureMode = captureMode
    }
}

class MediaPickerThumbnailButton: UIButton {

    required init() {
        let buttonSize = MediaPickerThumbnailButton.visibleSize + 2*MediaPickerThumbnailButton.contentMargin
        super.init(frame: CGRect(origin: .zero, size: .square(buttonSize)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let visibleSize: CGFloat = 42
    private static let contentMargin: CGFloat = 8

    func configure() {
        contentEdgeInsets = UIEdgeInsets(margin: MediaPickerThumbnailButton.contentMargin)

        let placeholderView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        placeholderView.layer.cornerRadius = 10
        placeholderView.layer.borderWidth = 1.5
        placeholderView.layer.borderColor = UIColor.ows_whiteAlpha80.cgColor
        placeholderView.clipsToBounds = true
        placeholderView.isUserInteractionEnabled = false
        insertSubview(placeholderView, at: 0)
        placeholderView.autoPinEdgesToSuperviewEdges(with: contentEdgeInsets)

        var authorizationStatus: PHAuthorizationStatus
        if #available(iOS 14, *) {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus()
        }
        guard authorizationStatus == .authorized else { return }

        // Async Fetch last image
        DispatchQueue.global(qos: .userInteractive).async {
            let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: nil)
            if let asset = fetchResult.lastObject {
                let targetImageSize = CGSize(square: MediaPickerThumbnailButton.visibleSize)
                PHImageManager.default().requestImage(for: asset, targetSize: targetImageSize, contentMode: .aspectFill, options: nil) { (image, _) in
                    if let image = image {
                        DispatchQueue.main.async {
                            self.updateWith(image: image)
                            placeholderView.alpha = 0
                        }
                    }
                }
            }
        }
    }

    private func updateWith(image: UIImage) {
        setImage(image, animated: self.window != nil)
        if let imageView {
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 10
            imageView.layer.borderWidth = 1.5
            imageView.layer.borderColor = UIColor.ows_whiteAlpha80.cgColor
            imageView.clipsToBounds = true
        }
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: contentEdgeInsets.leading + Self.visibleSize + contentEdgeInsets.trailing,
                      height: contentEdgeInsets.top + Self.visibleSize + contentEdgeInsets.bottom)
    }
}

// MARK: - Toolbars

class CameraTopBar: MediaTopBar {

    let closeButton = RoundMediaButton(image: UIImage(named: "media-composer-close"), backgroundStyle: .blur)

    private let cameraControlsContainerView: UIStackView
    let flashModeButton = FlashModeButton()
    let batchModeButton = CaptureModeButton()

    let recordingTimerView = RecordingDurationView(frame: .zero)

    override init(frame: CGRect) {
        cameraControlsContainerView = UIStackView(arrangedSubviews: [ batchModeButton, flashModeButton ])

        super.init(frame: frame)

        closeButton.accessibilityLabel = OWSLocalizedString("CAMERA_VO_CLOSE_BUTTON",
                                                           comment: "VoiceOver label for close (X) button in camera.")

        addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.layoutMarginsGuide.leadingAnchor.constraint(equalTo: controlsLayoutGuide.leadingAnchor).isActive = true
        closeButton.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor).isActive = true
        closeButton.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor).isActive = true

        addSubview(recordingTimerView)
        recordingTimerView.translatesAutoresizingMaskIntoConstraints = false
        recordingTimerView.centerYAnchor.constraint(equalTo: controlsLayoutGuide.centerYAnchor).isActive = true
        recordingTimerView.centerXAnchor.constraint(equalTo: controlsLayoutGuide.centerXAnchor).isActive = true

        cameraControlsContainerView.spacing = 0
        addSubview(cameraControlsContainerView)
        cameraControlsContainerView.translatesAutoresizingMaskIntoConstraints = false
        cameraControlsContainerView.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor).isActive = true
        cameraControlsContainerView.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor).isActive = true
        flashModeButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: controlsLayoutGuide.trailingAnchor).isActive = true

        updateElementsVisibility(animated: false)
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Mode

    enum Mode {
        case cameraControls, closeButton, videoRecording
    }

    private var internalMode: Mode = .cameraControls
    var mode: Mode {
        get { internalMode }
        set {
            setMode(newValue, animated: false)
        }
    }

    func setMode(_ mode: Mode, animated: Bool) {
        guard mode != internalMode else { return }
        internalMode = mode
        updateElementsVisibility(animated: animated)
    }

    private func updateElementsVisibility(animated: Bool) {
        switch mode {
        case .cameraControls:
            closeButton.setIsHidden(false, animated: animated)
            cameraControlsContainerView.setIsHidden(false, animated: animated)
            recordingTimerView.setIsHidden(true, animated: false)

        case .closeButton:
            closeButton.setIsHidden(false, animated: animated)
            cameraControlsContainerView.setIsHidden(true, animated: animated)
            recordingTimerView.setIsHidden(true, animated: false)

        case .videoRecording:
            closeButton.setIsHidden(true, animated: animated)
            cameraControlsContainerView.setIsHidden(true, animated: animated)
            recordingTimerView.setIsHidden(false, animated: animated)
        }
    }
}

class CameraBottomBar: UIView {

    private var compactHeightLayoutConstraints = [NSLayoutConstraint]()
    private var regularHeightLayoutConstraints = [NSLayoutConstraint]()
    var isCompactHeightLayout = false {
        didSet {
            guard oldValue != isCompactHeightLayout else { return }
            updateCompactHeightLayoutConstraints()
        }
    }

    enum Layout {
        case iPhone
        case iPad
    }
    private var _internalLayout: Layout = .iPhone
    var layout: Layout { _internalLayout }
    func setLayout(_ layout: Layout, animated: Bool) {
        guard _internalLayout != layout else { return }
        _internalLayout = layout
        updateUI(animated: animated)
    }

    enum Mode {
        case camera
        case videoRecording
        case text
    }
    private var _internalMode: Mode = .camera
    var mode: Mode { _internalMode }
    func setMode(_ mode: Mode, animated: Bool) {
        guard _internalMode != mode else { return }
        _internalMode = mode
        updateUI(animated: animated)
    }

    private func updateUI(animated: Bool) {
        let hideBottomButtons = mode != .camera || layout == .iPad
        photoLibraryButton.setIsHidden(hideBottomButtons, animated: animated)
        switchCameraButton.setIsHidden(hideBottomButtons, animated: animated)

        let hideCameraCaptureControl = mode == .text || layout == .iPad
        captureControl.setIsHidden(hideCameraCaptureControl, animated: animated)

        if isContentTypeSelectionControlAvailable {
            contentTypeSelectionControl.setIsHidden(mode == .videoRecording, animated: animated)
            proceedButton.setIsHidden(mode != .text, animated: animated)
        }
    }

    let photoLibraryButton = MediaPickerThumbnailButton()
    let switchCameraButton = CameraChooserButton(backgroundStyle: .solid(RoundMediaButton.defaultBackgroundColor))
    let proceedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(imageLiteralResourceName: "chevron-right-colored-42"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.sizeToFit()
        return button
    }()
    let controlButtonsLayoutGuide = UILayoutGuide() // area encompassing Photo Library and Switch Camera buttons.
    private var controlButtonsLayoutGuideConstraints: [NSLayoutConstraint]?
    func constrainControlButtonsLayoutGuideHorizontallyTo(leadingAnchor: NSLayoutXAxisAnchor?,
                                                          trailingAnchor: NSLayoutXAxisAnchor?) {
        if let existingConstraints = controlButtonsLayoutGuideConstraints {
            NSLayoutConstraint.deactivate(existingConstraints)
        }

        let referenceLeadingAnchor = leadingAnchor ?? layoutMarginsGuide.leadingAnchor
        let referenceTrailingAnchor = trailingAnchor ?? layoutMarginsGuide.trailingAnchor
        let constraints = [
            controlButtonsLayoutGuide.leadingAnchor.constraint(equalTo: referenceLeadingAnchor),
            controlButtonsLayoutGuide.trailingAnchor.constraint(equalTo: referenceTrailingAnchor)
        ]
        constraints.forEach { $0.priority = .defaultHigh - 10 }
        NSLayoutConstraint.activate(constraints)
        self.controlButtonsLayoutGuideConstraints = constraints
    }

    let captureControl = CameraCaptureControl(axis: .horizontal)
    var shutterButtonLayoutGuide: UILayoutGuide {
        captureControl.shutterButtonLayoutGuide
    }

    let isContentTypeSelectionControlAvailable: Bool
    private(set) lazy var contentTypeSelectionControl: UISegmentedControl = ContentTypeSelectionControl()

    init(isContentTypeSelectionControlAvailable: Bool) {
        self.isContentTypeSelectionControlAvailable = isContentTypeSelectionControlAvailable

        super.init(frame: .zero)

        preservesSuperviewLayoutMargins = true

        controlButtonsLayoutGuide.identifier = "ControlButtonsLayoutGuide"
        addLayoutGuide(controlButtonsLayoutGuide)
        addConstraint(controlButtonsLayoutGuide.topAnchor.constraint(greaterThanOrEqualTo: topAnchor))
        addConstraint({
            // This constraint imitates setting huggingPriority on the controlButtonsLayoutGuide
            // to prevent it from expanding too much on iPads.
            let heightConstraint = controlButtonsLayoutGuide.heightAnchor.constraint(
                equalToConstant: photoLibraryButton.intrinsicContentSize.height
            )
            heightConstraint.priority = .defaultHigh - 100
            return heightConstraint
        }())
        constrainControlButtonsLayoutGuideHorizontallyTo(leadingAnchor: nil, trailingAnchor: nil)

        captureControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captureControl)
        captureControl.autoPinEdge(toSuperviewEdge: .top)
        captureControl.autoPinTrailingToSuperviewMargin()
        addConstraint(captureControl.shutterButtonLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor))

        photoLibraryButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(photoLibraryButton)
        addConstraints([ photoLibraryButton.layoutMarginsGuide.leadingAnchor.constraint(equalTo: controlButtonsLayoutGuide.leadingAnchor),
                         photoLibraryButton.centerYAnchor.constraint(equalTo: controlButtonsLayoutGuide.centerYAnchor),
                         photoLibraryButton.topAnchor.constraint(greaterThanOrEqualTo: controlButtonsLayoutGuide.topAnchor) ])

        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(switchCameraButton)
        addConstraints([ switchCameraButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: controlButtonsLayoutGuide.trailingAnchor),
                         switchCameraButton.topAnchor.constraint(greaterThanOrEqualTo: controlButtonsLayoutGuide.topAnchor),
                         switchCameraButton.centerYAnchor.constraint(equalTo: controlButtonsLayoutGuide.centerYAnchor) ])

        if isContentTypeSelectionControlAvailable {
            contentTypeSelectionControl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(contentTypeSelectionControl)
            addConstraints([ contentTypeSelectionControl.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
                             contentTypeSelectionControl.centerYAnchor.constraint(equalTo: controlButtonsLayoutGuide.centerYAnchor) ])

            proceedButton.isHidden = true
            proceedButton.isEnabled = false
            proceedButton.accessibilityValue = OWSLocalizedString("CAMERA_VO_ARROW_RIGHT_PROCEED",
                                                                 comment: "VoiceOver label for -> button in text story composer.")
            proceedButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(proceedButton)
            addConstraints([ proceedButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: controlButtonsLayoutGuide.trailingAnchor),
                             proceedButton.centerYAnchor.constraint(equalTo: controlButtonsLayoutGuide.centerYAnchor) ])
        }

        // Compact Height:
        // With this layout owner of this view should be able to just define vertical position of the bar.
        if isContentTypeSelectionControlAvailable {
            // • control buttons are located below shutter button with a fixed spacing and are pinned to the bottom.
           compactHeightLayoutConstraints.append(
                contentsOf: [ controlButtonsLayoutGuide.topAnchor.constraint(equalTo: captureControl.bottomAnchor, constant: 8),
                              controlButtonsLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor) ])
        } else {
            // • control buttons are vertically centered with the shutter button.
            // • shutter button control takes the entire view height.
            compactHeightLayoutConstraints.append(
                contentsOf: [ controlButtonsLayoutGuide.centerYAnchor.constraint(equalTo: captureControl.shutterButtonLayoutGuide.centerYAnchor),
                              captureControl.bottomAnchor.constraint(equalTo: bottomAnchor) ])
        }

        // Regular Height:
        // • controls are located below the shutter button but exact spacing is to be defined by view controller.
        // • area with the controls is pinned to the bottom edge of the view.
        // With this layout owner of this view is supposed to add additional constraints
        // to top and bottom anchors of controlButtonsLayoutGuide thus positioning buttons properly.
        regularHeightLayoutConstraints.append(contentsOf: [ controlButtonsLayoutGuide.topAnchor.constraint(greaterThanOrEqualTo: captureControl.bottomAnchor),
                                                            controlButtonsLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor) ])

        updateCompactHeightLayoutConstraints()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateCompactHeightLayoutConstraints() {
        if isCompactHeightLayout {
            removeConstraints(regularHeightLayoutConstraints)
            addConstraints(compactHeightLayoutConstraints)
        } else {
            removeConstraints(compactHeightLayoutConstraints)
            addConstraints(regularHeightLayoutConstraints)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if isContentTypeSelectionControlAvailable && UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.async {
                self.updateContentTypePickerAccessibilityFrame()
            }
        }
    }

    // Override to allow touches that hit empty area of the toobar to pass through to views underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        guard view != self else { return nil }
        return view
    }

    private func updateContentTypePickerAccessibilityFrame() {
        guard isContentTypeSelectionControlAvailable else { return }

        // Make accessibility frame slightly larger so that order of things on the screen is correct.

        let pickerFrame = contentTypeSelectionControl.frame
        let dx: CGFloat = 20 // +20 pts each side
        let dy: CGFloat
        if isCompactHeightLayout {
            dy = 20 // +20 pts top and bottom
        } else {
            dy = 0.5 * max(0, controlButtonsLayoutGuide.layoutFrame.height - pickerFrame.height)
        }
        contentTypeSelectionControl.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(pickerFrame.insetBy(dx: -dx, dy: -dy), in: self)
    }

    fileprivate class ContentTypeSelectionControl: UISegmentedControl {

        static private let titleCamera = OWSLocalizedString(
            "STORY_COMPOSER_CAMERA",
            comment: "One of two possible sources when composing a new story. Displayed at the bottom in in-app camera."
        )
        static private let titleText = OWSLocalizedString(
            "STORY_COMPOSER_TEXT",
            comment: "One of two possible sources when composing a new story. Displayed at the bottom in in-app camera."
        )

        init() {
            super.init(frame: .zero)
            super.insertSegment(withTitle: ContentTypeSelectionControl.titleText.uppercased(), at: 0, animated: false)
            super.insertSegment(withTitle: ContentTypeSelectionControl.titleCamera.uppercased(), at: 0, animated: false)

            backgroundColor = .clear

            // Use a clear image for the background and the dividers
            let tintColorImage = UIImage(color: .clear, size: CGSize(width: 1, height: 32))
            setBackgroundImage(tintColorImage, for: .normal, barMetrics: .default)
            setDividerImage(tintColorImage, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)

            let normalFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
            let selectedFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)

            setTitleTextAttributes([ .font: normalFont, .foregroundColor: UIColor(white: 1, alpha: 0.7) ], for: .normal)
            setTitleTextAttributes([ .font: selectedFont, .foregroundColor: UIColor.white ], for: .selected)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

class CameraSideBar: UIView {

    var isRecordingVideo = false {
        didSet {
            cameraControlsContainerView.isHidden = isRecordingVideo
            photoLibraryButton.isHidden = isRecordingVideo
        }
    }

    private let cameraControlsContainerView: UIStackView
    let flashModeButton = FlashModeButton()
    let batchModeButton = CaptureModeButton()
    let switchCameraButton = CameraChooserButton(backgroundStyle: .blur)

    let photoLibraryButton = MediaPickerThumbnailButton()

    private(set) var cameraCaptureControl = CameraCaptureControl(axis: .vertical)

    override init(frame: CGRect) {
        cameraControlsContainerView = UIStackView(arrangedSubviews: [ batchModeButton, flashModeButton, switchCameraButton ])

        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(margin: 8)

        cameraControlsContainerView.spacing = 8
        cameraControlsContainerView.axis = .vertical
        addSubview(cameraControlsContainerView)
        cameraControlsContainerView.autoPinWidthToSuperviewMargins()
        cameraControlsContainerView.autoPinTopToSuperviewMargin()

        addSubview(cameraCaptureControl)
        cameraCaptureControl.autoHCenterInSuperview()
        cameraCaptureControl.shutterButtonLayoutGuide.topAnchor.constraint(equalTo: cameraControlsContainerView.bottomAnchor, constant: 24).isActive = true

        addSubview(photoLibraryButton)
        photoLibraryButton.autoHCenterInSuperview()
        photoLibraryButton.topAnchor.constraint(equalTo: cameraCaptureControl.shutterButtonLayoutGuide.bottomAnchor, constant: 24).isActive = true
        photoLibraryButton.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Accessibility

extension CameraCaptureControl {

    override var isAccessibilityElement: Bool {
        get { true }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [ .button ] }
        set { super.accessibilityTraits = newValue }
    }

    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(shutterButtonLayoutGuide.layoutFrame, in: self) }
        set { super.accessibilityFrame = newValue }
    }

    override var accessibilityLabel: String? {
        get {
            switch state {
            case .initial:
                return OWSLocalizedString("CAMERA_VO_TAKE_PICTURE",
                                         comment: "VoiceOver label for the round capture button in in-app camera.")

            case .recordingUsingVoiceOver:
                return OWSLocalizedString("CAMERA_VO_STOP_VIDEO_REC",
                                         comment: "VoiceOver label for the round capture button in in-app camera during video recording.")

            default:
                owsFailDebug("Invalid state")
                return nil
            }
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            guard state == .initial else { return [] }
            let actionName = OWSLocalizedString("CAMERA_VO_TAKE_VIDEO",
                                               comment: "VoiceOver label for other possible action for round capture button in in-app camera.")
            return [ UIAccessibilityCustomAction(name: actionName, target: self, selector: #selector(accessibilityStartVideoRecording)) ] }
        set { super.accessibilityCustomActions = newValue }
    }

    override func accessibilityActivate() -> Bool {
        switch state {
        case .initial:
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

extension MediaDoneButton {

    override var accessibilityLabel: String? {
        get { CommonStrings.doneButton }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            guard badgeNumber > 0 else { return nil }

            let format = OWSLocalizedString("CAMERA_VO_N_ITEMS", tableName: "PluralAware",
                                           comment: "VoiceOver text for blue Done button in camera, describing how many items have already been captured.")
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
            OWSLocalizedString("CAMERA_VO_FLASH_BUTTON",
                              comment: "VoiceOver label for Flash button in camera.")
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            switch flashMode {
            case .auto:
                return OWSLocalizedString("CAMERA_VO_FLASH_AUTO",
                                         comment: "VoiceOver description of current flash setting.")

            case .on:
                return OWSLocalizedString("CAMERA_VO_FLASH_ON",
                                         comment: "VoiceOver description of current flash setting.")

            case .off:
                return OWSLocalizedString("CAMERA_VO_FLASH_OFF",
                                         comment: "VoiceOver description of current flash setting.")

            @unknown default:
                owsFailDebug("unexpected photoCapture.flashMode: \(flashMode.rawValue)")
                return nil
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension CameraChooserButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString("CAMERA_VO_CAMERA_CHOOSER_BUTTON",
                              comment: "VoiceOver label for Switch Camera button in in-app camera.")
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityHint: String? {
        get {
            OWSLocalizedString("CAMERA_VO_CAMERA_CHOOSER_HINT",
                              comment: "VoiceOver hint for Switch Camera button in in-app camera.")
        }
        set { super.accessibilityHint = newValue }
    }

    override var accessibilityValue: String? {
        get {
            if isFrontCameraActive {
                return OWSLocalizedString("CAMERA_VO_CAMERA_FRONT_FACING",
                                         comment: "VoiceOver value for Switch Camera button that tells which camera is currently active.")
            } else {
                return OWSLocalizedString("CAMERA_VO_CAMERA_BACK_FACING",
                                         comment: "VoiceOver value for Switch Camera button that tells which camera is currently active.")
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension CaptureModeButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString("CAMERA_VO_CAMERA_ALBUM_MODE",
                              comment: "VoiceOver label for Flash button in camera.")
        }
        set { super.accessibilityLabel = newValue }
    }

    override var accessibilityValue: String? {
        get {
            switch captureMode {
            case .single:
                return OWSLocalizedString("CAMERA_VO_CAMERA_ALBUM_MODE_OFF",
                                         comment: "VoiceOver label for Switch Camera button in in-app camera.")

            case .multi:
                return OWSLocalizedString("CAMERA_VO_CAMERA_ALBUM_MODE_ON",
                                         comment: "VoiceOver label for Switch Camera button in in-app camera.")
            }
        }
        set { super.accessibilityValue = newValue }
    }
}

extension MediaPickerThumbnailButton {

    override var accessibilityLabel: String? {
        get {
            OWSLocalizedString("CAMERA_VO_PHOTO_LIBRARY_BUTTON",
                              comment: "VoiceOver label for button to choose existing photo/video in in-app camera")
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
        get { [ .button, .adjustable ] }
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

            let formatString = OWSLocalizedString("CAMERA_VO_ZOOM_LEVEL",
                                                 comment: "VoiceOver description of current camera zoom level.")
            return String(format: formatString, zoomValueString)
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

extension CameraBottomBar.ContentTypeSelectionControl {

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
                comment: "VoiceOver label for composer mode (CAMERA|TEXT) selector at the bottom of in-app camera screen."
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
