//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import WebRTC
import SignalServiceKit
import SignalMessaging
import SignalRingRTC

// TODO: Add category so that button handlers can be defined where button is created.
// TODO: Ensure buttons enabled & disabled as necessary.
class IndividualCallViewController: OWSViewController, CallObserver, CallAudioServiceDelegate {

    // MARK: - Properties

    let thread: TSContactThread
    let call: SignalCall
    var hasDismissed = false

    // MARK: - Views

    private lazy var blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private lazy var backgroundAvatarView = UIImageView()
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        dateFormatter.locale = Locale(identifier: "en_US")
        return dateFormatter
    }()

    private var callDurationTimer: Timer?

    // MARK: - Gradient Views

    private lazy var topGradientView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.ows_blackAlpha60.cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    private lazy var bottomContainerView = UIView.container()

    private lazy var bottomGradientView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.ows_blackAlpha60.cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    let gradientMargin: CGFloat = 46

    // MARK: - Contact Views

    private lazy var contactNameLabel = MarqueeLabel()
    private lazy var contactAvatarView = ConversationAvatarView(
        sizeClass: .customDiameter(200),
        localUserDisplayMode: .asUser,
        badged: false)
    private lazy var contactAvatarContainerView = UIView.container()
    private lazy var callStatusLabel = UILabel()
    private lazy var backButton = UIButton()

    // MARK: - Ongoing Audio Call Controls

    private lazy var ongoingAudioCallControls = UIStackView(
        arrangedSubviews: [
            UIView.hStretchingSpacer(),
            audioModeSourceButton,
            audioModeVideoButton,
            audioModeMuteButton,
            audioModeHangUpButton,
            UIView.hStretchingSpacer()
        ]
    )

    private lazy var audioModeHangUpButton = createButton(iconName: "phone-down-solid-28", action: #selector(didPressHangup))
    private lazy var audioModeSourceButton = createButton(iconName: "speaker-solid-28", action: #selector(didPressAudioSource))
    private lazy var audioModeMuteButton = createButton(iconName: "mic-off-solid-28", action: #selector(didPressMute))
    private lazy var audioModeVideoButton = createButton(iconName: "video-solid-28", action: #selector(didPressVideo))

    // MARK: - Ongoing Video Call Controls

    private lazy var ongoingVideoCallControls = UIStackView(
        arrangedSubviews: [
            UIView.hStretchingSpacer(),
            videoModeAudioSourceButton,
            videoModeFlipCameraButton,
            videoModeVideoButton,
            videoModeMuteButton,
            videoModeHangUpButton,
            UIView.hStretchingSpacer()
        ]
    )

    private lazy var videoModeHangUpButton = createButton(iconName: "phone-down-solid-28", action: #selector(didPressHangup))
    private lazy var videoModeAudioSourceButton = createButton(iconName: "speaker-solid-28", action: #selector(didPressAudioSource))
    private lazy var videoModeMuteButton = createButton(iconName: "mic-off-solid-28", action: #selector(didPressMute))
    private lazy var videoModeVideoButton = createButton(iconName: "video-solid-28", action: #selector(didPressVideo))
    private lazy var videoModeFlipCameraButton = createButton(iconName: "switch-camera-28", action: #selector(didPressFlipCamera))

    // MARK: - Incoming Audio Call Controls

    private lazy var incomingAudioCallControls = UIStackView(
        arrangedSubviews: [
            UIView.hStretchingSpacer(),
            audioDeclineIncomingButton,
            UIView.spacer(withWidth: 124),
            audioAnswerIncomingButton,
            UIView.hStretchingSpacer()
        ]
    )

    private lazy var audioAnswerIncomingButton = createButton(iconName: "phone-solid-28", action: #selector(didPressAnswerCall))
    private lazy var audioDeclineIncomingButton = createButton(iconName: "phone-down-solid-28", action: #selector(didPressDeclineCall))

    // MARK: - Incoming Video Call Controls

    private lazy var incomingVideoCallControls = UIStackView(
        arrangedSubviews: [
            videoAnswerIncomingAudioOnlyButton,
            incomingVideoCallBottomControls
        ]
    )

    private lazy var incomingVideoCallBottomControls = UIStackView(
        arrangedSubviews: [
            UIView.hStretchingSpacer(),
            videoDeclineIncomingButton,
            UIView.spacer(withWidth: 124),
            videoAnswerIncomingButton,
            UIView.hStretchingSpacer()
        ]
    )

    private lazy var videoAnswerIncomingButton = createButton(iconName: "video-solid-28", action: #selector(didPressAnswerCall))
    private lazy var videoAnswerIncomingAudioOnlyButton = createButton(iconName: "video-off-solid-28", action: #selector(didPressAnswerCall))
    private lazy var videoDeclineIncomingButton = createButton(iconName: "phone-down-solid-28", action: #selector(didPressDeclineCall))

    // MARK: - Video Views

    private lazy var remoteVideoView = RemoteVideoView()
    private weak var remoteVideoTrack: RTCVideoTrack?

    private lazy var localVideoView: LocalVideoView = {
        let localVideoView = LocalVideoView()
        localVideoView.captureSession = call.videoCaptureController.captureSession
        return localVideoView
    }()

    // MARK: - Gestures

    lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTouchRootView))
    lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleLocalVideoPan))

    var shouldRemoteVideoControlsBeHidden = false {
        didSet {
            updateCallUI()
        }
    }

    // MARK: - Audio Source

    var hasAlternateAudioSources: Bool {
        Logger.info("available audio sources: \(allAudioSources)")
        // internal mic and speakerphone will be the first two, any more than one indicates e.g. an attached bluetooth device.

        // TODO is this sufficient? Are their devices w/ bluetooth but no external speaker? e.g. ipod?
        return allAudioSources.count > 2
    }

    var allAudioSources: Set<AudioSource> = Set()

    var appropriateAudioSources: Set<AudioSource> {
        if call.individualCall.hasLocalVideo {
            let appropriateForVideo = allAudioSources.filter { audioSource in
                if audioSource.isBuiltInSpeaker {
                    return true
                } else {
                    guard let portDescription = audioSource.portDescription else {
                        owsFailDebug("Only built in speaker should be lacking a port description.")
                        return false
                    }

                    // Don't use receiver when video is enabled. Only bluetooth or speaker
                    return portDescription.portType != AVAudioSession.Port.builtInMic
                }
            }
            return Set(appropriateForVideo)
        } else {
            return allAudioSources
        }
    }

    // MARK: - Initializers

    required init(call: SignalCall) {
        // TODO: Eventually unify UI for group and individual calls
        owsAssertDebug(call.isIndividualCall)
        self.call = call
        self.thread = TSContactThread.getOrCreateThread(contactAddress: call.individualCall.remoteAddress)
        super.init()

        allAudioSources = Set(callService.audioService.availableInputs)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateOrientationForPhone),
                                               name: CallService.phoneOrientationDidChange,
                                               object: nil)
    }

    deinit {
        // These views might be in the return to call PIP's hierarchy,
        // we want to remove them so they are free'd when the call ends
        remoteVideoView.removeFromSuperview()
        localVideoView.removeFromSuperview()
    }

    // MARK: - View Lifecycle

    @objc
    func didBecomeActive() {
        if self.isViewLoaded {
            shouldRemoteVideoControlsBeHidden = false
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateLocalVideoLayout()
        }, completion: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        callDurationTimer?.invalidate()
        callDurationTimer = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateCallUI()
        if call.offerMediaType == .video {
            callService.sendInitialPhoneOrientationNotification()
        }
    }

    override func loadView() {
        view = UIView()
        view.clipsToBounds = true
        view.backgroundColor = UIColor.black
        view.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        createViews()
        createViewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        contactNameLabel.text = contactsManager.displayName(for: thread.contactAddress)
        updateAvatarImage()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAvatarImage),
            name: .OWSContactsManagerSignalAccountsDidChange,
            object: nil
        )

        // Subscribe for future call updates
        call.addObserverAndSyncState(observer: self)

        assert(callService.audioService.delegate == nil)
        callService.audioService.delegate = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Create Views

    func createViews() {
        view.isUserInteractionEnabled = true

        view.addGestureRecognizer(tapGesture)
        localVideoView.addGestureRecognizer(panGesture)
        panGesture.delegate = self
        tapGesture.require(toFail: panGesture)

        // The callee's avatar is rendered behind the blurred background.
        backgroundAvatarView.contentMode = .scaleAspectFill
        backgroundAvatarView.isUserInteractionEnabled = false
        view.addSubview(backgroundAvatarView)
        backgroundAvatarView.autoPinEdgesToSuperviewEdges()

        // Dark blurred background.
        blurView.isUserInteractionEnabled = false
        view.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        // Create the video views first, as they are under the other views.
        createVideoViews()

        view.addSubview(topGradientView)
        topGradientView.autoPinWidthToSuperview()
        topGradientView.autoPinEdge(toSuperviewEdge: .top)

        view.addSubview(bottomContainerView)
        bottomContainerView.autoPinWidthToSuperview()
        bottomContainerView.autoPinEdge(toSuperviewEdge: .bottom)

        bottomContainerView.addSubview(bottomGradientView)
        bottomGradientView.autoPinWidthToSuperview()
        bottomGradientView.autoPinEdge(toSuperviewEdge: .bottom)

        createContactViews()
        createOngoingCallControls()
        createIncomingCallControls()
    }

    @objc
    func didTouchRootView(sender: UIGestureRecognizer) {
        if !remoteVideoView.isHidden {
            shouldRemoteVideoControlsBeHidden = !shouldRemoteVideoControlsBeHidden
        }
    }

    func createVideoViews() {
        remoteVideoView.isUserInteractionEnabled = false
        remoteVideoView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "remoteVideoView")
        remoteVideoView.isHidden = true
        remoteVideoView.isGroupCall = false
        view.addSubview(remoteVideoView)

        // We want the local video view to use the aspect ratio of the screen, so we change it to "aspect fill".
        localVideoView.contentMode = .scaleAspectFill
        localVideoView.clipsToBounds = true
        localVideoView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "localVideoView")
        localVideoView.isHidden = true
        view.addSubview(localVideoView)
    }

    func createContactViews() {

        let backButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")
        backButton.setImage(backButtonImage, for: .normal)
        backButton.autoSetDimensions(to: CGSize(square: 40))
        backButton.addTarget(self, action: #selector(didTapLeaveCall(sender:)), for: .touchUpInside)
        topGradientView.addSubview(backButton)

        // marquee config
        contactNameLabel.type = .continuous
        // This feels pretty slow when you're initially waiting for it, but when you're overlaying video calls, anything faster is distracting.
        contactNameLabel.speed = .duration(30.0)
        contactNameLabel.animationCurve = .linear
        contactNameLabel.fadeLength = 10.0
        contactNameLabel.animationDelay = 5
        // Add trailing space after the name scrolls before it wraps around and scrolls back in.
        contactNameLabel.trailingBuffer = ScaleFromIPhone5(80.0)

        // label config
        contactNameLabel.font = UIFont.ows_dynamicTypeTitle1
        contactNameLabel.textAlignment = .center
        contactNameLabel.textColor = UIColor.white
        contactNameLabel.layer.shadowOffset = .zero
        contactNameLabel.layer.shadowOpacity = 0.25
        contactNameLabel.layer.shadowRadius = 4

        topGradientView.addSubview(contactNameLabel)

        callStatusLabel.font = UIFont.ows_dynamicTypeBody
        callStatusLabel.textAlignment = .center
        callStatusLabel.textColor = UIColor.white
        callStatusLabel.layer.shadowOffset = .zero
        callStatusLabel.layer.shadowOpacity = 0.25
        callStatusLabel.layer.shadowRadius = 4

        topGradientView.addSubview(callStatusLabel)

        contactAvatarContainerView.addSubview(contactAvatarView)
        view.insertSubview(contactAvatarContainerView, belowSubview: localVideoView)

        backButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "leaveCallViewButton")
        contactNameLabel.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "contactNameLabel")
        callStatusLabel.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "callStatusLabel")
        contactAvatarView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "contactAvatarView")
    }

    func createOngoingCallControls() {
        audioModeSourceButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_AUDIO_SOURCE_LABEL",
                                                                 comment: "Accessibility label for selection the audio source")

        audioModeHangUpButton.unselectedBackgroundColor = .ows_accentRed
        audioModeHangUpButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_HANGUP_LABEL",
                                                                 comment: "Accessibility label for hang up call")

        audioModeMuteButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_MUTE_LABEL",
                                                                   comment: "Accessibility label for muting the microphone")

        audioModeVideoButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_TO_VIDEO_LABEL", comment: "Accessibility label to switch to video call")

        videoModeAudioSourceButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_AUDIO_SOURCE_LABEL",
                                                                      comment: "Accessibility label for selection the audio source")

        videoModeHangUpButton.unselectedBackgroundColor = .ows_accentRed
        videoModeHangUpButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_HANGUP_LABEL",
                                                                 comment: "Accessibility label for hang up call")

        videoModeMuteButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_MUTE_LABEL", comment: "Accessibility label for muting the microphone")
        videoModeMuteButton.alpha = 0.9

        videoModeFlipCameraButton.selectedIconColor = videoModeFlipCameraButton.iconColor
        videoModeFlipCameraButton.selectedBackgroundColor = videoModeFlipCameraButton.unselectedBackgroundColor
        videoModeFlipCameraButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_CAMERA_DIRECTION", comment: "Accessibility label to toggle front- vs. rear-facing camera")
        videoModeFlipCameraButton.alpha = 0.9

        videoModeVideoButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_TO_AUDIO_LABEL", comment: "Accessibility label to switch to audio only")
        videoModeVideoButton.alpha = 0.9

        ongoingAudioCallControls.spacing = 16
        ongoingAudioCallControls.axis = .horizontal
        bottomGradientView.addSubview(ongoingAudioCallControls)

        ongoingVideoCallControls.spacing = 16
        ongoingVideoCallControls.axis = .horizontal
        bottomGradientView.addSubview(ongoingVideoCallControls)

        // Ensure that the controls are always horizontally centered
        for stackView in [ongoingAudioCallControls, ongoingVideoCallControls] {
            guard let leadingSpacer = stackView.arrangedSubviews.first, let trailingSpacer = stackView.arrangedSubviews.last else {
                return owsFailDebug("failed to get spacers")
            }
            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        }

        audioModeHangUpButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioHangUpButton")
        audioModeSourceButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioSourceButton")
        audioModeMuteButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioModeMuteButton")
        audioModeVideoButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioModeVideoButton")

        videoModeHangUpButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoHangUpButton")
        videoModeAudioSourceButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoAudioSourceButton")
        videoModeMuteButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoModeMuteButton")
        videoModeFlipCameraButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoModeFlipCameraButton")
        videoModeVideoButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoModeVideoButton")
    }

    func presentAudioSourcePicker() {
        AssertIsOnMainThread()

        guard !callService.audioService.presentRoutePicker() else { return }

        // Fallback to action sheet based picker, which is buggy
        owsFailDebug("Failed to present native route picker, maybe a new iOS version broke it?")

        let actionSheetController = ActionSheetController(title: nil, message: nil)

        let dismissAction = ActionSheetAction(title: CommonStrings.dismissButton, style: .cancel)
        actionSheetController.addAction(dismissAction)

        let currentAudioSource = callService.audioService.currentAudioSource
        for audioSource in self.appropriateAudioSources {
            let routeAudioAction = ActionSheetAction(title: audioSource.localizedName, style: .default) { _ in
                self.callService.audioService.currentAudioSource = audioSource
            }

            // create checkmark for active audio source.
            if currentAudioSource == audioSource {
                routeAudioAction.trailingIcon = .checkCircle24
            }

            actionSheetController.addAction(routeAudioAction)
        }

        // Note: It's critical that we present from this view and
        // not the "frontmost view controller" since this view may
        // reside on a separate window.
        presentActionSheet(actionSheetController)
    }

    @objc
    func updateAvatarImage() {
        databaseStorage.read { transaction in
            contactAvatarView.update(transaction) { config in
                config.dataSource = .thread(thread)
            }
            backgroundAvatarView.image = contactsManagerImpl.avatarImage(forAddress: thread.contactAddress,
                                                                         shouldValidate: true,
                                                                         transaction: transaction)
        }
    }

    func createIncomingCallControls() {
        audioAnswerIncomingButton.text = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
                                                           comment: "label for accepting incoming calls")
        audioAnswerIncomingButton.unselectedBackgroundColor = .ows_accentGreen
        audioAnswerIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
                                                                    comment: "label for accepting incoming calls")

        audioDeclineIncomingButton.text = NSLocalizedString("CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
                                                            comment: "label for declining incoming calls")
        audioDeclineIncomingButton.unselectedBackgroundColor = .ows_accentRed
        audioDeclineIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
                                                                     comment: "label for declining incoming calls")

        incomingAudioCallControls.axis = .horizontal
        incomingAudioCallControls.alignment = .center
        bottomGradientView.addSubview(incomingAudioCallControls)

        audioAnswerIncomingButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioAnswerIncomingButton")
        audioDeclineIncomingButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "audioDeclineIncomingButton")

        videoAnswerIncomingButton.text = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
                                                           comment: "label for accepting incoming calls")
        videoAnswerIncomingButton.unselectedBackgroundColor = .ows_accentGreen
        videoAnswerIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
                                                                         comment: "label for accepting incoming calls")

        videoAnswerIncomingAudioOnlyButton.text = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_AUDIO_ONLY_LABEL",
                                                                    comment: "label for accepting incoming video calls as audio  only")
        videoAnswerIncomingAudioOnlyButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_AUDIO_ONLY_LABEL",
                                                                                comment: "label for accepting incoming video calls as audio  only")

        videoDeclineIncomingButton.text = NSLocalizedString("CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
                                                            comment: "label for declining incoming calls")
        videoDeclineIncomingButton.unselectedBackgroundColor = .ows_accentRed
        videoDeclineIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
                                                                          comment: "label for declining incoming calls")

        incomingVideoCallBottomControls.axis = .horizontal
        incomingVideoCallBottomControls.alignment = .center

        incomingVideoCallControls.axis = .vertical
        incomingVideoCallControls.spacing = 20
        bottomContainerView.addSubview(incomingVideoCallControls)

        // Ensure that the controls are always horizontally centered
        for stackView in [incomingAudioCallControls, incomingVideoCallBottomControls] {
            guard let leadingSpacer = stackView.arrangedSubviews.first, let trailingSpacer = stackView.arrangedSubviews.last else {
                return owsFailDebug("failed to get spacers")
            }
            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        }

        videoAnswerIncomingButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoAnswerIncomingButton")
        videoAnswerIncomingAudioOnlyButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoAnswerIncomingAudioOnlyButton")
        videoDeclineIncomingButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "videoDeclineIncomingButton")
    }

    private func createButton(iconName: String, action: Selector) -> CallButton {
        let button = CallButton(iconName: iconName)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalLow()
        return button
    }

    // MARK: - Layout

    func createViewConstraints() {

        let contactVSpacing: CGFloat = 3
        let bottomMargin = ScaleFromIPhone5To7Plus(23, 41)
        let avatarMargin = ScaleFromIPhone5To7Plus(25, 50)

        backButton.autoPinEdge(toSuperviewEdge: .leading)

        backButton.autoPinEdge(toSuperviewMargin: .top)
        contactNameLabel.autoPinEdge(toSuperviewMargin: .top)

        contactNameLabel.autoPinEdge(.leading, to: .trailing, of: backButton, withOffset: 8, relation: .greaterThanOrEqual)
        contactNameLabel.autoHCenterInSuperview()
        contactNameLabel.setContentHuggingVerticalHigh()
        contactNameLabel.setCompressionResistanceHigh()

        callStatusLabel.autoPinEdge(.top, to: .bottom, of: contactNameLabel, withOffset: contactVSpacing)
        callStatusLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: gradientMargin)
        callStatusLabel.autoHCenterInSuperview()
        callStatusLabel.setContentHuggingVerticalHigh()
        callStatusLabel.setCompressionResistanceHigh()

        remoteVideoView.autoPinEdgesToSuperviewEdges()

        contactAvatarContainerView.autoPinEdge(.top, to: .bottom, of: callStatusLabel, withOffset: +avatarMargin)
        contactAvatarContainerView.autoPinEdge(.bottom, to: .top, of: ongoingAudioCallControls, withOffset: -avatarMargin)
        contactAvatarContainerView.autoPinWidthToSuperview(withMargin: avatarMargin)

        contactAvatarView.autoCenterInSuperview()

        ongoingAudioCallControls.autoPinEdge(toSuperviewEdge: .top, withInset: gradientMargin)
        incomingVideoCallControls.autoPinEdge(toSuperviewEdge: .top)

        for controls in [incomingVideoCallControls, incomingAudioCallControls, ongoingAudioCallControls, ongoingVideoCallControls] {
            controls.autoPinWidthToSuperviewMargins()
            controls.autoPinEdge(toSuperviewEdge: .bottom, withInset: bottomMargin)
            controls.setContentHuggingVerticalHigh()
        }
    }

    internal func updateRemoteVideoLayout() {
        remoteVideoView.isHidden = !self.hasRemoteVideoTrack
        updateCallUI()
    }

    private var lastLocalVideoBoundingRect: CGRect = .zero
    private var localVideoBoundingRect: CGRect {
        view.layoutIfNeeded()

        var rect = view.frame
        rect.origin.x += view.layoutMargins.left
        rect.size.width -= view.layoutMargins.left + view.layoutMargins.right

        let topInset = shouldRemoteVideoControlsBeHidden
            ? view.layoutMargins.top
            : topGradientView.height - gradientMargin + 14
        let bottomInset = shouldRemoteVideoControlsBeHidden
            ? view.layoutMargins.bottom
            : bottomGradientView.height - gradientMargin + 14
        rect.origin.y += topInset
        rect.size.height -= topInset + bottomInset

        lastLocalVideoBoundingRect = rect

        return rect
    }

    private var isRenderingLocalVanityVideo: Bool {
        return [.idle, .dialing, .remoteRinging, .localRinging_Anticipatory, .localRinging_ReadyToAnswer].contains(call.individualCall.state) && !localVideoView.isHidden
    }

    private var previousOrigin: CGPoint!
    private func updateLocalVideoLayout() {
        guard localVideoView.superview == view else { return }

        guard !call.individualCall.isEnded else { return }

        guard !isRenderingLocalVanityVideo else {
            view.bringSubviewToFront(topGradientView)
            view.bringSubviewToFront(bottomContainerView)
            view.layoutIfNeeded()
            localVideoView.frame = view.frame
            return
        }

        guard !localVideoView.isHidden else { return }

        view.bringSubviewToFront(localVideoView)

        let pipSize = ReturnToCallViewController.pipSize
        let lastBoundingRect = lastLocalVideoBoundingRect
        let boundingRect = localVideoBoundingRect

        // Prefer to start in the top right
        if previousOrigin == nil {
            previousOrigin = CGPoint(
                x: boundingRect.maxX - pipSize.width,
                y: boundingRect.minY
            )

        // If the bounding rect has gotten bigger, and we were at the top or
        // bottom edge move the pip so it stays at the top or bottom edge.
        } else if boundingRect.minY < lastBoundingRect.minY && previousOrigin.y == lastBoundingRect.minY {
            previousOrigin.y = boundingRect.minY
        } else if boundingRect.maxY > lastBoundingRect.maxY && previousOrigin.y + pipSize.height == lastBoundingRect.maxY {
            previousOrigin.y += boundingRect.maxY - lastBoundingRect.maxY
        }

        let newFrame = CGRect(origin: previousOrigin, size: pipSize).pinnedToVerticalEdge(of: localVideoBoundingRect)
        previousOrigin = newFrame.origin

        UIView.animate(withDuration: 0.25) { self.localVideoView.frame = newFrame }
    }

    private var startingTranslation: CGPoint?
    @objc
    func handleLocalVideoPan(sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            let translation = sender.translation(in: localVideoView)
            sender.setTranslation(.zero, in: localVideoView)

            localVideoView.frame.origin.y += translation.y
            localVideoView.frame.origin.x += translation.x
        case .ended, .cancelled, .failed:
            localVideoView.animateDecelerationToVerticalEdge(
                withDuration: 0.35,
                velocity: sender.velocity(in: localVideoView),
                boundingRect: localVideoBoundingRect
            ) { _ in self.previousOrigin = self.localVideoView.frame.origin }
        default:
            break
        }
    }

    // MARK: - Methods

    func showCallFailed(error: Error) {
        // TODO Show something in UI.
        Logger.error("call failed with error: \(error)")
    }

    // MARK: - View State

    func localizedTextForCallState() -> String {
        assert(Thread.isMainThread)

        switch call.individualCall.state {
        case .idle, .remoteHangup, .remoteHangupNeedPermission, .localHangup:
            return NSLocalizedString("IN_CALL_TERMINATED", comment: "Call setup status label")
        case .dialing:
            return NSLocalizedString("IN_CALL_CONNECTING", comment: "Call setup status label")
        case .remoteRinging:
            return NSLocalizedString("IN_CALL_RINGING", comment: "Call setup status label")
        case .localRinging_Anticipatory, .localRinging_ReadyToAnswer:
            switch call.individualCall.offerMediaType {
            case .audio:
                return NSLocalizedString("IN_CALL_RINGING_AUDIO", comment: "Call setup status label")
            case .video:
                return NSLocalizedString("IN_CALL_RINGING_VIDEO", comment: "Call setup status label")
            }
        case .answering, .accepting:
            return NSLocalizedString("IN_CALL_SECURING", comment: "Call setup status label")
        case .connected:
            let callDuration = call.connectionDuration()
            let callDurationDate = Date(timeIntervalSinceReferenceDate: callDuration)
            var formattedDate = dateFormatter.string(from: callDurationDate)
            if formattedDate.hasPrefix("00:") {
                // Don't show the "hours" portion of the date format unless the
                // call duration is at least 1 hour.
                formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 3)...])
            } else {
                // If showing the "hours" portion of the date format, strip any leading
                // zeroes.
                if formattedDate.hasPrefix("0") {
                    formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 1)...])
                }
            }
            return formattedDate
        case .reconnecting:
            return NSLocalizedString("IN_CALL_RECONNECTING", comment: "Call setup status label")
        case .remoteBusy:
            return NSLocalizedString("END_CALL_RESPONDER_IS_BUSY", comment: "Call setup status label")
        case .localFailure:
            if let error = call.error {
                switch error {
                case .timeout(description: _):
                    if self.call.individualCall.direction == .outgoing {
                        return NSLocalizedString("CALL_SCREEN_STATUS_NO_ANSWER", comment: "Call setup status label after outgoing call times out")
                    }
                default:
                    break
                }
            }

            return NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label")
        case .answeredElsewhere:
            return NSLocalizedString("IN_CALL_ENDED_BECAUSE_ANSWERED_ELSEWHERE", comment: "Call screen label when call was canceled on this device because the call recipient answered on another device.")
        case .declinedElsewhere:
            return NSLocalizedString("IN_CALL_ENDED_BECAUSE_DECLINED_ELSEWHERE", comment: "Call screen label when call was canceled on this device because the call recipient declined on another device.")
        case .busyElsewhere:
            return NSLocalizedString("IN_CALL_ENDED_BECAUSE_BUSY_ELSEWHERE", comment: "Call screen label when call was canceled on this device because the call recipient has a call in progress on another device.")
        }
    }

    var isBlinkingReconnectLabel = false
    func updateCallStatusLabel() {
        assert(Thread.isMainThread)

        let text = String(format: CallStrings.callStatusFormat,
                          localizedTextForCallState())
        self.callStatusLabel.text = text

        // Handle reconnecting blinking
        if case .reconnecting = call.individualCall.state {
            if !isBlinkingReconnectLabel {
                isBlinkingReconnectLabel = true
                UIView.animate(withDuration: 0.7, delay: 0, options: [.autoreverse, .repeat],
                               animations: {
                                self.callStatusLabel.alpha = 0.2
                }, completion: nil)
            } else {
                // already blinking
            }
        } else {
            // We're no longer in a reconnecting state, either the call failed or we reconnected.
            // Stop the blinking animation
            if isBlinkingReconnectLabel {
                self.callStatusLabel.layer.removeAllAnimations()
                self.callStatusLabel.alpha = 1
                isBlinkingReconnectLabel = false
            }
        }
    }

    func updateCallUI() {
        assert(Thread.isMainThread)
        updateCallStatusLabel()

        // Marquee scrolling is distracting during a video call, disable it.
        contactNameLabel.labelize = call.individualCall.hasLocalVideo

        audioModeMuteButton.isSelected = call.individualCall.isMuted
        videoModeMuteButton.isSelected = call.individualCall.isMuted
        audioModeVideoButton.isSelected = call.individualCall.hasLocalVideo
        videoModeVideoButton.isSelected = call.individualCall.hasLocalVideo

        localVideoView.isHidden = !call.individualCall.hasLocalVideo

        updateRemoteVideoTrack(
            remoteVideoTrack: call.individualCall.isRemoteVideoEnabled ? call.individualCall.remoteVideoTrack : nil
        )

        // Show Incoming vs. Ongoing call controls
        if [.localRinging_Anticipatory, .localRinging_ReadyToAnswer].contains(call.individualCall.state) {
            let isVideoOffer = call.individualCall.offerMediaType == .video
            incomingVideoCallControls.isHidden = !isVideoOffer
            incomingAudioCallControls.isHidden = isVideoOffer
            ongoingVideoCallControls.isHidden = true
            ongoingAudioCallControls.isHidden = true
        } else {
            incomingVideoCallControls.isHidden = true
            incomingAudioCallControls.isHidden = true
            ongoingVideoCallControls.isHidden = !call.individualCall.hasLocalVideo
            ongoingAudioCallControls.isHidden = call.individualCall.hasLocalVideo
        }

        // Rework control state if remote video is available.
        let hasRemoteVideo = !remoteVideoView.isHidden
        remoteVideoView.isFullScreen = true
        remoteVideoView.isScreenShare = call.individualCall.isRemoteSharingScreen
        contactAvatarView.isHidden = hasRemoteVideo || isRenderingLocalVanityVideo

        // Layout controls immediately to avoid spurious animation.
        for controls in [incomingVideoCallControls, incomingAudioCallControls, ongoingAudioCallControls, ongoingVideoCallControls] {
            controls.layoutIfNeeded()
        }

        // Also hide other controls if user has tapped to hide them.
        let hideRemoteControls = shouldRemoteVideoControlsBeHidden && !remoteVideoView.isHidden
        let remoteControlsAreHidden = bottomContainerView.isHidden && topGradientView.isHidden
        if hideRemoteControls != remoteControlsAreHidden {
            self.bottomContainerView.isHidden = false
            self.topGradientView.isHidden = false

            UIView.animate(withDuration: 0.15, animations: {
                self.bottomContainerView.alpha = hideRemoteControls ? 0 : 1
                self.topGradientView.alpha = hideRemoteControls ? 0 : 1
            }) { _ in
                self.bottomContainerView.isHidden = hideRemoteControls
                self.topGradientView.isHidden = hideRemoteControls
            }
        }

        let videoControls = [videoModeAudioSourceButton, videoModeFlipCameraButton, videoModeVideoButton, videoModeMuteButton, videoModeHangUpButton]

        // Audio Source Handling (bluetooth)
        if self.hasAlternateAudioSources, let audioSource = callService.audioService.currentAudioSource {
            audioModeSourceButton.isHidden = false
            videoModeAudioSourceButton.isHidden = false

            videoModeAudioSourceButton.isHidden = !call.individualCall.hasLocalVideo
            videoModeAudioSourceButton.showDropdownArrow = true
            audioModeSourceButton.isHidden = call.individualCall.hasLocalVideo
            audioModeSourceButton.showDropdownArrow = true

            // Use small controls, because we have 5 buttons now.
            videoControls.forEach { $0.isSmall = true }

            if audioSource.isBuiltInEarPiece {
                audioModeSourceButton.iconName = "phone-solid-28"
                videoModeAudioSourceButton.iconName = "phone-solid-28"
            } else if audioSource.isBuiltInSpeaker {
                audioModeSourceButton.iconName = "speaker-solid-28"
                videoModeAudioSourceButton.iconName = "speaker-solid-28"
            } else {
                audioModeSourceButton.iconName = "speaker-bt-solid-28"
                videoModeAudioSourceButton.iconName = "speaker-bt-solid-28"
            }
        } else if UIDevice.current.isIPad {
            // iPad *only* supports speaker mode, if there are no external
            // devices connected, so we don't need to show the button unless
            // we have alternate audio sources.
            audioModeSourceButton.isHidden = true
            videoModeAudioSourceButton.isHidden = true
        } else {
            audioModeSourceButton.isHidden = false
            videoModeAudioSourceButton.isHidden = false

            // No bluetooth audio detected
            audioModeSourceButton.iconName = "speaker-solid-28"
            audioModeSourceButton.showDropdownArrow = false

            videoModeAudioSourceButton.iconName = "speaker-solid-28"
            videoModeAudioSourceButton.showDropdownArrow = false

            videoControls.forEach { $0.isSmall = false }
            videoModeAudioSourceButton.isHidden = true
        }

        // Update local video
        localVideoView.layer.cornerRadius = isRenderingLocalVanityVideo ? 0 : 8
        updateLocalVideoLayout()

        // Dismiss Handling
        switch call.individualCall.state {
        case .remoteHangupNeedPermission:
            displayNeedPermissionErrorAndDismiss()
        case .remoteHangup, .remoteBusy, .localFailure, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            Logger.debug("dismissing after delay because new state is \(call.individualCall.state)")
            dismissIfPossible(shouldDelay: true)
        case .localHangup:
            Logger.debug("dismissing immediately from local hangup")
            dismissIfPossible(shouldDelay: false)
        default: break
        }

        if call.individualCall.state == .connected {
            if callDurationTimer == nil {
                let kDurationUpdateFrequencySeconds = 1 / 20.0
                callDurationTimer = WeakTimer.scheduledTimer(timeInterval: TimeInterval(kDurationUpdateFrequencySeconds),
                                                         target: self,
                                                         userInfo: nil,
                                                         repeats: true) {[weak self] _ in
                                                            self?.updateCallDuration()
                }
            }
        } else {
            callDurationTimer?.invalidate()
            callDurationTimer = nil
        }

        scheduleControlTimeoutIfNecessary()
    }

    func displayNeedPermissionErrorAndDismiss() {
        guard !hasDismissed else { return }

        hasDismissed = true

        callService.audioService.delegate = nil

        contactNameLabel.removeFromSuperview()
        callStatusLabel.removeFromSuperview()
        incomingAudioCallControls.removeFromSuperview()
        incomingVideoCallControls.removeFromSuperview()
        ongoingAudioCallControls.removeFromSuperview()
        ongoingVideoCallControls.removeFromSuperview()
        backButton.removeFromSuperview()

        let needPermissionStack = UIStackView()
        needPermissionStack.axis = .vertical
        needPermissionStack.spacing = 20

        view.addSubview(needPermissionStack)
        needPermissionStack.autoPinWidthToSuperview(withMargin: 16)
        needPermissionStack.autoVCenterInSuperview()

        needPermissionStack.addArrangedSubview(contactAvatarContainerView)
        contactAvatarContainerView.autoSetDimension(.height, toSize: 200)

        let shortName = SDSDatabaseStorage.shared.read {
            return self.contactsManager.shortDisplayName(
                for: self.thread.contactAddress,
                transaction: $0
            )
        }

        let needPermissionLabel = UILabel()
        needPermissionLabel.text = String(
            format: NSLocalizedString("CALL_VIEW_NEED_PERMISSION_ERROR_FORMAT",
                                      comment: "Error displayed on the 'call' view when the callee needs to grant permission before we can call them. Embeds {callee short name}."),
            shortName
        )
        needPermissionLabel.numberOfLines = 0
        needPermissionLabel.lineBreakMode = .byWordWrapping
        needPermissionLabel.textAlignment = .center
        needPermissionLabel.textColor = Theme.darkThemePrimaryColor
        needPermissionLabel.font = .ows_dynamicTypeBody
        needPermissionStack.addArrangedSubview(needPermissionLabel)

        let okayButton = OWSFlatButton()
        okayButton.useDefaultCornerRadius()
        okayButton.setTitle(title: CommonStrings.okayButton, font: UIFont.ows_dynamicTypeBody.ows_semibold, titleColor: Theme.accentBlueColor)
        okayButton.setBackgroundColors(upColor: .ows_gray05)
        okayButton.contentEdgeInsets = UIEdgeInsets(top: 13, left: 34, bottom: 13, right: 34)

        okayButton.setPressedBlock { [weak self] in
            self?.dismissImmediately(completion: nil)
        }

        let okayButtonContainer = UIView()
        okayButtonContainer.addSubview(okayButton)
        okayButton.autoPinHeightToSuperview()
        okayButton.autoHCenterInSuperview()

        needPermissionStack.addArrangedSubview(okayButtonContainer)

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.dismissImmediately(completion: nil)
        }
    }

    func updateCallDuration() {
        updateCallStatusLabel()
    }

    @objc
    private func updateOrientationForPhone(_ notification: Notification) {
        let rotationAngle = notification.object as! CGFloat

        if view.window == nil {
            self.contactAvatarView.transform = CGAffineTransform(rotationAngle: rotationAngle)
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .allowUserInteraction) {
                self.contactAvatarView.transform = CGAffineTransform(rotationAngle: rotationAngle)
            }
        }
    }

    // MARK: - Video control timeout

    private var controlTimeoutTimer: Timer?
    private func scheduleControlTimeoutIfNecessary() {
        if remoteVideoView.isHidden || shouldRemoteVideoControlsBeHidden {
            controlTimeoutTimer?.invalidate()
            controlTimeoutTimer = nil
        }

        guard controlTimeoutTimer == nil else { return }
        controlTimeoutTimer = .weakScheduledTimer(
            withTimeInterval: 5,
            target: self,
            selector: #selector(timeoutControls),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func timeoutControls() {
        controlTimeoutTimer?.invalidate()
        controlTimeoutTimer = nil

        guard !remoteVideoView.isHidden && !shouldRemoteVideoControlsBeHidden else { return }
        shouldRemoteVideoControlsBeHidden = true
    }

    // MARK: - Actions

    /**
     * Ends a connected call. Do not confuse with `didPressDeclineCall`.
     */
    @objc
    func didPressHangup(sender: UIButton) {
        Logger.info("")

        callService.callUIAdapter.localHangupCall(call)

        dismissIfPossible(shouldDelay: false)
    }

    @objc
    func didPressMute(sender: UIButton) {
        Logger.info("")
        let isMuted = !sender.isSelected

        callService.callUIAdapter.setIsMuted(call: call, isMuted: isMuted)
    }

    @objc
    func didPressAudioSource(sender button: UIButton) {
        Logger.info("")

        if self.hasAlternateAudioSources {
            presentAudioSourcePicker()
        } else {
            didPressSpeakerphone(sender: button)
        }
    }

    func didPressSpeakerphone(sender button: UIButton) {
        Logger.info("")

        button.isSelected = !button.isSelected
        callService.audioService.requestSpeakerphone(call: call.individualCall, isEnabled: button.isSelected)
    }

    func didPressTextMessage(sender button: UIButton) {
        Logger.info("")

        dismissIfPossible(shouldDelay: false)
    }

    @objc
    func didPressAnswerCall(sender: UIButton) {
        Logger.info("")

        if sender == videoAnswerIncomingAudioOnlyButton {
            // Answer without video, set state before answering.
            callService.callUIAdapter.setHasLocalVideo(call: call, hasLocalVideo: false)
        }

        callService.callUIAdapter.answerCall(call)

        // We should always be unmuted when we answer an incoming call.
        // Explicitly setting it so will cause us to prompt for
        // microphone permissions if necessary.
        callService.callUIAdapter.setIsMuted(call: call, isMuted: false)
    }

    @objc
    func didPressVideo(sender: UIButton) {
        Logger.info("")
        let hasLocalVideo = !sender.isSelected

        // When turning off video, default speakerphone to on.
        if !hasLocalVideo {
            if !hasAlternateAudioSources {
                audioModeSourceButton.isSelected = true
            }
            callService.audioService.requestSpeakerphone(isEnabled: true)
        }

        callService.callUIAdapter.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    @objc
    func didPressRing(sender: UIButton) {
        owsFailDebug("1:1 calls always ring")
    }

    @objc
    func didPressFlipCamera(sender: UIButton) {
        sender.isSelected = !sender.isSelected

        let isUsingFrontCamera = !sender.isSelected
        Logger.info("with isUsingFrontCamera: \(isUsingFrontCamera)")

        callService.callUIAdapter.setCameraSource(call: call, isUsingFrontCamera: isUsingFrontCamera)
    }

    /**
     * Denies an incoming not-yet-connected call, Do not confuse with `didPressHangup`.
     */
    @objc
    func didPressDeclineCall(sender: UIButton) {
        Logger.info("")

        callService.callUIAdapter.localHangupCall(call)

        dismissIfPossible(shouldDelay: false)
    }

    @objc
    func didTapLeaveCall(sender: UIButton) {
        OWSWindowManager.shared.leaveCallView()
    }

    // MARK: - CallObserver

    internal func individualCallStateDidChange(_ call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("new call status: \(state)")

        self.updateCallUI()
    }

    internal func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI()
    }

    internal func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI()
    }

    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI()
    }

    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        updateRemoteVideoTrack(remoteVideoTrack: isVideoMuted ? nil : call.individualCall.remoteVideoTrack)
    }

    func individualCallRemoteSharingScreenDidChange(_ call: SignalCall, isRemoteSharingScreen: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI()
    }

    // MARK: - CallAudioServiceDelegate

    func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService) {
        AssertIsOnMainThread()

        // Which sources are available depends on the state of your Session.
        // When the audio session is not yet in PlayAndRecord none are available
        // Then if we're in speakerphone, bluetooth isn't available.
        // So we accrue all possible audio sources in a set, and that list lives as longs as the CallViewController
        // The downside of this is that if you e.g. unpair your bluetooth mid call, it will still appear as an option
        // until your next call.
        // FIXME: There's got to be a better way, but this is where I landed after a bit of work, and seems to work
        // pretty well in practice.
        let availableInputs = callAudioService.availableInputs
        self.allAudioSources.formUnion(availableInputs)
        updateCallUI()
    }

    func callAudioServiceDidChangeAudioSource(_ callAudioService: CallAudioService, audioSource: AudioSource?) {
        // You might have switched to a newly available route (like a bluetooth device connecting),
        // update the UI to reflect it.
        let availableInputs = callAudioService.availableInputs
        self.allAudioSources.formUnion(availableInputs)
        updateCallUI()

        guard let audioSource = audioSource else {
            audioModeSourceButton.isSelected = false
            videoModeAudioSourceButton.isSelected = false
            return
        }

        audioModeSourceButton.isSelected = !audioSource.isBuiltInEarPiece
        videoModeAudioSourceButton.isSelected = !audioSource.isBuiltInEarPiece
    }

    // MARK: - Video

    var hasRemoteVideoTrack: Bool {
        return self.remoteVideoTrack != nil
    }

    internal func updateRemoteVideoTrack(remoteVideoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        guard self.remoteVideoTrack != remoteVideoTrack else {
            Logger.debug("ignoring redundant update")
            return
        }

        self.remoteVideoTrack?.remove(remoteVideoView)
        self.remoteVideoTrack = nil
        remoteVideoView.renderFrame(nil)
        self.remoteVideoTrack = remoteVideoTrack
        self.remoteVideoTrack?.add(remoteVideoView)

        shouldRemoteVideoControlsBeHidden = false

        if remoteVideoTrack != nil {
            playRemoteEnabledVideoHapticFeedback()
        }

        updateRemoteVideoLayout()
    }

    // MARK: Video Haptics

    let feedbackGenerator = NotificationHapticFeedback()
    var lastHapticTime: TimeInterval = CACurrentMediaTime()
    func playRemoteEnabledVideoHapticFeedback() {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastHapticTime > 5 else {
            Logger.debug("ignoring haptic feedback since it's too soon")
            return
        }
        feedbackGenerator.notificationOccurred(.success)
        lastHapticTime = currentTime
    }

    // MARK: - Dismiss

    internal func dismissIfPossible(shouldDelay: Bool, completion: (() -> Void)? = nil) {
        callService.audioService.delegate = nil

        if hasDismissed {
            // Don't dismiss twice.
            return
        } else if shouldDelay {
            hasDismissed = true

            if UIApplication.shared.applicationState == .active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.dismissImmediately(completion: completion)
                }
            } else {
                dismissImmediately(completion: completion)
            }
        } else {
            hasDismissed = true
            dismissImmediately(completion: completion)
        }
    }

    internal func dismissImmediately(completion: (() -> Void)?) {
        OWSWindowManager.shared.endCall(self)
        completion?()
    }
}

