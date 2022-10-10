//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.

import UIKit
import AVFoundation
import PromiseKit
import SessionUIKit
import SignalUtilitiesKit

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment)
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
}

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
}

extension PhotoCaptureError: LocalizedError {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .assertionError:
            return NSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

class PhotoCaptureViewController: OWSViewController {

    weak var delegate: PhotoCaptureViewControllerDelegate?

    private var photoCapture: PhotoCapture!

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        if let photoCapture = photoCapture {
            photoCapture.stopCapture().done {
                Logger.debug("stopCapture completed")
            }.retainUntilComplete()
        }
    }

    // MARK: - Overrides

    override func loadView() {
        self.view = UIView()
        self.view.themeBackgroundColor = .newConversation_background
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPhotoCapture()
        setupOrientationMonitoring()
        
        updateNavigationItems()
        updateFlashModeControl()

        let initialCaptureOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) ?? .portrait
        updateIconOrientations(isAnimated: false, captureOrientation: initialCaptureOrientation)

        view.addGestureRecognizer(pinchZoomGesture)
        view.addGestureRecognizer(focusGesture)
        view.addGestureRecognizer(doubleTapToSwitchCameraGesture)
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: -
    var isRecordingMovie: Bool = false
    let recordingTimerView = RecordingTimerView()

    func updateNavigationItems() {
        if isRecordingMovie {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = nil
            navigationItem.titleView = recordingTimerView
            recordingTimerView.sizeToFit()
        }
        else {
            navigationItem.titleView = nil
            navigationItem.leftBarButtonItem = dismissControl.barButtonItem
            let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            fixedSpace.width = 16

            navigationItem.rightBarButtonItems = [switchCameraControl.barButtonItem, fixedSpace, flashModeControl.barButtonItem]
        }
    }

    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        Logger.debug("")
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Views

    let captureButton = CaptureButton()
    var previewView: CapturePreviewView!

    class PhotoControl {
        let button: OWSButton
        let barButtonItem: UIBarButtonItem

        init(imageName: String, block: @escaping () -> Void) {
            self.button = OWSButton(imageName: imageName, tintColor: .white, block: block)
            button.autoPinToSquareAspectRatio()
            button.themeShadowColor = .black
            button.layer.shadowOffset = CGSize.zero
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 4

            self.barButtonItem = UIBarButtonItem(customView: button)
        }

        func setImage(imageName: String) {
            button.setImage(imageName: imageName)
        }
    }

    private lazy var dismissControl: PhotoControl = {
        return PhotoControl(imageName: "X") { [weak self] in
            self?.didTapClose()
        }
    }()

    private lazy var switchCameraControl: PhotoControl = {
        return PhotoControl(imageName: "ic_switch_camera") { [weak self] in
            self?.didTapSwitchCamera()
        }
    }()

    private lazy var flashModeControl: PhotoControl = {
        return PhotoControl(imageName: "ic_flash_mode_auto") { [weak self] in
            self?.didTapFlashMode()
        }
    }()

