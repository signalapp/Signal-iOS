//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import AVFoundation
import Foundation
import Lottie
import Photos
import UIKit
import SignalMessaging
import SignalUI

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewControllerDidFinish(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerViewWillAppear(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
    func photoCaptureViewControllerDidRequestPresentPhotoLibrary(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController,
                                    didRequestSwitchCaptureModeTo captureMode: PhotoCaptureViewController.CaptureMode,
                                    completion: @escaping (Bool) -> Void)
    func photoCaptureViewControllerCanShowTextEditor(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
}

protocol PhotoCaptureViewControllerDataSource: AnyObject {
    var numberOfMediaItems: Int { get }
    func addMedia(attachment: SignalAttachment)
}

class PhotoCaptureViewController: OWSViewController {

    weak var delegate: PhotoCaptureViewControllerDelegate?
    weak var dataSource: PhotoCaptureViewControllerDataSource?
    private var interactiveDismiss: PhotoCaptureInteractiveDismiss?

    public lazy var photoCapture = PhotoCapture()
    private var hasCaptureStarted = false

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        photoCapture.stopCapture().done {
            Logger.debug("stopCapture completed")
        }
    }

    // MARK: - Overrides

    override func viewDidLoad() {
        super.viewDidLoad()

        definesPresentationContext = true

        view.backgroundColor = Theme.darkThemeBackgroundColor
        view.preservesSuperviewLayoutMargins = true

        initializeUI()

        setupPhotoCapture()
        // If the view is already visible, setup the volume button listener
        // now that the capture UI is ready. Otherwise, we'll wait until
        // we're visible.
        if isVisible {
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }

        updateFlashModeControl(animated: false)

        if let navigationController = navigationController {
            let interactiveDismiss = PhotoCaptureInteractiveDismiss(viewController: navigationController)
            interactiveDismiss.interactiveDismissDelegate = self
            interactiveDismiss.addGestureRecognizer(to: view)
            self.interactiveDismiss = interactiveDismiss
        }

        bottomBar.photoLibraryButton.configure()
        if let sideBar = sideBar {
            sideBar.photoLibraryButton.configure()
        }
    }

    private var isVisible = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        delegate?.photoCaptureViewControllerViewWillAppear(self)

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

        if let dataSource = dataSource, dataSource.numberOfMediaItems > 0 {
            captureMode = .multi
        }
        updateDoneButtonAppearance()
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
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !CurrentAppContext().hasActiveCall
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard UIDevice.current.isIPad else { return }

        // Since we support iPad multitasking, we cannot *disable* rotation of our views.
        // Rotating the preview layer is really distracting, so we fade out the preview layer
        // while the rotation occurs.
        self.previewView.alpha = 0
        coordinator.animate(alongsideTransition: { _ in },
                            completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.previewView.alpha = 1
            }
        })
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        // Safe area insets will change during interactive dismiss - ignore those changes.
        guard !(interactiveDismiss?.interactionInProgress ?? false) else { return }

        if let contentLayoutGuideTop = contentLayoutGuideTop {
            contentLayoutGuideTop.constant = view.safeAreaInsets.top

            // Rounded corners if preview view isn't full-screen.
            previewView.previewLayer.cornerRadius = view.safeAreaInsets.top > 0 ? 18 : 0
        }

        if let bottomBarControlsLayoutGuideBottom = bottomBarControlsLayoutGuideBottom {
            bottomBarControlsLayoutGuideBottom.constant = -view.safeAreaInsets.bottom
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        isIPadUIInRegularMode = traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular
    }

    // MARK: - Layout Code

    private var isIPadUIInRegularMode = false {
        didSet {
            guard oldValue != isIPadUIInRegularMode else { return }
            updateIPadInterfaceLayout()
        }
    }

    private let contentLayoutGuide = UILayoutGuide()
    private var contentLayoutGuideTop: NSLayoutConstraint? // controls vertical position of `contentLayoutGuide` on iPhones.

    private var isRecordingVideo: Bool = false {
        didSet { updateUIOnVideoRecordingStateChange() }
    }

    enum CaptureMode {
        case single
        case multi
    }
    private(set) var captureMode: CaptureMode = .single {
        didSet {
            topBar.batchModeButton.setCaptureMode(captureMode, animated: true)
            if let sideBar = sideBar {
                sideBar.batchModeButton.setCaptureMode(captureMode, animated: true)
            }
        }
    }

    func switchToMultiCaptureMode() {
        self.captureMode = .multi
    }

    private let topBar = CameraTopBar(frame: .zero)

    private lazy var bottomBar = CameraBottomBar(isContentTypeSelectionControlAvailable: delegate?.photoCaptureViewControllerCanShowTextEditor(self) ?? false)
    private var bottomBarControlsLayoutGuideBottom: NSLayoutConstraint?

    private var sideBar: CameraSideBar? // Optional because most devices are iPhones and will never need this.

    private var frontCameraZoomControl: CameraZoomSelectionControl?
    private var rearCameraZoomControl: CameraZoomSelectionControl?
    private var cameraZoomControlIPhoneConstraints: [NSLayoutConstraint]?
    private var cameraZoomControlIPadConstraints: [NSLayoutConstraint]?

    private lazy var tapToFocusView: AnimationView = {
        let view = AnimationView(name: "tap_to_focus")
        view.animationSpeed = 1
        view.backgroundBehavior = .forceFinish
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.autoSetDimensions(to: CGSize(square: 150))
        view.setContentHuggingHigh()
        return view
    }()
    private lazy var tapToFocusCenterXConstraint = tapToFocusView.centerXAnchor.constraint(equalTo: previewView.leftAnchor)
    private lazy var tapToFocusCenterYConstraint = tapToFocusView.centerYAnchor.constraint(equalTo: previewView.topAnchor)
    private var lastUserFocusTapPoint: CGPoint?

    private var previewView: CapturePreviewView {
        photoCapture.previewView
    }

    private lazy var doneButton: MediaDoneButton = {
        let button = MediaDoneButton(type: .custom)
        button.badgeNumber = 0
        button.userInterfaceStyleOverride = .dark
        return button
    }()
    private lazy var doneButtonIPhoneConstraints = [ doneButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                                                     doneButton.centerYAnchor.constraint(equalTo: bottomBar.shutterButtonLayoutGuide.centerYAnchor) ]
    private var doneButtonIPadConstraints: [NSLayoutConstraint]?

    private func initializeUI() {
        // `contentLayoutGuide` defines area occupied by the content:
        // either camera viewfinder or text story composing area.
        view.addLayoutGuide(contentLayoutGuide)
        // Always full-width.
        view.addConstraints([ contentLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                              contentLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor) ])
        if UIDevice.current.isIPad {
            // Full-height on iPads.
            view.addConstraints([ contentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
                                  contentLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor) ])
        } else {
            // 9:16 aspect ratio on iPhones.
            // Note that there's no constraint on the bottom edge of the `contentLayoutGuide`.
            // This works because all iPhones have screens 9:16 or taller.
            view.addConstraint(contentLayoutGuide.heightAnchor.constraint(equalTo: contentLayoutGuide.widthAnchor, multiplier: 16/9))
            // Constrain to the top of the view now and update offset with the height of top safe area later.
            // Can't constrain to the safe area layout guide because safe area insets changes during interactive dismiss.
            let constraint = contentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor)
            view.addConstraint(constraint)
            contentLayoutGuideTop = constraint
        }

        // Step 1. Initialize all UI elements for iPhone layout (which can also be used on an iPad).

        // Camera Viewfinder - simply occupies the entire frame of `contentLayoutGuide`.
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        view.addConstraints([ previewView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                              previewView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
                              previewView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                              previewView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor) ])
        configureCameraGestures()

        // Top Bar
        view.addSubview(topBar)
        topBar.closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        topBar.batchModeButton.addTarget(self, action: #selector(didTapBatchMode), for: .touchUpInside)
        topBar.flashModeButton.addTarget(self, action: #selector(didTapFlashMode), for: .touchUpInside)
        topBar.autoPinWidthToSuperview()
        if UIDevice.current.isIPad {
            topBar.autoPinEdge(toSuperviewSafeArea: .top)
        } else {
            topBar.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor).isActive = true
        }

        // Bottom Bar (contains shutter button)
        view.addSubview(bottomBar)
        bottomBar.isCompactHeightLayout = !UIDevice.current.hasIPhoneXNotch
        bottomBar.switchCameraButton.addTarget(self, action: #selector(didTapSwitchCamera), for: .touchUpInside)
        bottomBar.photoLibraryButton.addTarget(self, action: #selector(didTapPhotoLibrary), for: .touchUpInside)
        if bottomBar.isContentTypeSelectionControlAvailable {
            bottomBar.contentTypeSelectionControl.selectedSegmentIndex = 0
            bottomBar.contentTypeSelectionControl.addTarget(self, action: #selector(contentTypeChanged), for: .valueChanged)
        }
        bottomBar.autoPinWidthToSuperview()
        if bottomBar.isCompactHeightLayout {
            // On devices with home button bar is simply pinned to the bottom of the screen
            // with a fixed margin that defines space under the shutter button.
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        } else {
            // On `notch` devices:
            //  i. Shutter button is placed 16 pts above the bottom edge of the preview view.
            bottomBar.shutterButtonLayoutGuide.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -16).isActive = true

            //  ii. Other buttons are centered vertically in the black box between bottom of the preview view and top of bottom safe area.
            bottomBar.controlButtonsLayoutGuide.topAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor).isActive = true
            // Constrain to the bottom of the view now and update offset with the height of bottom safe area later.
            // Can't constrain to the safe area layout guide because safe area insets changes during interactive dismiss.
            let constraint = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            view.addConstraint(constraint)
            bottomBarControlsLayoutGuideBottom = constraint
        }

        // Camera Zoom Controls
        cameraZoomControlIPhoneConstraints = []

        let availableFrontCameras = photoCapture.cameraZoomFactorMap(forPosition: .front)
        if availableFrontCameras.count > 0 {
            let cameras = availableFrontCameras.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1) }

            let cameraZoomControl = CameraZoomSelectionControl(availableCameras: cameras)
            cameraZoomControl.delegate = self
            view.addSubview(cameraZoomControl)
            self.frontCameraZoomControl = cameraZoomControl

            let cameraZoomControlConstraints =
            [ cameraZoomControl.centerXAnchor.constraint(equalTo: bottomBar.shutterButtonLayoutGuide.centerXAnchor),
              cameraZoomControl.bottomAnchor.constraint(equalTo: bottomBar.shutterButtonLayoutGuide.topAnchor, constant: -32) ]
            view.addConstraints(cameraZoomControlConstraints)
            cameraZoomControlIPhoneConstraints?.append(contentsOf: cameraZoomControlConstraints)
        }

        let availableRearCameras = photoCapture.cameraZoomFactorMap(forPosition: .back)
        if availableRearCameras.count > 0 {
            let cameras = availableRearCameras.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1) }

            let cameraZoomControl = CameraZoomSelectionControl(availableCameras: cameras)
            cameraZoomControl.delegate = self
            view.addSubview(cameraZoomControl)
            self.rearCameraZoomControl = cameraZoomControl

            let cameraZoomControlConstraints =
            [ cameraZoomControl.centerXAnchor.constraint(equalTo: bottomBar.shutterButtonLayoutGuide.centerXAnchor),
              cameraZoomControl.bottomAnchor.constraint(equalTo: bottomBar.shutterButtonLayoutGuide.topAnchor, constant: -32) ]
            view.addConstraints(cameraZoomControlConstraints)
            cameraZoomControlIPhoneConstraints?.append(contentsOf: cameraZoomControlConstraints)
        }
        updateUIOnCameraPositionChange()

        // Done Button
        view.addSubview(doneButton)
        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints(doneButtonIPhoneConstraints)
        doneButton.addTarget(self, action: #selector(didTapDoneButton), for: .touchUpInside)

        // Focusing frame
        previewView.addSubview(tapToFocusView)
        previewView.addConstraints([ tapToFocusCenterXConstraint, tapToFocusCenterYConstraint ])

        // Step 2. Check if we're running on an iPad and update UI accordingly.
        // Note that `traitCollectionDidChange` won't be called during initial view loading process.
        isIPadUIInRegularMode = traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular

        // This background footer doesn't let view controller underneath current VC
        // to be visible at the bottom of the screen during interactive dismiss.
        if UIDevice.current.hasIPhoneXNotch {
            let blackFooter = UIView()
            blackFooter.backgroundColor = view.backgroundColor
            view.insertSubview(blackFooter, at: 0)
            blackFooter.autoPinWidthToSuperview()
            blackFooter.autoPinEdge(toSuperviewEdge: .bottom)
            blackFooter.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5).isActive = true
        }
    }

    private func initializeIPadSpecificUIIfNecessary() {
        guard sideBar == nil else { return }

        let sideBar = CameraSideBar(frame: .zero)
        sideBar.cameraCaptureControl.delegate = photoCapture
        sideBar.batchModeButton.addTarget(self, action: #selector(didTapBatchMode), for: .touchUpInside)
        sideBar.flashModeButton.addTarget(self, action: #selector(didTapFlashMode), for: .touchUpInside)
        sideBar.switchCameraButton.addTarget(self, action: #selector(didTapSwitchCamera), for: .touchUpInside)
        sideBar.photoLibraryButton.addTarget(self, action: #selector(didTapPhotoLibrary), for: .touchUpInside)
        view.addSubview(sideBar)
        sideBar.autoPinTrailingToSuperviewMargin(withInset: 12)
        sideBar.cameraCaptureControl.shutterButtonLayoutGuide.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        self.sideBar = sideBar

        sideBar.batchModeButton.setImage(topBar.batchModeButton.image(for: .normal), for: .normal)
        updateFlashModeControl(animated: false)

        doneButtonIPadConstraints = [ doneButton.centerXAnchor.constraint(equalTo: sideBar.centerXAnchor),
                                      doneButton.bottomAnchor.constraint(equalTo: sideBar.topAnchor, constant: -8)]

        cameraZoomControlIPadConstraints = []
        if let cameraZoomControl = frontCameraZoomControl {
            let constraints = [ cameraZoomControl.centerYAnchor.constraint(equalTo: sideBar.cameraCaptureControl.shutterButtonLayoutGuide.centerYAnchor),
                                cameraZoomControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32)]
            cameraZoomControlIPadConstraints?.append(contentsOf: constraints)
        }
        if let cameraZoomControl = rearCameraZoomControl {
            let constraints = [ cameraZoomControl.centerYAnchor.constraint(equalTo: sideBar.cameraCaptureControl.shutterButtonLayoutGuide.centerYAnchor),
                                cameraZoomControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32)]
            cameraZoomControlIPadConstraints?.append(contentsOf: constraints)
        }
    }

    private func updateIPadInterfaceLayout() {
        owsAssertDebug(UIDevice.current.isIPad)

        if isIPadUIInRegularMode {
            initializeIPadSpecificUIIfNecessary()

            view.removeConstraints(doneButtonIPhoneConstraints)
            if let doneButtonIPadConstraints = doneButtonIPadConstraints {
                view.addConstraints(doneButtonIPadConstraints)
            }
        } else {
            if let doneButtonIPadConstraints = doneButtonIPadConstraints {
                view.removeConstraints(doneButtonIPadConstraints)
            }
            view.addConstraints(doneButtonIPhoneConstraints)
        }

        if let cameraZoomControl = frontCameraZoomControl {
            cameraZoomControl.axis = isIPadUIInRegularMode ? .vertical : .horizontal
        }
        if let cameraZoomControl = rearCameraZoomControl {
            cameraZoomControl.axis = isIPadUIInRegularMode ? .vertical : .horizontal
        }
        if let iPhoneConstraints = cameraZoomControlIPhoneConstraints,
           let iPadConstraints = cameraZoomControlIPadConstraints {
            if isIPadUIInRegularMode {
                view.removeConstraints(iPhoneConstraints)
                view.addConstraints(iPadConstraints)
            } else {
                view.removeConstraints(iPadConstraints)
                view.addConstraints(iPhoneConstraints)
            }
        }

        if !isRecordingVideo {
            topBar.setMode(isIPadUIInRegularMode ? .closeButton : .cameraControls, animated: true)
        }
        bottomBar.isHidden = isIPadUIInRegularMode
        sideBar?.isHidden = !isIPadUIInRegularMode
    }

    func updateDoneButtonAppearance() {
        if captureMode == .multi, let badgeNumber = dataSource?.numberOfMediaItems, badgeNumber > 0 {
            doneButton.badgeNumber = badgeNumber
            doneButton.isHidden = false
        } else {
            doneButton.isHidden = true
        }
        if bottomBar.isCompactHeightLayout {
            bottomBar.switchCameraButton.isHidden = !doneButton.isHidden
        }
    }

    private func updateUIOnCameraPositionChange(animated: Bool = false) {
        let isFrontCamera = photoCapture.desiredPosition == .front
        frontCameraZoomControl?.setIsHidden(!isFrontCamera, animated: animated)
        rearCameraZoomControl?.setIsHidden(isFrontCamera, animated: animated)
        bottomBar.switchCameraButton.isFrontCameraActive = isFrontCamera
        if let sideBar = sideBar {
            sideBar.switchCameraButton.isFrontCameraActive = isFrontCamera
        }
    }

    private func updateUIOnVideoRecordingStateChange() {
        if isRecordingVideo {
            topBar.setMode(.videoRecording, animated: true)
            topBar.recordingTimerView.startCounting()

            let captureControlState: CameraCaptureControl.State = UIAccessibility.isVoiceOverRunning ? .recordingUsingVoiceOver : .recording
            bottomBar.captureControl.setState(captureControlState, animationDuration: 0.4)
            if let sideBar = sideBar {
                sideBar.cameraCaptureControl.setState(captureControlState, animationDuration: 0.4)
            }
        } else {
            topBar.setMode(isIPadUIInRegularMode ? .closeButton : .cameraControls, animated: true)
            topBar.recordingTimerView.stopCounting()

            bottomBar.captureControl.setState(.initial, animationDuration: 0.2)
            if let sideBar = sideBar {
                sideBar.cameraCaptureControl.setState(.initial, animationDuration: 0.2)
            }
        }

        bottomBar.isRecordingVideo = isRecordingVideo
        if let sideBar = sideBar {
            sideBar.isRecordingVideo = isRecordingVideo
        }

        doneButton.isHidden = isRecordingVideo || doneButton.badgeNumber == 0
    }

    private func updateIconOrientations(isAnimated: Bool, captureOrientation: AVCaptureVideoOrientation) {
        guard !UIDevice.current.isIPad else { return }

        Logger.verbose("captureOrientation: \(captureOrientation)")

        let transformFromOrientation: CGAffineTransform
        switch captureOrientation {
        case .portrait:
            transformFromOrientation = .identity
        case .portraitUpsideDown:
            transformFromOrientation = CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight:
            transformFromOrientation = CGAffineTransform(rotationAngle: .halfPi)
        case .landscapeLeft:
            transformFromOrientation = CGAffineTransform(rotationAngle: -1 * .halfPi)
        @unknown default:
            owsFailDebug("unexpected captureOrientation: \(captureOrientation.rawValue)")
            transformFromOrientation = .identity
        }

        // Don't "unrotate" the switch camera icon if the front facing camera had been selected.
        let tranformFromCameraType: CGAffineTransform = photoCapture.desiredPosition == .front ? CGAffineTransform(rotationAngle: -.pi) : .identity

        var buttonsToUpdate: [UIView] = [ topBar.batchModeButton, topBar.flashModeButton, bottomBar.photoLibraryButton ]
        if let cameraZoomControl = frontCameraZoomControl {
            buttonsToUpdate.append(contentsOf: cameraZoomControl.cameraZoomLevelIndicators)
        }
        if let cameraZoomControl = rearCameraZoomControl {
            buttonsToUpdate.append(contentsOf: cameraZoomControl.cameraZoomLevelIndicators)
        }
        let updateOrientation = {
            buttonsToUpdate.forEach { $0.transform = transformFromOrientation }
            self.bottomBar.switchCameraButton.transform = transformFromOrientation.concatenating(tranformFromCameraType)
        }

        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }
}

// MARK: - Button Actions

extension PhotoCaptureViewController {

    @objc
    private func didTapClose() {
        delegate?.photoCaptureViewControllerDidCancel(self)
    }

    @objc
    private func didTapSwitchCamera() {
        switchCameraPosition()
    }

    private func switchCameraPosition() {
        if let switchCameraButton = isIPadUIInRegularMode ? sideBar?.switchCameraButton : bottomBar.switchCameraButton {
            switchCameraButton.performSwitchAnimation()
        }
        photoCapture.switchCameraPosition().done { [weak self] in
            self?.updateUIOnCameraPositionChange(animated: true)
        }.catch { error in
            self.showFailureUI(error: error)
        }
    }

    @objc
    private func didTapFlashMode() {
        firstly {
            photoCapture.switchFlashMode()
        }.done {
            self.updateFlashModeControl(animated: true)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    @objc
    private func didTapBatchMode() {
        guard let delegate = delegate else {
            return
        }
        let targetMode: CaptureMode = {
            switch captureMode {
            case .single: return .multi
            case .multi: return .single
            }
        }()
        delegate.photoCaptureViewController(self, didRequestSwitchCaptureModeTo: targetMode) { approved in
            if approved {
                self.captureMode = targetMode
                self.updateDoneButtonAppearance()
            }
        }
    }

    @objc
    private func didTapPhotoLibrary() {
        delegate?.photoCaptureViewControllerDidRequestPresentPhotoLibrary(self)
    }

    @objc
    private func didTapDoneButton() {
        delegate?.photoCaptureViewControllerDidFinish(self)
    }

    @objc
    private func contentTypeChanged() {
        Logger.verbose("")
    }
}

// MARK: - Camera Gesture Recognizers

extension PhotoCaptureViewController {

    private func configureCameraGestures() {
        previewView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:))))

        let doubleTapToSwitchCameraGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapToSwitchCamera(tapGesture:)))
        doubleTapToSwitchCameraGesture.numberOfTapsRequired = 2
        previewView.addGestureRecognizer(doubleTapToSwitchCameraGesture)

        let tapToFocusGesture = UITapGestureRecognizer(target: self, action: #selector(didTapFocusExpose(tapGesture:)))
        tapToFocusGesture.require(toFail: doubleTapToSwitchCameraGesture)
        previewView.addGestureRecognizer(tapToFocusGesture)
    }

    @objc
    func didPinchZoom(pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began:
            photoCapture.beginPinchZoom()
            fallthrough
        case .changed:
            photoCapture.updatePinchZoom(withScale: pinchGesture.scale)
        case .ended:
            photoCapture.completePinchZoom(withScale: pinchGesture.scale)
        default:
            break
        }
    }

    @objc
    func didDoubleTapToSwitchCamera(tapGesture: UITapGestureRecognizer) {
        guard !isRecordingVideo else {
            // - Orientation gets out of sync when switching cameras mid movie.
            // - Audio gets out of sync when switching cameras mid movie
            // https://stackoverflow.com/questions/13951182/audio-video-out-of-sync-after-switch-camera
            return
        }

        switchCameraPosition()
    }

    @objc
    func didTapFocusExpose(tapGesture: UITapGestureRecognizer) {
        let viewLocation = tapGesture.location(in: previewView)
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: viewLocation)
        photoCapture.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        lastUserFocusTapPoint = devicePoint

        if let focusFrameSuperview = tapToFocusView.superview {
            positionTapToFocusView(center: tapGesture.location(in: focusFrameSuperview))
            startFocusAnimation()
        }
    }
}

