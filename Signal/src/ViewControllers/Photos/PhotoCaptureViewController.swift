//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import LibSignalClient
import Lottie
import Photos
import SignalServiceKit
import SignalUI

protocol PhotoCaptureViewControllerDelegate: AnyObject {
    func photoCaptureViewControllerDidFinish(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewController(
        _ photoCaptureViewController: PhotoCaptureViewController,
        didFinishWithTextAttachment textAttachment: UnsentTextAttachment,
    )
    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerViewWillAppear(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
    func photoCaptureViewControllerDidRequestPresentPhotoLibrary(_ photoCaptureViewController: PhotoCaptureViewController)
    func photoCaptureViewController(
        _ photoCaptureViewController: PhotoCaptureViewController,
        didRequestSwitchCaptureModeTo captureMode: PhotoCaptureViewController.CaptureMode,
        completion: @escaping (Bool) -> Void,
    )
    func photoCaptureViewControllerCanShowTextEditor(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool
}

protocol PhotoCaptureViewControllerDataSource: AnyObject {
    var numberOfMediaItems: Int { get }
    func addMedia(attachment: PreviewableAttachment)
}

class PhotoCaptureViewController: OWSViewController, OWSNavigationChildController, SheetDismissalDelegate,
    CameraCaptureSessionDelegate, CameraZoomSelectionControlDelegate, InteractiveDismissDelegate,
    LinkPreviewAttachmentViewControllerDelegate, QRCodeSampleBufferScannerDelegate, TextStoryComposerViewDelegate
{
    private let attachmentLimits: OutgoingAttachmentLimits

    init(attachmentLimits: OutgoingAttachmentLimits) {
        self.attachmentLimits = attachmentLimits
        super.init()
    }

    weak var delegate: PhotoCaptureViewControllerDelegate?
    weak var dataSource: PhotoCaptureViewControllerDataSource?
    private var interactiveDismiss: PhotoCaptureInteractiveDismiss?

    private lazy var qrCodeSampleBufferScanner = QRCodeSampleBufferScanner(delegate: self)
    private lazy var cameraCaptureSession = CameraCaptureSession(
        delegate: self,
        attachmentLimits: attachmentLimits,
        qrCodeSampleBufferScanner: qrCodeSampleBufferScanner,
    )

    private var qrCodeScanned = false {
        didSet {
            updateShouldProcessQRCodes()
        }
    }

    /// The underlying stored atomic for `shouldProcessQRCodes`.
    /// Update its value by calling `updateShouldProcessQRCodes`.
    private let _shouldProcessQRCodes = AtomicBool(false, lock: .init())

    private func updateShouldProcessQRCodes() {
        _shouldProcessQRCodes.set(!qrCodeScanned && !isRecordingVideo && isViewVisible)
    }

    private let sleepBlock = DeviceSleepBlockObject(blockReason: "Photo Capture")

    private var isCameraReady = false {
        didSet {
            guard isCameraReady != oldValue else { return }

            if isCameraReady {
                cameraCaptureSession.beginObservingVolumeButtons()
                DependenciesBridge.shared.deviceSleepManager!.addBlock(blockObject: sleepBlock)
            } else {
                cameraCaptureSession.stopObservingVolumeButtons()
                DependenciesBridge.shared.deviceSleepManager!.removeBlock(blockObject: sleepBlock)
            }
        }
    }

    private var hasCameraStarted = false {
        didSet {
            isCameraReady = isViewVisible && hasCameraStarted
        }
    }

    private var isViewVisible = false {
        didSet {
            isCameraReady = isViewVisible && hasCameraStarted
            updateShouldProcessQRCodes()
        }
    }

    deinit {
        cameraCaptureSession.stop().done {
            Logger.debug("stopCapture completed")
        }
    }

    // MARK: - Overrides

    override func viewDidLoad() {
        super.viewDidLoad()

        definesPresentationContext = true
        overrideUserInterfaceStyle = .dark // always dark
        layout = layoutForCurrentViewState()

        view.backgroundColor = .Signal.mediaBackground

        initializeUI()

        setupPhotoCapture()

        updateFlashModeControl(animated: false)

        if let navigationController {
            let interactiveDismiss = PhotoCaptureInteractiveDismiss(viewController: navigationController)
            interactiveDismiss.interactiveDismissDelegate = self
            interactiveDismiss.addGestureRecognizer(to: view)
            self.interactiveDismiss = interactiveDismiss
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        delegate?.photoCaptureViewControllerViewWillAppear(self)

        let previewOrientation: AVCaptureVideoOrientation
        if UIDevice.current.isIPad, let windowScene = view.window?.windowScene {
            previewOrientation = AVCaptureVideoOrientation(interfaceOrientation: windowScene.interfaceOrientation) ?? .portrait
        } else {
            previewOrientation = .portrait
        }
        UIViewController.attemptRotationToDeviceOrientation()
        cameraCaptureSession.updateVideoPreviewConnection(toOrientation: previewOrientation)
        updateButtonIconOrientations(isAnimated: false, captureOrientation: previewOrientation)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: nil,
        )

        resumePhotoCapture()

        if let dataSource, dataSource.numberOfMediaItems > 0 {
            captureMode = .multi
        }
        updateCameraModeProceedButtonBadgeAndVisibility(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        isViewVisible = true
        cameraCaptureSession.updateVideoCaptureOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewVisible = false
        pausePhotoCapture()
    }

    override var prefersStatusBarHidden: Bool {
        guard AppEnvironment.shared.callService.callServiceState.currentCall == nil else { return false }
        return (UIDevice.current.isIPad || UIDevice.current.hasIPhoneXNotch) == false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    var prefersNavigationBarHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard UIDevice.current.isIPad else { return }

        // Since we support iPad multitasking, we cannot *disable* rotation of our views.
        // Rotating the preview layer is really distracting, so we fade out the preview layer
        // while the rotation occurs.
        self.previewView.alpha = 0
        coordinator.animate(
            alongsideTransition: { _ in
                self.layout = self.layoutForCurrentViewState()
            },
            completion: { _ in
                UIView.animate(withDuration: 0.1) {
                    self.previewView.alpha = 1
                }
            },
        )
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        // Safe area insets will change during interactive dismiss - ignore those changes.
        guard !(interactiveDismiss?.interactionInProgress ?? false) else { return }

        if let contentViewTopEdgeConstraintPhoneLayout {
            contentViewTopEdgeConstraintPhoneLayout.constant = view.safeAreaInsets.top
        }
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()

        // Make padding above top buttons same as leading/trailing margin
        // for concentric corners look.
        topBar.directionalLayoutMargins.top = view.directionalLayoutMargins.leading
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        layout = layoutForCurrentViewState()
    }

    // MARK: - Subview Configuration

    private var isInitialUISetupComplete = false

    private let isUsingLiquidGlassUI: Bool = if #available(iOS 26, *) { true } else { false }

    private func contentViewCornerRadius() -> CGFloat {
        guard layout.useCornerRounding else {
            return 0
        }
        // Rounded corners if preview view isn't full-screen.
        return isUsingLiquidGlassUI ? 40 : 18
    }

    // We'll do rounded corners on this view so it's important to add all UI elements to this view.
    private let contentView = UIView()

    private var bottomAreaProtectionView: UIView?

    // Values match ContentTypeSelectionControl.selectedSegmentIndex.
    private enum ComposerMode: Int {
        case camera = 0
        case text
    }

    private var _composerMode: ComposerMode = .camera
    private var composerMode: ComposerMode {
        get { _composerMode }
        set { setComposerMode(newValue, animated: false) }
    }

    private func setComposerMode(_ composerMode: ComposerMode, animated: Bool) {
        owsAssertDebug(!isRecordingVideo, "Invalid state - should not be recording video")

        guard _composerMode != composerMode else { return }
        _composerMode = composerMode

        guard let composerTypeSelectionControl else {
            owsFailDebug("composerTypeSelectionControl not initialized")
            return
        }

        if composerMode == .text {
            startObservingKeyboardNotifications()
            initializeTextEditorUI()
        }

        updateTopBarMode(animated: animated)

        updateCameraBottomBarVisibility(animated: animated)
        updateCameraSideBarVisibility(animated: animated)

        // Show / hide camera controls and viewfinder.
        let hideCameraUI = composerMode != .camera
        previewView.setIsHidden(hideCameraUI, animated: animated)
        cameraZoomControlsView?.setIsHidden(hideCameraUI, animated: animated)
        updateCameraModeProceedButtonBadgeAndVisibility(animated: animated)

        // Show / hide text editor controls.
        let hideTextComposerUI = composerMode != .text
        textStoryComposerView.setIsHidden(hideTextComposerUI, animated: animated)
        textEditorToolbar.setIsHidden(hideTextComposerUI, animated: animated)
        textStoryModeProceedButton.setIsHidden(hideTextComposerUI, animated: animated)

        // Stop / start camera as necessary.
        switch composerMode {
        case .camera: resumePhotoCapture()
        case .text: pausePhotoCapture()
        }

        // Update CAMERA | TEXT switch if necessary.
        if composerTypeSelectionControl.selectedSegmentIndex != composerMode.rawValue {
            composerTypeSelectionControl.selectedSegmentIndex = composerMode.rawValue
        }
    }

    private var _isRecordingVideo = false
    private var isRecordingVideo: Bool {
        get { _isRecordingVideo }
        set { setIsRecordingVideo(newValue, animated: false) }
    }

    private func setIsRecordingVideo(_ isRecordingVideo: Bool, animated: Bool) {
        guard _isRecordingVideo != isRecordingVideo else { return }
        _isRecordingVideo = isRecordingVideo

        updateShouldProcessQRCodes()

        updateTopBarMode(animated: animated)
        if isRecordingVideo {
            topBar.recordingTimerView.duration = 0

            let captureControlState: CameraCaptureControl.RecordingState = UIAccessibility.isVoiceOverRunning ? .recordingUsingVoiceOver : .recording
            let animationDuration: TimeInterval = animated ? 0.4 : 0
            cameraBottomBar.captureControl.setRecordingState(
                captureControlState,
                animationDuration: animationDuration,
            )
            if let cameraSideBar {
                cameraSideBar.cameraCaptureControl.setRecordingState(
                    captureControlState,
                    animationDuration: animationDuration,
                )
            }
        } else {
            let animationDuration: TimeInterval = animated ? 0.2 : 0
            cameraBottomBar.captureControl.setRecordingState(
                .notRecording,
                animationDuration: animationDuration,
            )
            if let cameraSideBar {
                cameraSideBar.cameraCaptureControl.setRecordingState(
                    .notRecording,
                    animationDuration: animationDuration,
                )
            }
        }

        cameraBottomBar.setIsRecordingVideo(isRecordingVideo, animated: animated)
        if let cameraSideBar {
            cameraSideBar.setIsRecordingVideo(isRecordingVideo, animated: animated)
        }

        updateCameraModeProceedButtonBadgeAndVisibility(animated: animated)
    }

    // Defines whether UI is advanced to the media review screen after
    // taking a photo or a video.
    enum CaptureMode {
        case single
        case multi
    }

    var captureMode: CaptureMode = .single {
        didSet {
            // Animate changes because `captureMode` can only be changed by user tapping the corresponding button.
            topBar.captureModeButton.setMode(captureMode, animated: true)
            if let cameraSideBar {
                cameraSideBar.captureModeButton.setMode(captureMode, animated: true)
            }
            updateCameraModeProceedButtonBadgeAndVisibility(animated: false)
        }
    }

    private let topBar = CameraTopBar()
    // Top bar will show:
    // • only close button on iPad and then in text story editing mode.
    // • only recording indicator when recording a video.
    // • close button, Flash and Capture Mode buttons on iPhones.
    private func updateTopBarMode(animated: Bool) {
        let mode: CameraTopBar.Mode = {
            if case .text = composerMode {
                return .closeButton
            }
            if isRecordingVideo {
                return .videoRecording
            }
            if layout.showsSideBar {
                return .closeButton
            }
            return .cameraControls
        }()
        topBar.setMode(mode, animated: animated)
    }

    private var cameraBottomBar = CameraBottomBar()

    private func updateCameraBottomBarVisibility(animated: Bool) {
        // Camera bottom bar is hidden:
        // • when camera side bar controls are visible.
        // • when text editor is visible.

        let isBottomBarHidden: Bool = switch composerMode {
        case .text: true
        case .camera: layout.showsSideBar
        }
        cameraBottomBar.setIsHidden(isBottomBarHidden, animated: animated)
    }

    private let bottomBarLayoutMargin: CGFloat = 44

    // Camera controls shown in regular x regular layouts.
    // Centered vertically along the trailing edge of the screen.
    // Optional because most devices will never need it.
    private var cameraSideBar: CameraSideBar?

    private func updateCameraSideBarVisibility(animated: Bool) {
        // Side bar is hidden when not in regular x regular UI.

        guard let cameraSideBar else { return }
        let isSideBarHidden: Bool = switch composerMode {
        case .camera: layout.showsSideBar == false
        case .text: true
        }
        cameraSideBar.setIsHidden(isSideBarHidden, animated: true)
    }

    // Optional because cameras are not guaranteed to be available.
    private var cameraZoomControlsView: CameraZoomControlsView?

    // Optional because in some flows (e.g. launching from chat) it's camera-only UI.
    private var composerTypeSelectionControl: ComposerTypeSelectionControl?
    // Composer mode selection control is only hidden when editing text story.
    private func updateComposerTypeSelectionControlVisibility(animated: Bool) {
        guard let composerTypeSelectionControl, isTextEditorUIInitialized else { return }

        composerTypeSelectionControl.setIsHidden(textStoryComposerView.isEditing, animated: animated)
    }

    private lazy var cameraModeProceedButton = BadgedProceedButton(frame: .zero)
    func updateCameraModeProceedButtonBadgeAndVisibility(animated: Bool) {
        let badgeNumber = dataSource?.numberOfMediaItems ?? 0
        let isProceedButtonHidden = switch composerMode {
        case .camera: isRecordingVideo || badgeNumber == 0
        case .text: true
        }
        cameraModeProceedButton.badgeNumber = badgeNumber
        cameraModeProceedButton.setIsHidden(isProceedButtonHidden, animated: animated)
    }

    // MARK: - Camera Controls

    private lazy var tapToFocusView: LottieAnimationView = {
        let view = LottieAnimationView(name: "tap_to_focus")
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
        cameraCaptureSession.previewView
    }

    // MARK: - Text Editor

    private var isTextEditorUIInitialized = false

    private lazy var textStoryComposerView = TextStoryComposerView(text: "")

    private lazy var textEditorToolbar = TextStoryComposerToolbarView()

    // Leading and bottom margin.
    private let textEditorToolbarLayoutMargin: CGFloat = 20

    private lazy var textStoryModeProceedButton = BadgedProceedButton()

    // This constraint gets updated when onscreen keyboard appears/disappears.
    private var textStoryComposerContentLayoutGuideBottomPhone: NSLayoutConstraint?
    private var textStoryComposerContentLayoutGuideBottomPad: NSLayoutConstraint?
    private var observingKeyboardNotifications = false

    // MARK: - Layout

    private enum Layout {
        case pad // Any device having `regular` width and height.
        case padNarrow // iPad device when height is `regular` and width is `compact`.
        case phone // Modern phones with a 9:19.5 screen.
        case legacyPhone // Older phones with a 9:16 screen.

        var showsSideBar: Bool {
            self == .pad
        }

        var useCornerRounding: Bool {
            self == .phone
        }
    }

    private func layoutForCurrentViewState() -> Layout {
        guard view.bounds.isEmpty == false else { return .phone }
        let viewAspectRatio = view.bounds.size.aspectRatio

        if
            (traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular) ||
            (traitCollection.userInterfaceIdiom == .pad)
        {
            return viewAspectRatio > 9 / 16 ? .pad : .padNarrow
        }

        // Up until iPhone X aspect ratio was 9:16.
        // Modern iPhones are 9:19.5.
        if viewAspectRatio > 9 / 18 {
            return .legacyPhone
        }
        return .phone
    }

    private var layout: Layout = .phone {
        didSet {
            guard oldValue != layout else { return }
            if isInitialUISetupComplete {
                updateInterfaceForCurrentViewState(animated: true)
            }
        }
    }

    private func updateInterfaceForCurrentViewState(animated: Bool) {
        // Initialize camera side bar if needed.
        if layout.showsSideBar {
            initializeCameraSideBar()
        }

        // Update constraints.
        if let layoutSpecificConstraints {
            NSLayoutConstraint.deactivate(layoutSpecificConstraints)
        }
        let layoutSpecificConstraints: [NSLayoutConstraint] = switch layout {
        case .pad, .padNarrow: constraintsForPadLayout(isWideLayout: layout.showsSideBar)
        case .phone: constraintsForPhoneLayout()
        case .legacyPhone: constraintsForLegacyPhoneLayout()
        }
        NSLayoutConstraint.activate(layoutSpecificConstraints)
        self.layoutSpecificConstraints = layoutSpecificConstraints

        // Orientation of camera zoom control is layout-dependent.
        if let cameraZoomControlsView {
            cameraZoomControlsView.axis = layout.showsSideBar ? .vertical : .horizontal
        }

        // Orientation of text story composer's toolbar is layout-dependent.
        if isTextEditorUIInitialized {
            textEditorToolbar.axis = layout.showsSideBar ? .vertical : .horizontal
        }

        // Apply corner rounding if necessary.
        let cornerRadius = contentViewCornerRadius()
        if #available(iOS 26, *) {
            contentView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
        } else {
            contentView.layer.cornerRadius = cornerRadius
        }

        // Bottom area protection.
        // On modern iphones, top controls are shown over camera viewfinder.
        // To make interactive dismiss look nicer, view's background is set to `clear`.
        // This black view at the bottom lets us keep background underneath controls
        // at the bottom of the screen, below camera viewfinder / text story composer area.
        // For other layouts this is not reqired: on legacy phones camera viewfinder occupies
        // the entire screen area and on pad layouts we keep black backgrounds during dismiss.
        let bottomAreaProtectionRequired = layout == .phone
        if bottomAreaProtectionRequired {
            let protectionView = bottomAreaProtectionView ?? UIView()
            protectionView.backgroundColor = view.backgroundColor
            if protectionView.superview == nil {
                protectionView.translatesAutoresizingMaskIntoConstraints = false
                view.insertSubview(protectionView, at: 0)
                NSLayoutConstraint.activate([
                    protectionView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
                    protectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    protectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    protectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ])
                bottomAreaProtectionView = protectionView
            }
        } else {
            bottomAreaProtectionView?.removeFromSuperview()
            bottomAreaProtectionView = nil
        }

        // Update view states.
        updateTopBarMode(animated: animated)
        updateCameraBottomBarVisibility(animated: animated)
        updateCameraSideBarVisibility(animated: animated)
    }

    private var layoutSpecificConstraints: [NSLayoutConstraint]?

    // Controls vertical position of `contentView` in `phone` layout.
    private var contentViewTopEdgeConstraintPhoneLayout: NSLayoutConstraint?

    private func constraintsForPadLayout(isWideLayout: Bool) -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()

        // Use this, instead of `self.view`, to position all UI elements.
        let topLevelContentContainer = view!

        // Fix content view at 9:16 aspect ratio.
        constraints.append(contentView.heightAnchor.constraint(
            equalTo: contentView.widthAnchor,
            multiplier: 16 / 9,
        ))

        // Content view is centered in view controller's view using "aspect fit" logic.
        constraints.append(contentsOf: [
            contentView.centerXAnchor.constraint(equalTo: topLevelContentContainer.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: topLevelContentContainer.centerYAnchor),

            contentView.topAnchor.constraint(greaterThanOrEqualTo: topLevelContentContainer.topAnchor),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: topLevelContentContainer.leadingAnchor),
        ])

        // Stretch content view as much as possible.
        let sizingConstraints = [
            contentView.widthAnchor.constraint(equalTo: topLevelContentContainer.widthAnchor),
            contentView.heightAnchor.constraint(equalTo: topLevelContentContainer.heightAnchor),
        ]
        sizingConstraints.forEach { $0.priority = .defaultHigh }
        constraints += sizingConstraints

        // Top bar: pinned to view's top edge.
        constraints.append(topBar.topAnchor.constraint(
            equalTo: topLevelContentContainer.topAnchor,
        ))

        let layoutPadding: CGFloat = 28

        // CAMERA | TEXT control, bottom camera controls, side camera controls, Proceed button.
        // Note that `cameraBottomBar` might be hidden - but we still position it properly.

        // Proceed button is horizontally aligned to the trailing edge of the screen.
        constraints.append(cameraModeProceedButton.trailingAnchor.constraint(
            equalTo: topLevelContentContainer.trailingAnchor,
            constant: -layoutPadding,
        ))

        if let composerTypeSelectionControl {
            constraints += [
                // CAMERA | TEXT control is pinned to the bottom of the screen with a fixed margin.
                composerTypeSelectionControl.bottomAnchor.constraint(
                    equalTo: topLevelContentContainer.bottomAnchor,
                    constant: -layoutPadding,
                ),

                // Bottom camera controls are placed above CAMERA | TEXT with a fixed margin.
                // Note that `cameraBottomBar` might be hidden - but we still position it properly.
                cameraBottomBar.bottomAnchor.constraint(
                    equalTo: composerTypeSelectionControl.topAnchor,
                    constant: -layoutPadding,
                ),

                // Proceed button is centered vertically with CAMERA | TEXT control.
                cameraModeProceedButton.centerYAnchor.constraint(
                    equalTo: composerTypeSelectionControl.centerYAnchor,
                ),
            ]
        } else {
            constraints += [
                // Proceed button is pinned to the bottom of the screen with a fixed margin.
                cameraModeProceedButton.bottomAnchor.constraint(
                    equalTo: topLevelContentContainer.bottomAnchor,
                    constant: -layoutPadding,
                ),

                // Bottom camera controls are placed above the Proceed button with a fixed margin.
                cameraBottomBar.bottomAnchor.constraint(
                    equalTo: cameraModeProceedButton.topAnchor,
                    constant: -layoutPadding,
                ),
            ]
        }

        // Along the trailing edge of the screen with a fixed margin, vertically centered.
        // Note that `cameraSideBar` might be hidden.
        if let cameraSideBar {
            constraints += [
                cameraSideBar.trailingAnchor.constraint(
                    equalTo: topLevelContentContainer.trailingAnchor,
                    constant: -layoutPadding,
                ),
                cameraSideBar.cameraCaptureControl.shutterButtonLayoutGuide.centerYAnchor.constraint(
                    equalTo: topLevelContentContainer.centerYAnchor,
                ),
            ]
        }

        // Camera Zoom control:
        // * wide layout: along the leading edge of the screen, centered vertically.
        // * narrow layout: above camera shutter with a fixed spacing, centered horizontally.
        if let cameraZoomControlsView {
            if isWideLayout {
                constraints += [
                    cameraZoomControlsView.leadingAnchor.constraint(
                        equalTo: topLevelContentContainer.leadingAnchor,
                        constant: layoutPadding,
                    ),
                    cameraZoomControlsView.centerYAnchor.constraint(
                        equalTo: topLevelContentContainer.centerYAnchor,
                    ),
                ]
            } else {
                constraints += [
                    cameraZoomControlsView.bottomAnchor.constraint(
                        equalTo: cameraBottomBar.topAnchor,
                        constant: -16,
                    ),
                    cameraZoomControlsView.centerXAnchor.constraint(
                        equalTo: topLevelContentContainer.centerXAnchor,
                    ),
                ]
            }
        }

        // Text Editor constraints.
        if isTextEditorUIInitialized, let composerTypeSelectionControl {
            // Text composer toolbar:
            // * wide layout: along the trailing edge of the screen, centered vertically.
            // * narrow layout: along the leading edge of the screen, fixed distance above CAMERA | TEXT control.
            if isWideLayout {
                constraints += [
                    textEditorToolbar.trailingAnchor.constraint(
                        equalTo: topLevelContentContainer.trailingAnchor,
                        constant: -layoutPadding,
                    ),
                    textEditorToolbar.centerYAnchor.constraint(
                        equalTo: topLevelContentContainer.centerYAnchor,
                    ),
                ]
            } else {
                constraints += [
                    textEditorToolbar.leadingAnchor.constraint(
                        equalTo: topLevelContentContainer.leadingAnchor,
                        constant: layoutPadding,
                    ),
                    textEditorToolbar.bottomAnchor.constraint(
                        equalTo: composerTypeSelectionControl.topAnchor,
                        constant: -layoutPadding,
                    ),
                ]
            }

            if
                let textStoryComposerContentLayoutGuideBottomPad,
                let textStoryComposerContentLayoutGuideBottomPhone
            {
                if isWideLayout {
                    constraints.append(textStoryComposerContentLayoutGuideBottomPad)
                } else {
                    constraints.append(textStoryComposerContentLayoutGuideBottomPhone)
                }
            }
        }

        return constraints
    }

    private func constraintsForPhoneLayout() -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()

        // Constraint for position of the top edge of the content view - created earlier.
        if let contentViewTopEdgeConstraintPhoneLayout {
            constraints.append(contentViewTopEdgeConstraintPhoneLayout)
        }

        // Content view is full-width.
        constraints += [
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]

        // Fix content view at 9:16 aspect ratio.
        // Note that there's no constraint on the bottom edge of the `contentView`
        // because this type of layout is only used on iPhones with 9:19 and taller screen aspect ratios.
        constraints.append(contentView.heightAnchor.constraint(
            equalTo: contentView.widthAnchor,
            multiplier: 16 / 9,
        ))

        // Top bar: vertically aligned with camera viewfinder / text story composer area.
        constraints.append(topBar.topAnchor.constraint(
            equalTo: contentView.topAnchor,
        ))

        // Camera controls are placed above the bottom edge of the camera viewfinder with a fixed inset.
        constraints.append(cameraBottomBar.photoLibraryButton.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor,
            constant: -bottomBarLayoutMargin,
        ))

