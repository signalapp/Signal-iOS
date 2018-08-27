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

    @objc
    public init(audioDescription: String) {
        self.audioDescription = audioDescription
    }

    deinit {
        OWSAudioSession.shared.ensureAudioSessionActivationStateAfterDelay()
    }
}

@objc
public class OWSAudioSession: NSObject {

    // Force singleton access
    @objc public static let shared = OWSAudioSession()
    private override init() {}
    private let avAudioSession = AVAudioSession.sharedInstance()

    private var currentActivities: [Weak<AudioActivity>] = []

    // Respects hardware mute switch, plays through external speaker, mixes with backround audio
    // appropriate for foreground sound effects.
    @objc
    public func startAmbientAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        startAudioActivity(audioActivity)
        guard currentActivities.count == 1 else {
            // We don't want to clobber the audio capabilities configured by (e.g.) media playback or an in-progress call
            Logger.info("not touching audio session since another currentActivity exists.")
            return
        }

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryAmbient)
        } catch {
            owsFailDebug("failed with error: \(error)")
        }
    }

    // Ignores hardware mute switch, plays through external speaker
    @objc
    public func startPlaybackAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        startAudioActivity(audioActivity)

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryPlayback)
        } catch {
            owsFailDebug("failed with error: \(error)")
        }
    }

    @objc
    public func startRecordingAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        Logger.debug("")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        assert(avAudioSession.recordPermission() == .granted)

        startAudioActivity(audioActivity)

        do {
            try avAudioSession.setCategory(AVAudioSessionCategoryRecord)
            return true
        } catch {
            owsFailDebug("failed with error: \(error)")
            return false
        }
    }

    @objc
    public func startAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("with \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        self.currentActivities.append(Weak(value: audioActivity))
    }

    @objc
    public func endAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("with audioActivity: \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        currentActivities = currentActivities.filter { return $0.value != audioActivity }
        ensureAudioSessionActivationStateAfterDelay()
    }

    fileprivate func ensureAudioSessionActivationStateAfterDelay() {
        // Without this delay, we sometimes error when deactivating the audio session with:
        //     Error Domain=NSOSStatusErrorDomain Code=560030580 “The operation couldn’t be completed. (OSStatus error 560030580.)”
        // aka "AVAudioSessionErrorCodeIsBusy"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.ensureAudioSessionActivationState()
        }
    }

    private func ensureAudioSessionActivationState() {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        // Cull any stale activities
        currentActivities = currentActivities.compactMap { oldActivity in
            guard oldActivity.value != nil else {
                // Normally we should be explicitly stopping an audio activity, but this allows
                // for recovery if the owner of the AudioAcivity was GC'd without ending it's
                // audio activity
                Logger.warn("an old activity has been gc'd")
                return nil
            }

            // return any still-active activities
            return oldActivity
        }

        guard currentActivities.isEmpty else {
            Logger.debug("not deactivating due to currentActivities: \(currentActivities)")
            return
        }

        do {
            // When playing audio in Signal, other apps audio (e.g. Music) is paused.
            // By notifying when we deactivate, the other app can resume playback.
            try avAudioSession.setActive(false, with: [.notifyOthersOnDeactivation])
        } catch {
            owsFailDebug("failed with error: \(error)")
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
    @objc
    public func configureRTCAudio() {
        Logger.info("")
        rtcAudioSession.useManualAudio = true
    }

    /**
     * Because we useManualAudio with our RTCAudioSession, we have to start/stop the recording audio session ourselves.
     * See header for details on  manual audio.
     */
    @objc
    public var isRTCAudioEnabled: Bool {
        get {
            return rtcAudioSession.isAudioEnabled
        }
        set {
            rtcAudioSession.isAudioEnabled = newValue
        }
    }
}