    lazy var pinchZoomGesture: UIPinchGestureRecognizer = {
        return UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:)))
    }()

    lazy var focusGesture: UITapGestureRecognizer = {
        return UITapGestureRecognizer(target: self, action: #selector(didTapFocusExpose(tapGesture:)))
    }()

    lazy var doubleTapToSwitchCameraGesture: UITapGestureRecognizer = {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapToSwitchCamera(tapGesture:)))
        tapGesture.numberOfTapsRequired = 2
        return tapGesture
    }()

    // MARK: - Events

    @objc
    func didTapClose() {
        self.delegate?.photoCaptureViewControllerDidCancel(self)
    }

    @objc
    func didTapSwitchCamera() {
        Logger.debug("")
        switchCamera()
    }

    @objc
    func didDoubleTapToSwitchCamera(tapGesture: UITapGestureRecognizer) {
        Logger.debug("")
        switchCamera()
    }

    private func switchCamera() {
        UIView.animate(withDuration: 0.2) {
            let epsilonToForceCounterClockwiseRotation: CGFloat = 0.00001
            self.switchCameraControl.button.transform = self.switchCameraControl.button.transform.rotate(.pi + epsilonToForceCounterClockwiseRotation)
        }
        photoCapture.switchCamera().catch { error in
            self.showFailureUI(error: error)
        }.retainUntilComplete()
    }

    @objc
    func didTapFlashMode() {
        Logger.debug("")
        photoCapture.switchFlashMode().done {
            self.updateFlashModeControl()
        }.retainUntilComplete()
    }

    @objc
    func didPinchZoom(pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began: fallthrough
        case .changed:
            photoCapture.updateZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        case .ended:
            photoCapture.completeZoom(scaleFromPreviousZoomFactor: pinchGesture.scale)
        default:
            break
        }
    }

    @objc
    func didTapFocusExpose(tapGesture: UITapGestureRecognizer) {
        let viewLocation = tapGesture.location(in: view)
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: viewLocation)
        photoCapture.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    // MARK: - Orientation

    private func setupOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeDeviceOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )
    }

    var lastKnownCaptureOrientation: AVCaptureVideoOrientation = .portrait

    @objc
    func didChangeDeviceOrientation(notification: Notification) {
        let currentOrientation = UIDevice.current.orientation

        if let captureOrientation = AVCaptureVideoOrientation(deviceOrientation: currentOrientation) {
            // since the "face up" and "face down" orientations aren't reflected in the photo output,
            // we need to capture the last known _other_ orientation so we can reflect the appropriate
            // portrait/landscape in our captured photos.
            Logger.verbose("lastKnownCaptureOrientation: \(lastKnownCaptureOrientation)->\(captureOrientation)")
            lastKnownCaptureOrientation = captureOrientation
            updateIconOrientations(isAnimated: true, captureOrientation: captureOrientation)
        }
    }

    // MARK: -

    private func updateIconOrientations(isAnimated: Bool, captureOrientation: AVCaptureVideoOrientation) {
        Logger.verbose("captureOrientation: \(captureOrientation)")

        let transformFromOrientation: CGAffineTransform
        switch captureOrientation {
        case .portrait:
            transformFromOrientation = .identity
        case .portraitUpsideDown:
            transformFromOrientation = CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft:
            transformFromOrientation = CGAffineTransform(rotationAngle: .halfPi)
        case .landscapeRight:
            transformFromOrientation = CGAffineTransform(rotationAngle: -1 * .halfPi)
        }

        // Don't "unrotate" the switch camera icon if the front facing camera had been selected.
        let tranformFromCameraType: CGAffineTransform = photoCapture.desiredPosition == .front ? CGAffineTransform(rotationAngle: -.pi) : .identity

        let updateOrientation = {
            self.flashModeControl.button.transform = transformFromOrientation
            self.switchCameraControl.button.transform   = transformFromOrientation.concatenating(tranformFromCameraType)
        }

        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }

    private func setupPhotoCapture() {
        photoCapture = PhotoCapture()
        photoCapture.delegate = self
        captureButton.delegate = photoCapture
        previewView = CapturePreviewView(session: photoCapture.session)

        photoCapture.startCapture()
            .done { [weak self] in
                self?.showCaptureUI()
            }
            .catch { [weak self] error in
                self?.showFailureUI(error: error)
            }
            .retainUntilComplete()
    }

    private func showCaptureUI() {
        Logger.debug("")
        view.addSubview(previewView)
        if UIDevice.current.hasIPhoneXNotch {
            previewView.autoPinEdgesToSuperviewEdges()
        } else {
            previewView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 0, bottom: 40, trailing: 0))
        }

        view.addSubview(captureButton)
        captureButton.autoHCenterInSuperview()
        captureButton.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: SendMediaNavigationController.bottomButtonsCenterOffset).isActive = true
    }

    private func showFailureUI(error: Error) {
        Logger.error("error: \(error)")
        let modal: ConfirmationModal = ConfirmationModal(
            info: ConfirmationModal.Info(
                title: CommonStrings.errorAlertTitle,
                explanation: error.localizedDescription,
                cancelTitle: CommonStrings.dismissButton,
                cancelStyle: .alert_text,
                afterClosed: { [weak self] in self?.dismiss(animated: true) }
            )
        )
        
        present(modal, animated: true)
    }

    private func updateFlashModeControl() {
        let imageName: String
        switch photoCapture.flashMode {
        case .auto:
            imageName = "ic_flash_mode_auto"
        case .on:
            imageName = "ic_flash_mode_on"
        case .off:
            imageName = "ic_flash_mode_off"
        default: preconditionFailure()
        }

        self.flashModeControl.setImage(imageName: imageName)
    }
}