        // CAMERA | TEXT control has a fixed spacing below the content view.
        if let composerTypeSelectionControl {
            constraints.append(composerTypeSelectionControl.topAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: 16,
            ))
        }

        // Camera Zoom control: above camera shutter with a fixed spacing, horizontally centered.
        if let cameraZoomControlsView {
            constraints += [
                cameraZoomControlsView.bottomAnchor.constraint(equalTo: cameraBottomBar.topAnchor, constant: -44),
                cameraZoomControlsView.centerXAnchor.constraint(equalTo: cameraBottomBar.centerXAnchor),
            ]
        }

        // Camera mode proceed button:
        // * horizontal: aligned to the trailing edge of the screen.
        // * vertical: below camera viewfinder, aligned with CAMERA | TEXT control if it's there.
        constraints.append(cameraModeProceedButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor))
        if let composerTypeSelectionControl {
            constraints.append(cameraModeProceedButton.centerYAnchor.constraint(
                equalTo: composerTypeSelectionControl.centerYAnchor,
            ))
        } else {
            constraints.append(cameraModeProceedButton.topAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: 28,
            ))
        }

        if isTextEditorUIInitialized {
            // Text composer toolbar is pinned to the bottom leading of the composer area with a fixed padding.
            let layoutMargin = OWSTableViewController2.defaultHOuterMargin
            constraints += [
                textEditorToolbar.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor,
                    constant: layoutMargin,
                ),
                textEditorToolbar.bottomAnchor.constraint(
                    equalTo: textStoryComposerView.bottomAnchor,
                    constant: -layoutMargin,
                ),
            ]

            if let textStoryComposerContentLayoutGuideBottomPhone {
                constraints.append(textStoryComposerContentLayoutGuideBottomPhone)
            }
        }

        return constraints
    }

    private func constraintsForLegacyPhoneLayout() -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()

        // Full-screen content view.
        constraints += [
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]

        // Top bar: attached to view's top safe area.
        constraints.append(topBar.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor,
        ))

        // CAMERA | TEXT control, bottom camera controls, Proceed button.
        let verticalSpacing: CGFloat = 28
        // Proceed button is horizontally aligned to the trailing edge of the screen.
        constraints.append(cameraModeProceedButton.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -verticalSpacing,
        ))

        if let composerTypeSelectionControl {
            constraints += [
                // CAMERA | TEXT control is pinned to the bottom of the screen with a fixed margin.
                composerTypeSelectionControl.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor,
                    constant: -verticalSpacing,
                ),

                // Camera controls are placed above CAMERA | TEXT with a fixed margin.
                cameraBottomBar.bottomAnchor.constraint(
                    equalTo: composerTypeSelectionControl.topAnchor,
                    constant: -verticalSpacing,
                ),

                // Proceed button is centered vertically with CAMERA | TEXT control.
                cameraModeProceedButton.centerYAnchor.constraint(
                    equalTo: composerTypeSelectionControl.centerYAnchor,
                ),
            ]
        } else {
            constraints += [
                // Proceed button is pinned to the bottom of the screen with a fixed margin.
                cameraModeProceedButton.bottomAnchor.constraint(
                    equalTo: contentView.bottomAnchor,
                    constant: -verticalSpacing,
                ),

                // Camera controls are placed above the Proceed button with a fixed margin.
                cameraBottomBar.bottomAnchor.constraint(
                    equalTo: cameraModeProceedButton.topAnchor,
                    constant: -verticalSpacing,
                ),
            ]
        }

        // Camera Zoom control: above camera shutter with a fixed spacing, horizontally centered.
        if let cameraZoomControlsView {
            constraints += [
                cameraZoomControlsView.bottomAnchor.constraint(equalTo: cameraBottomBar.topAnchor, constant: -16),
                cameraZoomControlsView.centerXAnchor.constraint(equalTo: cameraBottomBar.centerXAnchor),
            ]
        }

        if isTextEditorUIInitialized, let composerTypeSelectionControl {
            // Toolbar is placed above CAMERA | TEXT control with a fixed spacing,
            // along the leading edge with a standard padding.
            let layoutMargin = OWSTableViewController2.defaultHOuterMargin
            constraints += [
                textEditorToolbar.leadingAnchor.constraint(
                    equalTo: contentView.leadingAnchor,
                    constant: layoutMargin,
                ),
                textEditorToolbar.bottomAnchor.constraint(
                    equalTo: composerTypeSelectionControl.topAnchor,
                    constant: -verticalSpacing,
                ),
            ]

            if let textStoryComposerContentLayoutGuideBottomPhone {
                constraints.append(textStoryComposerContentLayoutGuideBottomPhone)
            }
        }

        return constraints
    }

    private func initializeUI() {
        // `contentView` is the container view for camera viewfinder and text story editor.
        contentView.clipsToBounds = true
        contentView.preservesSuperviewLayoutMargins = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        // Variable top margin used in `phone` layout.
        // Constrain to the top of the view now and update offset with the height of top safe area later.
        // Can't constrain to the safe area layout guide because safe area insets changes during interactive dismiss.
        contentViewTopEdgeConstraintPhoneLayout = contentView.topAnchor.constraint(equalTo: view.topAnchor)

        // Step 1.
        // Initialize UI elements that are used on all devices and set up permanently active constraints.

        // Camera Viewfinder - always occupies the entire frame of `contentView`.
        previewView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        configureCameraGestures()

        // Top Bar
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.closeButton.addAction(
            UIAction { [weak self] _ in self?.didTapClose() },
            for: .primaryActionTriggered,
        )
        topBar.captureModeButton.addAction(
            UIAction { [weak self] _ in self?.didTapBatchMode() },
            for: .primaryActionTriggered,
        )
        topBar.flashModeButton.addAction(
            UIAction { [weak self] _ in self?.didTapFlashMode() },
            for: .primaryActionTriggered,
        )
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            // Vertical position constraint is device-dependent.
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Bottom Bar
        cameraBottomBar.translatesAutoresizingMaskIntoConstraints = false
        cameraBottomBar.photoLibraryButton.addAction(
            UIAction { [weak self] _ in self?.didTapPhotoLibrary() },
            for: .primaryActionTriggered,
        )
        cameraBottomBar.switchCameraButton.addAction(
            UIAction { [weak self] _ in self?.switchCameraPosition() },
            for: .primaryActionTriggered,
        )
        view.addSubview(cameraBottomBar)
        NSLayoutConstraint.activate([
            cameraBottomBar.photoLibraryButton.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: bottomBarLayoutMargin,
            ),
            cameraBottomBar.switchCameraButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -bottomBarLayoutMargin,
            ),
            // Vertical position constraints are device-dependent.
        ])

        // Content type (CAMERA | TEXT) selection control. Not added when camera is launched from the chat.
        if delegate?.photoCaptureViewControllerCanShowTextEditor(self) ?? false {
            let composerTypeSelectionControl = ComposerTypeSelectionControl()
            composerTypeSelectionControl.selectedSegmentIndex = 0
            composerTypeSelectionControl.translatesAutoresizingMaskIntoConstraints = false
            composerTypeSelectionControl.addAction(
                UIAction { [weak self] _ in self?.didTapChangeComposerMode() },
                for: .valueChanged,
            )
            view.addSubview(composerTypeSelectionControl)

            // Horizontal position is fixed for all devices.
            // Vertical position varies between layouts.
            NSLayoutConstraint.activate([
                composerTypeSelectionControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            ])

            self.composerTypeSelectionControl = composerTypeSelectionControl
        }

        // Zoom control.
        if let cameraZoomControlsView = CameraZoomControlsView(cameraCaptureSession: cameraCaptureSession, axis: .horizontal) {
            cameraZoomControlsView.frontCameraZoomControl?.delegate = self
            cameraZoomControlsView.rearCameraZoomControl?.delegate = self
            cameraZoomControlsView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(cameraZoomControlsView)

            self.cameraZoomControlsView = cameraZoomControlsView

            // No constraints added here because position is device-dependent.
        }

        // > Proceed Button
        cameraModeProceedButton.isHidden = true
        cameraModeProceedButton.translatesAutoresizingMaskIntoConstraints = false
        cameraModeProceedButton.addAction(
            UIAction { [weak self] _ in self?.didTapCameraModeProceedButton() },
            for: .primaryActionTriggered,
        )
        view.addSubview(cameraModeProceedButton)

        // Focusing frame
        previewView.addSubview(tapToFocusView)
        NSLayoutConstraint.activate([tapToFocusCenterXConstraint, tapToFocusCenterYConstraint])

        // Step 2.
        // Activate constraints for the current layout and update control states.
        updateInterfaceForCurrentViewState(animated: false)

        updateUIOnCameraPositionChange()

        isInitialUISetupComplete = true
    }

    private func initializeCameraSideBar() {
        guard cameraSideBar == nil else { return }

        let sideBar = CameraSideBar(frame: .zero)
        sideBar.cameraCaptureControl.delegate = cameraCaptureSession
        sideBar.captureModeButton.mode = topBar.captureModeButton.mode
        sideBar.captureModeButton.addAction(
            UIAction { [weak self] _ in self?.didTapBatchMode() },
            for: .primaryActionTriggered,
        )
        sideBar.flashModeButton.addAction(
            UIAction { [weak self] _ in self?.didTapFlashMode() },
            for: .primaryActionTriggered,
        )
        sideBar.switchCameraButton.addAction(
            UIAction { [weak self] _ in self?.switchCameraPosition() },
            for: .primaryActionTriggered,
        )
        sideBar.photoLibraryButton.addAction(
            UIAction { [weak self] _ in self?.didTapPhotoLibrary() },
            for: .primaryActionTriggered,
        )
        view.addSubview(sideBar)
        sideBar.translatesAutoresizingMaskIntoConstraints = false

        // Pinned to the trailing edge of camera viewfinder, shutter button centered vertically.
        NSLayoutConstraint.activate([
            sideBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -28,
            ),
            sideBar.cameraCaptureControl.shutterButtonLayoutGuide.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor,
            ),
        ])
        self.cameraSideBar = sideBar

        updateFlashModeControl(animated: false)
    }

    private func updateUIOnCameraPositionChange(animated: Bool = false) {
        let isFrontCameraActive = cameraCaptureSession.desiredPosition == .front
        if let cameraZoomControlsView {
            cameraZoomControlsView.setIsFrontCameraActive(isFrontCameraActive, animated: animated)
        }
        cameraBottomBar.setIsFrontCameraActive(isFrontCameraActive, animated: animated)
        if let cameraSideBar {
            cameraSideBar.setIsFrontCameraActive(isFrontCameraActive, animated: animated)
        }
    }

    private func updateButtonIconOrientations(isAnimated: Bool, captureOrientation: AVCaptureVideoOrientation) {
        guard UIDevice.current.isIPad == false else { return }

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
        let transformFromCameraType: CGAffineTransform = cameraCaptureSession.desiredPosition == .front ? CGAffineTransform(rotationAngle: -.pi) : .identity

        var buttonsToUpdate: [UIView] = [topBar.captureModeButton, topBar.flashModeButton, cameraBottomBar.photoLibraryButton]
        if let cameraZoomControlsView {
            if let frontCameraZoomControl = cameraZoomControlsView.frontCameraZoomControl {
                buttonsToUpdate.append(contentsOf: frontCameraZoomControl.cameraZoomLevelIndicators)
            }
            if let rearCameraZoomControl = cameraZoomControlsView.rearCameraZoomControl {
                buttonsToUpdate.append(contentsOf: rearCameraZoomControl.cameraZoomLevelIndicators)
            }
        }

        let updateOrientation = {
            buttonsToUpdate.forEach { $0.transform = transformFromOrientation }
            self.cameraBottomBar.switchCameraButton.transform = transformFromOrientation.concatenating(transformFromCameraType)
        }

        if isAnimated {
            UIView.animate(withDuration: 0.3, animations: updateOrientation)
        } else {
            updateOrientation()
        }
    }

    // MARK: - Text Editor

    private func initializeTextEditorUI() {
        guard isTextEditorUIInitialized == false else { return }

        // Text story composer view.
        textStoryComposerView.delegate = self
        textStoryComposerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(textStoryComposerView, aboveSubview: previewView)

        // Text composer area occupies entire `contentView`, just like camera viewfinder does.
        NSLayoutConstraint.activate([
            textStoryComposerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textStoryComposerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textStoryComposerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textStoryComposerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Swipe right to switch to camera.
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeToCamera(gesture:)))
        swipeGesture.direction = CurrentAppContext().isRTL ? .left : .right
        textStoryComposerView.addGestureRecognizer(swipeGesture)

        // Choose Background and Attach Link buttons.
        textEditorToolbar.attachLinkButton.addAction(
            UIAction { [weak self] _ in
                self?.didTapAttachLinkPreviewButton()
            },
            for: .primaryActionTriggered,
        )
        textEditorToolbar.backgroundSelectionButton.addAction(
            UIAction { [weak self] _ in
                self?.didTapTextBackgroundButton()
            },
            for: .primaryActionTriggered,
        )
        updateTextBackgroundSelectionButton()
        textEditorToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textEditorToolbar)

        // > Proceed button without a badge.
        textStoryModeProceedButton.isEnabled = false
        textStoryModeProceedButton.addAction(
            UIAction { [weak self] _ in
                self?.didTapTextStoryProceedButton()
            },
            for: .primaryActionTriggered,
        )
        textStoryModeProceedButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textStoryModeProceedButton)
        // Proceed button in text story composer mode is the same as in camera mode.
        NSLayoutConstraint.activate([
            textStoryModeProceedButton.centerXAnchor.constraint(
                equalTo: cameraModeProceedButton.centerXAnchor,
            ),
            textStoryModeProceedButton.centerYAnchor.constraint(
                equalTo: cameraModeProceedButton.centerYAnchor,
            ),
        ])

        // These define bottom edge of the area that contains text view and link preview inside of the `textStoryComposerView`.
        // Initially the bottom edge is pinned to the top of `textEditorToolbar`.
        // If on-screen keyboard appears the constraint is updated so that content clears the keyboard.
        textStoryComposerContentLayoutGuideBottomPhone = textStoryComposerView.contentLayoutGuide.bottomAnchor.constraint(
            equalTo: textEditorToolbar.topAnchor,
        )
        textStoryComposerContentLayoutGuideBottomPad = textStoryComposerView.contentLayoutGuide.bottomAnchor.constraint(
            equalTo: textStoryComposerView.bottomAnchor,
        )

        isTextEditorUIInitialized = true

        // Re-apply constraints now that we have UI elements.
        updateInterfaceForCurrentViewState(animated: false)
    }

    private func updateTextEditorToolbarVisibility(animated: Bool) {
        let isTextEditorToolbarHidden = textStoryComposerView.isEditing || composerMode != .text
        textEditorToolbar.setIsHidden(isTextEditorToolbarHidden, animated: animated)
        // Hide CAMERA | TEXT control and Proceed button too.
        composerTypeSelectionControl?.setIsHidden(isTextEditorToolbarHidden, animated: animated)
        textStoryModeProceedButton.setIsHidden(isTextEditorToolbarHidden, animated: animated)
    }

    // Update background of the background selection button to match the editor.
    private func updateTextBackgroundSelectionButton() {
        textEditorToolbar.backgroundSelectionButton.background = textStoryComposerView.background
    }

    // MARK: - Keyboard Handling

    private func startObservingKeyboardNotifications() {
        guard !observingKeyboardNotifications else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        observingKeyboardNotifications = true
    }

    @objc
    private func handleKeyboardNotification(_ notification: Notification) {
        guard composerMode == .text else { return }

        guard
            let constraintPhone = textStoryComposerContentLayoutGuideBottomPhone,
            let constraintPad = textStoryComposerContentLayoutGuideBottomPad else { return }

        guard
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        // Detect floating keyboards - those should not adjust bottom inset for text input area.
        // Note that floating keyboard could co-exist with iPhone-like layouts.
        let keyboardFrame = textStoryComposerView.convert(endFrame, from: nil)
        let isNonFloatingKeyboardVisible = keyboardFrame.height > 0 &&
            keyboardFrame.minX <= textStoryComposerView.bounds.minX &&
            keyboardFrame.maxX >= textStoryComposerView.bounds.maxX

        let insetPhone: CGFloat
        let insetPad: CGFloat
        if isNonFloatingKeyboardVisible {
            let convertedKeyboardFrame = textEditorToolbar.convert(keyboardFrame, from: textStoryComposerView)
            insetPhone = convertedKeyboardFrame.minY - textEditorToolbar.bounds.maxY
            insetPad = keyboardFrame.minY - textStoryComposerView.bounds.maxY
        } else {
            insetPhone = textEditorToolbar.bounds.height
            insetPad = 0
        }

        let layoutUpdateBlock = {
            constraintPhone.constant = min(insetPhone, 0) - 8
            constraintPad.constant = min(insetPad, 0) - 8
        }
        if
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)
        {
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                options: animationCurve.asAnimationOptions,
                animations: { [self] in
                    layoutUpdateBlock()
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                },
            )
        } else {
            UIView.performWithoutAnimation {
                layoutUpdateBlock()
            }
        }
    }

    // MARK: - Button Actions

    private func didTapTextBackgroundButton() {
        textStoryComposerView.switchToNextBackground()
        updateTextBackgroundSelectionButton()
    }

    private func didTapAttachLinkPreviewButton() {
        let linkPreviewViewController = LinkPreviewAttachmentViewController(textStoryComposerView.linkPreviewDraft)
        linkPreviewViewController.delegate = self
        present(linkPreviewViewController, animated: true)
    }

    private func didTapTextStoryProceedButton() {
        let body: StyleOnlyMessageBody
        let textStyle: TextAttachment.TextStyle
        switch textStoryComposerView.textContent {
        case .empty:
            body = StyleOnlyMessageBody(plaintext: "")
            textStyle = .regular
        case .styledRanges(let contentBody):
            body = contentBody
            textStyle = .regular
        case .styled(let text, let style):
            body = StyleOnlyMessageBody(plaintext: text)
            textStyle = style
        }
        let textForegroundColor = textStoryComposerView.textForegroundColor
        let textBackgroundColor = textStoryComposerView.textBackgroundColor
        let background = textStoryComposerView.background

        // Styles are used only when forwading; we only get plaintext here.
        let unsentTextAttachment = UnsentTextAttachment(
            body: body,
            textStyle: textStyle,
            textForegroundColor: textForegroundColor,
            textBackgroundColor: textBackgroundColor,
            background: background,
            linkPreviewDraft: textStoryComposerView.linkPreviewDraft,
        )

        delegate?.photoCaptureViewController(self, didFinishWithTextAttachment: unsentTextAttachment)
    }

    @objc
    func didSwipeToCamera(gesture: UISwipeGestureRecognizer) {
        guard composerMode == .text else { return }
        setComposerMode(.camera, animated: true)
    }

    // MARK: - TextStoryComposerViewDelegate

    fileprivate func textStoryComposerDidBeginEditing(_ textStoryComposer: TextStoryComposerView) {
        updateCameraBottomBarVisibility(animated: true)
        updateTextEditorToolbarVisibility(animated: true)
    }

    fileprivate func textStoryComposerDidEndEditing(_ textStoryComposer: TextStoryComposerView) {
        updateCameraBottomBarVisibility(animated: true)
        updateTextEditorToolbarVisibility(animated: true)
    }

    fileprivate func textStoryComposerDidChange(_ textStoryComposer: TextStoryComposerView) {
        textStoryModeProceedButton.isEnabled = !textStoryComposer.isEmpty
    }

    // MARK: - LinkPreviewAttachmentViewControllerDelegate

    func linkPreviewAttachmentViewController(
        _ viewController: LinkPreviewAttachmentViewController,
        didFinishWith linkPreview: OWSLinkPreviewDraft,
    ) {
        textStoryComposerView.linkPreviewDraft = linkPreview
        viewController.dismiss(animated: true)
    }

    // MARK: - Button Actions

    private func didTapClose() {
        delegate?.photoCaptureViewControllerDidCancel(self)
    }

    private func switchCameraPosition() {
        if let switchCameraButton = layout == .pad ? cameraSideBar?.switchCameraButton : cameraBottomBar.switchCameraButton {
            switchCameraButton.performSwitchAnimation()
        }
        cameraCaptureSession.switchCameraPosition().done { [weak self] in
            self?.updateUIOnCameraPositionChange(animated: true)
            self?.cameraCaptureSession.updateVideoCaptureOrientation()
        }.catch { error in
            self.showFailureUI(error: error)
        }
    }

    private func didTapFlashMode() {
        cameraCaptureSession.toggleFlashMode().done {
            self.updateFlashModeControl(animated: true)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func didTapBatchMode() {
        guard let delegate else {
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
            }
        }
    }

    private func didTapPhotoLibrary() {
        delegate?.photoCaptureViewControllerDidRequestPresentPhotoLibrary(self)
    }

    private func didTapCameraModeProceedButton() {
        delegate?.photoCaptureViewControllerDidFinish(self)
    }

    private func didTapChangeComposerMode() {
        guard
            let composerTypeSelectionControl,
            let newComposerMode = ComposerMode(rawValue: composerTypeSelectionControl.selectedSegmentIndex)
        else {
            return
        }
        setComposerMode(newComposerMode, animated: true)
    }

    // MARK: - Camera Gesture Recognizers

    private func configureCameraGestures() {
        previewView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(didPinchZoom(pinchGesture:))))

        let doubleTapToSwitchCameraGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTapToSwitchCamera(tapGesture:)))
        doubleTapToSwitchCameraGesture.numberOfTapsRequired = 2
        previewView.addGestureRecognizer(doubleTapToSwitchCameraGesture)

        let tapToFocusGesture = UITapGestureRecognizer(target: self, action: #selector(didTapFocusExpose(tapGesture:)))
        tapToFocusGesture.require(toFail: doubleTapToSwitchCameraGesture)
        previewView.addGestureRecognizer(tapToFocusGesture)

        // Swipe left to switch to text story composer.
        if composerTypeSelectionControl != nil {
            let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeToTextComposer(gesture:)))
            swipeGesture.direction = CurrentAppContext().isRTL ? .right : .left
            previewView.addGestureRecognizer(swipeGesture)
        }
    }

    @objc
    private func didPinchZoom(pinchGesture: UIPinchGestureRecognizer) {
        switch pinchGesture.state {
        case .began:
            cameraCaptureSession.beginPinchZoom()
            fallthrough
        case .changed:
            cameraCaptureSession.updatePinchZoom(withScale: pinchGesture.scale)
        case .ended:
            cameraCaptureSession.completePinchZoom(withScale: pinchGesture.scale)
        default:
            break
        }
    }

    @objc
    private func didDoubleTapToSwitchCamera(tapGesture: UITapGestureRecognizer) {
        guard !isRecordingVideo else {
            // - Orientation gets out of sync when switching cameras mid movie.
            // - Audio gets out of sync when switching cameras mid movie
            // https://stackoverflow.com/questions/13951182/audio-video-out-of-sync-after-switch-camera
            return
        }

        switchCameraPosition()
    }

    @objc
    private func didTapFocusExpose(tapGesture: UITapGestureRecognizer) {
        let viewLocation = tapGesture.location(in: previewView)
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: viewLocation)
        cameraCaptureSession.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        lastUserFocusTapPoint = devicePoint

        if let focusFrameSuperview = tapToFocusView.superview {
            positionTapToFocusView(center: tapGesture.location(in: focusFrameSuperview))
            startFocusAnimation()
        }
    }

    @objc
    private func didSwipeToTextComposer(gesture: UISwipeGestureRecognizer) {
        guard composerMode == .camera else { return }
        guard cameraBottomBar.captureControl.recordingState == .notRecording else { return }
        setComposerMode(.text, animated: true)
    }

    // MARK: - Tap to Focus

    private func positionTapToFocusView(center: CGPoint) {
        tapToFocusCenterXConstraint.constant = center.x
        tapToFocusCenterYConstraint.constant = center.y
    }

    private func startFocusAnimation() {
        tapToFocusView.stop()
        tapToFocusView.play(fromProgress: 0.0, toProgress: 0.9)
    }

    private func completeFocusAnimation(forFocusPoint focusPoint: CGPoint) {
        guard let lastUserFocusTapPoint else { return }

        guard lastUserFocusTapPoint.within(0.005, of: focusPoint) else {
            return
        }

        tapToFocusView.play(toProgress: 1.0)
    }

    // MARK: - Photo Capture

    private func setupPhotoCapture() {
        cameraBottomBar.captureControl.delegate = cameraCaptureSession
        if let cameraSideBar {
            cameraSideBar.cameraCaptureControl.delegate = cameraCaptureSession
        }

        // If the session is already running, we're good to go.
        guard !cameraCaptureSession.avCaptureSession.isRunning else {
            self.hasCameraStarted = true
            return
        }

        firstly {
            cameraCaptureSession.prepare()
        }.catch { [weak self] error in
            guard let self else { return }
            self.showFailureUI(error: error)
        }
    }

    private func pausePhotoCapture() {
        guard cameraCaptureSession.avCaptureSession.isRunning else { return }
        cameraCaptureSession.stop().done { [weak self] in
            self?.hasCameraStarted = false
        }.catch { [weak self] error in
            self?.showFailureUI(error: error)
        }
    }

    private func resumePhotoCapture() {
        guard !cameraCaptureSession.avCaptureSession.isRunning else { return }
        cameraCaptureSession.resume().done { [weak self] in
            self?.hasCameraStarted = true
        }.catch { [weak self] error in
            self?.showFailureUI(error: error)
        }
    }

    private func showFailureUI(error: Error) {
        Logger.warn("error: \(error)")
        OWSActionSheets.showActionSheet(
            title: nil,
            message: error.userErrorDescription,
            buttonTitle: CommonStrings.dismissButton,
            buttonAction: { [weak self] _ in self?.dismiss(animated: true) },
        )
    }

    private func updateFlashModeControl(animated: Bool) {
        topBar.flashModeButton.setMode(cameraCaptureSession.flashMode, animated: animated)
        if let cameraSideBar {
            cameraSideBar.flashModeButton.setMode(cameraCaptureSession.flashMode, animated: animated)
        }
    }

    // MARK: - InteractiveDismissDelegate

    func interactiveDismissDidBegin(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        if bottomAreaProtectionView != nil {
            view.backgroundColor = .clear
        }
    }

    func interactiveDismiss(
        _ interactiveDismiss: UIPercentDrivenInteractiveTransition,
        didChangeProgress: CGFloat,
        touchOffset: CGPoint,
    ) { }

    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        dismiss(animated: true)
    }

    func interactiveDismissDidCancel(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        // Undo changes potentially made in `interactiveDismissDidBegin()`.
        view.backgroundColor = .Signal.mediaBackground
    }

    // MARK: - CameraZoomSelectionControlDelegate

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didSelect camera: CameraCaptureSession.CameraType) {
        guard let cameraZoomControlsView else {
            owsFailDebug("cameraZoomControlsView is nil")
            return
        }
        let position: AVCaptureDevice.Position = cameraZoomControl == cameraZoomControlsView.frontCameraZoomControl ? .front : .back
        cameraCaptureSession.switchCamera(to: camera, at: position, animated: true)
    }

    func cameraZoomControl(_ cameraZoomControl: CameraZoomSelectionControl, didChangeZoomFactor zoomFactor: CGFloat) {
        cameraCaptureSession.changeVisibleZoomFactor(to: zoomFactor, animated: true)
    }

    // MARK: - QRCodeSampleBufferScannerDelegate

    var shouldProcessQRCodes: Bool {
        _shouldProcessQRCodes.get()
    }

    @MainActor
    func qrCodeSampleBufferScanner(
        _ sampleBufferScanner: QRCodeSampleBufferScanner,
        didFindStringValue stringValue: String?,
        dataValue: Data?,
    ) {
        guard let qrCodeString = stringValue else {
            return
        }

        if
            let url = URL(string: qrCodeString),
            let usernameLink = Usernames.UsernameLink(usernameLinkUrl: url)
        {
            qrCodeScanned = true

            Task {
                guard
                    let (username, aci) = await UsernameQuerier().queryForUsernameLink(
                        link: usernameLink,
                        fromViewController: self,
                        failureSheetDismissalDelegate: self,
                    )
                else {
                    return
                }

                showUsernameLinkSheet(username: username, aci: aci)
            }
        } else if let provisioningURL = DeviceProvisioningURL(urlString: qrCodeString) {

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            switch provisioningURL.linkType {
            case .linkDevice where registeredState?.isPrimary == true:
                qrCodeScanned = true
                let linkDeviceWarningActionSheet = ActionSheetController(
                    message: OWSLocalizedString(
                        "LINKED_DEVICE_URL_OPENED_ACTION_SHEET_IN_APP_CAMERA_MESSAGE",
                        comment: "Message for an action sheet telling users how to link a device, when trying to open a device-linking URL from the in-app camera.",
                    ),
                )

                let showLinkedDevicesAction = ActionSheetAction(title: CommonStrings.continueButton) { _ in
                    self.dismiss(animated: true) {
                        SignalApp.shared.showAppSettings(mode: .linkedDevices)
                    }
                }

                let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton) { _ in
                    self.qrCodeScanned = false
                }

                linkDeviceWarningActionSheet.addAction(showLinkedDevicesAction)
                linkDeviceWarningActionSheet.addAction(cancelAction)
                presentActionSheet(linkDeviceWarningActionSheet)

            case .quickRestore:
                qrCodeScanned = true
                let presentBlock = {
                    self.dismiss(animated: true) {
                        AppEnvironment.shared.outgoingDeviceRestorePresenter.present(
                            provisioningURL: provisioningURL,
                            presentingViewController: CurrentAppContext().frontmostViewController()!,
                            animated: true,
                        )
                    }
                }
                // If anything is presented over the phone capture view, dismiss it first -
                // then dismiss the photo view and present the restore UI
                if navigationController?.presentedViewController != nil {
                    self.navigationController?.presentedViewController?.dismiss(animated: true) {
                        presentBlock()
                    }
                } else {
                    presentBlock()
                }

            case .linkDevice:
                Logger.warn("Scanned linkDevice provisioning URL, but not a registered primary.")
            }
        }
    }

    @MainActor
    func qrCodeSampleBufferScanner(_ sampleBufferScanner: QRCodeSampleBufferScanner, didFailWithError error: any Error) {
        self.showFailureUI(error: error)
    }

    private func showUsernameLinkSheet(username: String, aci: Aci) {
        // `shouldProcessQRCodes` should prevent QR codes being scanned after a
        // recording is done, but a race condition between the recording ending
        // and this view hiding can allow a scan to slip through, so do an extra
        // check after the username is queried before showing the sheet.
        guard isViewVisible else { return }
        OWSActionSheets.showConfirmationAlert(
            title: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "PHOTO_CAPTURE_USERNAME_QR_CODE_FOUND_TITLE_FORMAT",
                    comment: "Title for sheet presented from photo capture view indicating that a username QR code was found. Embeds {{username}}.",
                ),
                username,
            ),
            message: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "PHOTO_CAPTURE_USERNAME_QR_CODE_FOUND_MESSAGE_FORMAT",
                    comment: "Message for a sheet presented from photo capture view indicating that a username QR code was found. Embeds {{username}}.",
                ),
                username,
            ),
            proceedTitle: OWSLocalizedString(
                "PHOTO_CAPTURE_USERNAME_QR_CODE_FOUND_CTA",
                comment: "Button label for opening the chat on a sheet presented from photo capture view indicating that a username QR code was found.",
            ),
            proceedAction: { [weak self] _ in
                SignalApp.shared.presentConversationForAddress(
                    SignalServiceAddress(aci),
                    animated: false,
                )
                self?.dismiss(animated: true)
            },
            fromViewController: self,
            dismissalDelegate: self,
        )
    }

    // MARK: - SheetDismissalDelegate

    func didDismissPresentedSheet() {
        // Allow another QR code to be scanned
        qrCodeScanned = false
    }

    // MARK: - CameraCaptureSessionDelegate

    // MARK: Photo

    func cameraCaptureSessionDidStart(_ session: CameraCaptureSession) {
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

    func cameraCaptureSession(_ session: CameraCaptureSession, didFinishProcessing attachment: PreviewableAttachment) {
        dataSource?.addMedia(attachment: attachment)

        updateCameraModeProceedButtonBadgeAndVisibility(animated: true)

        if captureMode == .multi {
            resumePhotoCapture()
        } else {
            delegate?.photoCaptureViewControllerDidFinish(self)
        }
    }

    func cameraCaptureSession(_ session: CameraCaptureSession, didFailWith error: Error) {
        setIsRecordingVideo(false, animated: true)

        if error is VideoCaptureFailedError {
            // Don't show an error if the user aborts recording before video
            // recording has begun.
            return
        }
        showFailureUI(error: error)
    }

    func cameraCaptureSessionCanCaptureMoreItems(_ session: CameraCaptureSession) -> Bool {
        return delegate?.photoCaptureViewControllerCanCaptureMoreItems(self) ?? false
    }

    func photoCaptureDidTryToCaptureTooMany(_ session: CameraCaptureSession) {
        delegate?.photoCaptureViewControllerDidTryToCaptureTooMany(self)
    }

    // MARK: Video

    func cameraCaptureSessionWillStartVideoRecording(_ session: CameraCaptureSession) {
        setIsRecordingVideo(true, animated: true)
    }

    func cameraCaptureSessionDidStartVideoRecording(_ session: CameraCaptureSession) {
    }

    func cameraCaptureSessionDidStopVideoRecording(_ session: CameraCaptureSession) {
        setIsRecordingVideo(false, animated: true)
    }

    func cameraCaptureSession(_ session: CameraCaptureSession, videoRecordingDurationChanged duration: TimeInterval) {
        topBar.recordingTimerView.duration = duration
    }

    // MARK: UI

    var zoomScaleReferenceDistance: CGFloat? {
        guard let cameraZoomControlsView else { return nil }
        return 0.5 * (cameraZoomControlsView.axis == .horizontal ? previewView.bounds.height : previewView.bounds.width)
    }

    func cameraCaptureSession(
        _ session: CameraCaptureSession,
        didChangeZoomFactor zoomFactor: CGFloat,
        forCameraPosition position: AVCaptureDevice.Position,
    ) {
        guard
            let cameraZoomControlsView,
            let cameraZoomControl: CameraZoomSelectionControl = position == .front
            ? cameraZoomControlsView.frontCameraZoomControl
            : cameraZoomControlsView.rearCameraZoomControl
        else {
            owsFailDebug("Invalid configuration.")
            return
        }
        cameraZoomControl.currentZoomFactor = zoomFactor
    }

    func beginCaptureButtonAnimation(_ duration: TimeInterval) {
        cameraBottomBar.captureControl.setRecordingState(.recording, animationDuration: duration)
        if let cameraSideBar {
            cameraSideBar.cameraCaptureControl.setRecordingState(.recording, animationDuration: duration)
        }
    }

    func endCaptureButtonAnimation(_ duration: TimeInterval) {
        cameraBottomBar.captureControl.setRecordingState(.notRecording, animationDuration: duration)
        if let cameraSideBar {
            cameraSideBar.cameraCaptureControl.setRecordingState(.notRecording, animationDuration: duration)
        }
    }

    func cameraCaptureSession(_ session: CameraCaptureSession, didChangeOrientation orientation: AVCaptureVideoOrientation) {
        updateButtonIconOrientations(isAnimated: true, captureOrientation: orientation)
        if UIDevice.current.isIPad {
            session.updateVideoPreviewConnection(toOrientation: orientation)
        }
    }

    func cameraCaptureSession(_ session: CameraCaptureSession, didFinishFocusingAt focusPoint: CGPoint) {
        completeFocusAnimation(forFocusPoint: focusPoint)
    }

    @objc
    func sessionWasInterrupted(notification: Notification) {
        if let userInfo = notification.userInfo {
            guard
                let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
                let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue.intValue)
            else {
                Logger.info("session was interrupted for no apparent reason")
                return
            }
            Logger.info("session was interrupted with reason code: \(reason.rawValue)")
        }
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
            style: .regular,
            textForegroundColor: .white,
            textBackgroundColor: nil,
            background: TextStoryComposerView.defaultBackground,
        )

        // Placeholder Label
        textPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textPlaceholderLabel)
        addConstraints([
            textPlaceholderLabel.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            textPlaceholderLabel.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            textPlaceholderLabel.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            textPlaceholderLabel.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])

        // Prepare text styling toolbar - attached to keyboard.
        let toolbarSize = textViewAccessoryToolbar.systemLayoutSizeFitting(
            CGSize(width: UIScreen.main.bounds.width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
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

    override func layoutSubviews() {
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

    override func layoutTextContentAndLinkPreview() {
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
            contentLayoutGuide.layoutFrame.height - linkPreviewAreaHeight - 2 * TextStoryComposerView.textViewBackgroundVMargin,
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
            height: textViewSize.height + 2 * TextStoryComposerView.textViewBackgroundVMargin,
        )
        textViewBackgroundView.center = CGPoint(
            x: contentLayoutGuide.layoutFrame.center.x,
            y: contentLayoutGuide.layoutFrame.center.y - 0.5 * linkPreviewAreaHeight,
        )
        textView.center = textViewBackgroundView.bounds.center

        linkPreviewWrapperView.center = CGPoint(
            x: linkPreviewWrapperView.center.x,
            y: textViewBackgroundView.frame.maxY + LayoutConstants.linkPreviewAreaTopMargin + 0.5 * linkPreviewWrapperView.bounds.height,
        )
    }

    override func calculateTextContentSize() -> CGSize {
        guard isEditing else {
            return super.calculateTextContentSize()
        }
        let maxTextViewSize = contentLayoutGuide.layoutFrame.insetBy(
            dx: LayoutConstants.textBackgroundHMargin,
            dy: TextStoryComposerView.textViewBackgroundVMargin,
        ).size
        return textView.systemLayoutSizeFitting(
            maxTextViewSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
    }

    // MARK: -

    override var isEditing: Bool { textView.isFirstResponder }

    private var text: String? {
        get {
            switch super.textContent {
            case .empty:
                return nil
            case .styledRanges(let body):
                owsFailDebug("Should not have styled ranges in story text composer")
                return body.text
            case .styled(let body, _):
                return body
            }
        }
        set {
            super.textContent = .styled(body: newValue ?? "", style: textStyle)
        }
    }

    private var textStyle: TextAttachment.TextStyle = .regular {
        didSet {
            guard let text else {
                return
            }
            super.textContent = .styled(body: text, style: self.textStyle)
        }
    }

    var isEmpty: Bool {
        guard let text else { return true }
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
        let toolbar = TextStylingToolbar()
        toolbar.addAction(
            UIAction { [weak self] _ in self?.didChangeTextColor() },
            for: .valueChanged,
        )
        toolbar.textStyleButton.addAction(
            UIAction { [weak self] _ in self?.didTapTextStyleButton() },
            for: .primaryActionTriggered,
        )
        toolbar.decorationStyleButton.addAction(
            UIAction { [weak self] _ in self?.didTapDecorationStyleButton() },
            for: .primaryActionTriggered,
        )
        toolbar.doneButton.addAction(
            UIAction { [weak self] _ in self?.didTapTextViewDoneButton() },
            for: .primaryActionTriggered,
        )
        return toolbar
    }()

    private let textPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .ows_whiteAlpha60
        label.font = .dynamicTypeLargeTitle1Clamped
        label.text = OWSLocalizedString(
            "STORY_COMPOSER_TAP_ADD_TEXT",
            comment: "Placeholder text in text stories compose UI",
        )
        return label
    }()

    override func updateVisibilityOfComponents(animated: Bool) {
        super.updateVisibilityOfComponents(animated: animated)

        let isEditing = isEditing
        textPlaceholderLabel.setIsHidden(isEditing || !isEmpty, animated: animated)
        textViewBackgroundView.setIsHidden(!isEditing, animated: animated)
    }

    private func updateTextViewAttributes() {
        let selectedTextRange = textView.selectedTextRange

        let text = text ?? ""
        textView.text = transformedText(text, for: textStyle)

        let (fontPointSize, textAlignment) = sizeAndAlignment(forText: text)
        textView.updateWith(
            textForegroundColor: textForegroundColor,
            font: .font(for: textStyle, withPointSize: fontPointSize),
            textAlignment: textAlignment,
            textDecorationColor: nil,
            decorationStyle: .none,
        )
        textView.selectedTextRange = selectedTextRange
        textViewBackgroundView.backgroundColor = textBackgroundColor
    }

    private func adjustFontSizeIfNecessary() {
        guard let currentFontSize = textView.font?.pointSize else { return }
        let text = text?.stripped ?? ""
        let desiredFontSize = sizeAndAlignment(forText: text).fontPointSize
        guard desiredFontSize != currentFontSize else { return }
        updateTextAttributes()
        updateTextViewAttributes()
    }

    private func validateTextViewAttributes() {
        guard let attributedString = textView.attributedText else { return }

        // Re-apply attributes to the entire text view's text if more than one font style is detected.
        // That could happen as a result of undo / redo operation.
        var shouldReapplyAttributes = false
        var previousFont: UIFont?
        attributedString.enumerateAttribute(.font, in: attributedString.entireRange) { attributeValue, range, stop in
            guard let font = attributeValue as? UIFont else { return }

            if let previousFont, !previousFont.isEqual(font) {
                shouldReapplyAttributes = true
                stop.pointee = true
            }
            previousFont = font
        }
        if shouldReapplyAttributes {
            updateTextViewAttributes()
        }
    }

    @objc
    private func placeholderTapped() {
        if textView.isFirstResponder {
            textView.acceptAutocorrectSuggestion()
            textView.resignFirstResponder()
        } else {
            textView.becomeFirstResponder()
        }
    }

    private func didTapTextStyleButton() {
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

    private func didTapDecorationStyleButton() {
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

    private func didChangeTextColor() {
        // Depending on text decoration style color picker changes either color of the text or background color.
        // That's why we need to update both.
        let textForegroundColor = textViewAccessoryToolbar.textForegroundColor
        let textBackgroundColor = textViewAccessoryToolbar.textBackgroundColor
        setTextForegroundColor(textForegroundColor, backgroundColor: textBackgroundColor)

        updateTextViewAttributes()
    }

    private func didTapTextViewDoneButton() {
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
        text = text?.stripped
        textView.text = text
        updateTextAttributes()
        updateVisibilityOfComponents(animated: true)
        delegate?.textStoryComposerDidEndEditing(self)
    }

    private var updatingTextViewText = false

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {

        guard !updatingTextViewText else { return false }

        let originalInput = text ?? ""
        let (shouldChange, changedString) = TextHelper.shouldChangeCharactersInRange(
            with: originalInput,
            editingRange: range,
            replacementString: replacementText,
            maxGlyphCount: 700,
        )

        if let changedString {
            text = changedString
            textView.text = transformedText(changedString, for: textStyle)
            textView.delegate?.textViewDidChange?(textView)
            return false
        }

        guard shouldChange else {
            return false
        }

        text = (originalInput as NSString).replacingCharacters(in: range, with: replacementText)

        let transformedText = transformedText(text ?? "", for: textStyle)
        guard text == transformedText else {
            // If this method is called as a result of using apple's autocomplete suggestion bar
            // there is a bug where setting the UITextView's text will trigger another call of this delegate
            // method. Inputting text any other way suppresses calls to this delegate method as a result
            // of changes to the text within the method itself. To work around this apple bug, keep track of
            // re-entrancy manually and suppress it ourselves.
            updatingTextViewText = true
            textView.text = transformedText
            textView.delegate?.textViewDidChange?(textView)
            updatingTextViewText = false
            return false
        }

        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        // If you swipe type, a space is inserted between words, by putting that space
        // before the subsequent word in the `shouldChangeTextIn: range:` method.
        // If you swipe type and then tap a single letter, `shouldChangeTextIn:` only gets
        // the letters, NOT the space, but the NSConcreteTextStorage _somehow_ gets that
        // space. In order to avoid this leading to discrepancies between `self.text` and
        // the text being displayed, we sync the two up here, after the space has been applied.
        self.text = transformedText(textView.text ?? "", for: textStyle)
        adjustFontSizeIfNecessary()
        validateTextViewAttributes()
        delegate?.textStoryComposerDidChange(self)
        setNeedsLayout()
    }

    // MARK: - Link Preview

    fileprivate var linkPreviewDraft: OWSLinkPreviewDraft? {
        didSet {
            if let linkPreviewDraft {
                let state: LinkPreviewState
                if let callLink = CallLink(url: linkPreviewDraft.url) {
                    state = LinkPreviewCallLink(previewType: .draft(linkPreviewDraft), callLink: callLink)
                } else {
                    state = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
                }
                linkPreview = state
            } else {
                linkPreview = nil
            }
            delegate?.textStoryComposerDidChange(self)
        }
    }

    private lazy var deleteLinkPreviewButton: UIButton = {
        let button = RoundMediaButton(image: Theme.iconImage(.buttonX), backgroundStyle: .blurLight)
        button.tintColor = Theme.lightThemePrimaryColor
        button.ows_contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.layoutMargins = UIEdgeInsets(margin: 2)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTapDeleteLinkPreviewButton), for: .touchUpInside)
        return button
    }()

    override func reloadLinkPreviewAppearance() {
        super.reloadLinkPreviewAppearance()

        guard let linkPreviewView else { return }

        if deleteLinkPreviewButton.superview == nil {
            linkPreviewWrapperView.addSubview(deleteLinkPreviewButton)
        }
        linkPreviewWrapperView.bringSubviewToFront(deleteLinkPreviewButton)
        linkPreviewWrapperView.addConstraints([
            deleteLinkPreviewButton.centerXAnchor.constraint(equalTo: linkPreviewView.trailingAnchor, constant: -5),
            deleteLinkPreviewButton.centerYAnchor.constraint(equalTo: linkPreviewView.topAnchor, constant: 5),
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
        .gradient(.init(colors: [.init(rgbHex: 0x19A9FA), .init(rgbHex: 0x7097D7), .init(rgbHex: 0xD1998D), .init(rgbHex: 0xFFC369)])),
        .gradient(.init(colors: [.init(rgbHex: 0x4437D8), .init(rgbHex: 0x6B70DE), .init(rgbHex: 0xB774E0), .init(rgbHex: 0xFF8E8E)])),
        .gradient(.init(colors: [.init(rgbHex: 0x004044), .init(rgbHex: 0x2C5F45), .init(rgbHex: 0x648E52), .init(rgbHex: 0x93B864)])),
    ]

    func switchToNextBackground() {
        var nextBackgroundIndex = currentBackgroundIndex + 1
        if nextBackgroundIndex > TextStoryComposerView.textBackgrounds.count - 1 {
            nextBackgroundIndex = 0
        }
        currentBackgroundIndex = nextBackgroundIndex
    }
}

private class TextStoryComposerToolbarView: UIView {

    typealias Axis = NSLayoutConstraint.Axis

    var axis: Axis {
        get { stackView.axis }
        set {
            stackView.axis = newValue
            if #available(iOS 26, *) {
                updateStackViewLayoutMargins()
            }
        }
    }

    let backgroundSelectionButton = TextEditorBackgroundSelectionButton()

    let attachLinkButton: UIButton = {
        let hasBackground: Bool = if #available(iOS 26, *) { false } else { true }
        let configuration = UIButton.Configuration.roundMedia(
            image: UIImage(resource: .link),
            size: 44,
            withBackground: hasBackground,
        )
        return UIButton(configuration: configuration)
    }()

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        stackView.addArrangedSubviews([backgroundSelectionButton, attachLinkButton])
        stackView.axis = .horizontal
        stackView.translatesAutoresizingMaskIntoConstraints = false

        guard #available(iOS 26, *) else {
            stackView.spacing = 16
            addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: topAnchor),
                stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            return
        }

        // Add Liquid Glass panel on newer iOS versions.
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.spacing = 4
        updateStackViewLayoutMargins()

        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        let glassEffectView = UIVisualEffectView(effect: glassEffect)
        glassEffectView.clipsToBounds = true
        glassEffectView.cornerConfiguration = .capsule()
        glassEffectView.contentView.addSubview(stackView)
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),

            glassEffectView.topAnchor.constraint(equalTo: topAnchor),
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 26, *)
    private func updateStackViewLayoutMargins() {
        if stackView.axis == .horizontal {
            stackView.directionalLayoutMargins = .init(hMargin: 6, vMargin: 0)
        } else {
            stackView.directionalLayoutMargins = .init(hMargin: 0, vMargin: 6)
        }
    }

    class TextEditorBackgroundSelectionButton: UIButton {

        var background: TextAttachment.Background? {
            didSet {
                updateBackground()
            }
        }

        var buttonSize: CGSize = .square(44) {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        private let gradientView = GradientView(colors: [])

        private func updateBackground() {
            guard let background else { return }

            // This will display our gradient.
            let gradientView = GradientView(colors: [])
            switch background {
            case .color(let color):
                gradientView.colors = [color, color]

            case .gradient(let gradient):
                gradientView.colors = gradient.colors
                gradientView.locations = gradient.locations

                gradientView.setAngle(gradient.angle)
            }

            // This will give us round shape without needing to specify corner radius at init.
            let circleView = CircleView()
            circleView.clipsToBounds = true
            circleView.layer.borderWidth = 2
            circleView.layer.borderColor = UIColor.white.cgColor
            circleView.addSubview(gradientView)

            let backgroundView: UIView
            if #available(iOS 26, *) {
                // Transparent background on iOS 26+ because we put the button onto a shared glass pill.
                backgroundView = UIView()
                backgroundView.directionalLayoutMargins = .init(margin: 10)
                backgroundView.addSubview(circleView)
            } else {
                // Blur background on legacy iOS versions to match `roundMedia()` style.
                let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
                blurView.contentView.addSubview(circleView)

                backgroundView = blurView
                backgroundView.directionalLayoutMargins = .init(margin: 8)
            }

            circleView.translatesAutoresizingMaskIntoConstraints = false
            gradientView.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                gradientView.topAnchor.constraint(equalTo: circleView.topAnchor),
                gradientView.leadingAnchor.constraint(equalTo: circleView.leadingAnchor),
                gradientView.trailingAnchor.constraint(equalTo: circleView.trailingAnchor),
                gradientView.bottomAnchor.constraint(equalTo: circleView.bottomAnchor),

                gradientView.topAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.topAnchor),
                gradientView.leadingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.leadingAnchor),
                gradientView.trailingAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.trailingAnchor),
                gradientView.bottomAnchor.constraint(equalTo: backgroundView.layoutMarginsGuide.bottomAnchor),
            ])

            configuration?.background.customView = backgroundView
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            configuration = .plain()
            configuration?.cornerStyle = .capsule
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize { buttonSize }
    }
}
