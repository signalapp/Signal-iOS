//  Created by Michael Kirk on 11/10/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import WebRTC
import PromiseKit

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
class CallViewController: UIViewController {

    enum CallDirection {
        case unspecified, outgoing, incoming
    }

    let TAG = "[CallViewController]"

    // Dependencies
    let callService: CallService
    let callUIAdapter: CallUIAdapter
    let contactsManager: OWSContactsManager
    let audioService: CallAudioService

    // MARK: Properties

    var peerConnectionClient: PeerConnectionClient?
    var callDirection: CallDirection = .unspecified
    var thread: TSContactThread!
    var call: SignalCall!

    @IBOutlet weak var contactNameLabel: UILabel!
    @IBOutlet weak var contactAvatarView: AvatarImageView!
    @IBOutlet weak var callStatusLabel: UILabel!

    // MARK: Outgoing or Accepted Call Controls

    @IBOutlet weak var callControls: UIView!
    @IBOutlet weak var muteButton: UIButton!
    @IBOutlet weak var speakerPhoneButton: UIButton!

    // MARK: Incoming Call Controls

    @IBOutlet weak var incomingCallControls: UIView!

    // MARK: Initializers

    required init?(coder aDecoder: NSCoder) {
        contactsManager = Environment.getCurrent().contactsManager
        callService = Environment.getCurrent().callService
        callUIAdapter = callService.callUIAdapter
        audioService = CallAudioService()
        super.init(coder: aDecoder)
    }

    required init() {
        contactsManager = Environment.getCurrent().contactsManager
        callService = Environment.getCurrent().callService
        callUIAdapter = callService.callUIAdapter
        audioService = CallAudioService()
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {

        guard let thread = self.thread else {
            Logger.error("\(TAG) tried to show call call without specifying thread.")
            showCallFailed(error: OWSErrorMakeAssertionError())
            return
        }

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

        call.stateDidChange = callStateDidChange
        callStateDidChange(call.state)
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
        callControls.isHidden = callState == .localRinging
        incomingCallControls.isHidden = callState != .localRinging

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

    // MARK: - Actions

    func callStateDidChange(_ newState: CallState) {
        DispatchQueue.main.async {
            self.updateCallUI(callState: newState)
        }
        self.audioService.handleState(newState)
    }

    /**
     * Ends a connected call. Do not confuse with `didPressDeclineCall`.
     */
    @IBAction func didPressHangup(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        if let call = self.call {
            callUIAdapter.endCall(call)
        } else {
            Logger.warn("\(TAG) hung up, but call was unexpectedly nil")
        }

        self.dismiss(animated: true)
    }

    @IBAction func didPressMute(sender muteButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        muteButton.isSelected = !muteButton.isSelected
        CallService.signalingQueue.async {
            self.callService.handleToggledMute(isMuted: muteButton.isSelected)
        }
    }

    @IBAction func didPressSpeakerphone(sender speakerphoneButton: UIButton) {
        Logger.info("\(TAG) called \(#function)")
        speakerphoneButton.isSelected = !speakerphoneButton.isSelected
        audioService.isSpeakerphoneEnabled = speakerphoneButton.isSelected
    }

    @IBAction func didPressAnswerCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        guard let call = self.call else {
            Logger.error("\(TAG) call was unexpectedly nil. Terminating call.")
            self.callStatusLabel.text = NSLocalizedString("END_CALL_UNCATEGORIZED_FAILURE", comment: "Call setup status label")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss(animated: true)
            }
            return
        }

        CallService.signalingQueue.async {
            self.callService.handleAnswerCall(call)
        }
    }

    /**
     * Denies an incoming not-yet-connected call, Do not confuse with `didPressHangup`.
     */
    @IBAction func didPressDeclineCall(sender: UIButton) {
        Logger.info("\(TAG) called \(#function)")

        if let call = self.call {
            callUIAdapter.declineCall(call)
        } else {
            Logger.warn("\(TAG) denied call, but call was unexpectedly nil")
        }

        self.dismiss(animated: true)
    }
}
