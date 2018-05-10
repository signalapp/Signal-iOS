//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC
import PromiseKit
import SignalServiceKit
import SignalMessaging

// TODO: Add category so that button handlers can be defined where button is created.
// TODO: Ensure buttons enabled & disabled as necessary.
class CallViewController: OWSViewController, CallObserver, CallServiceObserver, CallAudioServiceDelegate {

    let TAG = "[CallViewController]"

    // Dependencies
    var callUIAdapter: CallUIAdapter {
        return SignalApp.shared().callUIAdapter
    }

    // Feature Flag
    @objc public static let kShowCallViewOnSeparateWindow = true

    let contactsManager: OWSContactsManager

    // MARK: - Properties

    let thread: TSContactThread
    let call: SignalCall
    var hasDismissed = false

    // MARK: - Views

    var hasConstraints = false
    var blurView: UIVisualEffectView!
    var dateFormatter: DateFormatter?

    // MARK: - Contact Views

    var contactNameLabel: MarqueeLabel!
    var contactAvatarView: AvatarImageView!
    var contactAvatarContainerView: UIView!
    var callStatusLabel: UILabel!
    var callDurationTimer: Timer?

    // MARK: - Ongoing Call Controls

    var ongoingCallControls: UIStackView!

    var ongoingAudioCallControls: UIStackView!
    var ongoingVideoCallControls: UIStackView!

    var hangUpButton: UIButton!
    var audioSourceButton: UIButton!
    var audioModeMuteButton: UIButton!
    var audioModeVideoButton: UIButton!
    var videoModeMuteButton: UIButton!
    var videoModeVideoButton: UIButton!
    var videoModeFlipCameraButton: UIButton!

    // MARK: - Incoming Call Controls

    var incomingCallControls: UIStackView!

    var acceptIncomingButton: UIButton!
    var declineIncomingButton: UIButton!

    // MARK: - Video Views

    var remoteVideoView: RemoteVideoView!
    var localVideoView: RTCCameraPreviewView!
    weak var localVideoTrack: RTCVideoTrack?
    weak var remoteVideoTrack: RTCVideoTrack?
    var localVideoConstraints: [NSLayoutConstraint] = []

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    var shouldRemoteVideoControlsBeHidden = false {
        didSet {
            updateCallUI(callState: call.state)
        }
    }

    // MARK: - Settings Nag Views

    var isShowingSettingsNag = false {
        didSet {
            if oldValue != isShowingSettingsNag {
                updateCallUI(callState: call.state)
            }
        }
    }
    var settingsNagView: UIView!
    var settingsNagDescriptionLabel: UILabel!

    // MARK: - Audio Source

    var hasAlternateAudioSources: Bool {
        Logger.info("\(TAG) available audio sources: \(allAudioSources)")
        // internal mic and speakerphone will be the first two, any more than one indicates e.g. an attached bluetooth device.

        // TODO is this sufficient? Are their devices w/ bluetooth but no external speaker? e.g. ipod?
        return allAudioSources.count > 2
    }

    var allAudioSources: Set<AudioSource> = Set()

    var appropriateAudioSources: Set<AudioSource> {
        if call.hasLocalVideo {
            let appropriateForVideo = allAudioSources.filter { audioSource in
                if audioSource.isBuiltInSpeaker {
                    return true
                } else {
                    guard let portDescription = audioSource.portDescription else {
                        owsFail("Only built in speaker should be lacking a port description.")
                        return false
                    }

                    // Don't use receiver when video is enabled. Only bluetooth or speaker
                    return portDescription.portType != AVAudioSessionPortBuiltInMic
                }
            }
            return Set(appropriateForVideo)
        } else {
            return allAudioSources
        }
    }

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(call: SignalCall) {
        contactsManager = Environment.current().contactsManager
        self.call = call
        self.thread = TSContactThread.getOrCreateThread(contactId: call.remotePhoneNumber)
        super.init(nibName: nil, bundle: nil)

        allAudioSources = Set(callUIAdapter.audioService.availableInputs)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func didBecomeActive() {
        if (self.isViewLoaded) {
            shouldRemoteVideoControlsBeHidden = false
        }
    }

    // MARK: - View Lifecycle

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        UIDevice.current.isProximityMonitoringEnabled = false

        callDurationTimer?.invalidate()
        callDurationTimer = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIDevice.current.isProximityMonitoringEnabled = true
        updateCallUI(callState: call.state)

        self.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()
    }

