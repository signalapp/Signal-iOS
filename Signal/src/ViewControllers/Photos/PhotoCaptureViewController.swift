//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

        previewView.setIsHidden(composerMode == .text, animated: animated)
        if textEditorUIInitialized {
            textViewContainerToolbar.setIsHidden(composerMode != .text, animated: animated)
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

        let hideDoneButton = isRecordingVideo || doneButton.badgeNumber == 0
        doneButton.setIsHidden(hideDoneButton, animated: animated)
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
                return textView.isFirstResponder
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
    private lazy var textViewContentLayoutGuide = UILayoutGuide()
    private lazy var textViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.preservesSuperviewLayoutMargins = true
        view.layer.masksToBounds = true

        view.addSubview(textViewContainerBackgroundView)
        textViewContainerBackgroundView.autoPinEdgesToSuperviewEdges()

        // This defines bounds for text content: text view and link preview.
        view.addLayoutGuide(textViewContentLayoutGuide)
        view.addConstraints([
            textViewContentLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            textViewContentLayoutGuide.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 8),
            textViewContentLayoutGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])

        // textViewWrapperView contains text view and link preview - these two are grouped together
        // and are centered vertically in text content area.
        textViewWrapperView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textViewWrapperView)
        view.addConstraints([
            textViewWrapperView.leadingAnchor.constraint(equalTo: textViewContentLayoutGuide.leadingAnchor),
            textViewWrapperView.topAnchor.constraint(greaterThanOrEqualTo: textViewContentLayoutGuide.topAnchor),
            textViewWrapperView.trailingAnchor.constraint(equalTo: textViewContentLayoutGuide.trailingAnchor),
            textViewWrapperView.bottomAnchor.constraint(lessThanOrEqualTo: textViewContentLayoutGuide.bottomAnchor),
            textViewWrapperView.centerYAnchor.constraint(equalTo: textViewContentLayoutGuide.centerYAnchor)
        ])

        // Placeholder text is centered in "text content area".
        textViewPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textViewPlaceholderLabel)
        view.addConstraints([
            textViewPlaceholderLabel.leadingAnchor.constraint(equalTo: textViewContentLayoutGuide.leadingAnchor),
            textViewPlaceholderLabel.topAnchor.constraint(equalTo: textViewContentLayoutGuide.topAnchor),
            textViewPlaceholderLabel.trailingAnchor.constraint(equalTo: textViewContentLayoutGuide.trailingAnchor),
            textViewPlaceholderLabel.bottomAnchor.constraint(equalTo: textViewContentLayoutGuide.bottomAnchor)
        ])

        return view
    }()
    private lazy var textViewContainerBackgroundView = GradientView(colors: [])
    private lazy var textViewContainerToolbar: UIView = {
        let stackView = UIStackView(arrangedSubviews: [ textBackgroundSelectionButton, textViewAttachLinkButton ])
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    private var textBackgroundIndex = 0
    private lazy var textBackgroundSelectionButton = RoundGradientButton()
    private lazy var textViewAttachLinkButton: UIButton = {
        let button = RoundMediaButton(image: UIImage(imageLiteralResourceName: "link-diagonal"), backgroundStyle: .blur)
        button.contentEdgeInsets = UIEdgeInsets(margin: 3)
        button.layoutMargins = .zero
        return button
    }()
    private lazy var textViewWrapperView: UIView = {
        let wrapperView = UIStackView(arrangedSubviews: [ textView, linkPreviewWrapperView ])
        wrapperView.axis = .vertical
        return wrapperView
    }()
    private lazy var textView: MediaTextView = {
        let textView = MediaTextView()
        textView.delegate = self
        textView.autoSetDimension(.height, toSize: 32, relation: .greaterThanOrEqual)
        return textView
    }()
    private lazy var textViewAccessoryToolbar: TextStylingToolbar = {
        let toolbar = TextStylingToolbar(layout: .textStory)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.colorPickerView.delegate = self
        toolbar.textStyleButton.addTarget(self, action: #selector(didTapTextStyleButton), for: .touchUpInside)
        toolbar.decorationStyleButton.addTarget(self, action: #selector(didTapDecorationStyleButton), for: .touchUpInside)
        toolbar.doneButton.addTarget(self, action: #selector(didTapTextViewDoneButton), for: .touchUpInside)
        return toolbar
    }()
    private lazy var textViewPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .ows_whiteAlpha60
        label.font = .ows_dynamicTypeLargeTitle1Clamped
        label.isUserInteractionEnabled = true
        label.text = NSLocalizedString("STORY_COMPOSER_TAP_ADD_TEXT",
                                       value: "Tap to add text",
                                       comment: "Placeholder text in text stories compose UI")
        return label
    }()

    // This constraint gets updated when onscreen keyboard appears/disappears.
    private var textViewBottomToScreenBottomConstraint: NSLayoutConstraint?
    private var observingKeyboardNotifications = false

    private var linkPreview: OWSLinkPreviewDraft?
    private var linkPreviewView: UIView?
    private lazy var linkPreviewWrapperView: UIView = {
        let view = UIView()
        view.layoutMargins = UIEdgeInsets(margin: 20)
        return view
    }()
    private lazy var deleteLinkPreviewButton: UIButton = {
        let button = RoundMediaButton(image: UIImage(imageLiteralResourceName: "x-24"), backgroundStyle: .blur)
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.layoutMargins = UIEdgeInsets(margin: 2)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

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
            textViewContainer.layer.cornerRadius = isIPadUIInRegularMode || UIDevice.current.hasIPhoneXNotch ? 18 : 0

            if isIPadUIInRegularMode {
                view.removeConstraints(textEditoriPhoneConstraints)
                view.addConstraints(textEditoriPadConstraints)
            } else {
                view.removeConstraints(textEditoriPadConstraints)
                view.addConstraints(textEditoriPhoneConstraints)
            }
        }
    }

    private func updateDoneButtonAppearance() {
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
        textViewPlaceholderLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(textViewPlaceholderTapped)))

        // Prepare text styling toolbar (only visible when editing text).
        let toolbarSize = textViewAccessoryToolbar.systemLayoutSizeFitting(CGSize(width: view.width, height: .greatestFiniteMagnitude),
                                                                           withHorizontalFittingPriority: .required,
                                                                           verticalFittingPriority: .fittingSizeLevel)
        textViewAccessoryToolbar.bounds.size = toolbarSize
        textView.inputAccessoryView = textViewAccessoryToolbar
        updateTextViewAttributes(using: textViewAccessoryToolbar)

        // Set up text view container.
        textViewContainer.layer.cornerRadius = isIPadUIInRegularMode || UIDevice.current.hasIPhoneXNotch ? 18 : 0
        view.insertSubview(textViewContainer, aboveSubview: previewView)
        textEditoriPhoneConstraints.append(contentsOf: [
            textViewContainer.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            textViewContainer.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            textViewContainer.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            textViewContainer.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        ])

        // This constraint would allow to resize textView to clear onscreen keyboard.
        textViewBottomToScreenBottomConstraint = textViewContainer.bottomAnchor.constraint(greaterThanOrEqualTo: textViewContentLayoutGuide.bottomAnchor)
        textViewBottomToScreenBottomConstraint?.isActive = true

        // Choose Background and Attach Link buttons.
        view.addSubview(textViewContainerToolbar)
        // Align leading edge of Background button to leading edge of the Close button at the top.
        view.addConstraint(textViewContainerToolbar.leadingAnchor.constraint(equalTo: topBar.controlsLayoutGuide.leadingAnchor))
        textEditoriPhoneConstraints.append({
            // On iPhones text content should not overlap with Background and Attach Link buttons.
            let constraint = textViewContentLayoutGuide.bottomAnchor.constraint(
                equalTo: textViewContainerToolbar.topAnchor, constant: -16)
            constraint.priority = .defaultHigh
            return constraint
        }())
        if bottomBar.isCompactHeightLayout {
            textEditoriPhoneConstraints.append(
                textViewContainerToolbar.bottomAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.topAnchor))
        } else {
            textEditoriPhoneConstraints.append(
                textViewContainerToolbar.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor, constant: -16))
        }

        if isIPadUIInRegularMode {
            initializeTextEditoriPadUI()
        } else {
            view.addConstraints(textEditoriPhoneConstraints)
        }

        updateTextBackground()

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
            textViewContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            textViewContainer.bottomAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.topAnchor, constant: -24),
            textViewContainer.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            textViewContainer.widthAnchor.constraint(equalTo: textViewContainer.heightAnchor, multiplier: 9/16)
        ])

        // Allow text view content take entire textViewContainer because all controls are outside of textViewContainer.
        // This is a non-required constraint because it needs to fail when on-screen keyboard is visible.
        textEditoriPadConstraints.append({
            let constraint = textViewContentLayoutGuide.bottomAnchor.constraint(equalTo: textViewContainer.layoutMarginsGuide.bottomAnchor)
            constraint.priority = .defaultHigh
            return constraint
        }())

        // Background and Add Link buttons are vertically centered with CAMERA|TEXT switch and Proceed button.
        textEditoriPadConstraints.append(
            textViewContainerToolbar.centerYAnchor.constraint(equalTo: bottomBar.controlButtonsLayoutGuide.centerYAnchor))

        view.addConstraints(textEditoriPadConstraints)
    }

    private var strippedTextViewText: String { textView.text.stripped }

    private var isTextViewContentEmpty: Bool {
        strippedTextViewText.isEmpty && linkPreview == nil
    }

    private static func desiredAttributes(forText text: String) -> (fontPointSize: CGFloat, textAlignment: NSTextAlignment) {
        switch text.count {
        case ..<50: return (34, .center)
        case 50...199: return (24, .center)
        default: return (18, .natural)
        }
    }

    private func updateTextViewAttributes(using textToolbar: TextStylingToolbar) {
        let (fontPointSize, textAlignment) = PhotoCaptureViewController.desiredAttributes(forText: strippedTextViewText)
        textView.update(using: textToolbar, fontPointSize: fontPointSize, textAlignment: textAlignment)
    }

    private func adjustFontSizeIfNecessary() {
        guard let currentFontSize = textView.font?.pointSize else { return }
        let desiredFontSize = PhotoCaptureViewController.desiredAttributes(forText: strippedTextViewText).fontPointSize
        guard desiredFontSize != currentFontSize else { return }
        updateTextViewAttributes(using: textViewAccessoryToolbar)
    }

    private func updateLinkPreviewAppearance() {
        if let linkPreviewView = linkPreviewView {
            linkPreviewView.removeFromSuperview()
            self.linkPreviewView = nil
        }

        guard let linkPreview = linkPreview else {
            linkPreviewWrapperView.isHiddenInStackView = true
            return
        }

        linkPreviewWrapperView.isHiddenInStackView = false

        let linkPreviewView = TextAttachmentView.LinkPreviewView(linkPreview: LinkPreviewDraft(linkPreviewDraft: linkPreview))
        linkPreviewWrapperView.addSubview(linkPreviewView)
        linkPreviewView.autoPinEdgesToSuperviewMargins()
        self.linkPreviewView = linkPreviewView

        if deleteLinkPreviewButton.superview == nil {
            linkPreviewWrapperView.addSubview(deleteLinkPreviewButton)
            deleteLinkPreviewButton.addTarget(self, action: #selector(didTapDeleteLinkPreviewButton), for: .touchUpInside)
        }
        linkPreviewWrapperView.addConstraints([
            deleteLinkPreviewButton.centerXAnchor.constraint(equalTo: linkPreviewView.trailingAnchor, constant: -5),
            deleteLinkPreviewButton.centerYAnchor.constraint(equalTo: linkPreviewView.topAnchor, constant: 5)
        ])
        linkPreviewWrapperView.bringSubviewToFront(deleteLinkPreviewButton)
    }

    private func updateTextEditorUI(animated: Bool) {
        let isPlaceholderHidden = textView.isFirstResponder || textView.hasText || linkPreview != nil
        textViewPlaceholderLabel.setIsHidden(isPlaceholderHidden, animated: animated)

        bottomBar.proceedButton.isEnabled = !isTextViewContentEmpty
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

        guard let constraint = textViewBottomToScreenBottomConstraint else { return }

        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let convertedEndFrame = textViewContainer.convert(endFrame, from: nil)
        let inset = textViewContainer.bounds.maxY - convertedEndFrame.minY

        let layoutUpdateBlock = {
            constraint.constant = inset + 16
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

    private func switchToNextBackground() {
        textBackgroundIndex += 1
        if textBackgroundIndex > PhotoCaptureViewController.textBackgrounds.count - 1 {
            textBackgroundIndex = 0
        }
        updateTextBackground()
    }

    private func updateTextBackground() {
        let textBackground = PhotoCaptureViewController.textBackgrounds[textBackgroundIndex]
        switch textBackground {
        case .color(let color):
            textViewContainerBackgroundView.colors = [ color, color ]
            textBackgroundSelectionButton.gradientView.colors = [ color, color ]

        case .gradient(let gradient):
            textViewContainerBackgroundView.colors = gradient.colors
            textViewContainerBackgroundView.locations = gradient.locations
            textViewContainerBackgroundView.setAngle(gradient.angle)

            textBackgroundSelectionButton.gradientView.colors = gradient.colors
            textBackgroundSelectionButton.gradientView.locations = gradient.locations
            textBackgroundSelectionButton.gradientView.setAngle(gradient.angle)
        }
    }

    // MARK: - Button Actions

    @objc
    private func textViewPlaceholderTapped() {
        textView.becomeFirstResponder()
    }

    @objc
    private func didTapTextStyleButton() {
        let currentTextStyle = textViewAccessoryToolbar.textStyle
        let nextTextStyle = MediaTextView.TextStyle(rawValue: currentTextStyle.rawValue + 1) ?? .regular

        // Update toolbar.
        textViewAccessoryToolbar.textStyle = nextTextStyle

        // Update text view.
        if textView.isFirstResponder {
            updateTextViewAttributes(using: textViewAccessoryToolbar)
        }
    }

    @objc
    private func didTapDecorationStyleButton() {
        // Switch between colored text with no background and white text over colored background.
        let currentDecorationStyle = textViewAccessoryToolbar.decorationStyle
        let nextDecorationStyle: MediaTextView.DecorationStyle = currentDecorationStyle == .none ? .inverted : .none

        // Update toolbar.
        textViewAccessoryToolbar.decorationStyle = nextDecorationStyle

        // Update text view.
        if textView.isFirstResponder {
            updateTextViewAttributes(using: textViewAccessoryToolbar)
        }
    }

    @objc
    private func didTapTextBackgroundButton() {
        switchToNextBackground()
    }

    @objc
    private func didTapAttachLinkPreviewButton() {
        let linkPreviewViewController = LinkPreviewAttachmentViewController(linkPreview)
        linkPreviewViewController.delegate = self
        present(linkPreviewViewController, animated: true)
    }

    @objc
    private func didTapDeleteLinkPreviewButton() {
        linkPreview = nil
        updateLinkPreviewAppearance()
        updateTextEditorUI(animated: true)
    }

    @objc
    private func didTapTextViewDoneButton() {
        Logger.verbose("")

        textView.acceptAutocorrectSuggestion()
        textView.resignFirstResponder()
    }

    @objc
    private func didTapTextStoryProceedButton() {
        Logger.verbose("")

        let textForegroundColor: UIColor
        let textBackgroundColor: UIColor?
        switch textViewAccessoryToolbar.decorationStyle {
        case .inverted:
            textForegroundColor = .white
            textBackgroundColor = textViewAccessoryToolbar.colorPickerView.color
        default:
            textForegroundColor = textViewAccessoryToolbar.colorPickerView.color
            textBackgroundColor = nil
        }

        let textStyle: TextAttachment.TextStyle = {
            switch textViewAccessoryToolbar.textStyle {
            case .regular: return .regular
            case .bold: return .bold
            case .condensed: return .condensed
            case .script: return .script
            case .serif: return .serif
            }
        }()
        let background = PhotoCaptureViewController.textBackgrounds[textBackgroundIndex]

        var validatedLinkPreview: OWSLinkPreview?
        if let linkPreview = linkPreview {
            self.databaseStorage.write { transaction in
                validatedLinkPreview = try? OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreview, transaction: transaction)
            }
        }

        let textAttachment = TextAttachment(
            text: strippedTextViewText,
            textStyle: textStyle,
            textForegroundColor: textForegroundColor,
            textBackgroundColor: textBackgroundColor,
            background: background,
            linkPreview: validatedLinkPreview)
        delegate?.photoCaptureViewController(self, didFinishWithTextAttachment: textAttachment)
    }
}

extension PhotoCaptureViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        updateBottomBarVisibility(animated: true)
        textViewContainerToolbar.setIsHidden(true, animated: true)
        linkPreviewWrapperView.setIsHidden(true, animated: true)
        updateTextEditorUI(animated: true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        updateBottomBarVisibility(animated: true)
        textViewContainerToolbar.setIsHidden(false, animated: true)
        linkPreviewWrapperView.setIsHidden(false, animated: true)
        updateTextEditorUI(animated: true)
    }

    func textViewDidChange(_ textView: UITextView) {
        adjustFontSizeIfNecessary()
        updateTextEditorUI(animated: false)
    }
}

extension PhotoCaptureViewController: ColorPickerBarViewDelegate {

    func colorPickerBarView(_ pickerView: ColorPickerBarView, didSelectColor color: ColorPickerBarColor) {
        updateTextViewAttributes(using: textViewAccessoryToolbar)
    }
}

extension PhotoCaptureViewController: LinkPreviewAttachmentViewControllerDelegate {

    func linkPreviewAttachmentViewController(_ viewController: LinkPreviewAttachmentViewController,
                                             didFinishWith linkPreview: OWSLinkPreviewDraft) {
        self.linkPreview = linkPreview
        updateLinkPreviewAppearance()
        updateTextEditorUI(animated: false)
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
            textViewContainer.setIsHidden(true, animated: true)

        case .text:
            startObservingKeyboardNotifications()
            initializeTextEditorUIIfNecessary()
            textViewContainer.setIsHidden(false, animated: true)
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
