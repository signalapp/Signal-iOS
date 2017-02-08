//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class CallAudioService: NSObject, CallObserver {

    private let TAG = "[CallAudioService]"
    private var vibrateTimer: Timer?
    private let soundPlayer = JSQSystemSoundPlayer.shared()!
    private let handleRinging: Bool

    enum SoundFilenames: String {
        case incomingRing = "r"
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

        ensureIsEnabled(call: call)
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        ensureIsEnabled(call: call)
    }

    private func ensureIsEnabled(call: SignalCall) {
        // Auto-enable speakerphone when local video is enabled.
        if call.hasLocalVideo {
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVideoChat,
                            options: .defaultToSpeaker)
        } else if call.isSpeakerphoneEnabled {
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat,
                            options: .defaultToSpeaker)
        } else {
            setAudioSession(category: AVAudioSessionCategoryPlayAndRecord,
                            mode: AVAudioSessionModeVoiceChat)
        }
    }

    // MARK: - Service action handlers

    public func handleState(call: SignalCall) {
        assert(Thread.isMainThread)

        Logger.verbose("\(TAG) in \(#function) new state: \(call.state)")

        switch call.state {
        case .idle: handleIdle()
        case .dialing: handleDialing()
        case .answering: handleAnswering()
        case .remoteRinging: handleRemoteRinging()
        case .localRinging: handleLocalRinging()
        case .connected: handleConnected(call:call)
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
        Logger.debug("\(TAG) in \(#function)")
        startRinging()
    }

    private func handleConnected(call: SignalCall) {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()

        // disable start recording to transmit call audio.
        ensureIsEnabled(call: call)
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

    // MARK: - Ringing

    private func startRinging() {
        guard handleRinging else {
            Logger.debug("\(TAG) ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }

        vibrateTimer = WeakTimer.scheduledTimer(timeInterval: vibrateRepeatDuration, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            self?.ringVibration()
        }
        vibrateTimer?.fire()

        // Stop other sounds and play ringer through external speaker
        setAudioSession(category: AVAudioSessionCategorySoloAmbient)

        soundPlayer.playSound(withFilename: SoundFilenames.incomingRing.rawValue, fileExtension: kJSQSystemSoundTypeCAF)
    }

    private func stopRinging() {
        guard handleRinging else {
            Logger.debug("\(TAG) ignoring \(#function) since CallKit handles it's own ringing state")
            return
        }
        Logger.debug("\(TAG) in \(#function)")

        // Stop vibrating
        vibrateTimer?.invalidate()
        vibrateTimer = nil

        soundPlayer.stopSound(withFilename: SoundFilenames.incomingRing.rawValue)

        // Stop solo audio, revert to default.
        setAudioSession(category: AVAudioSessionCategoryAmbient)
    }

    // public so it can be called by timer via selector
    public func ringVibration() {
        // Since a call notification is more urgent than a message notifaction, we
        // vibrate twice, like a pulse, to differentiate from a normal notification vibration.
        soundPlayer.playVibrateSound()
        DispatchQueue.default.asyncAfter(deadline: DispatchTime.now() + pulseDuration) {
            self.soundPlayer.playVibrateSound()
        }
    }

    private func setAudioSession(category: String,
                                 mode: String? = nil,
                                 options: AVAudioSessionCategoryOptions = AVAudioSessionCategoryOptions(rawValue: 0)) {
        do {
            if #available(iOS 10.0, *), let mode = mode {
                try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
                Logger.debug("\(self.TAG) set category: \(category) mode: \(mode) options: \(options)")
            } else {
                try AVAudioSession.sharedInstance().setCategory(category, with: options)
                Logger.debug("\(self.TAG) set category: \(category) options: \(options)")
            }
        } catch {
            let message = "\(self.TAG) in \(#function) failed to set category: \(category) with error: \(error)"
            assertionFailure(message)
            Logger.error(message)
        }
    }
}
