//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC
import PromiseKit

// TODO move this somewhere else.
@objc class CallAudioService: NSObject {
    private let TAG = "[CallAudioService]"
    private var vibrateTimer: Timer?
    private let audioManager = AppAudioManager.sharedInstance()

    // Mark: Vibration config
    private let vibrateRepeatDuration = 1.6

    // Our ring buzz is a pair of vibrations.
    // `pulseDuration` is the small pause between the two vibrations in the pair.
    private let pulseDuration = 0.2

    public var isSpeakerphoneEnabled = false {
        didSet {
            handleUpdatedSpeakerphone()
        }
    }

    public func handleState(_ state: CallState) {
        switch state {
        case .idle: handleIdle()
        case .dialing: handleDialing()
        case .answering: handleAnswering()
        case .remoteRinging: handleRemoteRinging()
        case .localRinging: handleLocalRinging()
        case .connected: handleConnected()
        case .localFailure: handleLocalFailure()
        case .localHangup: handleLocalHangup()
        case .remoteHangup: handleRemoteHangup()
        case .remoteBusy: handleBusy()
        }
    }

    private func handleIdle() {
        Logger.debug("\(TAG) \(#function)")
    }

    private func handleDialing() {
        Logger.debug("\(TAG) \(#function)")
    }

    private func handleAnswering() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
    }

    private func handleRemoteRinging() {
        Logger.debug("\(TAG) \(#function)")
    }

    private func handleLocalRinging() {
        Logger.debug("\(TAG) \(#function)")
        audioManager.setAudioEnabled(true)
        audioManager.handleInboundRing()
        do {
            // Respect silent switch.
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategorySoloAmbient)
            Logger.debug("\(TAG) set audio category to SoloAmbient")
        } catch {
            Logger.error("\(TAG) failed to change audio category to soloAmbient in \(#function)")
        }

        vibrateTimer = Timer.scheduledTimer(timeInterval: vibrateRepeatDuration, target: self, selector: #selector(vibrate), userInfo: nil, repeats: true)
    }

    private func handleConnected() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
        do {
            // Start recording
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
            Logger.debug("\(TAG) set audio category to PlayAndRecord")
        } catch {
            Logger.error("\(TAG) failed to change audio category to soloAmbient in \(#function)")
        }
    }

    private func handleLocalFailure() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
    }

    private func handleLocalHangup() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
    }

    private func handleRemoteHangup() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
    }

    private func handleBusy() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()
    }

    private func handleUpdatedSpeakerphone() {
        audioManager.toggleSpeakerPhone(isEnabled: isSpeakerphoneEnabled)
    }

    // MARK: Helpers

    private func stopRinging() {
        // Disables external speaker used for ringing, unless user enables speakerphone.
        audioManager.setDefaultAudioProfile()
        audioManager.cancelAllAudio()

        vibrateTimer?.invalidate()
        vibrateTimer = nil
    }

    public func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.default.asyncAfter(deadline: DispatchTime.now() + pulseDuration) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

// TODO: Add category so that button handlers can be defined where button is created.
// TODO: Add logic to button handlers.
// TODO: Ensure buttons enabled & disabled as necessary.
@objc(OWSCallViewController)
class CallViewController: UIViewController, CallDelegate {

    enum CallDirection {
        case unspecified, outgoing, incoming
    }

    let TAG = "[CallViewController]"

    // Dependencies

    let callUIAdapter: CallUIAdapter
    let contactsManager: OWSContactsManager
    let audioService: CallAudioService

    // MARK: Properties

    var peerConnectionClient: PeerConnectionClient?
    var callDirection: CallDirection = .unspecified
    var thread: TSContactThread!
    var call: SignalCall!

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
    var muteButton: UIButton!
    var speakerPhoneButton: UIButton!
    var textMessageButton: UIButton!
    var videoButton: UIButton!

    // MARK: Incoming Call Controls

    var incomingCallView: UIView!

    var acceptIncomingButton: UIButton!
    var declineIncomingButton: UIButton!

    // MARK: Control Groups

    var allControls: [UIView] {
        return incomingCallControls + ongoingCallControls
    }

    var incomingCallControls: [UIView] {
        return [ acceptIncomingButton, declineIncomingButton ]
    }

    var ongoingCallControls: [UIView] {
        return [ muteButton, speakerPhoneButton, textMessageButton, hangUpButton, videoButton ]
    }

