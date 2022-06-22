// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import AVFoundation
import SignalCoreKit
import SessionUtilitiesKit

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
        Environment.shared?.audioSession.ensureAudioSessionActivationStateAfterDelay()
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
            Environment.shared?.proximityMonitoringManager.add(lifetime: self)
        } else {
            Environment.shared?.proximityMonitoringManager.remove(lifetime: self)
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
        // FIXME: The code below was causing a bug, and disabling it * seems * fine. Don't feel super confident about it though...
        /*
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.ensureAudioSessionActivationState()
        }
         */
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
}
