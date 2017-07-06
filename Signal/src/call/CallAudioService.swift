//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation

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
                Logger.error("\(self.TAG) faild to build audio player with error: \(error)")
                newPlayer = nil
                assertionFailure()
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
            // Auto-enable speakerphone when local video is enabled.
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVideoChat,
                            options: [.defaultToSpeaker, .allowBluetooth])
        } else if call.isSpeakerphoneEnabled {
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat,
                            options: [.defaultToSpeaker, .allowBluetooth])
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
            Logger.error("\(self.TAG) unable to build player")
            assertionFailure()
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

    private func setAudioSession(category: String,
                                 mode: String? = nil,
                                 options: AVAudioSessionCategoryOptions = AVAudioSessionCategoryOptions(rawValue: 0)) {

        let session = AVAudioSession.sharedInstance()
        do {
            if #available(iOS 10.0, *), let mode = mode {
                let oldCategory = session.category
                let oldMode = session.mode
                let oldOptions = session.categoryOptions

                if oldCategory == category, oldMode == mode, oldOptions == options {
                    Logger.debug("\(self.TAG) in \(#function) doing nothing, since audio session is unchanged.")
                    return
                }

                if oldCategory != category {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldMode != mode {
                    Logger.debug("\(self.TAG) audio session changed mode: \(oldMode) -> \(mode) ")
                }
                if oldOptions != options {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldOptions) -> \(options) ")
                }

                Logger.debug("\(self.TAG) setting new category: \(category) mode: \(mode) options: \(options)")
                try session.setCategory(category, mode: mode, options: options)

            } else {
                let oldCategory = session.category
                let oldOptions = session.categoryOptions
                if session.category == category, session.categoryOptions == options {
                    Logger.debug("\(self.TAG) in \(#function) doing nothing, since audio session is unchanged.")
                    return
                }

                if oldCategory != category {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldCategory) -> \(category) ")
                }
                if oldOptions != options {
                    Logger.debug("\(self.TAG) audio session changed category: \(oldOptions) -> \(options) ")
                }

                Logger.debug("\(self.TAG) setting new category: \(category) options: \(options)")
                try session.setCategory(category, with: options)

            }
        } catch {
            let message = "\(self.TAG) in \(#function) failed to set category: \(category) mode: \(String(describing: mode)), options: \(options) with error: \(error)"
            assertionFailure(message)
            Logger.error(message)
        }
    }
}