    // MARK: Initializers

    required init?(coder aDecoder: NSCoder) {
        contactsManager = Environment.getCurrent().contactsManager
        let callService = Environment.getCurrent().callService!
        callUIAdapter = callService.callUIAdapter
        audioService = CallAudioService()
        super.init(coder: aDecoder)
    }

    required init() {
        contactsManager = Environment.getCurrent().contactsManager
        let callService = Environment.getCurrent().callService!
        callUIAdapter = callService.callUIAdapter
        audioService = CallAudioService()
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        callDurationTimer?.invalidate()
        callDurationTimer = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

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
        contactAvatarView.image = OWSAvatarBuilder.buildImage(for: thread, contactsManager: contactsManager)

        switch callDirection {
        case .unspecified:
            Logger.error("\(TAG) must set call direction before call starts.")
            showCallFailed(error: OWSErrorMakeAssertionError())
        case .outgoing:
            self.call = self.callUIAdapter.startOutgoingCall(handle: thread.contactIdentifier())
        case .incoming:
            Logger.error("\(TAG) handling Incoming call")
            // No-op, since call service is already set up at this point, the result of which was presenting this viewController.
        }

        call.delegate = self
        stateDidChange(call: call, state: call.state)
    }

    func createViews() {
        // Dark blurred background.
        let blurEffect = UIBlurEffect(style: .dark)
        blurView = UIVisualEffectView(effect: blurEffect)
        self.view.addSubview(blurView)

        createContactViews()
        createOngoingCallControls()
        createIncomingCallControls()
    }

    func createContactViews() {
        contactNameLabel = UILabel()
        contactNameLabel.font = UIFont.ows_lightFont(withSize:ScaleFromIPhone5To7Plus(32, 40))
        contactNameLabel.textColor = UIColor.white
        self.view.addSubview(contactNameLabel)

        callStatusLabel = UILabel()
        callStatusLabel.font = UIFont.ows_regularFont(withSize:ScaleFromIPhone5To7Plus(19, 25))
        callStatusLabel.textColor = UIColor.white
        self.view.addSubview(callStatusLabel)

        contactAvatarView = AvatarImageView()
        self.view.addSubview(contactAvatarView)
    }

    func buttonSize() -> CGFloat {
        return ScaleFromIPhone5To7Plus(84, 108)
    }

    func buttonInset() -> CGFloat {
        return ScaleFromIPhone5To7Plus(7, 9)
    }

    func createOngoingCallControls() {

        textMessageButton = createButton(imageName:"message-active-wide",
                                                action:#selector(didPressTextMessage))
        muteButton = createButton(imageName:"mute-active-wide",
                                  action:#selector(didPressMute))
        speakerPhoneButton = createButton(imageName:"speaker-active-wide",
                                          action:#selector(didPressSpeakerphone))
        videoButton = createButton(imageName:"video-active-wide",
                                   action:#selector(didPressVideo))
        hangUpButton = createButton(imageName:"hangup-active-wide",
                                    action:#selector(didPressHangup))

        ongoingCallView = createContainerForCallControls(controlGroups : [
            [textMessageButton, videoButton],
            [muteButton, speakerPhoneButton ],
            [hangUpButton ]
            ])
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
            row.autoPinWidthToSuperview()
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
            var lastSpacer: UIView?
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
                    if lastSpacer != nil {
                        spacer.autoMatch(.width, to:.width, of:lastSpacer!)
                    }
                    lastSpacer = spacer
                }

                lastSubview = subview
            }
            subviews.first!.autoPinEdge(toSuperviewEdge:.left)
            subviews.last!.autoPinEdge(toSuperviewEdge:.right)
        } else if subviews.count == 1 {
            // If there's only one subview in this row, center it.
            let subview = subviews.first!
            row.addSubview(subview)
            subview.autoCenterInSuperview()
        }

        return row
    }

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
            let ongoingBottomMargin = ScaleFromIPhone5To7Plus(23, 41)
            let incomingBottomMargin = CGFloat(41)
            let avatarTopSpacing = ScaleFromIPhone5To7Plus(25, 50)
            // The buttons have built-in 10% margins, so to appear centered
            // the avatar's bottom spacing should be a bit less.
            let avatarBottomSpacing = ScaleFromIPhone5To7Plus(18, 41)

            // Dark blurred background.
            blurView.autoPinEdgesToSuperviewEdges()

            contactNameLabel.autoPinEdge(toSuperviewEdge:.top, withInset:topMargin)
            contactNameLabel.autoPinWidthToSuperview(withMargin:contactHMargin)
            contactNameLabel.setContentHuggingVerticalHigh()

            callStatusLabel.autoPinEdge(.top, to:.bottom, of:contactNameLabel, withOffset:contactVSpacing)
            callStatusLabel.autoPinWidthToSuperview(withMargin:contactHMargin)
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
        }

        super.updateViewConstraints()
    }

