//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

public let CallAudioServiceSessionChanged = Notification.Name("CallAudioServiceSessionChanged")

struct AudioSource: Hashable {

//    let name: String
    let image: UIImage
    let localizedName: String
    let portDescription: AVAudioSessionPortDescription?
    let isBuiltInSpeaker: Bool

//    init(name: String, image: UIImage, isCurrentRoute: Bool) {
//        
//    }
//    

    init(localizedName: String, image: UIImage, isBuiltInSpeaker: Bool, portDescription: AVAudioSessionPortDescription? = nil) {
        self.localizedName = localizedName
        self.image = image
        self.isBuiltInSpeaker = isBuiltInSpeaker
        self.portDescription = portDescription
    }

    init(portDescription: AVAudioSessionPortDescription) {
        self.init(localizedName: portDescription.portName,
                  image:#imageLiteral(resourceName: "button_phone_white"), // TODO
                  isBuiltInSpeaker: false,
                  portDescription: portDescription)
    }

    // Speakerphone is handled separately from the other audio routes as it doesn't appear as an "input"
    static var builtInSpeaker: AudioSource {
        return self.init(localizedName: NSLocalizedString("AUDIO_ROUTE_BUILT_IN_SPEAKER", comment: "action sheet button title to enable built in speaker during a call"),
                         image: #imageLiteral(resourceName: "button_phone_white"), //TODO
                         isBuiltInSpeaker: true)
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
            owsFail("only the built in speaker should lack a port description")
            return false
        }

        guard let rhsPortDescription = rhs.portDescription else {
            owsFail("only the built in speaker should lack a port description")
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

@objc class CallAudioService: NSObject, CallObserver {

    private let TAG = "[CallAudioService]"
    private var vibrateTimer: Timer?
    private let audioPlayer = AVAudioPlayer()
    private let handleRinging: Bool

    class Sound {
        let TAG = "[Sound]"

        static let incomingRing = Sound(filePath: "r", fileExtension: "caf", loop: true)
        static let outgoingRing = Sound(filePath: "outring", fileExtension: "mp3", loop: true)
        static let dialing = Sound(filePath: "sonarping", fileExtension: "mp3", loop: true)
        static let busy = Sound(filePath: "busy", fileExtension: "mp3", loop: false)
        static let failure = Sound(filePath: "failure", fileExtension: "mp3", loop: false)

        let filePath: String
        let fileExtension: String
        let url: URL

        let loop: Bool

        init(filePath: String, fileExtension: String, loop: Bool) {
            self.filePath = filePath
            self.fileExtension = fileExtension
            self.url = Bundle.main.url(forResource: self.filePath, withExtension: self.fileExtension)!
            self.loop = loop
        }

        lazy var player: AVAudioPlayer? = {
            let newPlayer: AVAudioPlayer?
            do {
                try newPlayer = AVAudioPlayer(contentsOf: self.url, fileTypeHint: nil)
                if self.loop {
                    newPlayer?.numberOfLoops = -1
                }
            } catch {
                owsFail("\(self.TAG) failed to build audio player with error: \(error)")
                newPlayer = nil
            }
            return newPlayer
        }()
    }

    // MARK: Vibration config
    private let vibrateRepeatDuration = 1.6

    // Our ring buzz is a pair of vibrations.
    // `pulseDuration` is the small pause between the two vibrations in the pair.
    private let pulseDuration = 0.2

    // MARK: - Initializers

    init(handleRinging: Bool) {
        self.handleRinging = handleRinging
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        self.handleState(call:call)
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        Logger.verbose("\(TAG) in \(#function) is no-op")
    }

    internal func speakerphoneDidChange(call: SignalCall, isEnabled: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    private func ensureProperAudioSession(call: SignalCall?) {
        guard let call = call else {
            setAudioSession(category: AVAudioSessionCategoryPlayback,
                            mode: AVAudioSessionModeDefault)
            return
        }

        if call.state == .localRinging {
            // SoloAmbient plays through speaker, but respects silent switch
            setAudioSession(category: AVAudioSessionCategorySoloAmbient,
                            mode: AVAudioSessionModeDefault)
        } else if call.hasLocalVideo {
            // Don't allow bluetooth for local video if speakerphone has been explicitly chosen by the user.
            let options: AVAudioSessionCategoryOptions = call.isSpeakerphoneEnabled ? [.defaultToSpeaker] : [.defaultToSpeaker, .allowBluetooth]

            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVideoChat,
                            options: options)
        } else if call.isSpeakerphoneEnabled {
            // Ensure no bluetooth if user has specified speakerphone
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat,
                            options: [.defaultToSpeaker])
        } else {
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat,
                            options: [.allowBluetooth])
        }
    }

