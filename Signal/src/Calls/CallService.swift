//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC
import SignalMessaging

// All Observer methods will be invoked from the main thread.
@objc(OWSCallServiceObserver)
protocol CallServiceObserver: AnyObject {
    /**
     * Fired whenever the call changes.
     */
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?)
}

@objc
public final class CallService: LightweightCallManager {
    public typealias CallManagerType = CallManager<SignalCall, CallService>

    private var _callManager: CallManagerType! = nil
    public private(set) var callManager: CallManagerType {
        get { _callManager }
        set {
            if _callManager == nil {
                _callManager = newValue
            } else {
                owsFailDebug("Should only be set once")
            }
        }
    }

    public var callUIAdapter: CallUIAdapter!

    @objc
    public let individualCallService = IndividualCallService()
    let groupCallMessageHandler = GroupCallUpdateMessageHandler()
    let groupCallRemoteVideoManager = GroupCallRemoteVideoManager()

    lazy private(set) var audioService = CallAudioService()

    public var earlyRingNextIncomingCall = false

    /// Current call *must* be set on the main thread. It may be read off the main thread if the current call state must be consulted,
    /// but othere call state may race (observer state, sleep state, etc.)
    private var _currentCallLock = UnfairLock()
    private var _currentCall: SignalCall?
    @objc
    public private(set) var currentCall: SignalCall? {
        get {
            _currentCallLock.withLock {
                _currentCall
            }
        }
        set {
            AssertIsOnMainThread()

            let oldValue: SignalCall? = _currentCallLock.withLock {
                let oldValue = _currentCall
                _currentCall = newValue
                return oldValue
            }

            oldValue?.removeObserver(self)
            newValue?.addObserverAndSyncState(observer: self)

            updateIsVideoEnabled()

            // Prevent device from sleeping while we have an active call.
            if oldValue != newValue {
                if let oldValue = oldValue {
                    DeviceSleepManager.shared.removeBlock(blockObject: oldValue)
                    if !UIDevice.current.isIPad {
                        UIDevice.current.endGeneratingDeviceOrientationNotifications()
                    }
                }

                if let newValue = newValue {
                    assert(calls.contains(newValue))
                    DeviceSleepManager.shared.addBlock(blockObject: newValue)

                    if newValue.isIndividualCall {

                        // By default, individual calls should start out with speakerphone disabled.
                        self.audioService.requestSpeakerphone(isEnabled: false)

                        individualCallService.startCallTimer()
                    }

                    if !UIDevice.current.isIPad {
                        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                    }
                } else {
                    individualCallService.stopAnyCallTimer()
                }
            }

            // To be safe, we reset the early ring on any call change so it's not left set from an unexpected state change
            earlyRingNextIncomingCall = false

            Logger.debug("\(oldValue as Optional) -> \(newValue as Optional)")

            let observers = self.observers
            DispatchQueue.main.async {
                for observer in observers.elements {
                    observer.didUpdateCall(from: oldValue, to: newValue)
                }
            }
        }
    }

    /// True whenever CallService has any call in progress.
    /// The call may not yet be visible to the user if we are still in the middle of signaling.
    @objc
    public var hasCallInProgress: Bool {
        calls.count > 0
    }

    /// Track all calls that are currently "in play". Usually this is 1 or 0, but when dealing
    /// with a rapid succession of calls, it's possible to have multiple.
    ///
    /// For example, if the client receives two call offers, we hand them both off to RingRTC,
    /// which will let us know which one, if any, should become the "current call". But in the
    /// meanwhile, we still want to track that calls are in-play so we can prevent the user from
    /// placing an outgoing call.
    private let _calls = AtomicSet<SignalCall>()
    private var calls: Set<SignalCall> { _calls.allValues }

    private func addCall(_ call: SignalCall) {
        _calls.insert(call)
        postActiveCallsDidChange()
    }

    private func removeCall(_ call: SignalCall) -> Bool {
        let didRemove = _calls.remove(call)
        postActiveCallsDidChange()
        return didRemove
    }

