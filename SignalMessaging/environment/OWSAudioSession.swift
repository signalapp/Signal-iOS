//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import WebRTC

public struct AudioActivityOptions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let playback = AudioActivityOptions(rawValue: 1 << 0)
    public static let record = AudioActivityOptions(rawValue: 1 << 1)
    public static let proximitySwitchesToEarPiece = AudioActivityOptions(rawValue: 1 << 2)
}

@objc
public class AudioActivity: NSObject {
    let audioDescription: String

    let options: AudioActivityOptions

    @objc
    public init(audioDescription: String) {
        self.audioDescription = audioDescription
        self.options = []
    }

    public init(audioDescription: String, options: AudioActivityOptions) {
        self.audioDescription = audioDescription
        self.options = options
    }

    deinit {
        audioSession.ensureAudioSessionActivationStateAfterDelay()
    }

    // MARK: Dependencies

    var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    // MARK: Factory Methods

    @objc
    public class func playbackActivity(audioDescription: String) -> AudioActivity {
        return AudioActivity(audioDescription: audioDescription, options: .playback)
    }

    @objc
    public class func recordActivity(audioDescription: String) -> AudioActivity {
        return AudioActivity(audioDescription: audioDescription, options: .record)
    }

    @objc
    public class func voiceNoteActivity(audioDescription: String) -> AudioActivity {
        return AudioActivity(audioDescription: audioDescription, options: [.playback, .proximitySwitchesToEarPiece])
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
        NotificationCenter.default.addObserver(self, selector: #selector(proximitySensorStateDidChange(notification:)), name: .UIDeviceProximityStateDidChange, object: nil)
    }

    // MARK: Dependencies

    private let avAudioSession = AVAudioSession.sharedInstance()

    private let device = UIDevice.current

    // MARK: 

    private var currentActivities: [Weak<AudioActivity>] = []
    var aggregateOptions: AudioActivityOptions {
        return  AudioActivityOptions(self.currentActivities.compactMap { $0.value?.options })
    }

    @objc
    public func startAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        Logger.debug("with \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        self.currentActivities.append(Weak(value: audioActivity))

        do {
            if aggregateOptions.contains(.record) {
                assert(avAudioSession.recordPermission() == .granted)
                try avAudioSession.setCategory(AVAudioSessionCategoryRecord)
            } else if aggregateOptions.contains(.playback) {
                try avAudioSession.setCategory(AVAudioSessionCategoryPlayback)
            } else {
                Logger.debug("no category option specified. Leaving category untouched.")
            }

            if aggregateOptions.contains(.proximitySwitchesToEarPiece) {
                self.device.isProximityMonitoringEnabled = true
                self.shouldAdjustAudioForProximity = true
            } else {
                self.device.isProximityMonitoringEnabled = false
                self.shouldAdjustAudioForProximity = false
            }
            ensureProximityState()

            return true
        } catch {
            owsFailDebug("failed with error: \(error)")
            return false
        }

    }

    var shouldAdjustAudioForProximity: Bool = false
    func proximitySensorStateDidChange(notification: Notification) {
        if shouldAdjustAudioForProximity {
            ensureProximityState()
        }
    }

    // TODO: externally modified proximityState monitoring e.g. CallViewController
    // TODO: make sure we *undo* anything as appropriate if there are concurrent audio activities
    func ensureProximityState() {
        if self.device.proximityState {
            Logger.debug("proximityState: true")

            try! self.avAudioSession.overrideOutputAudioPort(.none)
        } else {
            Logger.debug("proximityState: false")
            do {
                try self.avAudioSession.overrideOutputAudioPort(.speaker)
            } catch {
                Logger.error("error: \(error)")
            }
        }
    }

    @objc
    public func endAudioActivity(_ audioActivity: AudioActivity) {
        Logger.debug("with audioActivity: \(audioActivity)")

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        currentActivities = currentActivities.filter { return $0.value != audioActivity }

        if aggregateOptions.contains(.proximitySwitchesToEarPiece) {
            self.device.isProximityMonitoringEnabled = true
            self.shouldAdjustAudioForProximity = true
        } else {
            self.device.isProximityMonitoringEnabled = false
            self.shouldAdjustAudioForProximity = false
        }
        ensureProximityState()

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
