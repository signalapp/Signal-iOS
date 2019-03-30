//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

@objc(OWSAudioActivity)
public class AudioActivity: NSObject {
    let audioDescription: String

    let behavior: OWSAudioBehavior

    @objc
    public init(audioDescription: String, behavior: OWSAudioBehavior) {
        self.audioDescription = audioDescription
        self.behavior = behavior
    }

    deinit {
        audioSession.ensureAudioSessionActivationStateAfterDelay()
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: 

    override public var description: String {
        return "<\(self.logTag) audioDescription: \"\(audioDescription)\">"
    }
}

@objc
public class OWSAudioSession: NSObject {

    @objc
    public func setup() {
        NotificationCenter.default.addObserver(self, selector: #selector(proximitySensorStateDidChange(notification:)), name: UIDevice.proximityStateDidChangeNotification, object: nil)
    }

    // MARK: Dependencies

    var proximityMonitoringManager: OWSProximityMonitoringManager {
        return Environment.shared.proximityMonitoringManager
    }

    private let avAudioSession = AVAudioSession.sharedInstance()

    private let device = UIDevice.current

    // MARK: 

    private var currentActivities: [Weak<AudioActivity>] = []
    var aggregateBehaviors: Set<OWSAudioBehavior> {
        return Set(self.currentActivities.compactMap { $0.value?.behavior })
    }

    @objc
    public func startAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        Logger.debug("with \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        self.currentActivities.append(Weak(value: audioActivity))

        do {
            try ensureAudioCategory()
            return true
        } catch {
            owsFailDebug("failed with error: \(error)")
            return false
        }
    }

    @objc
    public func endAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("with audioActivity: \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        currentActivities = currentActivities.filter { return $0.value != audioActivity }
        do {
            try ensureAudioCategory()
        } catch {
            owsFailDebug("error in ensureAudioCategory: \(error)")
        }
    }

    func ensureAudioCategory() throws {
        if aggregateBehaviors.contains(.audioMessagePlayback) {
            self.proximityMonitoringManager.add(lifetime: self)
        } else {
            self.proximityMonitoringManager.remove(lifetime: self)
        }

        if aggregateBehaviors.contains(.call) {
            // Do nothing while on a call.
            // WebRTC/CallAudioService manages call audio
            // Eventually it would be nice to consolidate more of the audio
            // session handling.
        } else if aggregateBehaviors.contains(.playAndRecord) {
            assert(avAudioSession.recordPermission == .granted)
            try avAudioSession.setCategory(.record)
        } else if aggregateBehaviors.contains(.audioMessagePlayback) {
            if self.device.proximityState {
                Logger.debug("proximityState: true")

                try avAudioSession.setCategory(.playAndRecord)
                try avAudioSession.overrideOutputAudioPort(.none)
            } else {
                Logger.debug("proximityState: false")
                try avAudioSession.setCategory(.playback)
            }
        } else if aggregateBehaviors.contains(.playback) {
            try avAudioSession.setCategory(.playback)
        } else {
            ensureAudioSessionActivationStateAfterDelay()
        }
    }

    @objc
    func proximitySensorStateDidChange(notification: Notification) {
        do {
            try ensureAudioCategory()
        } catch {
            owsFailDebug("error in response to proximity change: \(error)")
        }
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
            try avAudioSession.setActive(false, options: [.notifyOthersOnDeactivation])
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