    @objc
    public static let activeCallsDidChange = Notification.Name("activeCallsDidChange")

    private func postActiveCallsDidChange() {
        NotificationCenter.default.postNotificationNameAsync(Self.activeCallsDidChange, object: nil)
    }

    public override init() {
        super.init()
        callManager = CallManager(httpClient: httpClient)
        callManager.delegate = self
        SwiftSingletons.register(self)

        addObserverAndSyncState(observer: groupCallMessageHandler)
        addObserverAndSyncState(observer: groupCallRemoteVideoManager)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureBandwidthMode),
            name: Self.callServicePreferencesDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationChanged),
            name: .registrationStateDidChange,
            object: nil)

        // Note that we're not using the usual .owsReachabilityChanged
        // We want to update our bandwidth mode if the app has been backgrounded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureBandwidthMode),
            name: .reachabilityChanged,
            object: nil)

        // We don't support a rotating call screen on phones,
        // but we do still want to rotate the various icons.
        if !UIDevice.current.isIPad {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(phoneOrientationDidChange),
                                                   name: UIDevice.orientationDidChangeNotification,
                                                   object: nil)
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            SDSDatabaseStorage.shared.appendDatabaseChangeDelegate(self)
            if let localUuid = self.tsAccountManager.localUuid {
                self.callManager.setSelfUuid(localUuid)
            }
        }
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    @objc
    public func createCallUIAdapter() {
        AssertIsOnMainThread()

        if let call = callService.currentCall {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            callService.terminate(call: call)
        }

        self.callUIAdapter = CallUIAdapter()
    }

    // MARK: - Observers

    private var observers = WeakArray<CallServiceObserver>()

    @objc
    func addObserverAndSyncState(observer: CallServiceObserver) {
        addObserver(observer: observer, syncStateImmediately: true)
    }

    @objc
    func addObserver(observer: CallServiceObserver, syncStateImmediately: Bool) {
        AssertIsOnMainThread()

        observers.append(observer)

        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.didUpdateCall(from: nil, to: currentCall)
        }
    }

    // The observer-related methods should be invoked on the main thread.
    @objc
    func removeObserver(_ observer: CallServiceObserver) {
        AssertIsOnMainThread()
        observers.removeAll { $0 === observer }
    }

    // The observer-related methods should be invoked on the main thread.
    func removeAllObservers() {
        AssertIsOnMainThread()

        observers = []
    }

    // MARK: -

    /**
     * Local user toggled to mute audio.
     */
    func updateIsLocalAudioMuted(isLocalAudioMuted: Bool) {
        AssertIsOnMainThread()

        // Keep a reference to the call before permissions were requested...
        guard let call = currentCall else {
            owsFailDebug("missing currentCall")
            return
        }

        // If we're disabling the microphone, we don't need permission. Only need
        // permission to *enable* the microphone.
        guard !isLocalAudioMuted else {
            return updateIsLocalAudioMutedWithMicrophonePermission(call: call, isLocalAudioMuted: isLocalAudioMuted)
        }

        // This method can be initiated either from the CallViewController.videoButton or via CallKit
        // in either case we want to show the alert on the callViewWindow.
        guard let frontmostViewController =
                UIApplication.shared.findFrontmostViewController(ignoringAlerts: true,
                                                                 window: OWSWindowManager.shared.callViewWindow) else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            // Make sure the call is still valid (the one we asked permissions for).
            guard self.currentCall === call else {
                Logger.info("ignoring microphone permissions for obsolete call")
                return
            }

            guard granted else {
                return frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
            }

            // Success callback; microphone permissions are granted.
            self.updateIsLocalAudioMutedWithMicrophonePermission(call: call, isLocalAudioMuted: isLocalAudioMuted)
        }
    }

    private func updateIsLocalAudioMutedWithMicrophonePermission(call: SignalCall, isLocalAudioMuted: Bool) {
        AssertIsOnMainThread()

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        switch call.mode {
        case .group(let groupCall):
            groupCall.isOutgoingAudioMuted = isLocalAudioMuted
            call.groupCall(onLocalDeviceStateChanged: groupCall)
        case .individual(let individualCall):
            individualCall.isMuted = isLocalAudioMuted
            individualCallService.ensureAudioState(call: call)
        }
    }

    /**
     * Local user toggled video.
     */
    func updateIsLocalVideoMuted(isLocalVideoMuted: Bool) {
        AssertIsOnMainThread()

        // Keep a reference to the call before permissions were requested...
        guard let call = currentCall else {
            owsFailDebug("missing currentCall")
            return
        }

        // If we're disabling local video, we don't need permission. Only need
        // permission to *enable* video.
        guard !isLocalVideoMuted else {
            return updateIsLocalVideoMutedWithCameraPermissions(call: call, isLocalVideoMuted: isLocalVideoMuted)
        }

        // This method can be initiated either from the CallViewController.videoButton or via CallKit
        // in either case we want to show the alert on the callViewWindow.
        guard let frontmostViewController =
                UIApplication.shared.findFrontmostViewController(ignoringAlerts: true,
                                                                 window: OWSWindowManager.shared.callViewWindow) else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        frontmostViewController.ows_askForCameraPermissions { granted in
            // Make sure the call is still valid (the one we asked permissions for).
            guard self.currentCall === call else {
                Logger.info("ignoring camera permissions for obsolete call")
                return
            }

            if granted {
                // Success callback; camera permissions are granted.
                self.updateIsLocalVideoMutedWithCameraPermissions(call: call, isLocalVideoMuted: isLocalVideoMuted)
            }
        }
    }

    private func updateIsLocalVideoMutedWithCameraPermissions(call: SignalCall, isLocalVideoMuted: Bool) {
        AssertIsOnMainThread()

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        switch call.mode {
        case .group(let groupCall):
            groupCall.isOutgoingVideoMuted = isLocalVideoMuted
            call.groupCall(onLocalDeviceStateChanged: groupCall)
        case .individual(let individualCall):
            individualCall.hasLocalVideo = !isLocalVideoMuted
        }

        updateIsVideoEnabled()
    }

    func updateCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        call.videoCaptureController.switchCamera(isUsingFrontCamera: isUsingFrontCamera)
    }

    func cleanupStaleCall(_ staleCall: SignalCall, function: StaticString = #function, line: UInt = #line) {
        assert(staleCall !== currentCall)
        if let currentCall = currentCall {
            let error = OWSAssertionError("trying \(function):\(line) for call: \(staleCall) which is not currentCall: \(currentCall as Optional)")
            handleFailedCall(failedCall: staleCall, error: error)
        } else {
            Logger.info("ignoring \(function):\(line) for call: \(staleCall) since currentCall has ended.")
        }
    }

    @objc
    func configureBandwidthMode() {
        guard AppReadiness.isAppReady else { return }
        guard let currentCall = currentCall else { return }

        switch currentCall.mode {
        case let .group(call):
            let useLowBandwidth = Self.shouldUseLowBandwidthWithSneakyTransaction(for: call.localDeviceState.networkRoute)
            Logger.info("Configuring call for \(useLowBandwidth ? "low" : "standard") bandwidth")
            call.updateBandwidthMode(bandwidthMode: useLowBandwidth ? .low : .normal)
        case let .individual(call) where call.state == .connected:
            let useLowBandwidth = Self.shouldUseLowBandwidthWithSneakyTransaction(for: call.networkRoute)
            Logger.info("Configuring call for \(useLowBandwidth ? "low" : "standard") bandwidth")
            callManager.udpateBandwidthMode(bandwidthMode: useLowBandwidth ? .low : .normal)
        default:
            // Do nothing. We'll reapply the bandwidth mode once connected
            break
        }
    }

    static func shouldUseLowBandwidthWithSneakyTransaction(for networkRoute: NetworkRoute) -> Bool {
        let highBandwidthInterfaces = databaseStorage.read { readTx in
            Self.highBandwidthNetworkInterfaces(readTx: readTx)
        }
        if let allowsHighBandwidth = highBandwidthInterfaces.includes(networkRoute.localAdapterType) {
            return !allowsHighBandwidth
        }
        // If we aren't sure whether the current route's high-bandwidth, fall back to checking reachability.
        // This also handles the situation where WebRTC doesn't know what interface we're on,
        // which is always true on iOS 11.
        return !Self.reachabilityManager.isReachable(with: highBandwidthInterfaces)
    }

    // MARK: -

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall, error: Error) {
        AssertIsOnMainThread()
        Logger.debug("")

        let callError: SignalCall.CallError = {
            switch error {
            case let callError as SignalCall.CallError:
                return callError
            default:
                return SignalCall.CallError.externalError(underlyingError: error)
            }
        }()

        failedCall.error = callError

        if failedCall.isIndividualCall {
            individualCallService.handleFailedCall(failedCall: failedCall, error: callError, shouldResetUI: false, shouldResetRingRTC: true)
        }
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    func terminate(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call as Optional)")

        // If call is for the current call, clear it out first.
        if call === currentCall { currentCall = nil }

        if !removeCall(call) {
            owsFailDebug("unknown call: \(call)")
        }

        if !hasCallInProgress {
            audioSession.isRTCAudioEnabled = false
        }
        audioSession.endAudioActivity(call.audioActivity)

        switch call.mode {
        case .individual:
            break
        case .group(let groupCall):
            groupCall.leave()
            groupCall.disconnect()

            // Kick off a peek now that we've disconnected to get an updated participant state.
            if let thread = call.thread as? TSGroupThread {
                peekCallAndUpdateThread(thread)
            } else {
                owsFailDebug("Invalid thread type")
            }
        }
    }

    // MARK: - Video

    var shouldHaveLocalVideoTrack: Bool {
        AssertIsOnMainThread()

        guard let call = self.currentCall else {
            return false
        }

        // The iOS simulator doesn't provide any sort of camera capture
        // support or emulation (http://goo.gl/rHAnC1) so don't bother
        // trying to open a local stream.
        guard !Platform.isSimulator else { return false }
        guard UIApplication.shared.applicationState != .background else { return false }

        switch call.mode {
        case .individual(let individualCall):
            return individualCall.state == .connected && individualCall.hasLocalVideo
        case .group(let groupCall):
            return !groupCall.isOutgoingVideoMuted
        }
    }

    func updateIsVideoEnabled() {
        AssertIsOnMainThread()

        guard let call = self.currentCall else { return }

        switch call.mode {
        case .individual(let individualCall):
            if individualCall.state == .connected || individualCall.state == .reconnecting {
                callManager.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack, call: call)
            } else {
                // If we're not yet connected, just enable the camera but don't tell RingRTC
                // to start sending video. This allows us to show a "vanity" view while connecting.
                if !Platform.isSimulator && individualCall.hasLocalVideo {
                    call.videoCaptureController.startCapture()
                } else {
                    call.videoCaptureController.stopCapture()
                }
            }
        case .group(let groupCall):
            if !Platform.isSimulator && !groupCall.isOutgoingVideoMuted {
                call.videoCaptureController.startCapture()
            } else {
                call.videoCaptureController.stopCapture()
            }
        }
    }

    // MARK: -

    func buildAndConnectGroupCallIfPossible(thread: TSGroupThread) -> SignalCall? {
        AssertIsOnMainThread()
        guard !hasCallInProgress else { return nil }

        guard let call = SignalCall.groupCall(thread: thread) else { return nil }
        addCall(call)

        // By default, group calls should start out with speakerphone enabled.
        self.audioService.requestSpeakerphone(isEnabled: true)

        currentCall = call

        call.groupCall.isOutgoingAudioMuted = false
        call.groupCall.isOutgoingVideoMuted = false

        guard call.groupCall.connect() else {
            terminate(call: call)
            return nil
        }

        return call
    }

    func joinGroupCallIfNecessary(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)

        guard currentCall == nil || currentCall == call else {
            return owsFailDebug("A call is already in progress")
        }

        // The joined/joining call must always be the current call.
        currentCall = call

        // If we're not yet connected, connect now. This may happen if, for
        // example, the call ended unexpectedly.
        if call.groupCall.localDeviceState.connectionState == .notConnected {
            guard call.groupCall.connect() else {
                terminate(call: call)
                return
            }
        }

        // If we're not yet joined, join now. In general, it's unexpected that
        // this method would be called when you're already joined, but it is
        // safe to do so.
        if call.groupCall.localDeviceState.joinState == .notJoined { call.groupCall.join() }
    }

    func buildOutgoingIndividualCallIfPossible(thread: TSContactThread, hasVideo: Bool) -> SignalCall? {
        AssertIsOnMainThread()
        guard !hasCallInProgress else { return nil }

        let call = SignalCall.outgoingIndividualCall(thread: thread)
        call.individualCall.offerMediaType = hasVideo ? .video : .audio

        addCall(call)

        return call
    }

    func prepareIncomingIndividualCall(
        thread: TSContactThread,
        sentAtTimestamp: UInt64,
        callType: SSKProtoCallMessageOfferType
    ) -> SignalCall {
        AssertIsOnMainThread()

        let offerMediaType: TSRecentCallOfferType
        switch callType {
        case .offerAudioCall:
            offerMediaType = .audio
        case .offerVideoCall:
            offerMediaType = .video
        }

        let newCall = SignalCall.incomingIndividualCall(
            thread: thread,
            sentAtTimestamp: sentAtTimestamp,
            offerMediaType: offerMediaType
        )

        addCall(newCall)

        return newCall
    }

    // MARK: - Notifications

    @objc
    func didEnterBackground() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    @objc
    private func registrationChanged() {
        AssertIsOnMainThread()
        if let localUuid = tsAccountManager.localUuid {
            callManager.setSelfUuid(localUuid)
        }
    }

    /// The object is the rotation angle necessary to match the new orientation.
    static var phoneOrientationDidChange = Notification.Name("CallService.phoneOrientationDidChange")

    @objc
    private func phoneOrientationDidChange() {
        guard currentCall != nil else {
            return
        }
        sendPhoneOrientationNotification()
    }

    private func shouldReorientUI(for call: SignalCall) -> Bool {
        owsAssertDebug(!UIDevice.current.isIPad, "iPad has full UIKit rotation support")

        guard call.isIndividualCall else {
            // If we're in a group call, we don't want to use rotating icons,
            // because we don't rotate user video at the same time,
            // and that's very obvious for grid view or any non-speaker tile in speaker view.
            return false
        }

        // If we're in an audio-only 1:1 call, the user isn't going to be looking at the screen.
        // Don't distract them with rotating icons.
        return call.individualCall.hasLocalVideo || call.individualCall.isRemoteVideoEnabled
    }

    private func sendPhoneOrientationNotification() {
        owsAssertDebug(!UIDevice.current.isIPad, "iPad has full UIKit rotation support")

        let rotationAngle: CGFloat
        if let call = currentCall, !shouldReorientUI(for: call) {
            // We still send the notification in case we *previously* rotated the UI and now we need to revert back.
            // Example:
            // 1. In a 1:1 call, either the user or their contact (but not both) has video on
            // 2. the user has the phone in landscape
            // 3. whoever had video turns it off (but the icons are still landscape-oriented)
            // 4. the user rotates back to portrait
            rotationAngle = 0
        } else {
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                rotationAngle = .halfPi
            case .landscapeRight:
                rotationAngle = -.halfPi
            case .portrait, .portraitUpsideDown, .faceDown, .faceUp, .unknown:
                fallthrough
            @unknown default:
                rotationAngle = 0
            }
        }

        NotificationCenter.default.post(name: Self.phoneOrientationDidChange, object: rotationAngle)
    }

    /// Pretend the phone just changed orientations so that the call UI will autorotate.
    func sendInitialPhoneOrientationNotification() {
        guard !UIDevice.current.isIPad else {
            return
        }
        sendPhoneOrientationNotification()
    }

    // MARK: -

    private func updateGroupMembersForCurrentCallIfNecessary() {
        DispatchQueue.main.async {
            guard let call = self.currentCall, call.isGroupCall,
                  let groupThread = call.thread as? TSGroupThread else { return }

            let membershipInfo: [GroupMemberInfo]
            do {
                membershipInfo = try self.databaseStorage.read {
                    try self.groupMemberInfo(for: groupThread, transaction: $0)
                }
            } catch {
                owsFailDebug("Failed to fetch membership info: \(error)")
                return
            }
            call.groupCall.updateGroupMembers(members: membershipInfo)
        }
    }

    // MARK: - Bandwidth

    static let callServicePreferencesDidChange = Notification.Name("CallServicePreferencesDidChange")
    private static let keyValueStore = SDSKeyValueStore(collection: "CallService")
    private static let highBandwidthPreferenceKey = "HighBandwidthPreferenceKey"

    static func setHighBandwidthInterfaces(_ interfaceSet: NetworkInterfaceSet, writeTx: SDSAnyWriteTransaction) {
        Logger.info("Updating preferred low bandwidth interfaces: \(interfaceSet.rawValue)")

        keyValueStore.setUInt(interfaceSet.rawValue, key: highBandwidthPreferenceKey, transaction: writeTx)
        writeTx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(callServicePreferencesDidChange, object: nil)
        }
    }

    static func highBandwidthNetworkInterfaces(readTx: SDSAnyReadTransaction) -> NetworkInterfaceSet {
        guard let highBandwidthPreference = keyValueStore.getUInt(
                highBandwidthPreferenceKey,
                transaction: readTx) else { return .wifiAndCellular }

        return NetworkInterfaceSet(rawValue: highBandwidthPreference)
    }
}

