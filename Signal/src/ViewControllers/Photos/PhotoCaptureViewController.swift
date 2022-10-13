//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import Lottie
import Photos
import UIKit
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewControllerDidFinish(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController,
                                    didFinishWithTextAttachment textAttachment: TextAttachment)
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
    private var isCaptureReady = false {
        didSet {
            guard isCaptureReady != oldValue else { return }

            if isCaptureReady {
                BenchEventComplete(eventId: "Show-Camera")
                VolumeButtons.shared?.addObserver(observer: photoCapture)
                UIApplication.shared.isIdleTimerDisabled = true
            } else {
                VolumeButtons.shared?.removeObserver(photoCapture)
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
    private var hasCaptureStarted = false {
        didSet {
            isCaptureReady = isViewVisible && hasCaptureStarted
        }
    }
    private var isViewVisible = false {
        didSet {
            isCaptureReady = isViewVisible && hasCaptureStarted
        }
    }

    deinit {
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        delegate?.photoCaptureViewControllerViewWillAppear(self)

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
        isViewVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewVisible = false
        pausePhotoCapture()
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

    private enum ComposerMode {
        case camera
        case text
    }
    private var _internalComposerMode: ComposerMode = .camera
    private var composerMode: ComposerMode { _internalComposerMode }
    private func setComposerMode(_ composerMode: ComposerMode, animated: Bool) {
        owsAssertDebug(!isRecordingVideo, "Invalid state - should not be recording video")

        guard _internalComposerMode != composerMode else { return }
        _internalComposerMode = composerMode

        updateTopBarAppearance(animated: animated)
        // No need to update bottom bar's visibility because it's always visible if CAMERA|TEXT switch is accessible.
        bottomBar.setMode(composerMode == .text ? .text : .camera, animated: animated)
        updateSideBarVisibility(animated: animated)

        let hideZoomControl = composerMode == .text
        let isFrontCamera = photoCapture.desiredPosition == .front
        frontCameraZoomControl?.setIsHidden(hideZoomControl || !isFrontCamera, animated: animated)
        rearCameraZoomControl?.setIsHidden(hideZoomControl || isFrontCamera, animated: animated)

        doneButton.setIsHidden(shouldHideDoneButton, animated: animated)

        previewView.setIsHidden(composerMode == .text, animated: animated)
        if textEditorUIInitialized {
            textEditorToolbar.setIsHidden(composerMode != .text, animated: animated)
        }
    }

    private var _internalIsRecordingVideo = false
    private var isRecordingVideo: Bool { _internalIsRecordingVideo }
    private func setIsRecordingVideo(_ isRecordingVideo: Bool, animated: Bool) {
        guard _internalIsRecordingVideo != isRecordingVideo else { return }
        _internalIsRecordingVideo = isRecordingVideo

        updateTopBarAppearance(animated: animated)
        if isRecordingVideo {
            topBar.recordingTimerView.startCounting()

            let captureControlState: CameraCaptureControl.State = UIAccessibility.isVoiceOverRunning ? .recordingUsingVoiceOver : .recording
            let animationDuration: TimeInterval = animated ? 0.4 : 0
            bottomBar.captureControl.setState(captureControlState, animationDuration: animationDuration)
            if let sideBar = sideBar {
                sideBar.cameraCaptureControl.setState(captureControlState, animationDuration: animationDuration)
            }
        } else {
            topBar.recordingTimerView.stopCounting()

            let animationDuration: TimeInterval = animated ? 0.2 : 0
            bottomBar.captureControl.setState(.initial, animationDuration: animationDuration)
            if let sideBar = sideBar {
                sideBar.cameraCaptureControl.setState(.initial, animationDuration: animationDuration)
            }
        }

        bottomBar.setMode(isRecordingVideo ? .videoRecording : .camera, animated: animated)
        if let sideBar = sideBar {
            sideBar.isRecordingVideo = isRecordingVideo
        }

        doneButton.setIsHidden(shouldHideDoneButton, animated: animated)
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
    private func updateTopBarAppearance(animated: Bool) {
        let mode: CameraTopBar.Mode = {
            if isRecordingVideo {
                return .videoRecording
            }
            if composerMode == .text {
                return .closeButton
            }
            if isIPadUIInRegularMode {
                return .closeButton
            }
            return .cameraControls
        }()
        topBar.setMode(mode, animated: animated)
    }

    private lazy var bottomBar = CameraBottomBar(isContentTypeSelectionControlAvailable: delegate?.photoCaptureViewControllerCanShowTextEditor(self) ?? false)
    private var bottomBarControlsLayoutGuideBottom: NSLayoutConstraint?
    private func updateBottomBarVisibility(animated: Bool) {
        let isBarHidden: Bool = {
            if textEditorUIInitialized {
                return textStoryComposerView.isEditing
            }
            if bottomBar.isContentTypeSelectionControlAvailable {
                return false
            }
            return isIPadUIInRegularMode
        }()
        bottomBar.setIsHidden(isBarHidden, animated: animated)
    }

    private var sideBar: CameraSideBar? // Optional because most devices are iPhones and will never need this.
    private func updateSideBarVisibility(animated: Bool) {
        guard let sideBar = sideBar else { return }
        sideBar.setIsHidden(composerMode == .text || !isIPadUIInRegularMode, animated: true)
    }

    // MARK: - Camera Controls

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

    // MARK: - Text Editor

    private var textEditorUIInitialized = false
    private var textEditoriPhoneConstraints = [NSLayoutConstraint]()
    private var textEditoriPadConstraints = [NSLayoutConstraint]()

    private lazy var textStoryComposerView = TextStoryComposerView(text: "")

    private lazy var textEditorToolbar: UIView = {
        let stackView = UIStackView(arrangedSubviews: [ textBackgroundSelectionButton, textViewAttachLinkButton ])
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    private lazy var textBackgroundSelectionButton = RoundGradientButton()
    private lazy var textViewAttachLinkButton: UIButton = {
        let button = RoundMediaButton(image: UIImage(imageLiteralResourceName: "link-diagonal"), backgroundStyle: .blur)
        button.contentEdgeInsets = UIEdgeInsets(margin: 3)
        button.layoutMargins = .zero
        return button
    }()

    // This constraint gets updated when onscreen keyboard appears/disappears.
    private var textStoryComposerContentLayoutGuideBottomIphone: NSLayoutConstraint?
    private var textStoryComposerContentLayoutGuideBottomIpad: NSLayoutConstraint?
    private var observingKeyboardNotifications = false

    private lazy var doneButton: MediaDoneButton = {
        let button = MediaDoneButton(type: .custom)
        button.badgeNumber = 0
        button.userInterfaceStyleOverride = .dark
        return button
    }()
    private var shouldHideDoneButton: Bool {
        isRecordingVideo || composerMode == .text || doneButton.badgeNumber == 0
    }
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
            // On devices with home button and iPads bar is simply pinned to the bottom of the screen
            // with a fixed margin that defines space under the shutter button or CAMERA|TEXT switch.
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

        if textEditorUIInitialized {
            initializeTextEditoriPadUI()
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

        updateTopBarAppearance(animated: true)
        updateBottomBarVisibility(animated: true)
        bottomBar.setLayout(isIPadUIInRegularMode ? .iPad : .iPhone, animated: true)
        updateSideBarVisibility(animated: true)

        if textEditorUIInitialized {
            textStoryComposerView.layer.cornerRadius = isIPadUIInRegularMode || UIDevice.current.hasIPhoneXNotch ? 18 : 0

            if isIPadUIInRegularMode {
                view.removeConstraints(textEditoriPhoneConstraints)
                view.addConstraints(textEditoriPadConstraints)

                bottomBar.constrainControlButtonsLayoutGuideHorizontallyTo(
                    leadingAnchor: textStoryComposerView.leadingAnchor,
                    trailingAnchor: textStoryComposerView.trailingAnchor
                )
            } else {
                view.removeConstraints(textEditoriPadConstraints)
                view.addConstraints(textEditoriPhoneConstraints)

                bottomBar.constrainControlButtonsLayoutGuideHorizontallyTo(leadingAnchor: nil, trailingAnchor: nil)
            }
        }
    }

    private func updateDoneButtonAppearance() {
        if captureMode == .multi, let badgeNumber = dataSource?.numberOfMediaItems, badgeNumber > 0 {
            doneButton.badgeNumber = badgeNumber
        }
        doneButton.isHidden = shouldHideDoneButton
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

// MARK: - Text Editor

extension PhotoCaptureViewController {

    private func initializeTextEditorUIIfNecessary() {
        guard !textEditorUIInitialized else { return }

        // Connect button actions.
        bottomBar.proceedButton.addTarget(self, action: #selector(didTapTextStoryProceedButton), for: .touchUpInside)
        textBackgroundSelectionButton.addTarget(self, action: #selector(didTapTextBackgroundButton), for: .touchUpInside)
        textViewAttachLinkButton.addTarget(self, action: #selector(didTapAttachLinkPreviewButton), for: .touchUpInside)
        updateTextBackgroundSelectionButton()

        // Set up composer view.
        textStoryComposerView.delegate = self
        textStoryComposerView.translatesAutoresizingMaskIntoConstraints = false
        textStoryComposerView.layer.cornerRadius = isIPadUIInRegularMode || UIDevice.current.hasIPhoneXNotch ? 18 : 0
        view.insertSubview(textStoryComposerView, aboveSubview: previewView)
        textEditoriPhoneConstraints.append(contentsOf: [
            textStoryComposerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            textStoryComposerView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            textStoryComposerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            textStoryComposerView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        ])

        // Choose Background and Attach Link buttons.
        // Toolbar is added to VC's view because it might be located outside of the textStoryComposerView.
        view.addSubview(textEditorToolbar)
        // Align leading edge of Background button to leading edge of the content area of the `bottomBar`,
        // which is in turn might constrained to the leading edge of text editor "card".
        view.addConstraint(textEditorToolbar.leadingAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.leadingAnchor))
        if bottomBar.isCompactHeightLayout {
            // On devices without top and bottom safe areas buttons are placed above CAMERA | TEXT controls.
            textEditoriPhoneConstraints.append(
                textEditorToolbar.bottomAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.topAnchor))
        } else {
            // On devices with bottom safe area buttons are pinned to the bottom edge of the colored background,
            // which always clears CAMERA | TEXT controls.
            textEditoriPhoneConstraints.append(
                textEditorToolbar.bottomAnchor.constraint(equalTo: textStoryComposerView.bottomAnchor, constant: -16))
        }

        // This constraint defines bottom edge of the area that contains text view and link preview inside of the `textStoryComposerView`.
        // Initially the bottom edge is pinned to the top of `textEditorToolbar`.
        // If on-screen keyboard appears the constraint is updated so that content clears the keyboard.
        textStoryComposerContentLayoutGuideBottomIphone = textStoryComposerView.contentLayoutGuide.bottomAnchor.constraint(
            equalTo: textEditorToolbar.bottomAnchor)
        textEditoriPhoneConstraints.append(textStoryComposerContentLayoutGuideBottomIphone!)

        if isIPadUIInRegularMode {
            initializeTextEditoriPadUI()
        } else {
            view.addConstraints(textEditoriPhoneConstraints)
        }

        view.setNeedsLayout()
        UIView.performWithoutAnimation {
            self.view.layoutIfNeeded()
        }

        textEditorUIInitialized = true
    }

    private func initializeTextEditoriPadUI() {
        owsAssertDebug(textEditoriPadConstraints.isEmpty)

        // Container - 16:9 aspect ratio, constrained vertically, centered on the screen horizontally.
        textEditoriPadConstraints.append(contentsOf: [
            textStoryComposerView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            textStoryComposerView.bottomAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.topAnchor, constant: -24),
            textStoryComposerView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            textStoryComposerView.widthAnchor.constraint(equalTo: textStoryComposerView.heightAnchor, multiplier: 9/16)
        ])

        // This constraint defines bottom edge of the text content area
        // and would allow to resize content to clear onscreen keyboard.
        textStoryComposerContentLayoutGuideBottomIpad = textStoryComposerView.contentLayoutGuide.bottomAnchor.constraint(
            equalTo: textStoryComposerView.bottomAnchor, constant: -8)
        textEditoriPadConstraints.append(textStoryComposerContentLayoutGuideBottomIpad!)

        // Background and Add Link buttons are vertically centered with CAMERA|TEXT switch and Proceed button.
        textEditoriPadConstraints.append(
            textEditorToolbar.centerYAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.centerYAnchor))

        // Additional constraint that will at least 20 dp between Add Link button and CAMERA|TEXT switch.
        // This constraint will override
        textEditoriPadConstraints.append(
            textEditorToolbar.trailingAnchor.constraint(
                lessThanOrEqualTo: bottomBar.contentTypeSelectionControl.leadingAnchor,
                constant: -20
            )
        )
        if isIPadUIInRegularMode {
            bottomBar.constrainControlButtonsLayoutGuideHorizontallyTo(
                leadingAnchor: textStoryComposerView.leadingAnchor,
                trailingAnchor: textStoryComposerView.trailingAnchor
            )
        }

        view.addConstraints(textEditoriPadConstraints)
    }

    private func updateTextEditorToolbarVisibility(animated: Bool) {
        textEditorToolbar.setIsHidden(textStoryComposerView.isEditing || composerMode != .text, animated: animated)
    }

    // Update background of the background selection button to match the editor.
    private func updateTextBackgroundSelectionButton() {
        switch textStoryComposerView.background {
        case .color(let color):
            textBackgroundSelectionButton.gradientView.colors = [ color, color ]

        case .gradient(let gradient):
            textBackgroundSelectionButton.gradientView.colors = gradient.colors
            textBackgroundSelectionButton.gradientView.locations = gradient.locations
            textBackgroundSelectionButton.gradientView.setAngle(gradient.angle)
        }
    }

    // MARK: - Keyboard Handling

    private func startObservingKeyboardNotifications() {
        guard !observingKeyboardNotifications else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        observingKeyboardNotifications = true
    }

    @objc
    private func handleKeyboardNotification(_ notification: Notification) {
        guard composerMode == .text else { return }

        guard let iPhoneConstraint = textStoryComposerContentLayoutGuideBottomIphone else { return }
        let iPadConstraint = textStoryComposerContentLayoutGuideBottomIpad

        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let iPhoneInset = textEditorToolbar.convert(endFrame, from: nil).minY - textEditorToolbar.bounds.maxY
        var iPadInset: CGFloat = 0

        if isIPadUIInRegularMode {
            // Detection of the floating keyboard.
            let keyboardFrame = textStoryComposerView.convert(endFrame, from: nil)
            if  keyboardFrame.height > 0 &&
                keyboardFrame.minX <= textStoryComposerView.bounds.minX &&
                keyboardFrame.maxX >= textStoryComposerView.bounds.maxX {
                iPadInset = keyboardFrame.minY - textStoryComposerView.bounds.maxY
            } else {
                iPadInset = 0
            }
        }

        let layoutUpdateBlock = {
            iPhoneConstraint.constant = min(iPhoneInset, 0) - 8
            iPadConstraint?.constant = min(iPadInset, 0) - 8
        }
        if let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
           let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
           let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve) {
            UIView.beginAnimations("sheetResize", context: nil)
            UIView.setAnimationBeginsFromCurrentState(true)
            UIView.setAnimationCurve(animationCurve)
            UIView.setAnimationDuration(animationDuration)
            layoutUpdateBlock()
            view.setNeedsLayout()
            view.layoutIfNeeded()
            UIView.commitAnimations()
        } else {
            UIView.performWithoutAnimation {
                layoutUpdateBlock()
            }
        }
    }

    // MARK: - Background

    private class RoundGradientButton: RoundMediaButton {
        let gradientView = GradientView(colors: [])

        init() {
            let gradientCircleView = PillView()
            gradientCircleView.isUserInteractionEnabled = false
            gradientCircleView.layer.borderWidth = 2
            gradientCircleView.layer.borderColor = UIColor.white.cgColor
            gradientCircleView.addSubview(gradientView)
            gradientCircleView.autoSetDimensions(to: CGSize(square: 28))
            gradientView.autoPinEdgesToSuperviewEdges()

            super.init(image: nil, backgroundStyle: .blur, customView: gradientCircleView)

            contentEdgeInsets = .zero
            layoutMargins = .zero
        }

        override var intrinsicContentSize: CGSize { CGSize(square: 44) }
    }

    // MARK: - Button Actions

    @objc
    private func didTapTextBackgroundButton() {
        textStoryComposerView.switchToNextBackground()
        updateTextBackgroundSelectionButton()
    }

    @objc
    private func didTapAttachLinkPreviewButton() {
        let linkPreviewViewController = LinkPreviewAttachmentViewController(textStoryComposerView.linkPreviewDraft)
        linkPreviewViewController.delegate = self
        present(linkPreviewViewController, animated: true)
    }

    @objc
    private func didTapTextStoryProceedButton() {
        Logger.verbose("")

        let text = textStoryComposerView.text ?? ""
        let textForegroundColor = textStoryComposerView.textForegroundColor
        let textBackgroundColor = textStoryComposerView.textBackgroundColor
        let textStyle = textStoryComposerView.textStyle
        let background = textStoryComposerView.background

        var validatedLinkPreview: OWSLinkPreview?
        if let linkPreview = textStoryComposerView.linkPreviewDraft {
            self.databaseStorage.write { transaction in
                do {
                    validatedLinkPreview = try OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreview, transaction: transaction)
                } catch LinkPreviewError.featureDisabled {
                    validatedLinkPreview = OWSLinkPreview(urlString: linkPreview.urlString, title: nil, imageAttachmentId: nil)
                } catch {
                    Logger.error("Failed to generate link preview.")
                }
            }
        }

        guard validatedLinkPreview != nil || !text.isEmpty else {
            owsFailDebug("Empty content")
            return
        }

        let textAttachment = TextAttachment(
            text: text,
            textStyle: textStyle,
            textForegroundColor: textForegroundColor,
            textBackgroundColor: textBackgroundColor,
            background: background,
            linkPreview: validatedLinkPreview)
        delegate?.photoCaptureViewController(self, didFinishWithTextAttachment: textAttachment)
    }
}

extension PhotoCaptureViewController: TextStoryComposerViewDelegate {

    fileprivate func textStoryComposerDidBeginEditing(_ textStoryComposer: TextStoryComposerView) {
        updateBottomBarVisibility(animated: true)
        updateTextEditorToolbarVisibility(animated: true)
    }

    fileprivate func textStoryComposerDidEndEditing(_ textStoryComposer: TextStoryComposerView) {
        updateBottomBarVisibility(animated: true)
        updateTextEditorToolbarVisibility(animated: true)
    }

    fileprivate func textStoryComposerDidChange(_ textStoryComposer: TextStoryComposerView) {
        bottomBar.proceedButton.isEnabled = !textStoryComposer.isEmpty
    }
}

extension PhotoCaptureViewController: LinkPreviewAttachmentViewControllerDelegate {

    func linkPreviewAttachmentViewController(_ viewController: LinkPreviewAttachmentViewController,
                                             didFinishWith linkPreview: OWSLinkPreviewDraft) {
        textStoryComposerView.linkPreviewDraft = linkPreview
        viewController.dismiss(animated: true)
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
        let newComposerMode: ComposerMode = {
            switch bottomBar.contentTypeSelectionControl.selectedSegmentIndex {
            case 0:
                return .camera

            case 1:
                return .text

            default:
                owsFailDebug("Invalid segment index")
                return composerMode
            }
        }()
        setComposerMode(newComposerMode, animated: true)

        // Stop / start camera as necessary.
        switch newComposerMode {
        case .camera:
            resumePhotoCapture()
            textStoryComposerView.setIsHidden(true, animated: true)

        case .text:
            startObservingKeyboardNotifications()
            initializeTextEditorUIIfNecessary()
            textStoryComposerView.setIsHidden(false, animated: true)
            pausePhotoCapture()
        }
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

    private func setupPhotoCapture() {
        photoCapture.delegate = self
        bottomBar.captureControl.delegate = photoCapture
        if let sideBar = sideBar {
            sideBar.cameraCaptureControl.delegate = photoCapture
        }

        // If the session is already running, we're good to go.
        guard !photoCapture.session.isRunning else {
            self.hasCaptureStarted = true
            return
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
            self?.hasCaptureStarted = true
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
        setIsRecordingVideo(false, animated: true)

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
        setIsRecordingVideo(true, animated: true)
    }

    func photoCaptureDidBeginRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
    }

    func photoCaptureDidFinishRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
        setIsRecordingVideo(false, animated: true)
    }

    func photoCaptureDidCancelRecording(_ photoCapture: PhotoCapture) {
        Logger.verbose("")
        setIsRecordingVideo(false, animated: true)
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

private protocol TextStoryComposerViewDelegate: AnyObject {
    func textStoryComposerDidBeginEditing(_ textStoryComposer: TextStoryComposerView)
    func textStoryComposerDidEndEditing(_ textStoryComposer: TextStoryComposerView)
    func textStoryComposerDidChange(_ textStoryComposer: TextStoryComposerView)
}

private class TextStoryComposerView: TextAttachmentView, UITextViewDelegate {

    weak var delegate: TextStoryComposerViewDelegate?

    init(text: String) {
        super.init(
            text: text,
            textStyle: .regular,
            textForegroundColor: TextStylingToolbar.defaultColor(forLayout: .textStory).color,
            textBackgroundColor: nil,
            background: TextStoryComposerView.defaultBackground,
            linkPreview: nil
        )

        // Placeholder Label
        textPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textPlaceholderLabel)
        addConstraints([
            textPlaceholderLabel.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            textPlaceholderLabel.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            textPlaceholderLabel.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            textPlaceholderLabel.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        ])

        // Prepare text styling toolbar - attached to keyboard.
        let toolbarSize = textViewAccessoryToolbar.systemLayoutSizeFitting(
            CGSize(width: UIScreen.main.bounds.width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        textViewAccessoryToolbar.bounds.size = toolbarSize
        textView.inputAccessoryView = textViewAccessoryToolbar

        // Text View
        textViewBackgroundView.layer.cornerRadius = LayoutConstants.textBackgroundCornerRadius
        textViewBackgroundView.addSubview(textView)
        addSubview(textViewBackgroundView)

        updateTextViewAttributes()
        updateVisibilityOfComponents(animated: false)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(placeholderTapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Slightly smaller vertical margins for UITextView because UITextView
    // has larger embedded padding above and below the text.
    private static let textViewBackgroundVMargin = LayoutConstants.textBackgroundVMargin - 8
    private static let textViewBackgroundHMargin = LayoutConstants.textBackgroundHMargin

    override public func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = layoutMarginsGuide.layoutFrame.width
        if
            let contentWidthConstraint = textViewAccessoryToolbar.contentWidthConstraint,
            contentWidthConstraint.constant != contentWidth,
            contentWidth > 0
        {
            contentWidthConstraint.constant = contentWidth
        }
    }

    public override func layoutTextContentAndLinkPreview() {
        super.layoutTextContentAndLinkPreview()

        var textViewSize = textContentSize

        // Min dimensions for an empty text view.
        textViewSize.width = max(textViewSize.width, 20)
        textViewSize.height = max(textViewSize.height, 48)

        // Limit text view height to available content height, deducting link preview area height if needed.
        var linkPreviewAreaHeight: CGFloat = 0
        if linkPreviewView != nil {
            linkPreviewAreaHeight = linkPreviewWrapperView.frame.height + LayoutConstants.linkPreviewAreaTopMargin
        }
        textViewSize.height = min(
            textViewSize.height,
            contentLayoutGuide.layoutFrame.height - linkPreviewAreaHeight - 2 * TextStoryComposerView.textViewBackgroundVMargin
        )

        // Enable / disable vertical text scrolling if all text doesn't fit the available screen space.
        if textContentSize.height > textViewSize.height {
            textView.isScrollEnabled = true
        } else {
            textView.isScrollEnabled = false
        }
        textView.bounds.size = textViewSize

        textViewBackgroundView.bounds.size = CGSize(
            width: textViewSize.width + 2 * TextStoryComposerView.textViewBackgroundHMargin,
            height: textViewSize.height + 2 * TextStoryComposerView.textViewBackgroundVMargin
        )
        textViewBackgroundView.center = CGPoint(
            x: contentLayoutGuide.layoutFrame.center.x,
            y: contentLayoutGuide.layoutFrame.center.y - 0.5 * linkPreviewAreaHeight
        )
        textView.center = textViewBackgroundView.bounds.center

        linkPreviewWrapperView.center = CGPoint(
            x: linkPreviewWrapperView.center.x,
            y: textViewBackgroundView.frame.maxY + LayoutConstants.linkPreviewAreaTopMargin + 0.5 * linkPreviewWrapperView.bounds.height
        )
    }

    override func calculateTextContentSize() -> CGSize {
        guard isEditing else {
            return super.calculateTextContentSize()
        }
        let maxTextViewSize = contentLayoutGuide.layoutFrame.insetBy(
            dx: LayoutConstants.textBackgroundHMargin,
            dy: TextStoryComposerView.textViewBackgroundVMargin
        ).size
        return textView.systemLayoutSizeFitting(
            maxTextViewSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    // MARK: -

    override var isEditing: Bool { textView.isFirstResponder }

    var isEmpty: Bool {
        guard let text = text else { return true }
        return text.isEmpty && linkPreview == nil
    }

    // MARK: - Text View

    private lazy var textView: MediaTextView = {
        let textView = MediaTextView()
        textView.delegate = self
        textView.showsVerticalScrollIndicator = false
        return textView
    }()

    private let textViewBackgroundView = UIView()

    private lazy var textViewAccessoryToolbar: TextStylingToolbar = {
        let toolbar = TextStylingToolbar(layout: .textStory)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.addTarget(self, action: #selector(didChangeTextColor), for: .valueChanged)
        toolbar.textStyleButton.addTarget(self, action: #selector(didTapTextStyleButton), for: .touchUpInside)
        toolbar.decorationStyleButton.addTarget(self, action: #selector(didTapDecorationStyleButton), for: .touchUpInside)
        toolbar.doneButton.addTarget(self, action: #selector(didTapTextViewDoneButton), for: .touchUpInside)
        return toolbar
    }()

    private let textPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .ows_whiteAlpha60
        label.font = .ows_dynamicTypeLargeTitle1Clamped
        label.text = NSLocalizedString("STORY_COMPOSER_TAP_ADD_TEXT",
                                       value: "Tap to add text",
                                       comment: "Placeholder text in text stories compose UI")
        return label
    }()

    override public func updateVisibilityOfComponents(animated: Bool) {
        super.updateVisibilityOfComponents(animated: animated)

        let isEditing = isEditing
        textPlaceholderLabel.setIsHidden(isEditing || !isEmpty, animated: animated)
        textViewBackgroundView.setIsHidden(!isEditing, animated: animated)
    }

    private func updateTextViewAttributes() {
        let text = textView.text.stripped
        let (fontPointSize, textAlignment) = sizeAndAlignment(forText: text)
        textView.updateWith(
            textForegroundColor: textForegroundColor,
            font: font(for: textStyle, withPointSize: fontPointSize),
            textAlignment: textAlignment,
            textDecorationColor: nil,
            decorationStyle: .none)
        textViewBackgroundView.backgroundColor = textBackgroundColor
    }

    private func adjustFontSizeIfNecessary() {
        guard let currentFontSize = textView.font?.pointSize else { return }
        let text = textView.text.stripped
        let desiredFontSize = sizeAndAlignment(forText: text).fontPointSize
        guard desiredFontSize != currentFontSize else { return }
        self.text = text
        updateTextAttributes()
        updateTextViewAttributes()
    }

    @objc
    private func placeholderTapped() {
        textView.becomeFirstResponder()
    }

    @objc
    private func didTapTextStyleButton() {
        Logger.verbose("")

        let textStyle = textViewAccessoryToolbar.textStyle.next()
        textViewAccessoryToolbar.textStyle = textStyle

        self.textStyle = {
            switch textStyle {
            case .regular: return .regular
            case .bold: return .bold
            case .serif: return .serif
            case .script: return .script
            case .condensed: return .condensed
            }
        }()

        updateTextViewAttributes()
    }

    @objc
    private func didTapDecorationStyleButton() {
        Logger.verbose("")

        // "Underline" and "Outline" are not available in text story composer.
        var decorationStyle = textViewAccessoryToolbar.decorationStyle.next()
        if decorationStyle == .outline || decorationStyle == .underline {
            decorationStyle = .none
        }
        textViewAccessoryToolbar.decorationStyle = decorationStyle

        // `textViewAccessoryToolbar` defines both foreground and background color for text based on the decoration style.
        let textForegroundColor = textViewAccessoryToolbar.textForegroundColor
        let textBackgroundColor = textViewAccessoryToolbar.textBackgroundColor
        setTextForegroundColor(textForegroundColor, backgroundColor: textBackgroundColor)

        updateTextViewAttributes()
    }

    @objc
    private func didChangeTextColor() {
        Logger.verbose("")

        // Depending on text decoration style color picker changes either color of the text or background color.
        // That's why we need to update both.
        let textForegroundColor = textViewAccessoryToolbar.textForegroundColor
        let textBackgroundColor = textViewAccessoryToolbar.textBackgroundColor
        setTextForegroundColor(textForegroundColor, backgroundColor: textBackgroundColor)

        updateTextViewAttributes()
    }

    @objc
    private func didTapTextViewDoneButton() {
        Logger.verbose("")

        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        updateVisibilityOfComponents(animated: true)
        delegate?.textStoryComposerDidBeginEditing(self)
        setNeedsLayout()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.text = textView.text.stripped
        updateVisibilityOfComponents(animated: true)
        delegate?.textStoryComposerDidEndEditing(self)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Truncate the replacement to fit.
        return TextViewHelper.textView(
            textView,
            shouldChangeTextIn: range,
            replacementText: text,
            maxGlyphCount: 700
        )
    }

    func textViewDidChange(_ textView: UITextView) {
        self.text = textView.text.stripped
        adjustFontSizeIfNecessary()
        delegate?.textStoryComposerDidChange(self)
        setNeedsLayout()
    }

    // MARK: - Link Preview

    fileprivate var linkPreviewDraft: OWSLinkPreviewDraft? {
        didSet {
            if let linkPreviewDraft = linkPreviewDraft {
                linkPreview = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
            } else {
                linkPreview = nil
            }
            delegate?.textStoryComposerDidChange(self)
        }
    }

    private lazy var deleteLinkPreviewButton: UIButton = {
        let button = RoundMediaButton(image: UIImage(imageLiteralResourceName: "x-24"), backgroundStyle: .blurLight)
        button.tintColor = Theme.lightThemePrimaryColor
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.layoutMargins = UIEdgeInsets(margin: 2)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapDeleteLinkPreviewButton), for: .touchUpInside)
        return button
    }()

    override func reloadLinkPreviewAppearance() {
        super.reloadLinkPreviewAppearance()

        guard let linkPreviewView = linkPreviewView else { return }

        if deleteLinkPreviewButton.superview == nil {
            linkPreviewWrapperView.addSubview(deleteLinkPreviewButton)
        }
        linkPreviewWrapperView.bringSubviewToFront(deleteLinkPreviewButton)
        linkPreviewWrapperView.addConstraints([
            deleteLinkPreviewButton.centerXAnchor.constraint(equalTo: linkPreviewView.trailingAnchor, constant: -5),
            deleteLinkPreviewButton.centerYAnchor.constraint(equalTo: linkPreviewView.topAnchor, constant: 5)
        ])

        updateVisibilityOfComponents(animated: true)
    }

    @objc
    private func didTapDeleteLinkPreviewButton() {
        linkPreviewDraft = nil
    }

    // MARK: - Background

    private var currentBackgroundIndex = 0 {
        didSet {
            background = TextStoryComposerView.textBackgrounds[currentBackgroundIndex]
        }
    }

    private static var defaultBackground: TextAttachment.Background { textBackgrounds[0] }

    private static var textBackgrounds: [TextAttachment.Background] = [
        .color(.init(rgbHex: 0x688BD4)),
        .color(.init(rgbHex: 0x8687C1)),
        .color(.init(rgbHex: 0xB47F8C)),
        .color(.init(rgbHex: 0x899188)),
        .color(.init(rgbHex: 0x539383)),
        .gradient(.init(colors: [ .init(rgbHex: 0x19A9FA), .init(rgbHex: 0x7097D7), .init(rgbHex: 0xD1998D), .init(rgbHex: 0xFFC369) ])),
        .gradient(.init(colors: [ .init(rgbHex: 0x4437D8), .init(rgbHex: 0x6B70DE), .init(rgbHex: 0xB774E0), .init(rgbHex: 0xFF8E8E) ])),
        .gradient(.init(colors: [ .init(rgbHex: 0x004044), .init(rgbHex: 0x2C5F45), .init(rgbHex: 0x648E52), .init(rgbHex: 0x93B864) ]))
    ]

    func switchToNextBackground() {
        var nextBackgroundIndex = currentBackgroundIndex + 1
        if nextBackgroundIndex > TextStoryComposerView.textBackgrounds.count - 1 {
            nextBackgroundIndex = 0
        }
        currentBackgroundIndex = nextBackgroundIndex
    }
}
