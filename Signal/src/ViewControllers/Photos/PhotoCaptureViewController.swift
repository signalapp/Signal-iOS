//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import AVFoundation
import Foundation
import Lottie
import Photos
import UIKit
import SignalMessaging

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewControllerDidFinish(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
    func photoCaptureViewControllerDidRequestPresentPhotoLibrary(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didRequestSwitchBatchMode batchMode: Bool) -> Bool
}

protocol PhotoCaptureViewControllerDataSource: AnyObject {
    var numberOfMediaItems: Int { get }
    func addMedia(attachment: SignalAttachment)
}

enum PhotoCaptureError: Error {
    case assertionError(description: String)
    case initializationFailed
    case captureFailed
    case invalidVideo
}

extension PhotoCaptureError: LocalizedError, UserErrorDescriptionProvider {
    var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_INITIALIZE_CAMERA", comment: "alert title")
        case .captureFailed:
            return NSLocalizedString("PHOTO_CAPTURE_UNABLE_TO_CAPTURE_IMAGE", comment: "alert title")
        case .assertionError, .invalidVideo:
            return NSLocalizedString("PHOTO_CAPTURE_GENERIC_ERROR", comment: "alert title, generic error preventing user from capturing a photo")
        }
    }
}

// MARK: -

@objc
class PhotoCaptureViewController: OWSViewController, InteractiveDismissDelegate {
    
    weak var delegate: PhotoCaptureViewControllerDelegate?
    weak var dataSource: PhotoCaptureViewControllerDataSource?
    var interactiveDismiss: PhotoCaptureInteractiveDismiss!
    
    @objc public lazy var photoCapture = PhotoCapture()
    