extension CallService: CallObserver {
    public func individualCallStateDidChange(_ call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
        configureBandwidthMode()
    }

    public func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
    }

    public func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallLocalDeviceStateChanged")
        AssertIsOnMainThread()
        updateIsVideoEnabled()
        updateGroupMembersForCurrentCallIfNecessary()
        configureBandwidthMode()

        if call.groupCallRingState == .shouldRing &&
            call.ringRestrictions.isEmpty &&
            call.groupCall.localDeviceState.joinState == .joined &&
            call.groupCall.remoteDeviceStates.isEmpty {
            // Don't start ringing until we join the call successfully.
            call.groupCallRingState = .ringing
            call.groupCall.ringAll()
            audioService.playOutboundRing()
        }
    }

    public func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {}
    public func groupCallPeekChanged(_ call: SignalCall) {
        guard let thread = call.thread as? TSGroupThread else {
            owsFailDebug("Invalid thread for call: \(call)")
            return
        }
        guard let peekInfo = call.groupCall.peekInfo else {
            Logger.warn("No peek info for call: \(call)")
            return
        }
        DispatchQueue.sharedUtility.async {
            self.updateGroupCallMessageWithInfo(peekInfo, for: thread, timestamp: Date.ows_millisecondTimestamp())
        }
    }

    public func groupCallRequestMembershipProof(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallUpdateGroupMembershipProof")

        guard call === currentCall else { return cleanupStaleCall(call) }

        guard let groupThread = call.thread as? TSGroupThread else {
            return owsFailDebug("unexpectedly missing thread")
        }

        firstly {
            fetchGroupMembershipProof(for: groupThread)
        }.done(on: .main) { proof in
            call.groupCall.updateMembershipProof(proof: proof)
        }.catch(on: .main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to fetch group call credentials \(error)")
            } else {
                owsFailDebug("Failed to fetch group call credentials \(error)")
            }
        }
    }

    public func groupCallRequestGroupMembers(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallUpdateGroupMembers")

        guard call === currentCall else { return cleanupStaleCall(call) }

        updateGroupMembersForCurrentCallIfNecessary()
    }
}

