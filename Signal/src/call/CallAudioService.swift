//
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class CallAudioService: NSObject {
    private let TAG = "[CallAudioService]"
    private var vibrateTimer: Timer?
    private let audioManager = AppAudioManager.sharedInstance()
    private let soundPlayer = JSQSystemSoundPlayer.shared()!

    enum SoundFilenames: String {
        case incomingRing = "r"
    }

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

        vibrateTimer = Timer.scheduledTimer(timeInterval: vibrateRepeatDuration, target: self, selector: #selector(ringVibration), userInfo: nil, repeats: true)

        // Stop other sounds and play ringer through external speaker
        setAudioSession(category: AVAudioSessionCategorySoloAmbient)
        soundPlayer.playSound(withFilename: SoundFilenames.incomingRing.rawValue, fileExtension: kJSQSystemSoundTypeCAF)
    }

    private func handleConnected() {
        Logger.debug("\(TAG) \(#function)")
        stopRinging()

        // disable start recording to transmit call audio.
        setAudioSession(category: AVAudioSessionCategoryPlayAndRecord)
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
        // TODO
//        let category = AVAudioSession.sharedInstance().getCategory()
//        if isSpeakerphoneEnabled {
//            AVAudioSession.sharedInstance().setCategory(category, option: AVAudioSessionCategoryOptionDefaultToSpeaker)
//        } else {
        // Will this disable speaker?
//            AVAudioSession.sharedInstance().setCategory(category)
//        }

        audioManager.toggleSpeakerPhone(isEnabled: isSpeakerphoneEnabled)
    }

    // MARK: Helpers

    private func stopRinging() {
        vibrateTimer?.invalidate()
        vibrateTimer = nil
        soundPlayer.stopSound(withFilename: SoundFilenames.incomingRing.rawValue)
        // Stop playing out of speaker
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

    private func setAudioSession(category: String, options: AVAudioSessionCategoryOptions) {
        do {
            try AVAudioSession.sharedInstance().setCategory(category, with: options)
            Logger.debug("\(self.TAG) set category: \(category) options: \(options)")
        } catch {
            let message = "\(self.TAG) in \(#function) failed to set category: \(category) with error: \(error)"
            assertionFailure(message)
            Logger.error(message)
        }
    }

    private func setAudioSession(category: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(category)
            Logger.debug("\(self.TAG) set category: \(category)")
        } catch {
            let message = "\(self.TAG) in \(#function) failed to set category: \(category) with error: \(error)"
            assertionFailure(message)
            Logger.error(message)
        }
    }
}
