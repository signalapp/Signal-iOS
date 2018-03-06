//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

@objc
public class AudioActivity: NSObject {
    let audioDescription: String

    override public var description: String {
        return "<\(self.logTag) audioDescription: \"\(audioDescription)\">"
    }

    public
    init(audioDescription: String) {
        self.audioDescription = audioDescription
    }

    deinit {
        OWSAudioSession.shared.ensureAudioSessionActivationState()
    }
}

@objc
public class OWSAudioSession: NSObject {

    // Force singleton access
    public static let shared = OWSAudioSession()
    private override init() {}
    private let avAudioSession = AVAudioSession.sharedInstance()

    private var currentActivities: [Weak<AudioActivity>] = []

    // Respects hardware mute switch, plays through external speaker, mixes with backround audio
    // appropriate for foreground sound effects.
    public func startAmbientAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("\(logTag) in \(#function)")

        startAudioActivity(audioActivity)

        guard currentActivities.count == 1 else {
            // We don't want to clobber the audio capabilities configured by (e.g.) media playback or an in-progress call
            Logger.info("\(logTag) in \(#function) not touching audio session since another currentActivity exists.")
            return
        }

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryAmbient)
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
        }
    }

    // Ignores hardware mute switch, plays through external speaker
    public func startPlaybackAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("\(logTag) in \(#function)")

        startAudioActivity(audioActivity)

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryPlayback)
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
        }
    }

    public func startRecordingAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        Logger.debug("\(logTag) in \(#function)")

        assert(avAudioSession.recordPermission() == .granted)

        startAudioActivity(audioActivity)

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryRecord)
            return true
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
            return false
        }
    }

    public func startAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("\(logTag) in \(#function) with \(audioActivity)")

        self.currentActivities.append(Weak(value: audioActivity))
    }

    public func endAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("\(logTag) in \(#function) with audioActivity: \(audioActivity)")

        currentActivities = currentActivities.filter { return $0.value != audioActivity }
        ensureAudioSessionActivationState()
    }

    fileprivate func ensureAudioSessionActivationState() {
        // Cull any stale activities
        currentActivities = currentActivities.flatMap { oldActivity in
            guard oldActivity.value != nil else {
                // Normally we should be explicitly stopping an audio activity, but this allows
                // for recovery if the owner of the AudioAcivity was GC'd without ending it's
                // audio activity
                Logger.warn("\(logTag) an old activity has been gc'd")
                return nil
            }

            // return any still-active activities
            return oldActivity
        }

        guard currentActivities.count == 0 else {
            Logger.debug("\(logTag) not deactivating due to currentActivities: \(currentActivities)")
            return
        }

        do {
            // When playing audio in Signal, other apps audio (e.g. Music) is paused.
            // By notifying when we deactivate, the other app can resume playback.
            try avAudioSession.setActive(false, with: [.notifyOthersOnDeactivation])
        } catch {
            owsFail("\(logTag) in \(#function) failed with error: \(error)")
        }
    }

    // MARK: - WebRTC Audio

    /**
     * By default WebRTC starts the audio session (PlayAndRecord) immediately upon creating the peer connection
     * but we want to create the peer connection and set up all the signaling channels before we prompt the user
     * for an incoming call. Without manually handling the session, this would result in the user seeing a recording
     * permission requested (and recording banner) before they even know they have an incoming call.
     *
     * By using the `useManualAudio` and `isAudioEnabled` attributes of the RTCAudioSession we can delay recording until
     * it makes sense.
     */

    /**
     * The private class that manages AVAudioSession for WebRTC
     */
    private let rtcAudioSession = RTCAudioSession.sharedInstance()

    /**
     * This must be called before any audio tracks are added to the peerConnection, else we'll start recording before all
     * our signaling is set up.
     */
    public func configureRTCAudio() {
        Logger.info("\(logTag) in \(#function)")
        rtcAudioSession.useManualAudio = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to start/stop the recording audio session ourselves.
     * See header for details on  manual audio.
     */
    public var isRTCAudioEnabled: Bool {
        get {
            return rtcAudioSession.isAudioEnabled
        }
        set {
            rtcAudioSession.isAudioEnabled = newValue
        }
    }
}