    lazy var tapToFocusView: AnimationView = {
        let view = AnimationView(name: "tap_to_focus")
        view.animationSpeed = 1
        view.backgroundBehavior = .forceFinish
        view.contentMode = .scaleAspectFit
        view.autoSetDimensions(to: CGSize(square: 150))
        view.setContentHuggingHigh()
        return view
    }()
    
    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        photoCapture.stopCapture().done {
            Logger.debug("stopCapture completed")
        }
    }
    
    // MARK: - Overrides
    
    override func loadView() {
        view = UIView()
        view.backgroundColor = Theme.darkThemeBackgroundColor
        view.preservesSuperviewLayoutMargins = true
        
        definesPresentationContext = true
        
        view.addSubview(previewView)
        if UIDevice.current.isIPad {
            previewView.autoPinEdgesToSuperviewEdges()
        }
        
        view.addSubview(topBar)
        topBar.mode = .cameraControls
        topBar.autoPinWidthToSuperview()
        topBarOffsetFromTop = topBar.autoPinEdge(toSuperviewEdge: .top)
        
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBarOffsetFromBottom = bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        
        view.addSubview(cameraCaptureControl)
        if UIDevice.current.isIPad {
            //            captureButton.autoVCenterInSuperview()
            //            captureButton.autoPinTrailing(toEdgeOf: view, offset: -captureButtonMargin)
            //            captureButton.movieLockView.autoSetDimension(.width, toSize: 120)
        } else {
            captureButtonVPositionConstraint = cameraCaptureControl.autoPinEdge(toSuperviewEdge: .bottom)
            cameraCaptureControl.autoPinLeadingToSuperviewMargin()
            cameraCaptureControl.autoPinTrailingToSuperviewMargin()
        }
        
        view.addSubview(doneButton)
        doneButton.isHidden = true
        doneButton.autoPinTrailingToSuperviewMargin()
        doneButton.centerYAnchor.constraint(equalTo: cameraCaptureControl.centerYAnchor).isActive = true
        doneButton.addTarget(self, action: #selector(didTapDoneButton), for: .touchUpInside)
        
        // If the view is already visible, setup the volume button listener
        // now that the capture UI is ready. Otherwise, we'll wait until
        // we're visible.
        if isVisible {
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }
        
        view.addSubview(tapToFocusView)
        tapToFocusView.isUserInteractionEnabled = false
        tapToFocusLeftConstraint = tapToFocusView.centerXAnchor.constraint(equalTo: view.leftAnchor)
        tapToFocusLeftConstraint.isActive = true
        tapToFocusTopConstraint = tapToFocusView.centerYAnchor.constraint(equalTo: view.topAnchor)
        tapToFocusTopConstraint.isActive = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard !UIDevice.current.isIPad else {
            return
        }
        
        // Clamp capture view to 16:9
        var previewFrame = view.bounds
        var cornerRadius: CGFloat = 0
        let targetAspectRatio: CGFloat = 16/9
        let currentAspectRatio: CGFloat = previewFrame.height / previewFrame.width
        
        if abs(currentAspectRatio - targetAspectRatio) > 0.001 {
            previewFrame.y = view.safeAreaInsets.top
            previewFrame.height = previewFrame.width * targetAspectRatio
            cornerRadius = 18
        }
        previewView.frame = previewFrame
        previewView.previewLayer.cornerRadius = cornerRadius
        
        // Bottom bar is pinned to the bottom of the screen, residing either directly above safe area
        // or (for taller screens) floating in the center of the black area between the bottom of the capture view and safe area.
        let bottomBarHeight = bottomBar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize,
                                                                withHorizontalFittingPriority: .fittingSizeLevel,
                                                                verticalFittingPriority: .fittingSizeLevel).height
        let blackBarHeight = max(0, view.bounds.maxY - previewFrame.maxY - view.safeAreaInsets.bottom)
        bottomBarOffsetFromBottom.constant = -(max(0, (blackBarHeight - bottomBarHeight) / 2) + view.safeAreaInsets.bottom)
        
        // Bottom edge of the capture button is 16pts above either bottom edge of the camera capture view
        // or top of the bottom bar, whatever is higher.
        let captureButtonBaseline = view.bounds.maxY - view.safeAreaInsets.bottom - max(blackBarHeight, bottomBarHeight)
        captureButtonVPositionConstraint.constant = -(view.bounds.height - captureButtonBaseline + 16)
    }
    
    private var topBarOffsetFromTop: NSLayoutConstraint!
    private var bottomBarOffsetFromBottom: NSLayoutConstraint!
    private var captureButtonVPositionConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPhotoCapture()
        
        updateFlashModeControl()
        
        view.addGestureRecognizer(pinchZoomGesture)
        view.addGestureRecognizer(tapToFocusGesture)
        view.addGestureRecognizer(doubleTapToSwitchCameraGesture)
        
        if let navController = self.navigationController {
            interactiveDismiss = PhotoCaptureInteractiveDismiss(viewController: navController)
            interactiveDismiss.interactiveDismissDelegate = self
            interactiveDismiss.addGestureRecognizer(to: view)
        }
        
        tapToFocusGesture.require(toFail: doubleTapToSwitchCameraGesture)
        
        mediaPickerThumbnailButton.configure()
    }
    
    private var isVisible = false
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        isVisible = true
        let previewOrientation: AVCaptureVideoOrientation
        if UIDevice.current.isIPad {
            previewOrientation = AVCaptureVideoOrientation(interfaceOrientation: CurrentAppContext().interfaceOrientation)  ?? .portrait
        } else {
            previewOrientation = .portrait
        }
        UIViewController.attemptRotationToDeviceOrientation()
        photoCapture.updateVideoPreviewConnection(toOrientation: previewOrientation)
        updateIconOrientations(isAnimated: false, captureOrientation: previewOrientation)
        resumePhotoCapture()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if hasCaptureStarted {
            BenchEventComplete(eventId: "Show-Camera")
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        isVisible = false
        VolumeButtons.shared?.removeObserver(photoCapture)
        pausePhotoCapture()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    override var prefersStatusBarHidden: Bool {
        guard !CurrentAppContext().hasActiveCall else {
            return false
        }
        return true
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if UIDevice.current.isIPad {
            // Since we support iPad multitasking, we cannot *disable* rotation of our views.
            // Rotating the preview layer is really distracting, so we fade out the preview layer
            // while the rotation occurs.
            self.previewView.alpha = 0
            coordinator.animate(alongsideTransition: { _ in }) { _ in
                UIView.animate(withDuration: 0.1) {
                    self.previewView.alpha = 1
                }
            }
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        
        // we pin to a constant rather than margin, because on notched devices the
        // safeAreaInsets/margins change as the device rotates *EVEN THOUGH* the interface
        // is locked to portrait.
        // Only grab this once -- otherwise when we swipe to dismiss this is updated and the top bar jumps to having zero offset
        if topBarOffsetFromTop.constant == 0 {
            let maxInsetDimension = max(view.safeAreaInsets.top, view.safeAreaInsets.left, view.safeAreaInsets.bottom)
            topBarOffsetFromTop.constant = max(maxInsetDimension, previewView.frame.minY)
        }
    }
    
    // MARK: - Interactive Dismiss
    
    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
    
    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        dismiss(animated: true)
    }
    
    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
    }
    
    // MARK: - Top Bar
    
    private var isRecordingVideo: Bool = false {
        didSet {
            if isRecordingVideo {
                topBar.mode = .videoRecording
                topBar.recordingTimerView.startCounting()
                
                cameraCaptureControl.setState(.recording, animationDuration: 0.4)
            } else {
                topBar.mode = .cameraControls
                topBar.recordingTimerView.stopCounting()
                
                cameraCaptureControl.setState(.initial, animationDuration: 0.2)
            }
            
            doneButton.isHidden = isRecordingVideo || doneButton.badgeNumber == 0
            bottomBar.isHidden = isRecordingVideo
        }
    }
    private var isInBatchMode: Bool = false
    
    private class TopBar: UIView {
        let recordingTimerView = RecordingTimerView(frame: .zero)
        private let navStack: UIStackView
        
        init(navbarItems: [UIView]) {
            self.navStack = UIStackView(arrangedSubviews: navbarItems)
            
            super.init(frame: .zero)
            
            layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 4)
            
            addSubview(navStack)
            navStack.spacing = 16
            navStack.autoPinEdgesToSuperviewMargins()
            
            addSubview(recordingTimerView)
            recordingTimerView.autoPinHeightToSuperview(withMargin: 8)
            recordingTimerView.autoHCenterInSuperview()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        enum Mode {
            case cameraControls, videoRecording
        }
        
        var mode: Mode = .cameraControls {
            didSet {
                switch mode {
                case .videoRecording:
                    navStack.isHidden = true
                    recordingTimerView.isHidden = false
                case .cameraControls:
                    navStack.isHidden = false
                    recordingTimerView.isHidden = true
                }
            }
        }
    }
    
    private lazy var topBar: TopBar = {
        return TopBar(navbarItems: [dismissControl,
                                    UIView.hStretchingSpacer(),
                                    batchModeControl,
                                    flashModeControl])
    }()
    
    // MARK: - Bottom Bar
    
    private class BottomBar: UIView {
        let buttonStack: UIStackView
        
        init(items: [UIView]) {
            self.buttonStack = UIStackView(arrangedSubviews: items)
            
            super.init(frame: .zero)
            
            layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 14)
            
            addSubview(buttonStack)
            buttonStack.spacing = 16
            buttonStack.autoPinEdgesToSuperviewMargins()
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private lazy var bottomBar: BottomBar = {
        return BottomBar(items: [mediaPickerThumbnailButton.embeddedInContainerView(layoutMargins: UIEdgeInsets(margin: 4)),
                                 UIView.hStretchingSpacer(),
                                 switchCameraControl])
    }()
    
    func updateBottomBarItems () {
        
    }
    
    // MARK: - Views
    
    private let cameraCaptureControl = CameraCaptureControl()
    
    private var previewView: CapturePreviewView {
        return photoCapture.previewView
    }
    
    private lazy var mediaPickerThumbnailButton: MediaPickerThumbnailButton = {
        let button = MediaPickerThumbnailButton(frame: .zero)
        button.addTarget(self, action: #selector(didTapPhotoLibrary), for: .touchUpInside)
        return button
    }()
    
    private lazy var dismissControl: PhotoControl = {
        return PhotoControl(imageName: "media-composer-close") { [weak self] in
            self?.didTapClose()
        }
    }()
    
    private lazy var switchCameraControl: PhotoControl = {
        return PhotoControl(imageName: "media-composer-switch-camera-24") { [weak self] in
            self?.didTapSwitchCamera()
        }
    }()
    
    private lazy var flashModeControl: PhotoControl = {
        return PhotoControl(imageName: "media-composer-flash-auto-24") { [weak self] in
            self?.didTapFlashMode()
        }
    }()
    
    private lazy var batchModeControl: PhotoControl = {
        let control = PhotoControl(imageName: "media-composer-create-album-outline-24") { [weak self] in
            self?.didTapBatchMode()
        }
        return control
    }()
    
    private lazy var doneButton: MediaDoneButton = {
        let button = MediaDoneButton(type: .custom)
        button.badgeNumber = 0
        return button
    }()
    
    lazy var pinchZoomGesture: UIPinchGestureRecognizer = {
        return UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:)))
    }()
    
    lazy var tapToFocusGesture: UITapGestureRecognizer = {
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
        delegate?.photoCaptureViewControllerDidCancel(self)
    }
    
    @objc
    func didTapSwitchCamera() {
        switchCamera()
    }
    
    @objc
    func didDoubleTapToSwitchCamera(tapGesture: UITapGestureRecognizer) {
        guard !isRecordingVideo else {
            // - Orientation gets out of sync when switching cameras mid movie.
            // - Audio gets out of sync when switching cameras mid movie
            // https://stackoverflow.com/questions/13951182/audio-video-out-of-sync-after-switch-camera
            return
        }
        switchCamera()
    }
    
    private func switchCamera() {
        UIView.animate(withDuration: 0.2) {
            let epsilonToForceCounterClockwiseRotation: CGFloat = 0.00001
            self.switchCameraControl.transform = self.switchCameraControl.transform.rotate(.pi + epsilonToForceCounterClockwiseRotation)
        }
        photoCapture.switchCamera().catch { error in
            self.showFailureUI(error: error)
        }
    }
    
    @objc
    func didTapFlashMode() {
        firstly {
            photoCapture.switchFlashMode()
        }.done {
            self.updateFlashModeControl()
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }
    
    @objc
    func didTapBatchMode() {
        guard let delegate = delegate else {
            return
        }
        isInBatchMode = delegate.photoCaptureViewController(self, didRequestSwitchBatchMode: !isInBatchMode)
        let imageName = isInBatchMode ? "media-composer-create-album-solid-24" : "media-composer-create-album-outline-24"
        batchModeControl.setImage(imageName: imageName)
    }
    
    @objc
    func didTapPhotoLibrary() {
        delegate?.photoCaptureViewControllerDidRequestPresentPhotoLibrary(self)
    }
    
    @objc
    func didTapDoneButton() {
        delegate?.photoCaptureViewControllerDidFinish(self)
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

//        // If the user taps near the capture button, it's more likely a mis-tap than intentional.
//        // Skip the focus animation in that case, since it looks bad.
//        let captureButtonOrigin = captureButton.superview!.convert(captureButton.frame.origin, to: view)
//        if UIDevice.current.isIPad {
//            guard viewLocation.x < captureButtonOrigin.x else {
//                Logger.verbose("Skipping animation for right edge on iPad")
//
//                // Finish any outstanding focus animation, otherwise it will remain in an
//                // uncompleted state.
//                if let lastUserFocusTapPoint = lastUserFocusTapPoint {
//                    completeFocusAnimation(forFocusPoint: lastUserFocusTapPoint)
//                }
//                return
//            }
//        } else {
//            guard viewLocation.y < captureButtonOrigin.y else {
//                Logger.verbose("Skipping animation for bottom row on iPhone")
//
//                // Finish any outstanding focus animation, otherwise it will remain in an
//                // uncompleted state.
//                if let lastUserFocusTapPoint = lastUserFocusTapPoint {
//                    completeFocusAnimation(forFocusPoint: lastUserFocusTapPoint)
//                }
//                return
//            }
//        }

        lastUserFocusTapPoint = devicePoint
        do {
            let convertedPoint = tapToFocusView.superview!.convert(viewLocation, from: view)
            positionTapToFocusView(center: convertedPoint)
            tapToFocusView.superview?.layoutIfNeeded()
            startFocusAnimation()
        }
    }
    
    // MARK: - Focus Animations
    
    var tapToFocusLeftConstraint: NSLayoutConstraint!
    var tapToFocusTopConstraint: NSLayoutConstraint!
    func positionTapToFocusView(center: CGPoint) {
        tapToFocusLeftConstraint.constant = center.x
        tapToFocusTopConstraint.constant = center.y
    }
    
    func startFocusAnimation() {
        tapToFocusView.stop()
        tapToFocusView.play(fromProgress: 0.0, toProgress: 0.9)
    }
    
    var lastUserFocusTapPoint: CGPoint?
    func completeFocusAnimation(forFocusPoint focusPoint: CGPoint) {
        guard let lastUserFocusTapPoint = lastUserFocusTapPoint else {
            return
        }
        
        guard lastUserFocusTapPoint.within(0.005, of: focusPoint) else {
            Logger.verbose("focus completed for obsolete focus point. User has refocused.")
            return
        }
        
        tapToFocusView.play(toProgress: 1.0)
    }
    
    // MARK: - Orientation
    
    private func updateIconOrientations(isAnimated: Bool, captureOrientation: AVCaptureVideoOrientation) {
        guard !UIDevice.current.isIPad else {
            return
        }
        
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
        @unknown default:
            owsFailDebug("unexpected captureOrientation: \(captureOrientation.rawValue)")
            transformFromOrientation = .identity
        }
        
        // Don't "unrotate" the switch camera icon if the front facing camera had been selected.
        let tranformFromCameraType: CGAffineTransform = photoCapture.desiredPosition == .front ? CGAffineTransform(rotationAngle: -.pi) : .identity
        
        let updateOrientation = {
            self.flashModeControl.transform = transformFromOrientation
            self.switchCameraControl.transform = transformFromOrientation.concatenating(tranformFromCameraType)
        }
        
        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }
    
    // MARK: - Photo Capture
    
    var hasCaptureStarted = false
    
    private func captureReady() {
        self.hasCaptureStarted = true
        BenchEventComplete(eventId: "Show-Camera")
    }
    
    private func setupPhotoCapture() {
        photoCapture.delegate = self
        cameraCaptureControl.delegate = photoCapture
        
        // If the session is already running, we're good to go.
        guard !photoCapture.session.isRunning else {
            return self.captureReady()
        }
        
        firstly {
            photoCapture.prepareVideoCapture()
        }.catch { [weak self] error in
            guard let self = self else { return }
            self.showFailureUI(error: error)
        }
    }
    
    private func pausePhotoCapture() {
        guard photoCapture.session.isRunning else { return }
        firstly {
            photoCapture.stopCapture()
        }.done { [weak self] in
            self?.hasCaptureStarted = false
        }.catch { [weak self] error in
            self?.showFailureUI(error: error)
        }
    }
    
    private func resumePhotoCapture() {
        guard !photoCapture.session.isRunning else { return }
        firstly {
            photoCapture.resumeCapture()
        }.done { [weak self] in
            self?.captureReady()
        }.catch { [weak self] error in
            self?.showFailureUI(error: error)
        }
    }
    
    private func showFailureUI(error: Error) {
        Logger.error("error: \(error)")
        
        OWSActionSheets.showActionSheet(title: nil,
                                        message: error.userErrorDescription,
                                        buttonTitle: CommonStrings.dismissButton,
                                        buttonAction: { [weak self] _ in self?.dismiss(animated: true) })
    }
    
    private func updateFlashModeControl() {
        let imageName: String
        switch photoCapture.flashMode {
        case .auto:
            imageName = "media-composer-flash-auto-24"
        case .on:
            imageName = "media-composer-flash-filled-24"
        case .off:
            imageName = "media-composer-flash-outline-24"
        @unknown default:
            owsFailDebug("unexpected photoCapture.flashMode: \(photoCapture.flashMode.rawValue)")
            
            imageName = "media-composer-flash-auto-24"
        }
        
        self.flashModeControl.setImage(imageName: imageName)
    }
}

