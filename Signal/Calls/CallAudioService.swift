//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import AVKit
import SignalRingRTC
import SignalServiceKit
import SignalUI

protocol CallAudioServiceDelegate: AnyObject {
    @MainActor func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService)
    @MainActor func callAudioServiceDidChangeAudioSource(_ callAudioService: CallAudioService, audioSource: AudioSource?)
}

class CallAudioService: IndividualCallObserver, GroupCallObserver {

    weak var delegate: CallAudioServiceDelegate? {
        willSet {
            assert(newValue == nil || delegate == nil)
        }
    }

    // Track whether the speaker should be enabled or not.
    private(set) var isSpeakerEnabled = false

    private var observers = [NSObjectProtocol]()

    private var avAudioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }

    // MARK: - Initializers

    init(audioSession: AudioSession) {
        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings

        // Configure audio session so we don't prompt user with Record permission until call is connected.

        audioSession.configureRTCAudio()
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: avAudioSession, queue: nil) { [weak self] _ in
            self?.audioRouteDidChange()
        })
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - CallObserver

    func individualCallStateDidChange(_ call: IndividualCall, state: CallState) {
        AssertIsOnMainThread()
        handleState(call: call)
    }

    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {
        AssertIsOnMainThread()

        ensureProperAudioSession(call: call)
    }

    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {
        ensureProperAudioSession(call: call)
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        stopPlayingAnySounds()
        ensureProperAudioSession(call: call)
    }

    private var oldRaisedHands: [UInt32] = []
    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        if oldRaisedHands.isEmpty && !raisedHands.isEmpty {
            self.playRaiseHandSound()
        }
        oldRaisedHands = raisedHands
    }

    private let routePicker = AVRoutePickerView()

    @discardableResult
    public func presentRoutePicker() -> Bool {
        guard let routeButton = routePicker.subviews.first(where: { $0 is UIButton }) as? UIButton else {
            owsFailDebug("Failed to find subview to present route picker, falling back to old system")
            return false
        }

        routeButton.sendActions(for: .touchUpInside)

        return true
    }

    public func requestSpeakerphone(isEnabled: Bool) {
        // Save the enablement state. The AudioSession will be configured the
        // next time that the ensureProperAudioSession() is triggered.
        self.isSpeakerEnabled = isEnabled
    }

    @MainActor
    private func requestSpeakerphone(call: GroupCall, isEnabled: Bool) {
        // If toggled for an group call, save the enablement state and
        // update the AudioSession.
        self.isSpeakerEnabled = isEnabled
        self.ensureProperAudioSession(call: call)
    }

    @MainActor
    private func requestSpeakerphone(call: IndividualCall, isEnabled: Bool) {
        // If toggled for an individual call, save the enablement state and
        // update the AudioSession.
        self.isSpeakerEnabled = isEnabled
        self.ensureProperAudioSession(call: call)
    }

    @MainActor
    public func requestSpeakerphone(call: SignalCall, isEnabled: Bool) {
        switch call.mode {
        case .individual(let individualCall):
            requestSpeakerphone(call: individualCall, isEnabled: isEnabled)
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            requestSpeakerphone(call: call, isEnabled: isEnabled)
        }
    }

    private func audioRouteDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let currentAudioSource = self.currentAudioSource else {
                Logger.warn("Switched to route without audio source")
                return
            }
            self.delegate?.callAudioServiceDidChangeAudioSource(self, audioSource: currentAudioSource)
        }
    }

    @MainActor
    private func ensureProperAudioSession(call: SignalCall) {
        switch call.mode {
        case .individual(let call):
            ensureProperAudioSession(call: call)
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            ensureProperAudioSession(call: call)
        }
    }

    @MainActor
    private func ensureProperAudioSession(call: GroupCall) {
        guard call.ringRtcCall.localDeviceState.joinState != .notJoined else {
            // Revert to ambient audio.
            setAudioSession(category: .ambient, mode: .default)
            return
        }

        if !call.ringRtcCall.isOutgoingVideoMuted || self.isSpeakerEnabled {
            // The user is capturing video or wants to use the speaker for an
            // audio call, so choose the VideoChat mode, which enables the speaker
            // with the proximity sensor disabled.
            setAudioSession(category: .playAndRecord, mode: .videoChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        } else {
            // The user is not capturing video and doesn't want to use the speaker
            // for an audio call, so choose VoiceChat mode, which uses the receiver
            // with the proximity sensor enabled.
            setAudioSession(category: .playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        }
    }

    /// Set the AudioSession based on the state of the call. If video is captured locally,
    /// it is assumed that the speaker should be used. Otherwise audio will be routed
    /// through the receiver, or speaker if enabled.
    @MainActor
    private func ensureProperAudioSession(call: IndividualCall) {
        guard !call.isEnded, call.state != .answering else {
            // Revert to ambient audio.
            setAudioSession(category: .ambient, mode: .default)
            return
        }

        if [.localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting].contains(call.state) {
            // Set the AudioSession for playing a ring tone.
            setAudioSession(category: .playback, mode: .default)
        } else if call.hasLocalVideo || self.isSpeakerEnabled {
            if call.state == .dialing || call.state == .remoteRinging {
                // Set the AudioSession for playing a ringback tone through the
                // speaker with the proximity sensor disabled.
                setAudioSession(category: .playback, mode: .default)
            } else {
                // The user is capturing video or wants to use the speaker for an
                // audio call, so choose the VideoChat mode, which enables the speaker
                // with the proximity sensor disabled.
                setAudioSession(category: .playAndRecord, mode: .videoChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            }
        } else {
            // The user is not capturing video and doesn't want to use the speaker
            // for an audio call, so choose VoiceChat mode, which uses the receiver
            // with the proximity sensor enabled.
            setAudioSession(category: .playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        }
    }

    // MARK: - Service action handlers

    @MainActor
    private func handleState(call: IndividualCall) {
        Logger.verbose("new state: \(call.state)")

        // Stop playing sounds while switching audio session so we don't 
        // get any blips across a temporary unintended route.
        stopPlayingAnySounds()
        self.ensureProperAudioSession(call: call)

        switch call.state {
        case .dialing:
            handleDialing(call: call)

        case .remoteRinging:
            handleRemoteRinging(call: call)

        case .remoteHangup, .remoteHangupNeedPermission:
            vibrate()
            fallthrough
        case .localFailure, .localHangup:
            play(sound: .callEnded)
            handleCallEnded(call: call)

        case .remoteBusy:
            handleBusy(call: call)

        case .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            handleAnsweredElsewhere(call: call)

        case .idle, .answering, .connected, .reconnecting, .localRinging_Anticipatory, .localRinging_ReadyToAnswer, .accepting:
            break
        }
    }

    private func handleDialing(call: IndividualCall) {
        AssertIsOnMainThread()

        // HACK: Without this async, dialing sound only plays once. I don't really understand why. Does the audioSession
        // need some time to settle? Is something else interrupting our session?
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
            self.play(sound: .callConnecting)
        }
    }

    private func handleRemoteRinging(call: IndividualCall) {
        AssertIsOnMainThread()

        self.play(sound: .callOutboundRinging)
    }

    private func handleBusy(call: IndividualCall) {
        AssertIsOnMainThread()

        play(sound: .callBusy)

        // Let the busy sound play for 4 seconds. The full file is longer than necessary
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 4.0) {
            self.handleCallEnded(call: call)
        }
    }

    @MainActor
    private func handleAnsweredElsewhere(call: IndividualCall) {
        play(sound: .callEnded)
        handleCallEnded(call: call)
    }

    @MainActor
    private func handleCallEnded(call: IndividualCall) {
        // Sometimes (usually but not always) upon ending a call, the currentPlayer does not get
        // played to completion. This is necessary in order for the players
        // audioActivity to remove itself from AudioSession. Otherwise future AudioActivities,
        // like recording a voice note, will be prevented from having their needs met.
        //
        // Furthermore, no interruption delegate is called nor AVAudioSessionInterruptionNotification
        // is posted. I'm not sure why we have to do this.
        if let audioPlayer = currentPlayer {
            audioPlayer.stop()
        }

        setAudioSession(category: .ambient, mode: .default)
    }

    // MARK: Playing Sounds

    private var currentPlayer: AudioPlayer?

    private func stopPlayingAnySounds() {
        currentPlayer?.stop()
    }

    private func prepareToPlay(sound: StandardSound) -> AudioPlayer? {
        guard let newPlayer = Sounds.audioPlayer(forSound: .standard(sound), audioBehavior: .call) else {
            owsFailDebug("unable to build player for sound: \(sound.displayName)")
            return nil
        }
        Logger.info("playing sound: \(sound.displayName)")

        // It's important to stop the current player **before** starting the new player. In the case that
        // we're playing the same sound, since the player is memoized on the sound instance, we'd otherwise
        // stop the sound we just started.
        self.currentPlayer?.stop()
        self.currentPlayer = newPlayer

        return newPlayer
    }

    private func play(sound: StandardSound) {
        guard let newPlayer = prepareToPlay(sound: sound) else { return }
        newPlayer.play()
    }

    func vibrate() {
        // TODO implement HapticAdapter for iPhone7 and up
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    // MARK: - AudioSession MGMT
    // TODO move this to CallAudioSession?

    // Note this method is sensitive to the current audio session configuration.
    // Specifically if you call it while speakerphone is enabled you won't see 
    // any connected bluetooth routes.
    var availableInputs: [AudioSource] {
        guard let availableInputs = avAudioSession.availableInputs else {
            // I'm not sure why this would happen, but it may indicate an error.
            owsFailDebug("No available inputs or inputs not ready")
            return [AudioSource.builtInSpeaker]
        }

        Logger.info("availableInputs: \(availableInputs.map(\.logSafeDescription))")
        return [AudioSource.builtInSpeaker] + availableInputs.map { portDescription in
            return AudioSource(portDescription: portDescription)
        }
    }

    var hasExternalInputs: Bool { return availableInputs.count > 2 }

    var currentAudioSource: AudioSource? {
        let outputsByType = avAudioSession.currentRoute.outputs.reduce(
            into: [AVAudioSession.Port: AVAudioSessionPortDescription]()
        ) { result, portDescription in
            result[portDescription.portType] = portDescription
        }

        let inputsByType = avAudioSession.currentRoute.inputs.reduce(
            into: [AVAudioSession.Port: AVAudioSessionPortDescription]()
        ) { result, portDescription in
            result[portDescription.portType] = portDescription
        }

        if let builtInMic = inputsByType[.builtInMic], inputsByType[.builtInReceiver] != nil {
            return AudioSource(portDescription: builtInMic)
        } else if outputsByType[.builtInSpeaker] != nil {
            return AudioSource.builtInSpeaker
        } else if let firstRemaining = inputsByType.values.first {
            return AudioSource(portDescription: firstRemaining)
        } else {
            return nil
        }
    }

    // The default option upon entry is always .mixWithOthers, so we will set that
    // as our default value if no options are provided.
    @MainActor
    private func setAudioSession(category: AVAudioSession.Category,
                                 mode: AVAudioSession.Mode,
                                 options: AVAudioSession.CategoryOptions = AVAudioSession.CategoryOptions.mixWithOthers) {
        var audioSessionChanged = false
        do {
            let oldCategory = avAudioSession.category
            let oldMode = avAudioSession.mode
            let oldOptions = avAudioSession.categoryOptions

            guard oldCategory != category || oldMode != mode || oldOptions != options else {
                return
            }

            audioSessionChanged = true

            if oldCategory != category {
                Logger.debug("audio session changed category: \(oldCategory) -> \(category) ")
            }
            if oldMode != mode {
                Logger.debug("audio session changed mode: \(oldMode) -> \(mode) ")
            }
            if oldOptions != options {
                Logger.debug("audio session changed options: \(oldOptions) -> \(options) ")
            }
            try avAudioSession.setCategory(category, mode: mode, options: options)
        } catch {
            let message = "failed to set category: \(category), mode: \(mode), options: \(options) with error: \(error)"
            owsFailDebug(message)
        }

        if audioSessionChanged {
            Logger.info("audio session changed category: \(category), mode: \(mode), options: \(options)")
            self.delegate?.callAudioServiceDidChangeAudioSession(self)
        }
    }

    // MARK: - Manual sounds played for group calls

    func playOutboundRing() {
        play(sound: .callOutboundRinging)
    }

    func playJoinSound() {
        play(sound: .groupCallJoin)
    }

    func playLeaveSound() {
        play(sound: .groupCallLeave)
    }

    private func playRaiseHandSound() {
        play(sound: .raisedHand)
    }
}

extension CallAudioService: CallServiceStateObserver {
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        if currentPlayer?.isLooping == true {
            stopPlayingAnySounds()
        } else {
            // Let non-looping sounds play to completion.
        }
        switch oldValue?.mode {
        case nil:
            break
        case .individual(let call):
            call.removeObserver(self)
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.removeObserver(self)
        }
        switch newValue?.mode {
        case nil:
            break
        case .individual(let call):
            call.addObserverAndSyncState(self)
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.addObserver(self, syncStateImmediately: true)
        }
    }
}