extension IndividualCallViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return !localVideoView.isHidden && localVideoView.superview == view && call.individualCall.state == .connected
    }
}

extension IndividualCallViewController: CallViewControllerWindowReference {
    var remoteVideoViewReference: UIView { remoteVideoView }
    var localVideoViewReference: UIView { localVideoView }
    var remoteVideoAddress: SignalServiceAddress { thread.contactAddress }

    @objc
    public func returnFromPip(pipWindow: UIWindow) {
        // The call "pip" uses our remote and local video views since only
        // one `AVCaptureVideoPreviewLayer` per capture session is supported.
        // We need to re-add them when we return to this view.
        guard remoteVideoView.superview != view && localVideoView.superview != view else {
            return owsFailDebug("unexpectedly returned to call while we own the video views")
        }

        guard let splitViewSnapshot = SignalApp.shared().snapshotSplitViewController(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot rootViewController")
        }

        guard let pipSnapshot = pipWindow.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot pip")
        }

        view.insertSubview(remoteVideoView, aboveSubview: blurView)
        remoteVideoView.autoPinEdgesToSuperviewEdges()

        view.insertSubview(localVideoView, aboveSubview: contactAvatarContainerView)

        updateLocalVideoLayout()

        shouldRemoteVideoControlsBeHidden = false

        animateReturnFromPip(pipSnapshot: pipSnapshot, pipFrame: pipWindow.frame, splitViewSnapshot: splitViewSnapshot)
    }

    private func animateReturnFromPip(pipSnapshot: UIView, pipFrame: CGRect, splitViewSnapshot: UIView) {
        guard let window = view.window else { return owsFailDebug("missing window") }
        view.superview?.insertSubview(splitViewSnapshot, belowSubview: view)
        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        view.frame = pipFrame
        view.addSubview(pipSnapshot)
        pipSnapshot.autoPinEdgesToSuperviewEdges()

        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            pipSnapshot.alpha = 0
            self.view.frame = window.frame
            self.view.layoutIfNeeded()
        }) { _ in
            self.updateCallUI()
            splitViewSnapshot.removeFromSuperview()
            pipSnapshot.removeFromSuperview()
        }
    }
}
