//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC
import PromiseKit

// TODO: Add category so that button handlers can be defined where button is created.
// TODO: Ensure buttons enabled & disabled as necessary.
class CallViewController: UIViewController, CallObserver, CallServiceObserver, RTCEAGLVideoViewDelegate {

    let TAG = "[CallViewController]"

    // Dependencies

    let callUIAdapter: CallUIAdapter
    let contactsManager: OWSContactsManager

    // MARK: Properties

    var thread: TSContactThread!
    var call: SignalCall!
    var hasDismissed = false

    // MARK: Views

    var hasConstraints = false
    var blurView: UIVisualEffectView!
    var dateFormatter: DateFormatter?

    // MARK: Contact Views

    var contactNameLabel: UILabel!
    var contactAvatarView: AvatarImageView!
    var callStatusLabel: UILabel!
    var callDurationTimer: Timer?

    // MARK: Ongoing Call Controls

    var ongoingCallView: UIView!

    var hangUpButton: UIButton!
    var speakerPhoneButton: UIButton!
    var audioModeMuteButton: UIButton!
    var audioModeVideoButton: UIButton!
    var videoModeMuteButton: UIButton!
    var videoModeVideoButton: UIButton!
    // TODO: Later, we'll re-enable the text message button
    //       so users can send and read messages during a 
    //       call.
//    var textMessageButton: UIButton!

    // MARK: Incoming Call Controls

    var incomingCallView: UIView!

    var acceptIncomingButton: UIButton!
    var declineIncomingButton: UIButton!

    // MARK: Video Views

    var remoteVideoView: RTCEAGLVideoView!
    var localVideoView: RTCCameraPreviewView!
    weak var localVideoTrack: RTCVideoTrack?
    weak var remoteVideoTrack: RTCVideoTrack?
    var remoteVideoSize: CGSize! = CGSize.zero
    var remoteVideoConstraints: [NSLayoutConstraint] = []
    var localVideoConstraints: [NSLayoutConstraint] = []

    var shouldRemoteVideoControlsBeHidden = false {
        didSet {
            updateCallUI(callState: call.state)
        }
    }

    // MARK: Settings Nag Views

    var isShowingSettingsNag = false {
        didSet {
            if oldValue != isShowingSettingsNag {
                updateCallUI(callState: call.state)
            }
        }
    }
    var settingsNagView: UIView!
    var settingsNagDescriptionLabel: UILabel!

    // MARK: Initializers

    required init?(coder aDecoder: NSCoder) {
        contactsManager = Environment.getCurrent().contactsManager
        callUIAdapter = Environment.getCurrent().callUIAdapter
        super.init(coder: aDecoder)
        observeNotifications()
    }

    required init() {
        contactsManager = Environment.getCurrent().contactsManager
        callUIAdapter = Environment.getCurrent().callUIAdapter
        super.init(nibName: nil, bundle: nil)
        observeNotifications()
    }