    // MARK: - Service action handlers

    public func didUpdateVideoTracks(call: SignalCall?) {
        Logger.verbose("\(TAG) in \(#function)")

        self.ensureProperAudioSession(call: call)
    }

    public func handleState(call: SignalCall) {
        assert(Thread.isMainThread)

        Logger.verbose("\(TAG) in \(#function) new state: \(call.state)")

        switch call.state {
        case .idle: handleIdle(call: call)
        case .dialing: handleDialing(call: call)
        case .answering: handleAnswering(call: call)
        case .remoteRinging: handleRemoteRinging(call: call)
        case .localRinging: handleLocalRinging(call: call)
        case .connected: handleConnected(call: call)
        case .localFailure: handleLocalFailure(call: call)
        case .localHangup: handleLocalHangup(call: call)
        case .remoteHangup: handleRemoteHangup(call: call)
        case .remoteBusy: handleBusy(call: call)
        }
    }

    private func handleIdle(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
    }

    private func handleDialing(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)

        // HACK: Without this async, dialing sound only plays once. I don't really understand why. Does the audioSession
        // need some time to settle? Is somethign else interrupting our session?
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
            self.play(sound: Sound.dialing)
        }
    }

    private func handleAnswering(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()
        self.ensureProperAudioSession(call: call)
    }

    private func handleRemoteRinging(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()

        // FIXME if you toggled speakerphone before this point, the outgoing ring does not play through speaker. Why?
        self.play(sound: Sound.outgoingRing)
    }

    private func handleLocalRinging(call: SignalCall) {
        Logger.debug("\(TAG) in \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()
        ensureProperAudioSession(call: call)
        startRinging(call: call)
    }

    private func handleConnected(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()

        // start recording to transmit call audio.
        ensureProperAudioSession(call: call)
    }

    private func handleLocalFailure(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()

        play(sound: Sound.failure)
    }

    private func handleLocalHangup(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        handleCallEnded(call: call)
    }

    private func handleRemoteHangup(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        vibrate()

        handleCallEnded(call:call)
    }

    private func handleBusy(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()

        play(sound: Sound.busy)
        // Let the busy sound play for 4 seconds. The full file is longer than necessary
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4.0) {
            self.handleCallEnded(call: call)
        }
    }

    private func handleCallEnded(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        AssertIsOnMainThread()

        stopPlayingAnySounds()

        // Stop solo audio, revert to default.
        setAudioSession(category: AVAudioSessionCategoryAmbient)
    }

    // MARK: Playing Sounds

    var currentPlayer: AVAudioPlayer?

    private func stopPlayingAnySounds() {
        currentPlayer?.stop()
        stopAnyRingingVibration()
    }

    private func play(sound: Sound) {
        guard let newPlayer = sound.player else {
            owsFail("\(self.TAG) unable to build player")
            return
        }
        Logger.info("\(self.TAG) playing sound: \(sound.filePath)")

        // It's important to stop the current player **before** starting the new player. In the case that 
        // we're playing the same sound, since the player is memoized on the sound instance, we'd otherwise 
        // stop the sound we just started.
        self.currentPlayer?.stop()
        newPlayer.play()
        self.currentPlayer = newPlayer
    }

    // MARK: - Ringing

    private func startRinging(call: SignalCall) {
        guard handleRinging else {
            Logger.debug("\(TAG) ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }

        vibrateTimer = WeakTimer.scheduledTimer(timeInterval: vibrateRepeatDuration, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            self?.ringVibration()
        }
        vibrateTimer?.fire()
        play(sound: Sound.incomingRing)
    }

    private func stopAnyRingingVibration() {
        guard handleRinging else {
            Logger.debug("\(TAG) ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }
        Logger.debug("\(TAG) in \(#function)")

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

    // MARK - AudioSession MGMT
    // TODO move this to CallAudioSession?

    var hasAlternateAudioRoutes: Bool {
//        let session = AVAudioSession.sharedInstance()

        // PROBLEM: doesn't list bluetooth when speakerphone is enabled.
//        guard let availableInputs = session.availableInputs else {
//            // I'm not sure when this would happen.
//            owsFail("No available inputs or inputs not ready")
//            return false
//        }

        //
//        let availableInputs = session.currentRoute.inputs

        Logger.info("\(TAG) in \(#function) availableInputs: \(availableInputs)")
        for input in self.availableInputs {
            if input.portDescription?.portType == AVAudioSessionPortBluetoothHFP {
                return true
            }
        }

        return false
    }

    // Note this method is sensitive to the current audio session configuration.
    // Specifically if you call it while speakerphone is enabled you won't see 
    // any connected bluetooth routes.
    var availableInputs: [AudioSource] {
        let session = AVAudioSession.sharedInstance()
        // guard let availableOutputs = session.outputDataSources else {

        // Maybe... shows the bluetooth AND the receiver (but not speaker)
        // PROBLEM: doesn't list bluetooth when speakerphone is enabled.
        guard let availableInputs = session.availableInputs else {
            // I'm not sure when this would happen.
            owsFail("No available inputs or inputs not ready")
            return [AudioSource.builtInSpeaker]
        }

        // PROBLEM: doesn't list iphone internal
        // PROBLEM: doesn't list bluetooth until toggling speakerphone on/off
//        let availableInputs = session.currentRoute.inputs
//        let availableInputs = session.currentRoute.outputs

        // NOPE. only shows the single active one. (e.g. blue tooth XOR receive)
//        let availableOutputs = session.currentRoute.outputs

        Logger.info("\(TAG) in \(#function) availableInputs: \(availableInputs)")
        return [AudioSource.builtInSpeaker] + availableInputs.map { portDescription in
            // TODO get proper image
            // TODO set isCurrentRoute correctly
//            return AudioSource(name: output.dataSourceName, image:#imageLiteral(resourceName: "button_phone_white"), isCurrentRoute: false)
//            return AudioSource(name: output.portName, image:#imageLiteral(resourceName: "button_phone_white"), isCurrentRoute: false)

            return AudioSource(portDescription: portDescription)
        }
    }

//    var builtInMicrophoneSource: AudioSource? {
//        availableInputs.first { source -> Bool in
//            if source.uid =
//        }
//    }

    func currentAudioSource(call: SignalCall) -> AudioSource? {
        if call.isSpeakerphoneEnabled {
            return AudioSource.builtInSpeaker
        } else {
            let session = AVAudioSession.sharedInstance()
            guard let portDescription = session.currentRoute.inputs.first else {
                return nil
            }

            return AudioSource(portDescription: portDescription)
        }
    }

    public func setPreferredInput(call: SignalCall, audioSource: AudioSource?) {
        let session = AVAudioSession.sharedInstance()
        do {
            Logger.debug("\(TAG) in \(#function) audioSource: \(String(describing: audioSource))")
            try session.setPreferredInput(audioSource?.portDescription)
        } catch {
            owsFail("\(TAG) failed with error: \(error)")
        }
        self.ensureProperAudioSession(call: call)
    }

    private func setAudioSession(category: String,
                                 mode: String? = nil,
                                 options: AVAudioSessionCategoryOptions = AVAudioSessionCategoryOptions(rawValue: 0)) {

        let session = AVAudioSession.sharedInstance()
        var audioSessionChanged = false
        do {
            if #available(iOS 10.0, *), let mode = mode {
                let oldCategory = session.category
                let oldMode = session.mode
                let oldOptions = session.categoryOptions

                guard oldCategory != category || oldMode != mode || oldOptions != options else {
                    return
                }

                audioSessionChanged = true

                if oldCategory != category {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldMode != mode {
                    Logger.debug("\(self.TAG) audio session changed mode: \(oldMode) -> \(mode) ")
                }
                if oldOptions != options {
                    Logger.debug("\(self.TAG) audio session changed options: \(oldOptions) -> \(options) ")
                }
                try session.setCategory(category, mode: mode, options: options)

            } else {
                let oldCategory = session.category
                let oldOptions = session.categoryOptions

                guard session.category != category || session.categoryOptions != options else {
                    return
                }

                audioSessionChanged = true

                if oldCategory != category {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldOptions != options {
                    Logger.debug("\(self.TAG) audio session changed options: \(oldOptions) -> \(options) ")
                }
                try session.setCategory(category, with: options)

            }
        } catch {
            let message = "\(self.TAG) in \(#function) failed to set category: \(category) mode: \(String(describing: mode)), options: \(options) with error: \(error)"
            owsFail(message)
        }

        if audioSessionChanged {
            Logger.info("\(TAG) in \(#function)")
            NotificationCenter.default.post(name: CallAudioServiceSessionChanged, object: nil)
        }
    }
}
