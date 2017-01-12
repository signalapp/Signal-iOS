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

    // MARK: Layout

    var hasConstraints = false

    // MARK: Background

    var blurView: UIVisualEffectView!

    // MARK: Contact Views

    var contactNameLabel: UILabel!
    var contactAvatarView: AvatarImageView!
    var callStatusLabel: UILabel!

    // MARK: Ongoing Call Controls

    var ongoingCallView: UIView!

    var hangUpButton: UIButton!
    var muteButton: UIButton!
    var speakerPhoneButton: UIButton!
    // TODO: Which call states does this apply to?
    var textMessageButton: UIButton!
    var videoButton: UIButton!

    // MARK: Incoming Call Controls

    var incomingCallControlsRow: UIView!
    var acceptIncomingButton: UIButton!
    var declineIncomingButton: UIButton!

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

        // Contact views
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

        // Ongoing call controls
        let buttonSize = ScaleFromIPhone5To7Plus(70, 90)
        textMessageButton = createButton(imageName:"logoSignal",
                                         action:#selector(didPressTextMessage),
                                         buttonSize:buttonSize)
        muteButton = createButton(imageName:"mute-inactive",
                                  action:#selector(didPressMute),
                                  buttonSize:buttonSize)
        speakerPhoneButton = createButton(imageName:"speaker-inactive",
                                          action:#selector(didPressSpeakerphone),
                                          buttonSize:buttonSize)
        videoButton = createButton(imageName:"video-active",
                                   action:#selector(didPressVideo),
                                   buttonSize:buttonSize)
        hangUpButton = createButton(imageName:"endcall",
                                    action:#selector(didPressHangup),
                                    buttonSize:buttonSize)

        // A container for 3 rows of ongoing call controls.
        ongoingCallView = UIView()
        self.view.addSubview(ongoingCallView)
        let ongoingCallRows = [
            rowWithSubviews(subviews:[textMessageButton, videoButton],
                            fixedHeight:buttonSize),
            rowWithSubviews(subviews:[muteButton, speakerPhoneButton, ],
                            fixedHeight:buttonSize),
            rowWithSubviews(subviews:[hangUpButton],
                            fixedHeight:buttonSize),
            ]
        let ongoingCallRowSpacing = ScaleFromIPhone5To7Plus(20, 25)
        var lastRow: UIView?
        for row in ongoingCallRows {
            ongoingCallView.addSubview(row)
            row.autoPinWidthToSuperview()
            if lastRow != nil {
                row.autoPinEdge(.top, to:.bottom, of:lastRow!, withOffset:ongoingCallRowSpacing)
            }
            lastRow = row
        }

        ongoingCallView.setContentHuggingVerticalHigh()
        ongoingCallRows.first!.autoPinEdge(toSuperviewEdge:.top)
        ongoingCallRows.last!.autoPinEdge(toSuperviewEdge:.bottom)

        // Incoming call controls
        acceptIncomingButton = createButton(imageName:"call",
                                            action:#selector(didPressAnswerCall),
                                            buttonSize:buttonSize)
        declineIncomingButton = createButton(imageName:"endcall",
                                             action:#selector(didPressDeclineCall),
                                             buttonSize:buttonSize)

        incomingCallControlsRow = rowWithSubviews(subviews:[acceptIncomingButton, declineIncomingButton],
                                                  fixedHeight:buttonSize)
        self.view.addSubview(incomingCallControlsRow)
    }

    func createButton(imageName: String!, action: Selector!, buttonSize: CGFloat!) -> UIButton {
        let image = UIImage(named:imageName)
        Logger.error("button \(imageName) \(NSStringFromCGSize(image!.size))")
        Logger.flush()
        let button = UIButton()
        button.setImage(image, for:.normal)
        button.addTarget(self, action:action, for:.touchUpInside)
        button.autoSetDimension(.width, toSize:buttonSize)
        button.autoSetDimension(.height, toSize:buttonSize)
        return button
    }

    // Creates a row view that evenly spaces its subviews horizontally.
    // If there is only a single subview, it is centered.
    func rowWithSubviews(subviews: Array<UIButton>, fixedHeight: CGFloat) -> UIView {
        let row = UIView()
        row.setContentHuggingVerticalHigh()
        row.autoSetDimension(.height, toSize:fixedHeight)

        if subviews.count > 1 {
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
                        spacer.autoMatch(_:.width, to:.width, of:lastSpacer!)
                    }
                    lastSpacer = spacer
                }

                lastSubview = subview
            }
            subviews.first!.autoPinEdge(toSuperviewEdge:.left)
            subviews.last!.autoPinEdge(toSuperviewEdge:.right)

            Logger.error("row \(subviews.count) -> \(row.subviews.count)")

        } else if subviews.count == 1 {
            let subview = subviews.first!
            row.addSubview(subview)
            subview.autoCenterInSuperview()
        }

        return row
    }

    override func updateViewConstraints() {
        if (!hasConstraints) {
            // We only want to create our constraints once.
            //
            // Note that constraints are also created elsewhere.
            // This only creates the constraints for the top-level contents of the view.
            hasConstraints = true

            let topMargin = CGFloat(40)
            let contactHMargin = CGFloat(30)
            let contactVSpacing = CGFloat(3)
            let ongoingHMargin = ScaleFromIPhone5To7Plus(60, 90)
            let incomingHMargin = ScaleFromIPhone5To7Plus(60, 90)
            let ongoingBottomMargin = ScaleFromIPhone5To7Plus(30, 50)
            let incomingBottomMargin = CGFloat(50)
            let avatarVSpacing = ScaleFromIPhone5To7Plus(25, 50)

            // Dark blurred background.
            blurView.autoPinEdgesToSuperviewEdges()

            contactNameLabel.autoPinEdge(toSuperviewEdge:.top, withInset:topMargin)
            contactNameLabel.autoPinWidthToSuperview(withMargin:contactHMargin)
            contactNameLabel.setContentHuggingVerticalHigh()

            callStatusLabel.autoPinEdge(.top, to:.bottom, of:contactNameLabel, withOffset:contactVSpacing)
            callStatusLabel.autoPinWidthToSuperview(withMargin:contactHMargin)
            callStatusLabel.setContentHuggingVerticalHigh()

            contactAvatarView.autoPinEdge(.top, to:.bottom, of:callStatusLabel, withOffset:+avatarVSpacing)
            contactAvatarView.autoPinEdge(.bottom, to:.top, of:ongoingCallView, withOffset:-avatarVSpacing)
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
            incomingCallControlsRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:incomingBottomMargin)
            incomingCallControlsRow.autoPinWidthToSuperview(withMargin:incomingHMargin)
            incomingCallControlsRow.setContentHuggingVerticalHigh()
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
            return NSLocalizedString("IN_CALL_TALKING", comment: "Call setup status label")
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

        // Show Incoming vs. (Outgoing || Accepted) call controls
        let isRinging = callState == .localRinging
        for subview in allControls() {
            if isRinging {
                // Show incoming controls
                let isIncomingCallControl = incomingCallControls().contains(subview)
                subview.isHidden = !isIncomingCallControl
            } else {
                // Show ongoing controls
                let isOngoingCallControl = ongoingCallControls().contains(subview)
                subview.isHidden = !isOngoingCallControl
            }
        }

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
    }

    func allControls() -> [UIView] {
        return incomingCallControls() + ongoingCallControls()
    }

    func incomingCallControls() -> [UIView] {
        // TODO: Should this include textMessageButton?
        return [ acceptIncomingButton, declineIncomingButton, ]
    }

    func ongoingCallControls() -> [UIView] {
        return [ muteButton, speakerPhoneButton, textMessageButton, hangUpButton, videoButton, ]
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