    override func loadView() {
        self.view = UIView()

        self.view.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        createViews()
        createViewConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        contactNameLabel.text = contactsManager.stringForConversationTitle(withPhoneIdentifier: thread.contactIdentifier())
        updateAvatarImage()
        NotificationCenter.default.addObserver(forName: .OWSContactsManagerSignalAccountsDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let strongSelf = self else { return }
            Logger.info("\(strongSelf.TAG) updating avatar image")
            strongSelf.updateAvatarImage()
        }

        // Subscribe for future call updates
        call.addObserverAndSyncState(observer: self)

        SignalApp.shared().callService.addObserverAndSyncState(observer: self)

        assert(callUIAdapter.audioService.delegate == nil)
        callUIAdapter.audioService.delegate = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    // MARK: - Create Views

    func createViews() {
        self.view.isUserInteractionEnabled = true
        self.view.addGestureRecognizer(OWSAnyTouchGestureRecognizer(target: self,
                                                                    action: #selector(didTouchRootView)))

        // Dark blurred background.
        let blurEffect = UIBlurEffect(style: .dark)
        blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        self.view.addSubview(blurView)

        self.view.setHLayoutMargins(0)

        // Create the video views first, as they are under the other views.
        createVideoViews()
        createContactViews()
        createOngoingCallControls()
        createIncomingCallControls()
        createSettingsNagViews()
    }

    func didTouchRootView(sender: UIGestureRecognizer) {
        if !remoteVideoView.isHidden {
            shouldRemoteVideoControlsBeHidden = !shouldRemoteVideoControlsBeHidden
        }
    }

    func createVideoViews() {
        remoteVideoView = RemoteVideoView()
        remoteVideoView.isUserInteractionEnabled = false
        localVideoView = RTCCameraPreviewView()

        remoteVideoView.isHidden = true
        localVideoView.isHidden = true
        self.view.addSubview(remoteVideoView)
        self.view.addSubview(localVideoView)
    }

    func createContactViews() {
        contactNameLabel = MarqueeLabel()

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
        contactNameLabel.font = UIFont.ows_lightFont(withSize: ScaleFromIPhone5To7Plus(32, 40))
        contactNameLabel.textColor = UIColor.white
        contactNameLabel.layer.shadowOffset = CGSize.zero
        contactNameLabel.layer.shadowOpacity = 0.35
        contactNameLabel.layer.shadowRadius = 4

        self.view.addSubview(contactNameLabel)

        callStatusLabel = UILabel()
        callStatusLabel.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(19, 25))
        callStatusLabel.textColor = UIColor.white
        callStatusLabel.layer.shadowOffset = CGSize.zero
        callStatusLabel.layer.shadowOpacity = 0.35
        callStatusLabel.layer.shadowRadius = 4
        self.view.addSubview(callStatusLabel)

        contactAvatarContainerView = UIView.container()
        self.view.addSubview(contactAvatarContainerView)
        contactAvatarView = AvatarImageView()
        contactAvatarContainerView.addSubview(contactAvatarView)
    }

    func createSettingsNagViews() {
        settingsNagView = UIView()
        settingsNagView.isHidden = true
        self.view.addSubview(settingsNagView)

        let viewStack = UIView()
        settingsNagView.addSubview(viewStack)
        viewStack.autoPinWidthToSuperview()
        viewStack.autoVCenterInSuperview()

        settingsNagDescriptionLabel = UILabel()
        settingsNagDescriptionLabel.text = NSLocalizedString("CALL_VIEW_SETTINGS_NAG_DESCRIPTION_ALL",
                                                             comment: "Reminder to the user of the benefits of enabling CallKit and disabling CallKit privacy.")
        settingsNagDescriptionLabel.font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(16, 18))
        settingsNagDescriptionLabel.textColor = UIColor.white
        settingsNagDescriptionLabel.numberOfLines = 0
        settingsNagDescriptionLabel.lineBreakMode = .byWordWrapping
        viewStack.addSubview(settingsNagDescriptionLabel)
        settingsNagDescriptionLabel.autoPinWidthToSuperview()
        settingsNagDescriptionLabel.autoPinEdge(toSuperviewEdge: .top)

        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)
        let descriptionVSpacingHeight = ScaleFromIPhone5To7Plus(30, 60)

        let callSettingsButton = OWSFlatButton.button(title: NSLocalizedString("CALL_VIEW_SETTINGS_NAG_SHOW_CALL_SETTINGS",
                                                                              comment: "Label for button that shows the privacy settings."),
                                                      font: OWSFlatButton.fontForHeight(buttonHeight),
                                                      titleColor: UIColor.white,
                                                      backgroundColor: UIColor.ows_signalBrandBlue,
                                                      target: self,
                                                      selector: #selector(didPressShowCallSettings))
        viewStack.addSubview(callSettingsButton)
        callSettingsButton.autoSetDimension(.height, toSize: buttonHeight)
        callSettingsButton.autoPinWidthToSuperview()
        callSettingsButton.autoPinEdge(.top, to: .bottom, of: settingsNagDescriptionLabel, withOffset: descriptionVSpacingHeight)

        let notNowButton = OWSFlatButton.button(title: NSLocalizedString("CALL_VIEW_SETTINGS_NAG_NOT_NOW_BUTTON",
                                                                        comment: "Label for button that dismiss the call view's settings nag."),
                                                font: OWSFlatButton.fontForHeight(buttonHeight),
                                                titleColor: UIColor.white,
                                                backgroundColor: UIColor.ows_signalBrandBlue,
                                                target: self,
                                                selector: #selector(didPressDismissNag))
        viewStack.addSubview(notNowButton)
        notNowButton.autoSetDimension(.height, toSize: buttonHeight)
        notNowButton.autoPinWidthToSuperview()
        notNowButton.autoPinEdge(toSuperviewEdge: .bottom)
        notNowButton.autoPinEdge(.top, to: .bottom, of: callSettingsButton, withOffset: 12)
    }

    func buttonSize() -> CGFloat {
        return ScaleFromIPhone5To7Plus(84, 108)
    }

    func buttonInset() -> CGFloat {
        return ScaleFromIPhone5To7Plus(7, 9)
    }

    func createOngoingCallControls() {

//        textMessageButton = createButton(imageName:"message-active-wide",
//                                                action:#selector(didPressTextMessage))
        audioSourceButton = createButton(image: #imageLiteral(resourceName: "audio-call-speaker-inactive"),
                                          action: #selector(didPressAudioSource))
        audioSourceButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_AUDIO_SOURCE_LABEL",
                                                                 comment: "Accessibility label for selection the audio source")

        hangUpButton = createButton(image: #imageLiteral(resourceName: "hangup-active-wide"),
                                    action: #selector(didPressHangup))
        hangUpButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_HANGUP_LABEL",
                                                            comment: "Accessibility label for hang up call")

        audioModeMuteButton = createButton(image: #imageLiteral(resourceName: "audio-call-mute-inactive"),
                                           action: #selector(didPressMute))
        audioModeMuteButton.setImage(#imageLiteral(resourceName: "audio-call-mute-active"), for: .selected)

        audioModeMuteButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_MUTE_LABEL",
                                                                   comment: "Accessibility label for muting the microphone")

        audioModeVideoButton = createButton(image: #imageLiteral(resourceName: "audio-call-video-inactive"),
                                            action: #selector(didPressVideo))
        audioModeVideoButton.setImage(#imageLiteral(resourceName: "audio-call-video-active"), for: .selected)
        audioModeVideoButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_TO_VIDEO_LABEL", comment: "Accessibility label to switch to video call")

        videoModeMuteButton = createButton(image: #imageLiteral(resourceName: "video-mute-unselected"),
                                           action: #selector(didPressMute))
        videoModeMuteButton.setImage(#imageLiteral(resourceName: "video-mute-selected"), for: .selected)
        videoModeMuteButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_MUTE_LABEL", comment: "Accessibility label for muting the microphone")
        videoModeMuteButton.alpha = 0.9

        videoModeFlipCameraButton = createButton(image: #imageLiteral(resourceName: "video-switch-camera-unselected"),
                                                 action: #selector(didPressFlipCamera))

        videoModeFlipCameraButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_CAMERA_DIRECTION", comment: "Accessibility label to toggle front vs. rear facing camera")
        videoModeFlipCameraButton.alpha = 0.9

        videoModeVideoButton = createButton(image: #imageLiteral(resourceName: "video-video-unselected"),
                                            action: #selector(didPressVideo))
        videoModeVideoButton.setImage(#imageLiteral(resourceName: "video-video-selected"), for: .selected)
        videoModeVideoButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_SWITCH_TO_AUDIO_LABEL", comment: "Accessibility label to switch to audio only")
        videoModeVideoButton.alpha = 0.9

        ongoingCallControls = UIStackView(arrangedSubviews: [hangUpButton])
        ongoingCallControls.axis = .vertical
        ongoingCallControls.alignment = .center
        view.addSubview(ongoingCallControls)

        ongoingAudioCallControls = UIStackView(arrangedSubviews: [audioModeMuteButton, audioSourceButton, audioModeVideoButton])
        ongoingAudioCallControls.distribution = .equalSpacing
        ongoingAudioCallControls.axis = .horizontal

        ongoingVideoCallControls = UIStackView(arrangedSubviews: [videoModeMuteButton, videoModeFlipCameraButton, videoModeVideoButton])
        ongoingAudioCallControls.distribution = .equalSpacing
        ongoingVideoCallControls.axis = .horizontal
    }

    func presentAudioSourcePicker() {
        SwiftAssertIsOnMainThread(#function)

        let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let dismissAction = UIAlertAction(title: CommonStrings.dismissButton, style: .cancel, handler: nil)
        actionSheetController.addAction(dismissAction)

        let currentAudioSource = callUIAdapter.audioService.currentAudioSource(call: self.call)
        for audioSource in self.appropriateAudioSources {
            let routeAudioAction = UIAlertAction(title: audioSource.localizedName, style: .default) { _ in
                self.callUIAdapter.setAudioSource(call: self.call, audioSource: audioSource)
            }

            // HACK: private API to create checkmark for active audio source.
            routeAudioAction.setValue(currentAudioSource == audioSource, forKey: "checked")

            // TODO: pick some icons. Leaving out for MVP
            // HACK: private API to add image to actionsheet
            // routeAudioAction.setValue(audioSource.image, forKey: "image")

            actionSheetController.addAction(routeAudioAction)
        }

        // Note: It's critical that we present from this view and
        // not the "frontmost view controller" since this view may
        // reside on a separate window.
        self.present(actionSheetController, animated: true)
    }

    func updateAvatarImage() {
        contactAvatarView.image = OWSAvatarBuilder.buildImage(thread: thread, diameter: 400, contactsManager: contactsManager)
    }

    func createIncomingCallControls() {

        acceptIncomingButton = createButton(image: #imageLiteral(resourceName: "call-active-wide"),
                                            action: #selector(didPressAnswerCall))
        acceptIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_ACCEPT_INCOMING_CALL_LABEL",
                                                                    comment: "Accessibility label for accepting incoming calls")
        declineIncomingButton = createButton(image: #imageLiteral(resourceName: "hangup-active-wide"),
                                             action: #selector(didPressDeclineCall))
        declineIncomingButton.accessibilityLabel = NSLocalizedString("CALL_VIEW_DECLINE_INCOMING_CALL_LABEL",
                                                                     comment: "Accessibility label for declining incoming calls")

        incomingCallControls = UIStackView(arrangedSubviews: [acceptIncomingButton, declineIncomingButton])
        incomingCallControls.axis = .horizontal
        incomingCallControls.alignment = .center
        incomingCallControls.distribution = .equalSpacing

        view.addSubview(incomingCallControls)
    }

    func createButton(image: UIImage, action: Selector) -> UIButton {
        let button = UIButton()
        button.setImage(image, for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: buttonInset(),
                                              left: buttonInset(),
                                              bottom: buttonInset(),
                                              right: buttonInset())
        button.addTarget(self, action: action, for: .touchUpInside)
        button.autoSetDimension(.width, toSize: buttonSize())
        button.autoSetDimension(.height, toSize: buttonSize())
        return button
    }

    // MARK: - Layout

    func createViewConstraints() {
        let topMargin = CGFloat(40)
        let contactVSpacing = CGFloat(3)
        let settingsNagHMargin = CGFloat(30)
        let ongoingBottomMargin = ScaleFromIPhone5To7Plus(23, 41)
        let incomingHMargin = ScaleFromIPhone5To7Plus(30, 56)
        let incomingBottomMargin = CGFloat(41)
        let settingsNagBottomMargin = CGFloat(41)
        let avatarTopSpacing = ScaleFromIPhone5To7Plus(25, 50)
        // The buttons have built-in 10% margins, so to appear centered
        // the avatar's bottom spacing should be a bit less.
        let avatarBottomSpacing = ScaleFromIPhone5To7Plus(18, 41)
        // Layout of the local video view is a bit unusual because
        // although the view is square, it will be used
        let videoPreviewHMargin = CGFloat(0)

        // Dark blurred background.
        blurView.autoPinEdgesToSuperviewEdges()

        localVideoView.autoPinTrailingToSuperviewMargin(withInset: videoPreviewHMargin)
        localVideoView.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
        let localVideoSize = ScaleFromIPhone5To7Plus(80, 100)
        localVideoView.autoSetDimension(.width, toSize: localVideoSize)
        localVideoView.autoSetDimension(.height, toSize: localVideoSize)

        remoteVideoView.autoPinEdgesToSuperviewEdges()

        contactNameLabel.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
        contactNameLabel.autoPinLeadingToSuperviewMargin()
        contactNameLabel.setContentHuggingVerticalHigh()
        contactNameLabel.setCompressionResistanceHigh()

        callStatusLabel.autoPinEdge(.top, to: .bottom, of: contactNameLabel, withOffset: contactVSpacing)
        callStatusLabel.autoPinLeadingToSuperviewMargin()
        callStatusLabel.setContentHuggingVerticalHigh()
        callStatusLabel.setCompressionResistanceHigh()

        contactAvatarContainerView.autoPinEdge(.top, to: .bottom, of: callStatusLabel, withOffset: +avatarTopSpacing)
        contactAvatarContainerView.autoPinEdge(.bottom, to: .top, of: ongoingCallControls, withOffset: -avatarBottomSpacing)
        contactAvatarContainerView.autoPinWidthToSuperview(withMargin: avatarTopSpacing)

        contactAvatarView.autoCenterInSuperview()

        // Ensure ContacAvatarView gets as close as possible to it's superview edges while maintaining
        // aspect ratio.
        contactAvatarView.autoPinToSquareAspectRatio()
        contactAvatarView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
        contactAvatarView.autoPinEdge(toSuperviewEdge: .right, withInset: 0, relation: .greaterThanOrEqual)
        contactAvatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0, relation: .greaterThanOrEqual)
        contactAvatarView.autoPinEdge(toSuperviewEdge: .left, withInset: 0, relation: .greaterThanOrEqual)
        NSLayoutConstraint.autoSetPriority(UILayoutPriorityDefaultLow) {
            contactAvatarView.autoPinEdgesToSuperviewMargins()
        }

        // Ongoing call controls
        ongoingCallControls.autoPinEdge(toSuperviewEdge: .bottom, withInset: ongoingBottomMargin)
        ongoingCallControls.autoPinLeadingToSuperviewMargin()
        ongoingCallControls.autoPinTrailingToSuperviewMargin()
        ongoingCallControls.setContentHuggingVerticalHigh()

        // Incoming call controls
        incomingCallControls.autoPinEdge(toSuperviewEdge: .bottom, withInset: incomingBottomMargin)
        incomingCallControls.autoPinLeadingToSuperviewMargin(withInset: incomingHMargin)
        incomingCallControls.autoPinTrailingToSuperviewMargin(withInset: incomingHMargin)
        incomingCallControls.setContentHuggingVerticalHigh()

        // Settings nag views
        settingsNagView.autoPinEdge(toSuperviewEdge: .bottom, withInset: settingsNagBottomMargin)
        settingsNagView.autoPinWidthToSuperview(withMargin: settingsNagHMargin)
        settingsNagView.autoPinEdge(.top, to: .bottom, of: callStatusLabel)
    }

    override func updateViewConstraints() {
        updateRemoteVideoLayout()
        updateLocalVideoLayout()

        super.updateViewConstraints()
    }

    internal func updateRemoteVideoLayout() {
        remoteVideoView.isHidden = !self.hasRemoteVideoTrack
        updateCallUI(callState: call.state)
    }

    internal func updateLocalVideoLayout() {

        NSLayoutConstraint.deactivate(self.localVideoConstraints)

        var constraints: [NSLayoutConstraint] = []

        if localVideoView.isHidden {
            let contactHMargin = CGFloat(5)
            constraints.append(contactNameLabel.autoPinTrailingToSuperviewMargin(withInset: contactHMargin))
            constraints.append(callStatusLabel.autoPinTrailingToSuperviewMargin(withInset: contactHMargin))
        } else {
            let spacing = CGFloat(10)
            constraints.append(localVideoView.autoPinLeading(toTrailingEdgeOf: contactNameLabel, offset: spacing))
            constraints.append(localVideoView.autoPinLeading(toTrailingEdgeOf: callStatusLabel, offset: spacing))
        }

        self.localVideoConstraints = constraints
        updateCallUI(callState: call.state)
    }

    // MARK: - Methods

    func showCallFailed(error: Error) {
        // TODO Show something in UI.
        Logger.error("\(TAG) call failed with error: \(error)")
    }

    // MARK: - View State

    func localizedTextForCallState(_ callState: CallState) -> String {
        assert(Thread.isMainThread)

        switch callState {
        case .idle, .remoteHangup, .localHangup:
            return NSLocalizedString("IN_CALL_TERMINATED", comment: "Call setup status label")
        case .dialing:
            return NSLocalizedString("IN_CALL_CONNECTING", comment: "Call setup status label")
        case .remoteRinging, .localRinging:
            return NSLocalizedString("IN_CALL_RINGING", comment: "Call setup status label")
        case .answering:
            return NSLocalizedString("IN_CALL_SECURING", comment: "Call setup status label")
        case .connected:
            let callDuration = call.connectionDuration()
            let callDurationDate = Date(timeIntervalSinceReferenceDate: callDuration)
            if dateFormatter == nil {
                dateFormatter = DateFormatter()
                dateFormatter!.dateFormat = "HH:mm:ss"
                dateFormatter!.timeZone = TimeZone(identifier: "UTC")!
            }
            var formattedDate = dateFormatter!.string(from: callDurationDate)
            if formattedDate.hasPrefix("00:") {
                // Don't show the "hours" portion of the date format unless the
                // call duration is at least 1 hour.
                formattedDate = formattedDate.substring(from: formattedDate.index(formattedDate.startIndex, offsetBy: 3))
            } else {
                // If showing the "hours" portion of the date format, strip any leading
                // zeroes.
                if formattedDate.hasPrefix("0") {
                    formattedDate = formattedDate.substring(from: formattedDate.index(formattedDate.startIndex, offsetBy: 1))
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
                    if self.call.direction == .outgoing {
                        return NSLocalizedString("CALL_SCREEN_STATUS_NO_ANSWER", comment: "Call setup status label after outgoing call times out")
                    }
                default:
                    break
                }
            }

            return NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label")
        }
    }

    var isBlinkingReconnectLabel = false
    func updateCallStatusLabel(callState: CallState) {
        assert(Thread.isMainThread)

        let text = String(format: CallStrings.callStatusFormat,
                          localizedTextForCallState(callState))
        self.callStatusLabel.text = text

        // Handle reconnecting blinking
        if case .reconnecting = callState {
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

    func updateCallUI(callState: CallState) {
        assert(Thread.isMainThread)
        updateCallStatusLabel(callState: callState)
        if isShowingSettingsNag {
            settingsNagView.isHidden = false
            contactAvatarView.isHidden = true
            ongoingCallControls.isHidden = true
            return
        }

        // Marquee scrolling is distracting during a video call, disable it.
        contactNameLabel.labelize = call.hasLocalVideo

        audioModeMuteButton.isSelected = call.isMuted
        videoModeMuteButton.isSelected = call.isMuted
        audioModeVideoButton.isSelected = call.hasLocalVideo
        videoModeVideoButton.isSelected = call.hasLocalVideo

        // Show Incoming vs. Ongoing call controls
        let isRinging = callState == .localRinging
        incomingCallControls.isHidden = !isRinging
        incomingCallControls.isUserInteractionEnabled = isRinging
        ongoingCallControls.isHidden = isRinging
        ongoingCallControls.isUserInteractionEnabled = !isRinging

        // Rework control state if remote video is available.
        let hasRemoteVideo = !remoteVideoView.isHidden
        contactAvatarView.isHidden = hasRemoteVideo

        // Rework control state if local video is available.
        let hasLocalVideo = !localVideoView.isHidden

        if hasLocalVideo {
            ongoingAudioCallControls.removeFromSuperview()
            ongoingCallControls.insertArrangedSubview(ongoingVideoCallControls, at: 0)
        } else {
            ongoingVideoCallControls.removeFromSuperview()
            ongoingCallControls.insertArrangedSubview(ongoingAudioCallControls, at: 0)
        }

        // Also hide other controls if user has tapped to hide them.
        if shouldRemoteVideoControlsBeHidden && !remoteVideoView.isHidden {
            contactNameLabel.isHidden = true
            callStatusLabel.isHidden = true
            ongoingCallControls.isHidden = true
        } else {
            contactNameLabel.isHidden = false
            callStatusLabel.isHidden = false
        }

        // Audio Source Handling (bluetooth)
        if self.hasAlternateAudioSources {
            // With bluetooth, button does not stay selected. Pressing it pops an actionsheet
            // and the button should immediately "unselect".
            audioSourceButton.isSelected = false

            if hasLocalVideo {
                audioSourceButton.setImage(#imageLiteral(resourceName: "ic_speaker_bluetooth_inactive_video_mode"), for: .normal)
                audioSourceButton.setImage(#imageLiteral(resourceName: "ic_speaker_bluetooth_inactive_video_mode"), for: .selected)
            } else {
                audioSourceButton.setImage(#imageLiteral(resourceName: "ic_speaker_bluetooth_inactive_audio_mode"), for: .normal)
                audioSourceButton.setImage(#imageLiteral(resourceName: "ic_speaker_bluetooth_inactive_audio_mode"), for: .selected)
            }
            audioSourceButton.isHidden = false
        } else {
            // No bluetooth audio detected
            audioSourceButton.setImage(#imageLiteral(resourceName: "audio-call-speaker-inactive"), for: .normal)
            audioSourceButton.setImage(#imageLiteral(resourceName: "audio-call-speaker-active"), for: .selected)

            // If there's no bluetooth, we always use speakerphone, so no need for
            // a button, giving more screen back for the video.
            audioSourceButton.isHidden = hasLocalVideo
        }

        // Dismiss Handling
        switch callState {
        case .remoteHangup, .remoteBusy, .localFailure:
            Logger.debug("\(TAG) dismissing after delay because new state is \(callState)")
            dismissIfPossible(shouldDelay: true)
        case .localHangup:
            Logger.debug("\(TAG) dismissing immediately from local hangup")
            dismissIfPossible(shouldDelay: false)
        default: break
        }

        if callState == .connected {
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
    }

    func updateCallDuration() {
        updateCallStatusLabel(callState: call.state)
    }

    // We update the audioSourceButton outside of the main `updateCallUI`
    // because `updateCallUI` is intended to be idempotent, which isn't possible
    // with external speaker state because:
    // - the system API which enables the external speaker is a (somewhat slow) asyncronous
    //   operation
    // - we want to give immediate UI feedback by marking the pressed button as selected
    //   before the operation completes.
    func updateAudioSourceButtonIsSelected() {
        guard callUIAdapter.audioService.isSpeakerphoneEnabled else {
            self.audioSourceButton.isSelected = false
            return
        }

        // VideoChat mode enables the output speaker, but we don't
        // want to highlight the speaker button in that case.
        guard !call.hasLocalVideo else {
            self.audioSourceButton.isSelected = false
            return
        }

        self.audioSourceButton.isSelected = true
    }

    // MARK: - Actions

    /**
     * Ends a connected call. Do not confuse with `didPressDeclineCall`.
     */
    func didPressHangup(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        callUIAdapter.localHangupCall(call)

        dismissIfPossible(shouldDelay: false)
    }

    func didPressMute(sender muteButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        muteButton.isSelected = !muteButton.isSelected

        self.didTapLeaveCall()

        callUIAdapter.setIsMuted(call: call, isMuted: muteButton.isSelected)
    }

    func didPressAudioSource(sender button: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        if self.hasAlternateAudioSources {
            presentAudioSourcePicker()
        } else {
            didPressSpeakerphone(sender: button)
        }
    }

    func didPressSpeakerphone(sender button: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        button.isSelected = !button.isSelected
        callUIAdapter.audioService.requestSpeakerphone(isEnabled: button.isSelected)
    }

    func didPressTextMessage(sender button: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        dismissIfPossible(shouldDelay: false)
    }

    func didPressAnswerCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        callUIAdapter.answerCall(call)
    }

    func didPressVideo(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        let hasLocalVideo = !sender.isSelected

        callUIAdapter.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
    }

    func didPressFlipCamera(sender: UIButton) {
        // toggle value
        sender.isSelected = !sender.isSelected

        let useBackCamera = sender.isSelected
        Logger.info("\(TAG) in \(#function) with useBackCamera: \(useBackCamera)")

        callUIAdapter.setCameraSource(call: call, useBackCamera: useBackCamera)
    }

    /**
     * Denies an incoming not-yet-connected call, Do not confuse with `didPressHangup`.
     */
    func didPressDeclineCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        callUIAdapter.declineCall(call)

        dismissIfPossible(shouldDelay: false)
    }

    func didPressShowCallSettings(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        markSettingsNagAsComplete()

        dismissIfPossible(shouldDelay: false, ignoreNag: true, completion: {
            // Find the frontmost presented UIViewController from which to present the
            // settings views.
            let fromViewController = UIApplication.shared.findFrontmostViewController(ignoringAlerts: true)
            assert(fromViewController != nil)

            // Construct the "settings" view & push the "privacy settings" view.
            let navigationController = AppSettingsViewController.inModalNavigationController()
            navigationController.pushViewController(PrivacySettingsTableViewController(), animated: false)

            fromViewController?.present(navigationController, animated: true, completion: nil)
        })
    }

    func didPressDismissNag(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        markSettingsNagAsComplete()

        dismissIfPossible(shouldDelay: false, ignoreNag: true)
    }

    // We only show the "blocking" settings nag until the user has chosen
    // to view the privacy settings _or_ dismissed the nag at least once.
    // 
    // In either case, we set the "CallKit enabled" and "CallKit privacy enabled" 
    // settings to their default values to indicate that the user has reviewed
    // them.
    private func markSettingsNagAsComplete() {
        Logger.info("\(TAG) called \(#function)")

        let preferences = Environment.current().preferences!

        preferences.setIsCallKitEnabled(preferences.isCallKitEnabled())
        preferences.setIsCallKitPrivacyEnabled(preferences.isCallKitPrivacyEnabled())
    }

//    func didTapLeaveCall(sender: UIGestureRecognizer) {
    func didTapLeaveCall() {
        OWSWindowManager.shared().leaveCallView()
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        SwiftAssertIsOnMainThread(#function)
        Logger.info("\(self.TAG) new call status: \(state)")
        self.updateCallUI(callState: state)
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        SwiftAssertIsOnMainThread(#function)
        self.updateCallUI(callState: call.state)
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        SwiftAssertIsOnMainThread(#function)
        self.updateCallUI(callState: call.state)
    }

    func holdDidChange(call: SignalCall, isOnHold: Bool) {
        SwiftAssertIsOnMainThread(#function)
        self.updateCallUI(callState: call.state)
    }

    internal func audioSourceDidChange(call: SignalCall, audioSource: AudioSource?) {
        SwiftAssertIsOnMainThread(#function)
        self.updateCallUI(callState: call.state)
    }

    // MARK: - CallAudioServiceDelegate

    func callAudioService(_ callAudioService: CallAudioService, didUpdateIsSpeakerphoneEnabled isSpeakerphoneEnabled: Bool) {
        SwiftAssertIsOnMainThread(#function)

        updateAudioSourceButtonIsSelected()
    }

    func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService) {
        SwiftAssertIsOnMainThread(#function)

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
    }

    // MARK: - Video

    internal func updateLocalVideoTrack(localVideoTrack: RTCVideoTrack?) {
        SwiftAssertIsOnMainThread(#function)
        guard self.localVideoTrack != localVideoTrack else {
            return
        }

        self.localVideoTrack = localVideoTrack

        let source = localVideoTrack?.source as? RTCAVFoundationVideoSource

        localVideoView.captureSession = source?.captureSession
        let isHidden = source == nil
        Logger.info("\(TAG) \(#function) isHidden: \(isHidden)")
        localVideoView.isHidden = isHidden

        updateLocalVideoLayout()
        updateAudioSourceButtonIsSelected()
    }

    var hasRemoteVideoTrack: Bool {
        return self.remoteVideoTrack != nil
    }

    internal func updateRemoteVideoTrack(remoteVideoTrack: RTCVideoTrack?) {
        SwiftAssertIsOnMainThread(#function)
        guard self.remoteVideoTrack != remoteVideoTrack else {
            return
        }

        self.remoteVideoTrack?.remove(remoteVideoView)
        self.remoteVideoTrack = nil
        remoteVideoView.renderFrame(nil)
        self.remoteVideoTrack = remoteVideoTrack
        self.remoteVideoTrack?.add(remoteVideoView)
        shouldRemoteVideoControlsBeHidden = false

        updateRemoteVideoLayout()
    }

    internal func dismissIfPossible(shouldDelay: Bool, ignoreNag ignoreNagParam: Bool = false, completion: (() -> Void)? = nil) {
        callUIAdapter.audioService.delegate = nil

        let ignoreNag: Bool = {
            // Nothing to nag about on iOS11
            if #available(iOS 11, *) {
                return true
            } else {
                // otherwise on iOS10, nag as specified
                return ignoreNagParam
            }
        }()

        if hasDismissed {
            // Don't dismiss twice.
            return
        } else if !ignoreNag &&
            call.direction == .incoming &&
            UIDevice.current.supportsCallKit &&
            (!Environment.current().preferences.isCallKitEnabled() ||
                Environment.current().preferences.isCallKitPrivacyEnabled()) {

            isShowingSettingsNag = true

            // Update the nag view's copy to reflect the settings state.
            if Environment.current().preferences.isCallKitEnabled() {
                settingsNagDescriptionLabel.text = NSLocalizedString("CALL_VIEW_SETTINGS_NAG_DESCRIPTION_PRIVACY",
                                                                     comment: "Reminder to the user of the benefits of disabling CallKit privacy.")
            } else {
                settingsNagDescriptionLabel.text = NSLocalizedString("CALL_VIEW_SETTINGS_NAG_DESCRIPTION_ALL",
                                                                     comment: "Reminder to the user of the benefits of enabling CallKit and disabling CallKit privacy.")
            }
            settingsNagDescriptionLabel.superview?.setNeedsLayout()

            if Environment.current().preferences.isCallKitEnabledSet() ||
                Environment.current().preferences.isCallKitPrivacySet() {
                // User has already touched these preferences, only show
                // the "fleeting" nag, not the "blocking" nag.

                // Show nag for N seconds.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.dismissIfPossible(shouldDelay: false, ignoreNag: true)
                }
            }
        } else if shouldDelay {
            hasDismissed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.dismissImmediately(completion: completion)
            }
        } else {
            hasDismissed = true
            dismissImmediately(completion: completion)
        }
    }

    internal func dismissImmediately(completion: (() -> Void)?) {
        if CallViewController.kShowCallViewOnSeparateWindow {
            OWSWindowManager.shared().endCall(self)
            completion?()
        } else {
            self.dismiss(animated: true, completion: completion)
        }
    }

    // MARK: - CallServiceObserver

    internal func didUpdateCall(call: SignalCall?) {
        // Do nothing.
    }

    internal func didUpdateVideoTracks(call: SignalCall?,
                                       localVideoTrack: RTCVideoTrack?,
                                       remoteVideoTrack: RTCVideoTrack?) {
        SwiftAssertIsOnMainThread(#function)

        updateLocalVideoTrack(localVideoTrack: localVideoTrack)
        updateRemoteVideoTrack(remoteVideoTrack: remoteVideoTrack)
    }
}