// MARK: - Group call participant updates

extension CallService {
    @objc
    override public func peekCallAndUpdateThread(_ thread: TSGroupThread,
                                                 expectedEraId: String? = nil,
                                                 triggerEventTimestamp: UInt64 = NSDate.ows_millisecondTimeStamp(),
                                                 completion: (() -> Void)? = nil) {
        // If the currentCall is for the provided thread, we don't need to perform an explicit
        // peek. Connected calls will receive automatic updates from RingRTC
        guard currentCall?.thread != thread else {
            Logger.info("Ignoring peek request for the current call")
            return
        }
        super.peekCallAndUpdateThread(thread, expectedEraId: expectedEraId, triggerEventTimestamp: triggerEventTimestamp, completion: completion)
    }

    @objc
    override public func postUserNotificationIfNecessary(groupCallMessage: OWSGroupCallMessage, transaction: SDSAnyWriteTransaction) {
        AssertNotOnMainThread()

        // The message can't be for the current call
        guard self.currentCall?.thread.uniqueId != groupCallMessage.uniqueThreadId else { return }

        super.postUserNotificationIfNecessary(groupCallMessage: groupCallMessage, transaction: transaction)
    }
}

extension CallService: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard let thread = currentCall?.thread,
              thread.isGroupThread,
              databaseChanges.didUpdate(thread: thread) else { return }

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateGroupMembersForCurrentCallIfNecessary()
    }
}