// MARK: - Tap to Focus

extension PhotoCaptureViewController {

    private func positionTapToFocusView(center: CGPoint) {
        tapToFocusCenterXConstraint.constant = center.x
        tapToFocusCenterYConstraint.constant = center.y
    }

    private func startFocusAnimation() {
        tapToFocusView.stop()
        tapToFocusView.play(fromProgress: 0.0, toProgress: 0.9)
    }

    private func completeFocusAnimation(forFocusPoint focusPoint: CGPoint) {
        guard let lastUserFocusTapPoint = lastUserFocusTapPoint else { return }

        guard lastUserFocusTapPoint.within(0.005, of: focusPoint) else {
            Logger.verbose("focus completed for obsolete focus point. User has refocused.")
            return
        }

        tapToFocusView.play(toProgress: 1.0)
    }
}

// MARK: - Photo Capture

extension PhotoCaptureViewController {

    private func captureReady() {
        self.hasCaptureStarted = true
        BenchEventComplete(eventId: "Show-Camera")
        if isVisible {
            VolumeButtons.shared?.addObserver(observer: photoCapture)
        }
    }

    private func setupPhotoCapture() {
        photoCapture.delegate = self
        bottomBar.captureControl.delegate = photoCapture
        if let sideBar = sideBar {
            sideBar.cameraCaptureControl.delegate = photoCapture
        }

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

    private func updateFlashModeControl(animated: Bool) {
        topBar.flashModeButton.setFlashMode(photoCapture.flashMode, animated: animated)
        if let sideBar = sideBar {
            sideBar.flashModeButton.setFlashMode(photoCapture.flashMode, animated: animated)
        }
    }
}

extension PhotoCaptureViewController: InteractiveDismissDelegate {

    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        view.backgroundColor = .clear
    }

    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        dismiss(animated: true)
    }

    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        view.backgroundColor = Theme.darkThemeBackgroundColor
    }
}