extension PhotoCaptureViewController: PhotoCaptureDelegate {
    
    // MARK: - Photo
    
    func photoCaptureDidStart(_ photoCapture: PhotoCapture) {
        let captureFeedbackView = UIView()
        captureFeedbackView.backgroundColor = .black
        view.insertSubview(captureFeedbackView, aboveSubview: previewView)
        captureFeedbackView.autoPinEdgesToSuperviewEdges()
        
        // Ensure the capture feedback is laid out before we remove it,
        // depending on where we're coming from a layout pass might not
        // trigger in 0.05 seconds otherwise.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            captureFeedbackView.removeFromSuperview()
        }
    }
    
    func photoCapture(_ photoCapture: PhotoCapture, didFinishProcessing attachment: SignalAttachment) {
        dataSource?.addMedia(attachment: attachment)
        
        if isInBatchMode, let badgeNumber = dataSource?.numberOfMediaItems {
            doneButton.badgeNumber = badgeNumber
            doneButton.isHidden = false
        } else {
            doneButton.isHidden = true
            
            delegate?.photoCaptureViewControllerDidFinish(self)
        }
    }
    
    func photoCapture(_ photoCapture: PhotoCapture, didFailProcessing error: Error) {
        isRecordingVideo = false
        
        if case PhotoCaptureError.invalidVideo = error {
            // Don't show an error if the user aborts recording before video
            // recording has begun.
            return
        }
        showFailureUI(error: error)
    }
    
    func photoCaptureCanCaptureMoreItems(_ photoCapture: PhotoCapture) -> Bool {
        return delegate?.photoCaptureViewControllerCanCaptureMoreItems(self) ?? false
    }
    
    func photoCaptureDidTryToCaptureTooMany(_ photoCapture: PhotoCapture) {
        delegate?.photoCaptureViewControllerDidTryToCaptureTooMany(self)
    }
    
    // MARK: - Video
    
    func photoCaptureDidBeginRecording(_ photoCapture: PhotoCapture) {
        isRecordingVideo = true
    }
    
    func photoCaptureDidFinishRecording(_ photoCapture: PhotoCapture) {
        isRecordingVideo = false
    }
    
    func photoCaptureDidCancelRecording(_ photoCapture: PhotoCapture) {
        isRecordingVideo = false
    }
    
    // MARK: -
    
    var zoomScaleReferenceHeight: CGFloat? {
        return view.bounds.height
    }
    
    func beginCaptureButtonAnimation(_ duration: TimeInterval) {
        cameraCaptureControl.setState(.recording, animationDuration: duration)
    }
    
    func endCaptureButtonAnimation(_ duration: TimeInterval) {
        cameraCaptureControl.setState(.initial, animationDuration: duration)
    }
    
    func photoCapture(_ photoCapture: PhotoCapture, didChangeOrientation orientation: AVCaptureVideoOrientation) {
        updateIconOrientations(isAnimated: true, captureOrientation: orientation)
        if UIDevice.current.isIPad {
            photoCapture.updateVideoPreviewConnection(toOrientation: orientation)
        }
    }
    
    func photoCapture(_ photoCapture: PhotoCapture, didCompleteFocusing focusPoint: CGPoint) {
        completeFocusAnimation(forFocusPoint: focusPoint)
    }
}