extension CallService: CallManagerDelegate {
    public typealias CallManagerDelegateCallType = SignalCall

    /**
     * A call message should be sent to the given remote recipient.
     * Invoked on the main thread, asynchronously.
     * If there is any error, the UI can reset UI state and invoke the reset() API.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendCallMessage recipientUuid: UUID,
        message: Data,
        urgency: CallMessageUrgency
    ) {
        AssertIsOnMainThread()
        Logger.info("shouldSendCallMessage")

        // It's unlikely that this would ever have more than one call. But technically
        // we don't know which call this message is on behalf of. So we assume it's every
        // call with a participant with recipientUuid
        let relevantCalls = calls.filter { (call: SignalCall) -> Bool in
            call.participantAddresses
                .compactMap { $0.uuid }
                .contains(recipientUuid)
        }

        databaseStorage.write(.promise) { transaction in
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: recipientUuid),
                transaction: transaction
            )
        }.then(on: .global()) { thread throws -> Promise<Void> in
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)

            return try Self.databaseStorage.write { transaction in
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: try opaqueBuilder.build(),
                    transaction: transaction
                )

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) { _ in
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        }.catch(on: .main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to send opaque message \(error)")
            } else if error is UntrustedIdentityError {
                relevantCalls.forEach { $0.publishSendFailureUntrustedParticipantIdentity() }
            } else {
                Logger.error("Failed to send opaque message \(error)")
            }
            // TODO: Tell RingRTC something went wrong. API TBD
        }
    }

    /**
     * A call message should be sent to all other members of the given group.
     * Invoked on the main thread, asynchronously.
     * If there is any error, the UI can reset UI state and invoke the reset() API.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendCallMessageToGroup groupId: Data,
        message: Data,
        urgency: CallMessageUrgency
    ) {
        AssertIsOnMainThread()
        Logger.info("")

        databaseStorage.read(.promise) { transaction throws -> TSGroupThread in
            guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("tried to send call message to unknown group")
            }
            return thread
        }.then(on: .global()) { thread throws -> Promise<Void> in
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)

            return try Self.databaseStorage.write { transaction in
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: try opaqueBuilder.build(),
                    transaction: transaction
                )

                return ThreadUtil.enqueueMessagePromise(
                    message: callMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: .main) { _ in
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        }.catch(on: .main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to send opaque message \(error)")
            } else {
                Logger.error("Failed to send opaque message \(error)")
            }
            // TODO: Tell RingRTC something went wrong. API TBD
        }
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldCompareCalls call1: SignalCall,
        call2: SignalCall
    ) -> Bool {
        Logger.info("shouldCompareCalls")
        return call1.thread.uniqueId == call2.thread.uniqueId
    }

    // MARK: - 1:1 Call Delegates

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldStartCall call: SignalCall,
        callId: UInt64,
        isOutgoing: Bool,
        callMediaType: CallMediaType
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        guard currentCall == nil else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("a current call is already set"))
            return
        }

        if !calls.contains(call) {
            owsFailDebug("unknown call: \(call)")
        }

        call.individualCall.callId = callId

        // We grab this before updating the currentCall since it will unset it by default as a precaution.
        let shouldEarlyRing = earlyRingNextIncomingCall && !isOutgoing
        earlyRingNextIncomingCall = false

        // The call to be started is provided by the event.
        currentCall = call

        individualCallService.callManager(
            callManager,
            shouldStartCall: call,
            callId: callId,
            isOutgoing: isOutgoing,
            callMediaType: callMediaType,
            shouldEarlyRing: shouldEarlyRing
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onEvent call: SignalCall,
        event: CallManagerEvent
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            onEvent: call,
            event: event
        )
    }

    /**
     * onNetworkRouteChangedFor will be invoked when changes to the network routing (e.g. wifi/cellular) are detected.
     * Invoked on the main thread, asynchronously.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onNetworkRouteChangedFor call: SignalCall,
        networkRoute: NetworkRoute
    ) {
        Logger.info("Network route changed for call: \(call): \(networkRoute.localAdapterType.rawValue)")
        call.individualCall.networkRoute = networkRoute
        configureBandwidthMode()
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onAudioLevelsFor call: SignalCall,
        capturedLevel: UInt16,
        receivedLevel: UInt16
    ) {
        // TODO: Implement audio level handling for individual calls.
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendOffer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data,
        callMediaType: CallMediaType
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendOffer: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            opaque: opaque,
            callMediaType: callMediaType
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendAnswer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendAnswer: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            opaque: opaque
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendIceCandidates callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        candidates: [Data]
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendIceCandidates: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            candidates: candidates
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendHangup callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        hangupType: HangupType,
        deviceId: UInt32
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendHangup: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            hangupType: hangupType,
            deviceId: deviceId
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendBusy callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendBusy: callId,
            call: call,
            destinationDeviceId: destinationDeviceId
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onUpdateLocalVideoSession call: SignalCall,
        session: AVCaptureSession?
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            onUpdateLocalVideoSession: call,
            session: session
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onAddRemoteVideoTrack call: SignalCall,
        track: RTCVideoTrack
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            onAddRemoteVideoTrack: call,
            track: track
        )
    }

    /**
     * An update from `sender` has come in for the ring in `groupId` identified by `ringId`.
     *
     * `sender` will be the current user's ID if the update came from another device.
     *
     * Invoked on the main thread, asynchronously.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        didUpdateRingForGroup groupId: Data,
        ringId: Int64,
        sender: UUID,
        update: RingUpdate
    ) {
        Logger.info("Stubbed \(#function)")
    }
}

extension CallMessageUrgency {
    var protobufValue: SSKProtoCallMessageOpaqueUrgency {
    switch self {
    case .droppable: return .droppable
    case .handleImmediately: return .handleImmediately
    }
    }
}

extension NetworkInterfaceSet {
    func includes(_ ringRtcAdapter: NetworkAdapterType) -> Bool? {
        switch ringRtcAdapter {
        case .unknown, .vpn, .anyAddress:
            if self.isEmpty {
                return false
            } else if self.inverted.isEmpty {
                return true
            } else {
                // We don't know the underlying interface, so we can't assume anything.
                return nil
            }
        case .cellular, .cellular2G, .cellular3G, .cellular4G, .cellular5G:
            return self.contains(.cellular)
        case .ethernet, .wifi, .loopback:
            return self.contains(.wifi)
        }
    }
}
