//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import SignalServiceKit
import SignalMessaging

struct AudioSource: Hashable {

    let image: UIImage
    let localizedName: String
    let portDescription: AVAudioSessionPortDescription?

    // The built-in loud speaker / aka speakerphone
    let isBuiltInSpeaker: Bool

    // The built-in quiet speaker, aka the normal phone handset receiver earpiece
    let isBuiltInEarPiece: Bool

    init(localizedName: String, image: UIImage, isBuiltInSpeaker: Bool, isBuiltInEarPiece: Bool, portDescription: AVAudioSessionPortDescription? = nil) {
        self.localizedName = localizedName
        self.image = image
        self.isBuiltInSpeaker = isBuiltInSpeaker
        self.isBuiltInEarPiece = isBuiltInEarPiece
        self.portDescription = portDescription
    }

    init(portDescription: AVAudioSessionPortDescription) {

        let isBuiltInEarPiece = portDescription.portType == AVAudioSessionPortBuiltInMic

        // portDescription.portName works well for BT linked devices, but if we are using
        // the built in mic, we have "iPhone Microphone" which is a little awkward.
        // In that case, instead we prefer just the model name e.g. "iPhone" or "iPad"
        let localizedName = isBuiltInEarPiece ? UIDevice.current.localizedModel : portDescription.portName

        self.init(localizedName: localizedName,
                  image: #imageLiteral(resourceName: "button_phone_white"), // TODO
                  isBuiltInSpeaker: false,
                  isBuiltInEarPiece: isBuiltInEarPiece,
                  portDescription: portDescription)
    }

    // Speakerphone is handled separately from the other audio routes as it doesn't appear as an "input"
    static var builtInSpeaker: AudioSource {
        return self.init(localizedName: NSLocalizedString("AUDIO_ROUTE_BUILT_IN_SPEAKER", comment: "action sheet button title to enable built in speaker during a call"),
                         image: #imageLiteral(resourceName: "button_phone_white"), //TODO
                         isBuiltInSpeaker: true,
                         isBuiltInEarPiece: false)
    }

    // MARK: Hashable

    static func ==(lhs: AudioSource, rhs: AudioSource) -> Bool {
        // Simply comparing the `portDescription` vs the `portDescription.uid`
        // caused multiple instances of the built in mic to turn up in a set.
        if lhs.isBuiltInSpeaker && rhs.isBuiltInSpeaker {
            return true
        }

        if lhs.isBuiltInSpeaker || rhs.isBuiltInSpeaker {
            return false
        }

        guard let lhsPortDescription = lhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        guard let rhsPortDescription = rhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        return lhsPortDescription.uid == rhsPortDescription.uid
    }

    var hashValue: Int {
        guard let portDescription = self.portDescription else {
            assert(self.isBuiltInSpeaker)
            return "Built In Speaker".hashValue
        }
        return portDescription.uid.hash
    }
}

protocol CallAudioServiceDelegate: class {
    func callAudioService(_ callAudioService: CallAudioService, didUpdateIsSpeakerphoneEnabled isEnabled: Bool)
    func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService)
}

@objc class CallAudioService: NSObject, CallObserver {

    private var vibrateTimer: Timer?
    private let audioPlayer = AVAudioPlayer()
    private let handleRinging: Bool
    weak var delegate: CallAudioServiceDelegate? {
        willSet {
            assert(newValue == nil || delegate == nil)
        }
    }

    // MARK: Vibration config
    private let vibrateRepeatDuration = 1.6

    // Our ring buzz is a pair of vibrations.
    // `pulseDuration` is the small pause between the two vibrations in the pair.
    private let pulseDuration = 0.2