    func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didBecomeActive),
                                               name:NSNotification.Name.UIApplicationDidBecomeActive,
                                               object:nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func didBecomeActive() {
        shouldRemoteVideoControlsBeHidden = false
    }

    // MARK: View Lifecycle

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
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let thread = self.thread else {
            Logger.error("\(TAG) tried to show call call without specifying thread.")
            showCallFailed(error: OWSErrorMakeAssertionError())
            return
        }

        createViews()

        contactNameLabel.text = contactsManager.displayName(forPhoneIdentifier: thread.contactIdentifier())
        updateAvatarImage()
        NotificationCenter.default.addObserver(forName: .OWSContactsManagerSignalAccountsDidChange, object: nil, queue: nil) { _ in
            Logger.info("\(self.TAG) updating avatar image")
            self.updateAvatarImage()
        }

        assert(call != nil)
        // Subscribe for future call updates
        call.addObserverAndSyncState(observer: self)

        Environment.getCurrent().callService.addObserverAndSyncState(observer:self)
    }

    // MARK: - Create Views

    func createViews() {
        self.view.isUserInteractionEnabled = true
        self.view.addGestureRecognizer(OWSAnyTouchGestureRecognizer(target:self,
                                                                    action:#selector(didTouchRootView)))

        // Dark blurred background.
        let blurEffect = UIBlurEffect(style: .dark)
        blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        self.view.addSubview(blurView)

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
        remoteVideoView = RTCEAGLVideoView()
        remoteVideoView.delegate = self
        remoteVideoView.isUserInteractionEnabled = false
        localVideoView = RTCCameraPreviewView()
        remoteVideoView.isHidden = true
        localVideoView.isHidden = true
        self.view.addSubview(remoteVideoView)
        self.view.addSubview(localVideoView)
    }

    func createContactViews() {
        contactNameLabel = UILabel()
        contactNameLabel.font = UIFont.ows_lightFont(withSize:ScaleFromIPhone5To7Plus(32, 40))
        contactNameLabel.textColor = UIColor.white
        contactNameLabel.layer.shadowOffset = CGSize.zero
        contactNameLabel.layer.shadowOpacity = 0.35
        contactNameLabel.layer.shadowRadius = 4
        self.view.addSubview(contactNameLabel)

        callStatusLabel = UILabel()
        callStatusLabel.font = UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(19, 25))
        callStatusLabel.textColor = UIColor.white
        callStatusLabel.layer.shadowOffset = CGSize.zero
        callStatusLabel.layer.shadowOpacity = 0.35
        callStatusLabel.layer.shadowRadius = 4
        self.view.addSubview(callStatusLabel)

        contactAvatarView = AvatarImageView()
        self.view.addSubview(contactAvatarView)
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
        settingsNagDescriptionLabel.font = UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(16, 18))
        settingsNagDescriptionLabel.textColor = UIColor.white
        settingsNagDescriptionLabel.numberOfLines = 0
        settingsNagDescriptionLabel.lineBreakMode = .byWordWrapping
        viewStack.addSubview(settingsNagDescriptionLabel)
        settingsNagDescriptionLabel.autoPinWidthToSuperview()
        settingsNagDescriptionLabel.autoPinEdge(toSuperviewEdge:.top)

        let buttonHeight = ScaleFromIPhone5To7Plus(35, 45)
        let buttonFont = UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(14, 18))
        let buttonCornerRadius = CGFloat(4)
        let descriptionVSpacingHeight = ScaleFromIPhone5To7Plus(30, 60)

        let callSettingsButton = UIButton()
        callSettingsButton.setTitle(NSLocalizedString("CALL_VIEW_SETTINGS_NAG_SHOW_CALL_SETTINGS",
                                                      comment: "Label for button that shows the privacy settings"), for:.normal)
        callSettingsButton.setTitleColor(UIColor.white, for:.normal)
        callSettingsButton.titleLabel!.font = buttonFont
        callSettingsButton.addTarget(self, action:#selector(didPressShowCallSettings), for:.touchUpInside)
        callSettingsButton.backgroundColor = UIColor.ows_signalBrandBlue()
        callSettingsButton.layer.cornerRadius = buttonCornerRadius
        callSettingsButton.clipsToBounds = true
        viewStack.addSubview(callSettingsButton)
        callSettingsButton.autoSetDimension(.height, toSize:buttonHeight)
        callSettingsButton.autoPinWidthToSuperview()
        callSettingsButton.autoPinEdge(.top, to:.bottom, of:settingsNagDescriptionLabel, withOffset:descriptionVSpacingHeight)

        let notNowButton = UIButton()
        notNowButton.setTitle(NSLocalizedString("CALL_VIEW_SETTINGS_NAG_NOT_NOW_BUTTON",
                                                comment: "Label for button that dismiss the call view's settings nag."), for:.normal)
        notNowButton.setTitleColor(UIColor.white, for:.normal)
        notNowButton.titleLabel!.font = buttonFont
        notNowButton.addTarget(self, action:#selector(didPressDismissNag), for:.touchUpInside)
        notNowButton.backgroundColor = UIColor.ows_signalBrandBlue()
        notNowButton.layer.cornerRadius = buttonCornerRadius
        notNowButton.clipsToBounds = true
        viewStack.addSubview(notNowButton)
        notNowButton.autoSetDimension(.height, toSize:buttonHeight)
        notNowButton.autoPinWidthToSuperview()
        notNowButton.autoPinEdge(toSuperviewEdge:.bottom)
        notNowButton.autoPinEdge(.top, to:.bottom, of:callSettingsButton, withOffset:12)
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
        speakerPhoneButton = createButton(imageName:"audio-call-speaker-inactive",
                                          action:#selector(didPressSpeakerphone))
        hangUpButton = createButton(imageName:"hangup-active-wide",
                                    action:#selector(didPressHangup))
        audioModeMuteButton = createButton(imageName:"audio-call-mute-inactive",
                                           action:#selector(didPressMute))
        videoModeMuteButton = createButton(imageName:"video-mute-unselected",
                                           action:#selector(didPressMute))
        audioModeVideoButton = createButton(imageName:"audio-call-video-inactive",
                                            action:#selector(didPressVideo))
        videoModeVideoButton = createButton(imageName:"video-video-unselected",
                                            action:#selector(didPressVideo))

        setButtonSelectedImage(button: audioModeMuteButton, imageName: "audio-call-mute-active")
        setButtonSelectedImage(button: videoModeMuteButton, imageName: "video-mute-selected")
        setButtonSelectedImage(button: audioModeVideoButton, imageName: "audio-call-video-active")
        setButtonSelectedImage(button: videoModeVideoButton, imageName: "video-video-selected")
        setButtonSelectedImage(button: speakerPhoneButton, imageName: "audio-call-speaker-active")

        ongoingCallView = createContainerForCallControls(controlGroups : [
            [audioModeMuteButton, speakerPhoneButton, audioModeVideoButton ],
            [videoModeMuteButton, hangUpButton, videoModeVideoButton ]
            ])
    }

    func setButtonSelectedImage(button: UIButton, imageName: String) {
        let image = UIImage(named:imageName)
        assert(image != nil)
        button.setImage(image, for:.selected)
    }

    func updateAvatarImage() {
        contactAvatarView.image = OWSAvatarBuilder.buildImage(for: thread, contactsManager: contactsManager, diameter:400)
    }

    func createIncomingCallControls() {

        acceptIncomingButton = createButton(imageName:"call-active-wide",
                                            action:#selector(didPressAnswerCall))
        declineIncomingButton = createButton(imageName:"hangup-active-wide",
                                             action:#selector(didPressDeclineCall))

        incomingCallView = createContainerForCallControls(controlGroups : [
            [acceptIncomingButton, declineIncomingButton ]
            ])
    }

    func createContainerForCallControls(controlGroups: [[UIView]]) -> UIView {
        let containerView = UIView()
        self.view.addSubview(containerView)
        var rows: [UIView] = []
        for controlGroup in controlGroups {
            rows.append(rowWithSubviews(subviews:controlGroup))
        }
        let rowspacing = ScaleFromIPhone5To7Plus(6, 7)
        var prevRow: UIView?
        for row in rows {
            containerView.addSubview(row)
            row.autoHCenterInSuperview()
            if prevRow != nil {
                row.autoPinEdge(.top, to:.bottom, of:prevRow!, withOffset:rowspacing)
            }
            prevRow = row
        }

        containerView.setContentHuggingVerticalHigh()
        rows.first!.autoPinEdge(toSuperviewEdge:.top)
        rows.last!.autoPinEdge(toSuperviewEdge:.bottom)
        return containerView
    }

    func createButton(imageName: String, action: Selector) -> UIButton {
        let image = UIImage(named:imageName)
        assert(image != nil)
        let button = UIButton()
        button.setImage(image, for:.normal)
        button.imageEdgeInsets = UIEdgeInsets(top: buttonInset(),
                                              left: buttonInset(),
                                              bottom: buttonInset(),
                                              right: buttonInset())
        button.addTarget(self, action:action, for:.touchUpInside)
        button.autoSetDimension(.width, toSize:buttonSize())
        button.autoSetDimension(.height, toSize:buttonSize())
        return button
    }

    // Creates a row containing a given set of subviews.
    func rowWithSubviews(subviews: [UIView]) -> UIView {
        let row = UIView()
        row.setContentHuggingVerticalHigh()
        row.autoSetDimension(.height, toSize:buttonSize())

        if subviews.count > 1 {
            // If there's more than one subview in the row,
            // space them evenly within the row.
            var lastSubview: UIView?
            for subview in subviews {
                row.addSubview(subview)
                subview.setContentHuggingHorizontalHigh()
                subview.autoVCenterInSuperview()

                if lastSubview != nil {
                    let spacer = UIView()
                    spacer.isHidden = true
                    row.addSubview(spacer)
                    spacer.autoPinEdge(.left, to:.right, of:lastSubview!)
                    spacer.autoPinEdge(.right, to:.left, of:subview)
                    spacer.setContentHuggingHorizontalLow()
                    spacer.autoVCenterInSuperview()

                    if subviews.count == 2 {
                        // special case to hardcode the spacer's size when there is only 1 spacer.
                        spacer.autoSetDimension(.width, toSize: ScaleFromIPhone5To7Plus(46, 60))
                    } else {
                        spacer.autoSetDimension(.width, toSize: ScaleFromIPhone5To7Plus(3, 5))
                    }
                }

                lastSubview = subview
            }
            subviews.first!.autoPinEdge(toSuperviewEdge:.left)
            subviews.last!.autoPinEdge(toSuperviewEdge:.right)
        } else if subviews.count == 1 {
            // If there's only one subview in this row, center it.
            let subview = subviews.first!
            row.addSubview(subview)
            subview.autoVCenterInSuperview()
            subview.autoPinWidthToSuperview()
        }

        return row
    }

    // MARK: - Layout

    override func updateViewConstraints() {
        if !hasConstraints {
            // We only want to create our constraints once.
            //
            // Note that constraints are also created elsewhere.
            // This only creates the constraints for the top-level contents of the view.
            hasConstraints = true

            let topMargin = CGFloat(40)
            let contactHMargin = CGFloat(30)
            let contactVSpacing = CGFloat(3)
            let ongoingHMargin = ScaleFromIPhone5To7Plus(46, 72)
            let incomingHMargin = ScaleFromIPhone5To7Plus(46, 72)
            let settingsNagHMargin = CGFloat(30)
            let ongoingBottomMargin = ScaleFromIPhone5To7Plus(23, 41)
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

            localVideoView.autoPinEdge(toSuperviewEdge:.right, withInset:videoPreviewHMargin)
            localVideoView.autoPinEdge(toSuperviewEdge:.top, withInset:topMargin)
            let localVideoSize = ScaleFromIPhone5To7Plus(80, 100)
            localVideoView.autoSetDimension(.width, toSize:localVideoSize)
            localVideoView.autoSetDimension(.height, toSize:localVideoSize)

            contactNameLabel.autoPinEdge(toSuperviewEdge:.top, withInset:topMargin)
            contactNameLabel.autoPinEdge(toSuperviewEdge:.left, withInset:contactHMargin)
            contactNameLabel.setContentHuggingVerticalHigh()

            callStatusLabel.autoPinEdge(.top, to:.bottom, of:contactNameLabel, withOffset:contactVSpacing)
            callStatusLabel.autoPinEdge(toSuperviewEdge:.left, withInset:contactHMargin)
            callStatusLabel.setContentHuggingVerticalHigh()

            contactAvatarView.autoPinEdge(.top, to:.bottom, of:callStatusLabel, withOffset:+avatarTopSpacing)
            contactAvatarView.autoPinEdge(.bottom, to:.top, of:ongoingCallView, withOffset:-avatarBottomSpacing)
            contactAvatarView.autoHCenterInSuperview()
            // Stretch that avatar to fill the available space.
            contactAvatarView.setContentHuggingLow()
            contactAvatarView.setCompressionResistanceLow()
            // Preserve square aspect ratio of contact avatar.
            contactAvatarView.autoMatch(.width, to:.height, of:contactAvatarView)

            // Ongoing call controls
            ongoingCallView.autoPinEdge(toSuperviewEdge:.bottom, withInset:ongoingBottomMargin)
            ongoingCallView.autoPinWidthToSuperview(withMargin:ongoingHMargin)
            ongoingCallView.setContentHuggingVerticalHigh()

            // Incoming call controls
            incomingCallView.autoPinEdge(toSuperviewEdge:.bottom, withInset:incomingBottomMargin)
            incomingCallView.autoPinWidthToSuperview(withMargin:incomingHMargin)
            incomingCallView.setContentHuggingVerticalHigh()

            // Settings nag views
            settingsNagView.autoPinEdge(toSuperviewEdge:.bottom, withInset:settingsNagBottomMargin)
            settingsNagView.autoPinWidthToSuperview(withMargin:settingsNagHMargin)
            settingsNagView.autoPinEdge(.top, to:.bottom, of:callStatusLabel)
        }

        updateRemoteVideoLayout()
        updateLocalVideoLayout()

        super.updateViewConstraints()
    }

    internal func updateRemoteVideoLayout() {
        NSLayoutConstraint.deactivate(self.remoteVideoConstraints)

        var constraints: [NSLayoutConstraint] = []

        // We fill the screen with the remote video. The remote video's
        // aspect ratio may not (and in fact will very rarely) match the 
        // aspect ratio of the current device, so parts of the remote
        // video will be hidden offscreen.  
        //
        // It's better to trim the remote video than to adopt a letterboxed
        // layout.
        if remoteVideoSize.width > 0 && remoteVideoSize.height > 0 &&
            self.view.bounds.size.width > 0 && self.view.bounds.size.height > 0 {

            var remoteVideoWidth = self.view.bounds.size.width
            var remoteVideoHeight = self.view.bounds.size.height
            if remoteVideoSize.width / self.view.bounds.size.width > remoteVideoSize.height / self.view.bounds.size.height {
                remoteVideoWidth = round(self.view.bounds.size.height * remoteVideoSize.width / remoteVideoSize.height)
            } else {
                remoteVideoHeight = round(self.view.bounds.size.width * remoteVideoSize.height / remoteVideoSize.width)
            }
            constraints.append(remoteVideoView.autoSetDimension(.width, toSize:remoteVideoWidth))
            constraints.append(remoteVideoView.autoSetDimension(.height, toSize:remoteVideoHeight))
            constraints += remoteVideoView.autoCenterInSuperview()

            remoteVideoView.frame = CGRect(origin:CGPoint.zero,
                                           size:CGSize(width:remoteVideoWidth,
                                                       height:remoteVideoHeight))

            remoteVideoView.isHidden = false
        } else {
            constraints += remoteVideoView.autoPinEdgesToSuperviewEdges()
            remoteVideoView.isHidden = true
        }

        self.remoteVideoConstraints = constraints

        // We need to force relayout to occur immediately (and not
        // wait for a UIKit layout/render pass) or the remoteVideoView
        // (which presumably is updating its CALayer directly) will 
        // ocassionally appear to have bad frames.
        remoteVideoView.setNeedsLayout()
        remoteVideoView.superview?.setNeedsLayout()
        remoteVideoView.layoutIfNeeded()
        remoteVideoView.superview?.layoutIfNeeded()

        updateCallUI(callState: call.state)
    }

    internal func updateLocalVideoLayout() {

        NSLayoutConstraint.deactivate(self.localVideoConstraints)

        var constraints: [NSLayoutConstraint] = []

        if localVideoView.isHidden {
            let contactHMargin = CGFloat(30)
            constraints.append(contactNameLabel.autoPinEdge(toSuperviewEdge:.right, withInset:contactHMargin))
            constraints.append(callStatusLabel.autoPinEdge(toSuperviewEdge:.right, withInset:contactHMargin))
        } else {
            let spacing = CGFloat(10)
            constraints.append(contactNameLabel.autoPinEdge(.right, to:.left, of:localVideoView, withOffset:-spacing))
            constraints.append(callStatusLabel.autoPinEdge(.right, to:.left, of:localVideoView, withOffset:-spacing))
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
            if let call = self.call {
                let callDuration = call.connectionDuration()
                let callDurationDate = Date(timeIntervalSinceReferenceDate:callDuration)
                if dateFormatter == nil {
                    dateFormatter = DateFormatter()
                    dateFormatter!.dateFormat = "HH:mm:ss"
                    dateFormatter!.timeZone = TimeZone(identifier:"UTC")!
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
            } else {
                return NSLocalizedString("IN_CALL_TALKING", comment: "Call setup status label")
            }
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

    func updateCallStatusLabel(callState: CallState) {
        assert(Thread.isMainThread)

        let text = String(format: CallStrings.callStatusFormat,
                          localizedTextForCallState(callState))
        self.callStatusLabel.text = text
    }

    func updateCallUI(callState: CallState) {
        assert(Thread.isMainThread)
        updateCallStatusLabel(callState: callState)

        if isShowingSettingsNag {
            settingsNagView.isHidden = false
            contactAvatarView.isHidden = true
            ongoingCallView.isHidden = true
            return
        }

        audioModeMuteButton.isSelected = call.isMuted
        videoModeMuteButton.isSelected = call.isMuted
        audioModeVideoButton.isSelected = call.hasLocalVideo
        videoModeVideoButton.isSelected = call.hasLocalVideo
        speakerPhoneButton.isSelected = call.isSpeakerphoneEnabled

        // Show Incoming vs. Ongoing call controls
        let isRinging = callState == .localRinging
        incomingCallView.isHidden = !isRinging
        incomingCallView.isUserInteractionEnabled = isRinging
        ongoingCallView.isHidden = isRinging
        ongoingCallView.isUserInteractionEnabled = !isRinging

        // Rework control state if remote video is available.
        let hasRemoteVideo = !remoteVideoView.isHidden
        contactAvatarView.isHidden = hasRemoteVideo

        // Rework control state if local video is available.
        let hasLocalVideo = !localVideoView.isHidden
        for subview in [speakerPhoneButton, audioModeMuteButton, audioModeVideoButton] {
            subview?.isHidden = hasLocalVideo
        }
        for subview in [videoModeMuteButton, videoModeVideoButton] {
            subview?.isHidden = !hasLocalVideo
        }

        // Also hide other controls if user has tapped to hide them.
        if shouldRemoteVideoControlsBeHidden && !remoteVideoView.isHidden {
            contactNameLabel.isHidden = true
            callStatusLabel.isHidden = true
            ongoingCallView.isHidden = true
        } else {
            contactNameLabel.isHidden = false
            callStatusLabel.isHidden = false
        }

        // Dismiss Handling
        switch callState {
        case .remoteHangup, .remoteBusy, .localFailure:
            Logger.debug("\(TAG) dismissing after delay because new state is \(callState)")
            dismissIfPossible(shouldDelay:true)
        case .localHangup:
            Logger.debug("\(TAG) dismissing immediately from local hangup")
            dismissIfPossible(shouldDelay:false)
        default: break
        }

        if callState == .connected {
            if callDurationTimer == nil {
                let kDurationUpdateFrequencySeconds = 1 / 20.0
                callDurationTimer = WeakTimer.scheduledTimer(timeInterval: TimeInterval(kDurationUpdateFrequencySeconds),
                                                         target:self,
                                                         userInfo:nil,
                                                         repeats:true) {[weak self] _ in
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

    // MARK: - Actions

    /**
     * Ends a connected call. Do not confuse with `didPressDeclineCall`.
     */
    func didPressHangup(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        if let call = self.call {
            callUIAdapter.localHangupCall(call)
        } else {
            Logger.warn("\(TAG) hung up, but call was unexpectedly nil")
        }

        dismissIfPossible(shouldDelay:false)
    }

    func didPressMute(sender muteButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        muteButton.isSelected = !muteButton.isSelected
        if let call = self.call {
            callUIAdapter.setIsMuted(call: call, isMuted: muteButton.isSelected)
        } else {
            Logger.warn("\(TAG) pressed mute, but call was unexpectedly nil")
        }
    }

    func didPressSpeakerphone(sender speakerphoneButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        speakerphoneButton.isSelected = !speakerphoneButton.isSelected
        if let call = self.call {
            callUIAdapter.setIsSpeakerphoneEnabled(call: call, isEnabled: speakerphoneButton.isSelected)
        } else {
            Logger.warn("\(TAG) pressed mute, but call was unexpectedly nil")
        }
    }

    func didPressTextMessage(sender speakerphoneButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        dismissIfPossible(shouldDelay:false)
    }

    func didPressAnswerCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        guard let call = self.call else {
            Logger.error("\(TAG) call was unexpectedly nil. Terminating call.")

            let text = String(format: CallStrings.callStatusFormat,
                              NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label"))
            self.callStatusLabel.text = text

            dismissIfPossible(shouldDelay:true)
            return
        }

        callUIAdapter.answerCall(call)
    }

    func didPressVideo(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        let hasLocalVideo = !sender.isSelected
        if let call = self.call {
            callUIAdapter.setHasLocalVideo(call: call, hasLocalVideo: hasLocalVideo)
        } else {
            Logger.warn("\(TAG) pressed video, but call was unexpectedly nil")
        }
    }

    /**
     * Denies an incoming not-yet-connected call, Do not confuse with `didPressHangup`.
     */
    func didPressDeclineCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        if let call = self.call {
            callUIAdapter.declineCall(call)
        } else {
            Logger.warn("\(TAG) denied call, but call was unexpectedly nil")
        }

        dismissIfPossible(shouldDelay:false)
    }

    func didPressShowCallSettings(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        markSettingsNagAsComplete()

        dismissIfPossible(shouldDelay: false, ignoreNag: true, completion: {
            // Find the frontmost presented UIViewController from which to present the
            // settings views.
            let fromViewController = UIApplication.shared.frontmostViewController
            assert(fromViewController != nil)

            // Construct the "settings" view & push the "privacy settings" view.
            let navigationController = UINavigationController(rootViewController:SettingsTableViewController())
            navigationController.pushViewController(PrivacySettingsTableViewController(), animated:false)

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

        let preferences = Environment.getCurrent().preferences!

        preferences.setIsCallKitEnabled(preferences.isCallKitEnabled())
        preferences.setIsCallKitPrivacyEnabled(preferences.isCallKitPrivacyEnabled())
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) new call status: \(state)")
        self.updateCallUI(callState: state)
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI(callState: call.state)
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI(callState: call.state)
    }

    internal func speakerphoneDidChange(call: SignalCall, isEnabled: Bool) {
        AssertIsOnMainThread()
        self.updateCallUI(callState: call.state)
    }

    // MARK: - Video

    internal func updateLocalVideoTrack(localVideoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()
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
    }

    internal func updateRemoteVideoTrack(remoteVideoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()
        guard self.remoteVideoTrack != remoteVideoTrack else {
            return
        }

        self.remoteVideoTrack?.remove(remoteVideoView)
        self.remoteVideoTrack = nil
        remoteVideoView.renderFrame(nil)
        self.remoteVideoTrack = remoteVideoTrack
        self.remoteVideoTrack?.add(remoteVideoView)
        shouldRemoteVideoControlsBeHidden = false

        if remoteVideoTrack == nil {
            remoteVideoSize = CGSize.zero
        }

        updateRemoteVideoLayout()
    }

    internal func dismissIfPossible(shouldDelay: Bool, ignoreNag: Bool = false, completion: (() -> Swift.Void)? = nil) {
        if hasDismissed {
            // Don't dismiss twice.
            return
        } else if !ignoreNag &&
            call.direction == .incoming &&
            UIDevice.current.supportsCallKit &&
            (!Environment.getCurrent().preferences.isCallKitEnabled() ||
                Environment.getCurrent().preferences.isCallKitPrivacyEnabled()) {

            isShowingSettingsNag = true

            // Update the nag view's copy to reflect the settings state.
            if Environment.getCurrent().preferences.isCallKitEnabled() {
                settingsNagDescriptionLabel.text = NSLocalizedString("CALL_VIEW_SETTINGS_NAG_DESCRIPTION_PRIVACY",
                                                                     comment: "Reminder to the user of the benefits of disabling CallKit privacy.")
            } else {
                settingsNagDescriptionLabel.text = NSLocalizedString("CALL_VIEW_SETTINGS_NAG_DESCRIPTION_ALL",
                                                                     comment: "Reminder to the user of the benefits of enabling CallKit and disabling CallKit privacy.")
            }
            settingsNagDescriptionLabel.superview?.setNeedsLayout()

            if Environment.getCurrent().preferences.isCallKitEnabledSet() ||
                Environment.getCurrent().preferences.isCallKitPrivacySet() {
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
                strongSelf.dismiss(animated: true, completion:completion)
            }
        } else {
            hasDismissed = true
            self.dismiss(animated: false, completion:completion)
        }
    }

    // MARK: - CallServiceObserver

    internal func didUpdateCall(call: SignalCall?) {
        // Do nothing.
    }

    internal func didUpdateVideoTracks(call: SignalCall?,
                                       localVideoTrack: RTCVideoTrack?,
                                       remoteVideoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        updateLocalVideoTrack(localVideoTrack:localVideoTrack)
        updateRemoteVideoTrack(remoteVideoTrack:remoteVideoTrack)
    }

    // MARK: - RTCEAGLVideoViewDelegate

    internal func videoView(_ videoView: RTCEAGLVideoView, didChangeVideoSize size: CGSize) {
        AssertIsOnMainThread()

        if videoView != remoteVideoView {
            return
        }

        Logger.info("\(TAG) \(#function): \(size)")

        remoteVideoSize = size
        updateRemoteVideoLayout()
    }
}