// MARK: - Views

private class PhotoControl: UIView {
    let button: OWSButton
    
    private static let visibleButtonSize: CGFloat = 36  // both height and width
    private static let layoutMargin: CGFloat = 4        // both horizontal and vertical
    
    init(imageName: String, block: @escaping () -> Void) {
        self.button = OWSButton(imageName: imageName, tintColor: .ows_white, block: block)
        
        super.init(frame: CGRect(origin: .zero, size: CGSize(square: Self.visibleButtonSize + 2*Self.layoutMargin)))
        
        layoutMargins = UIEdgeInsets(margin: Self.layoutMargin)
        
        let blurView = CircleBlurView(effect: UIBlurEffect(style: .dark))
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewMargins()
        
        addSubview(button)
        button.autoPinEdgesToSuperviewMargins()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: Self.visibleButtonSize + layoutMargins.leading + layoutMargins.trailing,
                      height: Self.visibleButtonSize + layoutMargins.top + layoutMargins.bottom)
    }
    
    func setImage(imageName: String) {
        button.setImage(imageName: imageName)
    }
}

private class MediaPickerThumbnailButton: UIButton {
    
    private static let visibleSize = CGSize(square: 36)
    
    func configure() {
        layer.cornerRadius = 10
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.ows_whiteAlpha80.cgColor
        clipsToBounds = true
        
        let placeholderView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        insertSubview(placeholderView, at: 0)
        placeholderView.autoPinEdgesToSuperviewEdges()
        
        // Async Fetch last image
        DispatchQueue.global(qos: .userInteractive).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1
            
            let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
            if fetchResult.count > 0, let asset = fetchResult.firstObject {
                let targetImageSize = MediaPickerThumbnailButton.visibleSize
                PHImageManager.default().requestImage(for: asset, targetSize: targetImageSize, contentMode: .aspectFill, options: nil) { (image, _) in
                    DispatchQueue.main.async {
                        self.setImage(image, for: .normal)
                        placeholderView.alpha = 0
                    }
                }
            }
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return Self.visibleSize
    }
}