extension PhotoCaptureViewController: CameraZoomSelectionControlDelegate {

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didSelect camera: PhotoCapture.CameraType) {
        let position: AVCaptureDevice.Position = cameraZoomControl == frontCameraZoomControl ? .front : .back
        photoCapture.switchCamera(to: camera, at: position, animated: true)
    }

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didChangeZoomFactor zoomFactor: CGFloat) {
        photoCapture.changeVisibleZoomFactor(to: zoomFactor, animated: true)
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

        updateDoneButtonAppearance()

        if captureMode == .multi {
            resumePhotoCapture()
        } else {
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

    func photoCaptureWillBeginRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
        isRecordingVideo = true
    }

    func photoCaptureDidBeginRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
    }

    func photoCaptureDidFinishRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
        isRecordingVideo = false
    }

    func photoCaptureDidCancelRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
        isRecordingVideo = false
    }

    // MARK: -

    var zoomScaleReferenceDistance: CGFloat? {
        if isIPadUIInRegularMode {
            return previewView.bounds.width / 2
        }
        return previewView.bounds.height / 2
    }

    func photoCapture(_ photoCapture: PhotoCapture, didChangeVideoZoomFactor zoomFactor: CGFloat, forCameraPosition position: AVCaptureDevice.Position) {
        guard let cameraZoomControl = position == .front ? frontCameraZoomControl : rearCameraZoomControl else { return }
        cameraZoomControl.currentZoomFactor = zoomFactor
    }

    func beginCaptureButtonAnimation(_ duration: TimeInterval) {
        bottomBar.captureControl.setState(.recording, animationDuration: duration)
        if let sideBar = sideBar {
            sideBar.cameraCaptureControl.setState(.recording, animationDuration: duration)
        }
    }

    func endCaptureButtonAnimation(_ duration: TimeInterval) {
        bottomBar.captureControl.setState(.initial, animationDuration: duration)
        if let sideBar = sideBar {
            sideBar.cameraCaptureControl.setState(.initial, animationDuration: duration)
        }
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