    var audioSession: OWSAudioSession {
        return OWSAudioSession.shared
    }
    var avAudioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }

    // MARK: - Initializers

    init(handleRinging: Bool) {
        self.handleRinging = handleRinging

        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings

        // Configure audio session so we don't prompt user with Record permission until call is connected.

        audioSession.configureRTCAudio()
        NotificationCenter.default.addObserver(forName: .AVAudioSessionRouteChange, object: avAudioSession, queue: nil) { _ in
            assert(!Thread.isMainThread)
            self.updateIsSpeakerphoneEnabled()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        self.handleState(call: call)
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    internal func holdDidChange(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    internal func audioSourceDidChange(call: SignalCall, audioSource: AudioSource?) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)

        if let audioSource = audioSource, audioSource.isBuiltInSpeaker {
            self.isSpeakerphoneEnabled = true
        } else {
            self.isSpeakerphoneEnabled = false
        }
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    // Speakerphone can be manipulated by the in-app callscreen or via the system callscreen (CallKit).
    // Unlike other CallKit CallScreen buttons, enabling doesn't trigger a CXAction, so it's not as simple
    // to track state changes. Instead we never store the state and directly access the ground-truth in the
    // AVAudioSession.
    private(set) var isSpeakerphoneEnabled: Bool = false {
        didSet {
            self.delegate?.callAudioService(self, didUpdateIsSpeakerphoneEnabled: isSpeakerphoneEnabled)
        }
    }

    public func requestSpeakerphone(isEnabled: Bool) {
        // This is a little too slow to execute on the main thread and the results are not immediately available after execution
        // anyway, so we dispatch async. If you need to know the new value, you'll need to check isSpeakerphoneEnabled and take
        // advantage of the CallAudioServiceDelegate.callAudioService(_:didUpdateIsSpeakerphoneEnabled:)
        DispatchQueue.global().async {
            do {
                try self.avAudioSession.overrideOutputAudioPort( isEnabled ? .speaker : .none )
            } catch {
                owsFailDebug("failed to set \(#function) = \(isEnabled) with error: \(error)")
            }
        }
    }

    private func updateIsSpeakerphoneEnabled() {
        let value = avAudioSession.currentRoute.outputs.contains { (portDescription: AVAudioSessionPortDescription) -> Bool in
            return portDescription.portName == AVAudioSessionPortBuiltInSpeaker
        }
        DispatchQueue.main.async {
            self.isSpeakerphoneEnabled = value
        }
    }

    private func ensureProperAudioSession(call: SignalCall?) {
        AssertIsOnMainThread()

        guard let call = call, !call.isTerminated else {
            // Revert to default audio
            setAudioSession(category: AVAudioSessionCategorySoloAmbient,
                            mode: AVAudioSessionModeDefault)
            return
        }

        // Disallow bluetooth while (and only while) the user has explicitly chosen the built in receiver.
        //
        // NOTE: I'm actually not sure why this is required - it seems like we should just be able
        // to setPreferredInput to call.audioSource.portDescription in this case,
        // but in practice I'm seeing the call revert to the bluetooth headset.
        // Presumably something else (in WebRTC?) is touching our shared AudioSession. - mjk
        let options: AVAudioSessionCategoryOptions = call.audioSource?.isBuiltInEarPiece == true ? [] : [.allowBluetooth]

        if call.state == .localRinging {
            // SoloAmbient plays through speaker, but respects silent switch
            setAudioSession(category: AVAudioSessionCategorySoloAmbient,
                            mode: AVAudioSessionModeDefault)
        } else if call.hasLocalVideo {
            // Because ModeVideoChat affects gain, we don't want to apply it until the call is connected.
            // otherwise sounds like ringing will be extra loud for video vs. speakerphone

            // Apple Docs say that setting mode to AVAudioSessionModeVideoChat has the
            // side effect of setting options: .allowBluetooth, when I remove the (seemingly unnecessary)
            // option, and inspect AVAudioSession.sharedInstance.categoryOptions == 0. And availableInputs
            // does not include my linked bluetooth device
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVideoChat,
                            options: options)
        } else {
            // Apple Docs say that setting mode to AVAudioSessionModeVoiceChat has the
            // side effect of setting options: .allowBluetooth, when I remove the (seemingly unnecessary)
            // option, and inspect AVAudioSession.sharedInstance.categoryOptions == 0. And availableInputs
            // does not include my linked bluetooth device
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat,
                            options: options)
        }

        do {
            // It's important to set preferred input *after* ensuring properAudioSession
            // because some sources are only valid for certain category/option combinations.
            let existingPreferredInput = avAudioSession.preferredInput
            if  existingPreferredInput != call.audioSource?.portDescription {
                Logger.info("changing preferred input: \(String(describing: existingPreferredInput)) -> \(String(describing: call.audioSource?.portDescription))")
                try avAudioSession.setPreferredInput(call.audioSource?.portDescription)
            }

        } catch {
            owsFailDebug("failed setting audio source with error: \(error) isSpeakerPhoneEnabled: \(call.isSpeakerphoneEnabled)")
        }
    }

    // MARK: - Service action handlers

    public func didUpdateVideoTracks(call: SignalCall?) {
        Logger.verbose("")

        self.ensureProperAudioSession(call: call)
    }

    public func handleState(call: SignalCall) {
        assert(Thread.isMainThread)

        Logger.verbose("new state: \(call.state)")

        // Stop playing sounds while switching audio session so we don't 
        // get any blips across a temporary unintended route.
        stopPlayingAnySounds()
        self.ensureProperAudioSession(call: call)

        switch call.state {
        case .idle: handleIdle(call: call)
        case .dialing: handleDialing(call: call)
        case .answering: handleAnswering(call: call)
        case .remoteRinging: handleRemoteRinging(call: call)
        case .localRinging: handleLocalRinging(call: call)
        case .connected: handleConnected(call: call)
        case .reconnecting: handleReconnecting(call: call)
        case .localFailure: handleLocalFailure(call: call)
        case .localHangup: handleLocalHangup(call: call)
        case .remoteHangup: handleRemoteHangup(call: call)
        case .remoteBusy: handleBusy(call: call)
        }
    }

    private func handleIdle(call: SignalCall) {
        Logger.debug("")
    }

    private func handleDialing(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        // HACK: Without this async, dialing sound only plays once. I don't really understand why. Does the audioSession
        // need some time to settle? Is somethign else interrupting our session?
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
            self.play(sound: OWSSound.callConnecting)
        }
    }

    private func handleAnswering(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")
    }

    private func handleRemoteRinging(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        self.play(sound: OWSSound.callOutboundRinging)
    }

    private func handleLocalRinging(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        startRinging(call: call)
    }

    private func handleConnected(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")
    }

    private func handleReconnecting(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")
    }

    private func handleLocalFailure(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        play(sound: OWSSound.callFailure)
        handleCallEnded(call: call)
    }

    private func handleLocalHangup(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        handleCallEnded(call: call)
    }

    private func handleRemoteHangup(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        vibrate()

        handleCallEnded(call: call)
    }

    private func handleBusy(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        play(sound: OWSSound.callBusy)

        // Let the busy sound play for 4 seconds. The full file is longer than necessary
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4.0) {
            self.handleCallEnded(call: call)
        }
    }

    private func handleCallEnded(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        // Stop solo audio, revert to default.
        isSpeakerphoneEnabled = false
        setAudioSession(category: AVAudioSessionCategorySoloAmbient)
    }

    // MARK: Playing Sounds

    var currentPlayer: OWSAudioPlayer?

    private func stopPlayingAnySounds() {
        currentPlayer?.stop()
        stopAnyRingingVibration()
    }

    private func play(sound: OWSSound) {
        guard let newPlayer = OWSSounds.audioPlayer(for: sound) else {
            owsFailDebug("unable to build player for sound: \(OWSSounds.displayName(for: sound))")
            return
        }
        Logger.info("playing sound: \(OWSSounds.displayName(for: sound))")

        // It's important to stop the current player **before** starting the new player. In the case that 
        // we're playing the same sound, since the player is memoized on the sound instance, we'd otherwise 
        // stop the sound we just started.
        self.currentPlayer?.stop()
        newPlayer.playWithCurrentAudioCategory()
        self.currentPlayer = newPlayer
    }

    // MARK: - Ringing

    private func startRinging(call: SignalCall) {
        guard handleRinging else {
            Logger.debug("ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }

        vibrateTimer = WeakTimer.scheduledTimer(timeInterval: vibrateRepeatDuration, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            self?.ringVibration()
        }
        vibrateTimer?.fire()
        play(sound: .defaultiOSIncomingRingtone)
    }

    private func stopAnyRingingVibration() {
        guard handleRinging else {
            Logger.debug("ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }
        Logger.debug("")

        // Stop vibrating
        vibrateTimer?.invalidate()
        vibrateTimer = nil
    }

    // public so it can be called by timer via selector
    public func ringVibration() {
        // Since a call notification is more urgent than a message notifaction, we
        // vibrate twice, like a pulse, to differentiate from a normal notification vibration.
        vibrate()
        DispatchQueue.default.asyncAfter(deadline: DispatchTime.now() + pulseDuration) {
            self.vibrate()
        }
    }

    func vibrate() {
        // TODO implement HapticAdapter for iPhone7 and up
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    // MARK: - AudioSession MGMT
    // TODO move this to CallAudioSession?

    // Note this method is sensitive to the current audio session configuration.
    // Specifically if you call it while speakerphone is enabled you won't see 
    // any connected bluetooth routes.
    var availableInputs: [AudioSource] {
        guard let availableInputs = avAudioSession.availableInputs else {
            // I'm not sure why this would happen, but it may indicate an error.
            owsFailDebug("No available inputs or inputs not ready")
            return [AudioSource.builtInSpeaker]
        }

        Logger.info("availableInputs: \(availableInputs)")
        return [AudioSource.builtInSpeaker] + availableInputs.map { portDescription in
            return AudioSource(portDescription: portDescription)
        }
    }

    func currentAudioSource(call: SignalCall) -> AudioSource? {
        if let audioSource = call.audioSource {
            return audioSource
        }

        // Before the user has specified an audio source on the call, we rely on the existing
        // system state to determine the current audio source.
        // If a bluetooth is connected, this will be bluetooth, otherwise
        // this will be the receiver.
        guard let portDescription = avAudioSession.currentRoute.inputs.first else {
            return nil
        }

        return AudioSource(portDescription: portDescription)
    }

    private func setAudioSession(category: String,
                                 mode: String? = nil,
                                 options: AVAudioSessionCategoryOptions = AVAudioSessionCategoryOptions(rawValue: 0)) {

        AssertIsOnMainThread()

        var audioSessionChanged = false
        do {
            if #available(iOS 10.0, *), let mode = mode {
                let oldCategory = avAudioSession.category
                let oldMode = avAudioSession.mode
                let oldOptions = avAudioSession.categoryOptions

                guard oldCategory != category || oldMode != mode || oldOptions != options else {
                    return
                }

                audioSessionChanged = true

                if oldCategory != category {
                    Logger.debug("audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldMode != mode {
                    Logger.debug("audio session changed mode: \(oldMode) -> \(mode) ")
                }
                if oldOptions != options {
                    Logger.debug("audio session changed options: \(oldOptions) -> \(options) ")
                }
                try avAudioSession.setCategory(category, mode: mode, options: options)

            } else {
                let oldCategory = avAudioSession.category
                let oldOptions = avAudioSession.categoryOptions

                guard avAudioSession.category != category || avAudioSession.categoryOptions != options else {
                    return
                }

                audioSessionChanged = true

                if oldCategory != category {
                    Logger.debug("audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldOptions != options {
                    Logger.debug("audio session changed options: \(oldOptions) -> \(options) ")
                }
                try avAudioSession.setCategory(category, with: options)

            }
        } catch {
            let message = "failed to set category: \(category) mode: \(String(describing: mode)), options: \(options) with error: \(error)"
            owsFailDebug(message)
        }

        if audioSessionChanged {
            Logger.info("")
            self.delegate?.callAudioServiceDidChangeAudioSession(self)
        }
    }
}