class CapturePreviewView: UIView {
    
    let previewLayer: AVCaptureVideoPreviewLayer
    
    override var bounds: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }
    
    override var frame: CGRect {
        didSet {
            previewLayer.frame = bounds
        }
    }
    
    override var contentMode: UIView.ContentMode {
        set {
            switch newValue {
            case .scaleAspectFill:
                previewLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:
                previewLayer.videoGravity = .resizeAspect
            case .scaleToFill:
                previewLayer.videoGravity = .resize
            default:
                owsFailDebug("Unexpected contentMode")
            }
        }
        get {
            switch previewLayer.videoGravity {
            case .resizeAspectFill:
                return .scaleAspectFill
            case .resizeAspect:
                return .scaleAspectFit
            case .resize:
                return .scaleToFill
            default:
                owsFailDebug("Unexpected contentMode")
                return .scaleToFill
            }
        }
    }
    
    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        if Platform.isSimulator {
            // helpful for debugging layout on simulator which has no real capture device
            previewLayer.backgroundColor = UIColor.green.withAlphaComponent(0.4).cgColor
        }
        super.init(frame: .zero)
        self.contentMode = .scaleAspectFill
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class RecordingTimerView: PillView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)
        
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
        
        let stackView = UIStackView(arrangedSubviews: [icon, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 5
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        
        updateView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Subviews
    
    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_monospacedDigitFont(withSize: 20)
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
    
    var recordingStartTime: TimeInterval?
    
    func startCounting() {
        recordingStartTime = CACurrentMediaTime()
        timer = Timer.weakScheduledTimer(withTimeInterval: 0.1, target: self, selector: #selector(updateView), userInfo: nil, repeats: true)
        UIView.animate(withDuration: 0.5,
                       delay: 0,
                       options: [.autoreverse, .repeat],
                       animations: { self.icon.alpha = 1 })
    }
    
    func stopCounting() {
        timer?.invalidate()
        timer = nil
        icon.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.4) {
            self.icon.alpha = 0
        }
        label.text = nil
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
        let durationDate = Date(timeIntervalSinceReferenceDate: recordingDuration)
        label.text = timeFormatter.string(from: durationDate)
    }
}

private extension UIView {
    
    func embeddedInContainerView(layoutMargins: UIEdgeInsets = .zero) -> UIView {
        var containerViewFrame = bounds
        containerViewFrame.width += layoutMargins.leading + layoutMargins.trailing
        containerViewFrame.height += layoutMargins.top + layoutMargins.bottom
        let containerView = UIView(frame: containerViewFrame)
        containerView.layoutMargins = layoutMargins
        containerView.addSubview(self)
        autoPinEdgesToSuperviewMargins()
        return containerView
    }
}
