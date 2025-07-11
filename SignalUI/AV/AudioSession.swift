//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation
public import SignalServiceKit

public class AudioActivity: NSObject {
    let audioDescription: String

    let behavior: AudioBehavior

    public var requiresRecordingPermissions: Bool {
        switch behavior {
        case .playAndRecord, .call:
            return true
        case .playback, .playbackMixWithOthers, .audioMessagePlayback, .unknown:
            return false
        }
    }

    public var supportsBackgroundPlayback: Bool {
        // Currently, only audio messages and calls support background playback
        switch behavior {
        case .audioMessagePlayback, .call:
            return true
        case .playback, .playbackMixWithOthers, .playAndRecord, .unknown:
            return false
        }
    }

    public var backgroundPlaybackName: String? {
        switch behavior {
        case .audioMessagePlayback:
            return OWSLocalizedString("AUDIO_ACTIVITY_PLAYBACK_NAME_AUDIO_MESSAGE",
                                     comment: "A string indicating that an audio message is playing.")
        case .call:
            return nil

        default:
            owsFailDebug("unexpectedly fetched background name for type that doesn't support background playback")
            return nil
        }
    }

    public init(audioDescription: String, behavior: AudioBehavior) {
        self.audioDescription = audioDescription
        self.behavior = behavior
    }

    deinit {
        SUIEnvironment.shared.audioSessionRef.ensureAudioState()
    }

    override public var description: String {
        return "<AudioActivity: \"\(audioDescription)\">"
    }
}

public class AudioSession: NSObject {

    private let avAudioSession = AVAudioSession.sharedInstance()

    private let device = UIDevice.current

    public override init() {
        super.init()
    }

    public func performInitialSetup(appReadiness: AppReadiness) {
        if CurrentAppContext().isMainApp {
            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                self.setup()
            }
        }
    }

    private func setup() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximitySensorStateDidChange(notification:)),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil)

        ensureAudioState()
    }

    // MARK: -

    public private(set) var currentActivities: [Weak<AudioActivity>] = []
    var aggregateBehaviors: Set<AudioBehavior> {
        return Set(self.currentActivities.compactMap { $0.value?.behavior })
    }

    public var wantsBackgroundPlayback: Bool {
        return currentActivities.lazy.compactMap { $0.value?.supportsBackgroundPlayback }.contains(true)
    }

    public var outputVolume: Float {
        return avAudioSession.outputVolume
    }

    private let unfairLock = UnfairLock()

    public func startAudioActivity(_ audioActivity: AudioActivity) -> Bool {
        unfairLock.lock()
        defer { unfairLock.unlock() }

        if
            audioActivity.requiresRecordingPermissions,
            avAudioSession.recordPermission != .granted
        {
            Logger.warn("Attempting to start audio activity that requires recording permissions, but they are not granted!")
            return false
        }

        self.currentActivities.append(Weak(value: audioActivity))

        do {
            try reconcileAudioCategory()
            return true
        } catch {
            owsFailDebug("failed with error: \(error)")
            return false
        }
    }

    public func endAudioActivity(_ audioActivity: AudioActivity) {
        unfairLock.lock()
        defer { unfairLock.unlock() }

        currentActivities = currentActivities.filter { return $0.value != audioActivity }
        do {
            try reconcileAudioCategory()
        } catch {
            owsFailDebug("error in reconcileAudioCategory: \(error)")
        }
    }

    public func ensureAudioState() {
        unfairLock.lock()
        defer { unfairLock.unlock() }
        do {
            try reconcileAudioCategory()
        } catch {
            owsFailDebug("error in ensureAudioState: \(error)")
        }
    }

    @objc
    private func proximitySensorStateDidChange(notification: Notification) {
        ensureAudioState()
    }

    private func reconcileAudioCategory() throws {
        if aggregateBehaviors.contains(.audioMessagePlayback) {
            SSKEnvironment.shared.proximityMonitoringManagerRef.add(lifetime: self)
        } else {
            SSKEnvironment.shared.proximityMonitoringManagerRef.remove(lifetime: self)
        }

        if aggregateBehaviors.contains(.call) {
            // Do nothing while on a call.
            // WebRTC/CallAudioService manages call audio
            // Eventually it would be nice to consolidate more of the audio
            // session handling.
        } else if aggregateBehaviors.contains(.playAndRecord) {
            assert(avAudioSession.recordPermission == .granted)
            try setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP
                ]
            )
            try avAudioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } else if aggregateBehaviors.contains(.audioMessagePlayback) {
            if self.device.proximityState {
                try setCategory(.playAndRecord)
                try avAudioSession.overrideOutputAudioPort(.none)
            } else {
                try setCategory(.playback)
            }
        } else if aggregateBehaviors.contains(.playback) {
            try setCategory(.playback)
        } else if aggregateBehaviors.contains(.playbackMixWithOthers) {
            try setCategory(.playback, options: .mixWithOthers)
        } else {
            if avAudioSession.category != AVAudioSession.Category.ambient {
                try setCategory(.ambient)
            }

            ensureAudioSessionActivationState()
        }
    }

    private func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode? = nil,
        options: AVAudioSession.CategoryOptions = []
    ) throws {
        guard
            avAudioSession.category != category
            || (avAudioSession.mode != (mode ?? .default))
            || (avAudioSession.categoryOptions != options)
        else {
            return
        }
        if let mode = mode, !options.isEmpty {
            try avAudioSession.setCategory(category, mode: mode, options: options)
        } else if let mode = mode {
            try avAudioSession.setCategory(category, mode: mode)
        } else if !options.isEmpty {
            try avAudioSession.setCategory(category, options: options)
        } else {
            try avAudioSession.setCategory(category)
        }
    }

    private func ensureAudioSessionActivationState(remainingRetries: UInt = 3) {
        guard remainingRetries > 0 else {
            owsFailDebug("ensureAudioSessionActivationState has no remaining retries")
            return
        }

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
                    // We've dispatched asynchronously, have to re-acquire the lock.
                    self.unfairLock.lock()
                    defer { self.unfairLock.unlock() }
                    self.ensureAudioSessionActivationState(remainingRetries: remainingRetries - 1)
                }
                return
            } else {
                owsFailDebug("failed with error: \(error)")
            }
        }
    }
}

extension AVAudioSession.CategoryOptions {
    #if !canImport(AVFoundation, _version: 2360.61.4.11)
    public static let allowBluetoothHFP = Self.allowBluetooth
    #endif
}

extension AudioBehavior: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "OWSAudioBehavior.unknown"
        case .playback:
            return "OWSAudioBehavior.playback"
        case .playbackMixWithOthers:
            return "OWSAudioBehavior.playbackMixWithOthers"
        case .audioMessagePlayback:
            return "OWSAudioBehavior.audioMessagePlayback"
        case .playAndRecord:
            return "OWSAudioBehavior.playAndRecord"
        case .call:
            return "OWSAudioBehavior.call"
        }
    }
}