extension PhotoCaptureViewController: PhotoCaptureDelegate {

    // MARK: - Photo

    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessingAttachment attachment: SignalAttachment) {
        delegate?.photoCaptureViewController(self, didFinishProcessingAttachment: attachment)
    }

    func photoCapture(_ photoCapture: PhotoCapture, processingDidError error: Error) {
        showFailureUI(error: error)
    }

    // MARK: - Video

    func photoCaptureDidBeginVideo(_ photoCapture: PhotoCapture) {
        isRecordingMovie = true
        updateNavigationItems()
        recordingTimerView.startCounting()
    }

    func photoCaptureDidCompleteVideo(_ photoCapture: PhotoCapture) {
        isRecordingMovie = false
        recordingTimerView.stopCounting()
        updateNavigationItems()
    }

    func photoCaptureDidCancelVideo(_ photoCapture: PhotoCapture) {
        owsFailDebug("If we ever allow this, we should test.")
        isRecordingMovie = false
        recordingTimerView.stopCounting()
        updateNavigationItems()
    }

    // MARK: -

    var zoomScaleReferenceHeight: CGFloat? {
        return view.bounds.height
    }

    var captureOrientation: AVCaptureVideoOrientation {
        return lastKnownCaptureOrientation
    }
}

// MARK: - Views

protocol CaptureButtonDelegate: AnyObject {
    // MARK: Photo
    func didTapCaptureButton(_ captureButton: CaptureButton)

    // MARK: Video
    func didBeginLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCompleteLongPressCaptureButton(_ captureButton: CaptureButton)
    func didCancelLongPressCaptureButton(_ captureButton: CaptureButton)

    var zoomScaleReferenceHeight: CGFloat? { get }
    func longPressCaptureButton(_ captureButton: CaptureButton, didUpdateZoomAlpha zoomAlpha: CGFloat)
}

class CaptureButton: UIView {

    let innerButton = CircleView()

    var tapGesture: UITapGestureRecognizer!

    var longPressGesture: UILongPressGestureRecognizer!
    let longPressDuration = 0.5

    let zoomIndicator = CircleView()

    weak var delegate: CaptureButtonDelegate?

    let defaultDiameter: CGFloat = ScaleFromIPhone5To7Plus(60, 80)
    let recordingDiameter: CGFloat = ScaleFromIPhone5To7Plus(68, 120)
    var innerButtonSizeConstraints: [NSLayoutConstraint]!
    var zoomIndicatorSizeConstraints: [NSLayoutConstraint]!

    override init(frame: CGRect) {
        super.init(frame: frame)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        innerButton.addGestureRecognizer(tapGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress))
        longPressGesture.minimumPressDuration = longPressDuration
        innerButton.addGestureRecognizer(longPressGesture)

        addSubview(innerButton)
        innerButtonSizeConstraints = autoSetDimensions(to: CGSize(width: defaultDiameter, height: defaultDiameter))
        innerButton.themeBackgroundColor = .white
        innerButton.layer.shadowOffset = .zero
        innerButton.layer.shadowOpacity = 0.33
        innerButton.layer.shadowRadius = 2
        innerButton.alpha = 0.33
        innerButton.autoPinEdgesToSuperviewEdges()