    // objc accessible way to set our swift enum.
    func setOutgoingCallDirection() {
        callDirection = .outgoing
    }

    // objc accessible way to set our swift enum.
    func setIncomingCallDirection() {
        callDirection = .incoming
    }

    func showCallFailed(error: Error) {
        // TODO Show something in UI.
        Logger.error("\(TAG) call failed with error: \(error)")
    }

    func localizedTextForCallState(_ callState: CallState) -> String {
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
            return NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label")
        }
    }

    func updateCallUI(callState: CallState) {
        let textForState = localizedTextForCallState(callState)
        Logger.info("\(TAG) new call status: \(callState) aka \"\(textForState)\"")

        self.callStatusLabel.text = textForState

        // Show Incoming vs. Ongoing call controls
        let isRinging = callState == .localRinging
        incomingCallView.isHidden = !isRinging
        incomingCallView.isUserInteractionEnabled = isRinging
        ongoingCallView.isHidden = isRinging
        ongoingCallView.isUserInteractionEnabled = !isRinging

        // Dismiss Handling
        switch callState {
        case .remoteHangup, .remoteBusy, .localFailure:
            Logger.debug("\(TAG) dismissing after delay because new state is \(textForState)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss(animated: true)
            }
        case .localHangup:
            Logger.debug("\(TAG) dismissing immediately from local hangup")
            self.dismiss(animated: true)

        default: break
        }

        if callState == .connected {
            if callDurationTimer == nil {
                let kDurationUpdateFrequencySeconds = 1 / 20.0
                callDurationTimer = Timer.scheduledTimer(timeInterval: kDurationUpdateFrequencySeconds,
                                                         target:self,
                                                         selector:#selector(updateCallDuration),
                                                         userInfo:nil,
                                                         repeats:true)
            }
        } else {
            callDurationTimer?.invalidate()
            callDurationTimer = nil
        }
    }

    func updateCallDuration(timer: Timer?) {
        updateCallUI(callState: call.state)
    }

    // MARK: - Actions

    /**
     * Ends a connected call. Do not confuse with `didPressDeclineCall`.
     */
    func didPressHangup(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        if let call = self.call {
            callUIAdapter.endCall(call)
        } else {
            Logger.warn("\(TAG) hung up, but call was unexpectedly nil")
        }

        self.dismiss(animated: true)
    }

    func didPressMute(sender muteButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        muteButton.isSelected = !muteButton.isSelected
        if let call = self.call {
            callUIAdapter.toggleMute(call: call, isMuted: muteButton.isSelected)
        } else {
            Logger.warn("\(TAG) pressed mute, but call was unexpectedly nil")
        }
    }

    func didPressSpeakerphone(sender speakerphoneButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        speakerphoneButton.isSelected = !speakerphoneButton.isSelected
        audioService.isSpeakerphoneEnabled = speakerphoneButton.isSelected
    }

    func didPressTextMessage(sender speakerphoneButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        self.dismiss(animated: true)
    }

    func didPressAnswerCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        guard let call = self.call else {
            Logger.error("\(TAG) call was unexpectedly nil. Terminating call.")
            self.callStatusLabel.text = NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss(animated: true)
            }
            return
        }

        callUIAdapter.answerCall(call)
    }

    func didPressVideo(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        // TODO:
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

        self.dismiss(animated: true)
    }

    // MARK: - Call Delegate

    internal func stateDidChange(call: SignalCall, state: CallState) {
        DispatchQueue.main.async {
            self.updateCallUI(callState: state)
        }
        self.audioService.handleState(state)
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        DispatchQueue.main.async {
            self.muteButton.isSelected = call.isMuted
        }
    }
}
