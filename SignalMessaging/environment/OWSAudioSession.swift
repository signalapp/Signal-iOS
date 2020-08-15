//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

@objc(OWSAudioActivity)
public class AudioActivity: NSObject {
    let audioDescription: String

    let behavior: OWSAudioBehavior

    @objc public var supportsBackgroundPlayback: Bool {
        // Currently, only audio messages support background playback
        return [.audioMessagePlayback, .call].contains(behavior)
    }

    @objc public var backgroundPlaybackName: String? {
        switch behavior {
        case .audioMessagePlayback:
            return NSLocalizedString("AUDIO_ACTIVITY_PLAYBACK_NAME_AUDIO_MESSAGE",
                                     comment: "A string indicating that an audio message is playing.")
        case .call:
            return nil
        default:
            owsFailDebug("unexpectedly fetched background name for type that doesn't support background playback")
            return nil
        }
    }

    @objc
    public init(audioDescription: String, behavior: OWSAudioBehavior) {
        self.audioDescription = audioDescription
        self.behavior = behavior
    }

    deinit {
        audioSession.ensureAudioState()
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: 

    override public var description: String {
        return "<AudioActivity: \"\(audioDescription)\">"
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

    public private(set) var currentActivities: [Weak<AudioActivity>] = []
    var aggregateBehaviors: Set<OWSAudioBehavior> {
        return Set(self.currentActivities.compactMap { $0.value?.behavior })
    }

    @objc
    public var wantsBackgroundPlayback: Bool {
        return currentActivities.lazy.compactMap { $0.value?.supportsBackgroundPlayback }.contains(true)
    }

    @objc
    public func startAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        Logger.debug("with \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        self.currentActivities.append(Weak(value: audioActivity))

        do {
            try reconcileAudioCategory()
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
            try reconcileAudioCategory()
        } catch {
            owsFailDebug("error in reconcileAudioCategory: \(error)")
        }
    }

    @objc
    public func ensureAudioState() {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        do {
            try reconcileAudioCategory()
        } catch {
            owsFailDebug("error in ensureAudioState: \(error)")
        }
    }

    @objc
    func proximitySensorStateDidChange(notification: Notification) {
        ensureAudioState()
    }

    private func reconcileAudioCategory() throws {
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
            if avAudioSession.category != AVAudioSession.Category.soloAmbient {
                Logger.debug("reverting to default audio category: soloAmbient")
                try avAudioSession.setCategory(.soloAmbient)
            }

            ensureAudioSessionActivationState()
        }
    }

    func ensureAudioSessionActivationState(remainingRetries: UInt = 3) {
        guard remainingRetries > 0 else {
            owsFailDebug("ensureAudioSessionActivationState has no remaining retries")
            return
        }

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
        } catch let error as NSError {
            if error.code == AVAudioSession.ErrorCode.isBusy.rawValue {
                // Occasionally when trying to deactivate the audio session, we get a "busy" error.
                // In that case we should retry after a delay.
                //
                // Error Domain=NSOSStatusErrorDomain Code=560030580 “The operation couldn’t be completed. (OSStatus error 560030580.)”
                // aka "AVAudioSessionErrorCodeIsBusy"
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.ensureAudioSessionActivationState(remainingRetries: remainingRetries - 1)
                }
                return
            } else {
                owsFailDebug("failed with error: \(error)")
            }
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

extension OWSAudioBehavior: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "OWSAudioBehavior.unknown"
        case .playback:
            return "OWSAudioBehavior.playback"
        case .audioMessagePlayback:
            return "OWSAudioBehavior.audioMessagePlayback"
        case .playAndRecord:
            return "OWSAudioBehavior.playAndRecord"
        case .call:
            return "OWSAudioBehavior.call"
        @unknown default:
            owsFailDebug("")
            return "OWSAudioBehavior.unknown default"
        }
    }
}