        addSubview(zoomIndicator)
        zoomIndicatorSizeConstraints = zoomIndicator.autoSetDimensions(to: CGSize(width: defaultDiameter, height: defaultDiameter))
        zoomIndicator.isUserInteractionEnabled = false
        zoomIndicator.themeBorderColor = .white
        zoomIndicator.layer.borderWidth = 1.5
        zoomIndicator.autoAlignAxis(.horizontal, toSameAxisOf: innerButton)
        zoomIndicator.autoAlignAxis(.vertical, toSameAxisOf: innerButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Gestures

    @objc
    func didTap(_ gesture: UITapGestureRecognizer) {
        delegate?.didTapCaptureButton(self)
    }

    var initialTouchLocation: CGPoint?

    @objc
    func didLongPress(_ gesture: UILongPressGestureRecognizer) {
        Logger.verbose("")

        guard let gestureView = gesture.view else {
            owsFailDebug("gestureView was unexpectedly nil")
            return
        }

        switch gesture.state {
        case .possible: break
        case .began:
            initialTouchLocation = gesture.location(in: gesture.view)
            delegate?.didBeginLongPressCaptureButton(self)
            UIView.animate(withDuration: 0.2) {
                self.innerButtonSizeConstraints.forEach { $0.constant = self.recordingDiameter }
                self.zoomIndicatorSizeConstraints.forEach { $0.constant = self.recordingDiameter }
                self.superview?.layoutIfNeeded()
            }
        case .changed:
            guard let referenceHeight = delegate?.zoomScaleReferenceHeight else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceHeight > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation = initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            let currentLocation = gesture.location(in: gestureView)
            let minDistanceBeforeActivatingZoom: CGFloat = 30
            let distance = initialTouchLocation.y - currentLocation.y - minDistanceBeforeActivatingZoom
            let distanceForFullZoom = referenceHeight / 4
            let ratio = distance / distanceForFullZoom

            let alpha = ratio.clamp(0, 1)

            Logger.verbose("distance: \(distance), alpha: \(alpha)")

            let zoomIndicatorDiameter = CGFloatLerp(recordingDiameter, 3, alpha)
            self.zoomIndicatorSizeConstraints.forEach { $0.constant = zoomIndicatorDiameter }
            zoomIndicator.superview?.layoutIfNeeded()

            delegate?.longPressCaptureButton(self, didUpdateZoomAlpha: alpha)
        case .ended:
            UIView.animate(withDuration: 0.2) {
                self.innerButtonSizeConstraints.forEach { $0.constant = self.defaultDiameter }
                self.zoomIndicatorSizeConstraints.forEach { $0.constant = self.defaultDiameter }

                self.superview?.layoutIfNeeded()
            }
            delegate?.didCompleteLongPressCaptureButton(self)
        case .cancelled, .failed:

            UIView.animate(withDuration: 0.2) {
                self.innerButtonSizeConstraints.forEach { $0.constant = self.defaultDiameter }
                self.zoomIndicatorSizeConstraints.forEach { $0.constant = self.defaultDiameter }

                self.superview?.layoutIfNeeded()
            }
            delegate?.didCancelLongPressCaptureButton(self)
        default: break
        }
    }
}

class CapturePreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        self.contentMode = .scaleAspectFill
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class RecordingTimerView: UIView {

    let stackViewSpacing: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stackView = UIStackView(arrangedSubviews: [icon, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = stackViewSpacing

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        updateView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Subviews

    private lazy var label: UILabel = {
        let label: UILabel = UILabel()
        label.font = .ows_monospacedDigitFont(withSize: 20)
        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.layer.shadowOffset = CGSize.zero
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 4

        return label
    }()

    static let iconWidth: CGFloat = 6

    private let icon: UIView = {
        let icon = CircleView()
        icon.layer.shadowOffset = CGSize.zero
        icon.layer.shadowOpacity = 0.35
        icon.layer.shadowRadius = 4
        icon.themeBackgroundColor = .danger
        icon.autoSetDimensions(to: CGSize(width: iconWidth, height: iconWidth))
        icon.alpha = 0

        return icon
    }()

    // MARK: -
    var recordingStartTime: TimeInterval?

    func startCounting() {
        recordingStartTime = CACurrentMediaTime()
        timer = Timer.weakScheduledTimer(withTimeInterval: 0.1, target: self, selector: #selector(updateView), userInfo: nil, repeats: true)
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [.autoreverse, .repeat],
            animations: { self.icon.alpha = 1 }
        )
    }

    func stopCounting() {
        timer?.invalidate()
        timer = nil
        icon.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.4) {
            self.icon.alpha = 0
        }
    }

    // MARK: -

    private var timer: Timer?

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!

        return formatter
    }()

    // This method should only be called when the call state is "connected".
    var recordingDuration: TimeInterval {
        guard let recordingStartTime = recordingStartTime else {
            return 0
        }

        return CACurrentMediaTime() - recordingStartTime
    }

    @objc
    private func updateView() {
        let recordingDuration = self.recordingDuration
        Logger.verbose("recordingDuration: \(recordingDuration)")
        let durationDate = Date(timeIntervalSinceReferenceDate: recordingDuration)
        label.text = timeFormatter.string(from: durationDate)
    }
}
