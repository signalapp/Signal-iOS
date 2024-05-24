//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import LibSignalClient
import SignalServiceKit
import SignalRingRTC
import SignalUI
import WebRTC

/// Manages events related to both 1:1 and group calls, while the main app is
/// running.
///
/// Responsible for the 1:1 or group call this device is currently active in, if
/// any, as well as any other updates to other calls that we learn about.
final class CallService: CallServiceStateObserver, CallServiceStateDelegate {
    public typealias CallManagerType = CallManager<SignalCall, CallService>

    public let callManager: CallManagerType

    private var audioSession: AudioSession { NSObject.audioSession }
    private var databaseStorage: SDSDatabaseStorage { NSObject.databaseStorage }
    private var deviceSleepManager: DeviceSleepManager { DeviceSleepManager.shared }
    private var groupCallManager: GroupCallManager { NSObject.groupCallManager }
    private var reachabilityManager: SSKReachabilityManager { NSObject.reachabilityManager }

    public var callUIAdapter: CallUIAdapter

    let individualCallService: IndividualCallService
    let groupCallRemoteVideoManager: GroupCallRemoteVideoManager

    /// Needs to be lazily initialized, because it uses singletons that are not
    /// available when this class is initialized.
    private lazy var groupCallAccessoryMessageDelegate: GroupCallAccessoryMessageDelegate = {
        return GroupCallAccessoryMessageHandler(
            databaseStorage: databaseStorage,
            groupCallRecordManager: DependenciesBridge.shared.groupCallRecordManager,
            messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef
        )
    }()

    /// Needs to be lazily initialized, because it uses singletons that are not
    /// available when this class is initialized.
    private lazy var groupCallRecordRingUpdateDelegate: GroupCallRecordRingUpdateDelegate = {
        return GroupCallRecordRingUpdateHandler(
            callRecordStore: DependenciesBridge.shared.callRecordStore,
            groupCallRecordManager: DependenciesBridge.shared.groupCallRecordManager,
            interactionStore: DependenciesBridge.shared.interactionStore,
            threadStore: DependenciesBridge.shared.threadStore
        )
    }()

    private(set) lazy var audioService: CallAudioService = {
        let result = CallAudioService(audioSession: self.audioSession)
        callServiceState.addObserver(result, syncStateImmediately: true)
        return result
    }()

    public let earlyRingNextIncomingCall = AtomicBool(false, lock: .init())

    let callServiceState: CallServiceState

    public init(
        appContext: any AppContext,
        groupCallPeekClient: GroupCallPeekClient,
        mutableCurrentCall: AtomicValue<SignalCall?>
    ) {
        self.callManager = CallManager(
            httpClient: groupCallPeekClient.httpClient,
            fieldTrials: RingrtcFieldTrials.trials(with: appContext.appUserDefaults())
        )
        let callUIAdapter = CallUIAdapter()
        self.callUIAdapter = callUIAdapter
        self.callServiceState = CallServiceState(currentCall: mutableCurrentCall)
        self.individualCallService = IndividualCallService(
            callManager: self.callManager,
            callServiceState: self.callServiceState
        )
        self.groupCallRemoteVideoManager = GroupCallRemoteVideoManager(
            callServiceState: self.callServiceState
        )
        self.callManager.delegate = self
        SwiftSingletons.register(self)
        self.callServiceState.addObserver(self)

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
            selector: #selector(configureDataMode),
            name: Self.callServicePreferencesDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationChanged),
            name: .registrationStateDidChange,
            object: nil)

        // Note that we're not using the usual .owsReachabilityChanged
        // We want to update our data mode if the app has been backgrounded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureDataMode),
            name: .reachabilityChanged,
            object: nil
        )

        // We don't support a rotating call screen on phones,
        // but we do still want to rotate the various icons.
        if !UIDevice.current.isIPad {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(phoneOrientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            if let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
                self.callManager.setSelfUuid(localAci.rawUUID)
            }
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            SDSDatabaseStorage.shared.appendDatabaseChangeDelegate(self)

            self.callServiceState.addObserver(self.groupCallAccessoryMessageDelegate, syncStateImmediately: true)
            self.callServiceState.addObserver(self.groupCallRemoteVideoManager, syncStateImmediately: true)
        }
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    public func rebuildCallUIAdapter() {
        AssertIsOnMainThread()

        if let currentCall = callServiceState.currentCall {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            callServiceState.terminateCall(currentCall)
        }

        self.callUIAdapter = CallUIAdapter()
    }

    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        switch oldValue?.mode {
        case nil:
            break
        case .individual(let call):
            call.removeObserver(self)
        case .groupThread(let call):
            call.removeObserver(self)
        }
        switch newValue?.mode {
        case nil:
            break
        case .individual(let call):
            call.addObserverAndSyncState(self)
        case .groupThread(let call):
            call.addObserverAndSyncState(self)
        }

        updateIsVideoEnabled()

        // Prevent device from sleeping while we have an active call.
        if let oldValue {
            self.deviceSleepManager.removeBlock(blockObject: oldValue)
        }
        if let newValue {
            self.deviceSleepManager.addBlock(blockObject: newValue)
        }

        if !UIDevice.current.isIPad {
            if oldValue != nil {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            if newValue != nil {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            }
        }

        switch newValue?.mode {
        case .individual:
            // By default, individual calls should start out with speakerphone disabled.
            self.audioService.requestSpeakerphone(isEnabled: false)
        case .groupThread, nil:
            break
        }

        // To be safe, we reset the early ring on any call change so it's not left set from an unexpected state change.
        earlyRingNextIncomingCall.set(false)
    }

    func callServiceState(_ callServiceState: CallServiceState, didTerminateCall call: SignalCall) {
        if !callServiceState.hasActiveOrPendingCall {
            audioSession.isRTCAudioEnabled = false
        }
        audioSession.endAudioActivity(call.commonState.audioActivity)

        switch call.mode {
        case .individual:
            break
        case .groupThread:
            // Kick off a peek now that we've disconnected to get an updated participant state.
            guard let thread = call.thread as? TSGroupThread else {
                owsFailDebug("Invalid thread type")
                return
            }
            Task {
                await self.groupCallManager.peekGroupCallAndUpdateThread(
                    thread,
                    peekTrigger: .localEvent()
                )
            }
        }
    }

    // MARK: -

    /**
     * Local user toggled to mute audio.
     */
    func updateIsLocalAudioMuted(isLocalAudioMuted: Bool) {
        AssertIsOnMainThread()

        // Keep a reference to the call before permissions were requested...
        guard let currentCall = callServiceState.currentCall else {
            owsFailDebug("missing currentCall")
            return
        }

        // If we're disabling the microphone, we don't need permission. Only need
        // permission to *enable* the microphone.
        guard !isLocalAudioMuted else {
            return updateIsLocalAudioMutedWithMicrophonePermission(call: currentCall, isLocalAudioMuted: isLocalAudioMuted)
        }

        // This method can be initiated either from the CallViewController.videoButton or via CallKit
        // in either case we want to show the alert on the callViewWindow.
        guard let frontmostViewController =
                UIApplication.shared.findFrontmostViewController(ignoringAlerts: true,
                                                                 window: WindowManager.shared.callViewWindow) else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            // Make sure the call is still valid (the one we asked permissions for).
            guard self.callServiceState.currentCall === currentCall else {
                Logger.info("ignoring microphone permissions for obsolete call")
                return
            }

            if !granted {
                frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
            }

            let mutedAfterAskingForPermission = !granted
            self.updateIsLocalAudioMutedWithMicrophonePermission(call: currentCall, isLocalAudioMuted: mutedAfterAskingForPermission)
        }
    }

    private func updateIsLocalAudioMutedWithMicrophonePermission(call: SignalCall, isLocalAudioMuted: Bool) {
        AssertIsOnMainThread()
        owsAssert(call === callServiceState.currentCall)

        switch call.mode {
        case .groupThread(let groupThreadCall):
            groupThreadCall.ringRtcCall.isOutgoingAudioMuted = isLocalAudioMuted
            groupThreadCall.groupCall(onLocalDeviceStateChanged: groupThreadCall.ringRtcCall)
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
        guard let currentCall = callServiceState.currentCall else {
            owsFailDebug("missing currentCall")
            return
        }

        // If we're disabling local video, we don't need permission. Only need
        // permission to *enable* video.
        guard !isLocalVideoMuted else {
            return updateIsLocalVideoMutedWithCameraPermissions(call: currentCall, isLocalVideoMuted: isLocalVideoMuted)
        }

        // This method can be initiated either from the CallViewController.videoButton or via CallKit
        // in either case we want to show the alert on the callViewWindow.
        let frontmostViewController = UIApplication.shared.findFrontmostViewController(
            ignoringAlerts: true,
            window: WindowManager.shared.callViewWindow
        )
        guard let frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        frontmostViewController.ows_askForCameraPermissions { granted in
            // Make sure the call is still valid (the one we asked permissions for).
            guard self.callServiceState.currentCall === currentCall else {
                Logger.info("ignoring camera permissions for obsolete call")
                return
            }

            let mutedAfterAskingForPermission = !granted
            self.updateIsLocalVideoMutedWithCameraPermissions(call: currentCall, isLocalVideoMuted: mutedAfterAskingForPermission)
        }
    }

    private func updateIsLocalVideoMutedWithCameraPermissions(call: SignalCall, isLocalVideoMuted: Bool) {
        AssertIsOnMainThread()
        owsAssert(call === callServiceState.currentCall)

        switch call.mode {
        case .groupThread(let groupThreadCall):
            groupThreadCall.ringRtcCall.isOutgoingVideoMuted = isLocalVideoMuted
            groupThreadCall.groupCall(onLocalDeviceStateChanged: groupThreadCall.ringRtcCall)
        case .individual(let individualCall):
            individualCall.hasLocalVideo = !isLocalVideoMuted
        }

        updateIsVideoEnabled()
    }

    func updateCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        call.videoCaptureController.switchCamera(isUsingFrontCamera: isUsingFrontCamera)
    }

    @objc
    private func configureDataMode() {
        guard AppReadiness.isAppReady else { return }
        guard let currentCall = callServiceState.currentCall else { return }

        switch currentCall.mode {
        case .groupThread(let call):
            let useLowData = shouldUseLowDataWithSneakyTransaction(for: call.ringRtcCall.localDeviceState.networkRoute)
            Logger.info("Configuring call for \(useLowData ? "low" : "standard") data")
            call.ringRtcCall.updateDataMode(dataMode: useLowData ? .low : .normal)
        case let .individual(call) where call.state == .connected:
            let useLowData = shouldUseLowDataWithSneakyTransaction(for: call.networkRoute)
            Logger.info("Configuring call for \(useLowData ? "low" : "standard") data")
            callManager.updateDataMode(dataMode: useLowData ? .low : .normal)
        default:
            // Do nothing. We'll reapply the data mode once connected
            break
        }
    }

    func shouldUseLowDataWithSneakyTransaction(for networkRoute: NetworkRoute) -> Bool {
        let highDataInterfaces = databaseStorage.read { readTx in
            Self.highDataNetworkInterfaces(readTx: readTx)
        }
        if let allowsHighData = highDataInterfaces.includes(networkRoute.localAdapterType) {
            return !allowsHighData
        }
        // If we aren't sure whether the current route's high-data, fall back to checking reachability.
        // This also handles the situation where WebRTC doesn't know what interface we're on,
        // which is always true on iOS 11.
        return !reachabilityManager.isReachable(with: highDataInterfaces)
    }

    // MARK: -

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall, error: Error) {
        AssertIsOnMainThread()

        switch failedCall.mode {
        case .individual:
            individualCallService.handleFailedCall(
                failedCall: failedCall,
                error: error,
                shouldResetUI: false,
                shouldResetRingRTC: true
            )
        case .groupThread:
            callServiceState.terminateCall(failedCall)
        }
    }

    func handleLocalHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        switch call.mode {
        case .individual:
            individualCallService.handleLocalHangupCall(call)
        case .groupThread(let groupThreadCall):
            if case .incomingRing(_, let ringId) = groupThreadCall.groupCallRingState {
                guard let groupThreadCall = call.unpackGroupCall() else {
                    return
                }
                let groupThread = groupThreadCall.groupThread

                groupCallAccessoryMessageDelegate.localDeviceDeclinedGroupRing(
                    ringId: ringId,
                    groupThread: groupThread
                )

                do {
                    try callManager.cancelGroupRing(
                        groupId: groupThread.groupId,
                        ringId: ringId,
                        reason: .declinedByUser
                    )
                } catch {
                    owsFailDebug("RingRTC failed to cancel group ring \(ringId): \(error)")
                }
            }
            callServiceState.terminateCall(call)
        }
    }

    // MARK: - Video

    var shouldHaveLocalVideoTrack: Bool {
        AssertIsOnMainThread()

        guard let call = self.callServiceState.currentCall else {
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
        case .groupThread(let groupThreadCall):
            return !groupThreadCall.ringRtcCall.isOutgoingVideoMuted
        }
    }

    func updateIsVideoEnabled() {
        AssertIsOnMainThread()

        guard let call = self.callServiceState.currentCall else { return }

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
        case .groupThread:
            if shouldHaveLocalVideoTrack {
                call.videoCaptureController.startCapture()
            } else {
                call.videoCaptureController.stopCapture()
            }
        }
    }

    // MARK: -

    func buildAndConnectGroupCallIfPossible(thread: TSGroupThread, videoMuted: Bool) -> (SignalCall, GroupThreadCall)? {
        AssertIsOnMainThread()
        guard !callServiceState.hasActiveOrPendingCall else { return nil }

        guard let (call, groupThreadCall) = buildGroupCall(for: thread) else { return nil }
        callServiceState.addCall(call)

        // By default, group calls should start out with speakerphone enabled.
        self.audioService.requestSpeakerphone(isEnabled: true)

        groupThreadCall.ringRtcCall.isOutgoingAudioMuted = false
        groupThreadCall.ringRtcCall.isOutgoingVideoMuted = videoMuted

        callServiceState.setCurrentCall(call)

        guard groupThreadCall.ringRtcCall.connect() else {
            callServiceState.terminateCall(call)
            return nil
        }

        return (call, groupThreadCall)
    }

    private func buildGroupCall(for thread: TSGroupThread) -> (SignalCall, GroupThreadCall)? {
        owsAssertDebug(thread.groupModel.groupsVersion == .V2)

        let videoCaptureController = VideoCaptureController()
        let sfuURL = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL

        guard let groupCall = callManager.createGroupCall(
            groupId: thread.groupModel.groupId,
            sfuUrl: sfuURL,
            hkdfExtraInfo: Data.init(),
            audioLevelsIntervalMillis: nil,
            videoCaptureController: videoCaptureController
        ) else {
            owsFailDebug("Failed to create group call")
            return nil
        }

        let groupThreadCall = GroupThreadCall(
            ringRtcCall: groupCall,
            groupThread: thread,
            videoCaptureController: videoCaptureController
        )

        return (SignalCall(groupThreadCall: groupThreadCall), groupThreadCall)
    }

    func joinGroupCallIfNecessary(_ call: SignalCall, groupThreadCall: GroupThreadCall) {
        let currentCall = self.callServiceState.currentCall
        if currentCall === nil {
            callServiceState.setCurrentCall(call)
        } else if currentCall !== call {
            return owsFailDebug("A call is already in progress")
        }
        let groupCall = groupThreadCall.ringRtcCall

        // If we're not yet connected, connect now. This may happen if, for
        // example, the call ended unexpectedly.
        if groupCall.localDeviceState.connectionState == .notConnected {
            guard groupCall.connect() else {
                callServiceState.terminateCall(call)
                return
            }
        }

        // If we're not yet joined, join now. In general, it's unexpected that
        // this method would be called when you're already joined, but it is
        // safe to do so.
        if groupCall.localDeviceState.joinState == .notJoined {
            groupCall.join()
            // Group calls can get disconnected, but we don't count that as ending the call.
            // So this call may have already been reported.
            if groupThreadCall.commonState.systemState == .notReported && !groupThreadCall.groupCallRingState.isIncomingRing {
                callUIAdapter.startOutgoingCall(call: call)
            }
        }
    }

    @discardableResult
    @objc
    public func initiateCall(thread: TSThread, isVideo: Bool) -> Bool {
        initiateCall(thread: thread, isVideo: isVideo, untrustedThreshold: nil)
    }

    private func initiateCall(thread: TSThread, isVideo: Bool, untrustedThreshold: Date?) -> Bool {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            Logger.warn("aborting due to user not being registered.")
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                                                                     comment: "alert body shown when trying to use features in the app before completing registration-related setup."))
            return false
        }

        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        if let groupThread = thread as? TSGroupThread {
            return GroupCallViewController.presentLobby(thread: groupThread, videoMuted: !isVideo)
        }

        guard let thread = thread as? TSContactThread else {
            owsFailDebug("cannot initiate call to group thread")
            return false
        }

        let newUntrustedThreshold = Date()
        let showedAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: [thread.contactAddress],
            confirmationText: CallStrings.confirmAndCallButtonTitle,
            untrustedThreshold: untrustedThreshold
        ) { didConfirmIdentity in
            guard didConfirmIdentity else { return }
            _ = self.initiateCall(thread: thread, isVideo: isVideo, untrustedThreshold: newUntrustedThreshold)
        }
        guard !showedAlert else {
            return false
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            guard granted == true else {
                Logger.warn("aborting due to missing microphone permissions.")
                frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            if isVideo {
                frontmostViewController.ows_askForCameraPermissions { granted in
                    guard granted else {
                        Logger.warn("aborting due to missing camera permissions.")
                        return
                    }

                    self.callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: true)
                }
            } else {
                self.callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: false)
            }
        }

        return true
    }

    func buildOutgoingIndividualCallIfPossible(thread: TSContactThread, hasVideo: Bool) -> (SignalCall, IndividualCall)? {
        AssertIsOnMainThread()
        guard !callServiceState.hasActiveOrPendingCall else { return nil }

        let individualCall = IndividualCall.outgoingIndividualCall(
            thread: thread,
            offerMediaType: hasVideo ? .video : .audio
        )

        let call = SignalCall(individualCall: individualCall)

        callServiceState.addCall(call)

        return (call, individualCall)
    }

    // MARK: - Notifications

    @objc
    private func didEnterBackground() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    @objc
    private func registrationChanged() {
        AssertIsOnMainThread()
        if let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
            callManager.setSelfUuid(localAci.rawUUID)
        }
    }

    /// The object is the rotation angle necessary to match the new orientation.
    static var phoneOrientationDidChange = Notification.Name("CallService.phoneOrientationDidChange")

    @objc
    private func phoneOrientationDidChange() {
        guard callServiceState.currentCall != nil else {
            return
        }
        sendPhoneOrientationNotification()
    }

    private func shouldReorientUI(for call: SignalCall) -> Bool {
        owsAssertDebug(!UIDevice.current.isIPad, "iPad has full UIKit rotation support")

        switch call.mode {
        case .individual(let individualCall):
            // If we're in an audio-only 1:1 call, the user isn't going to be looking at the screen.
            // Don't distract them with rotating icons.
            return individualCall.hasLocalVideo || individualCall.isRemoteVideoEnabled
        case .groupThread:
            // If we're in a group call, we don't want to use rotating icons,
            // because we don't rotate user video at the same time,
            // and that's very obvious for grid view or any non-speaker tile in speaker view.
            return false
        }
    }

    private func sendPhoneOrientationNotification() {
        owsAssertDebug(!UIDevice.current.isIPad, "iPad has full UIKit rotation support")

        let rotationAngle: CGFloat
        if let call = callServiceState.currentCall, !shouldReorientUI(for: call) {
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
            let currentCall = self.callServiceState.currentCall
            guard let groupThreadCall = currentCall?.unpackGroupCall() else {
                return
            }

            let membershipInfo: [GroupMemberInfo]
            do {
                membershipInfo = try self.databaseStorage.read { tx in
                    try self.groupCallManager.groupCallPeekClient.groupMemberInfo(
                        groupThread: groupThreadCall.groupThread, tx: tx.asV2Read
                    )
                }
            } catch {
                owsFailDebug("Failed to fetch membership info: \(error)")
                return
            }
            groupThreadCall.ringRtcCall.updateGroupMembers(members: membershipInfo)
        }
    }

    // MARK: - Data Modes

    static let callServicePreferencesDidChange = Notification.Name("CallServicePreferencesDidChange")
    private static let keyValueStore = SDSKeyValueStore(collection: "CallService")
    // This used to be called "high bandwidth", but "data" is more accurate.
    private static let highDataPreferenceKey = "HighBandwidthPreferenceKey"

    static func setHighDataInterfaces(_ interfaceSet: NetworkInterfaceSet, writeTx: SDSAnyWriteTransaction) {
        Logger.info("Updating preferred low data interfaces: \(interfaceSet.rawValue)")

        keyValueStore.setUInt(interfaceSet.rawValue, key: highDataPreferenceKey, transaction: writeTx)
        writeTx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(callServicePreferencesDidChange, object: nil)
        }
    }

    static func highDataNetworkInterfaces(readTx: SDSAnyReadTransaction) -> NetworkInterfaceSet {
        guard let highDataPreference = keyValueStore.getUInt(
                highDataPreferenceKey,
                transaction: readTx) else { return .wifiAndCellular }

        return NetworkInterfaceSet(rawValue: highDataPreference)
    }
}

extension CallService: IndividualCallObserver {
    func individualCallStateDidChange(_ call: IndividualCall, state: CallState) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
        configureDataMode()
    }

    func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
    }
}

extension CallService: GroupThreadCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupThreadCall) {
        AssertIsOnMainThread()

        let groupCall = call.ringRtcCall
        let groupThread = call.groupThread

        Logger.info("")
        updateIsVideoEnabled()
        updateGroupMembersForCurrentCallIfNecessary()
        configureDataMode()

        if groupCall.localDeviceState.isJoined {
            if
                case .shouldRing = call.groupCallRingState,
                call.ringRestrictions.isEmpty,
                groupCall.remoteDeviceStates.isEmpty
            {
                // Don't start ringing until we join the call successfully.
                call.groupCallRingState = .ringing
                groupCall.ringAll()
                audioService.playOutboundRing()
            }

            if let eraId = groupCall.peekInfo?.eraId {
                groupCallAccessoryMessageDelegate.localDeviceMaybeJoinedGroupCall(
                    eraId: eraId,
                    groupThread: groupThread,
                    groupCallRingState: call.groupCallRingState
                )
            }
        } else {
            groupCallAccessoryMessageDelegate.localDeviceMaybeLeftGroupCall(
                groupThread: groupThread,
                groupCall: groupCall
            )
        }
    }

    func groupCallPeekChanged(_ call: GroupThreadCall) {
        AssertIsOnMainThread()

        let groupCall = call.ringRtcCall
        let groupThread = call.groupThread

        guard let peekInfo = groupCall.peekInfo else {
            GroupCallPeekLogger.shared.warn("No peek info for call: \(call)")
            return
        }

        if
            groupCall.localDeviceState.isJoined,
            let eraId = peekInfo.eraId
        {
            groupCallAccessoryMessageDelegate.localDeviceMaybeJoinedGroupCall(
                eraId: eraId,
                groupThread: groupThread,
                groupCallRingState: call.groupCallRingState
            )
        }

        databaseStorage.asyncWrite { tx in
            self.groupCallManager.updateGroupCallModelsForPeek(
                peekInfo: peekInfo,
                groupThread: groupThread,
                triggerEventTimestamp: Date.ows_millisecondTimestamp(),
                tx: tx
            )
        }
    }

    func groupCallEnded(_ call: GroupThreadCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()

        groupCallAccessoryMessageDelegate.localDeviceGroupCallDidEnd()
    }

    public func groupCallRemoteDeviceStatesChanged(_ call: GroupThreadCall) {
        guard case .ringing = call.groupCallRingState else {
            return
        }
        if !call.ringRtcCall.remoteDeviceStates.isEmpty {
            // The first time someone joins after a ring, we need to mark the call accepted.
            // (But if we didn't ring, the call will have already been marked accepted.)
            callUIAdapter.recipientAcceptedCall(.groupThread(call))
        }
    }

    func groupCallRequestMembershipProof(_ call: GroupThreadCall) {
        Logger.info("groupCallUpdateGroupMembershipProof")

        let groupCall = call.ringRtcCall
        let groupThread = call.groupThread

        Task { [groupCallManager] in
            do {
                let proof = try await groupCallManager.groupCallPeekClient.fetchGroupMembershipProof(groupThread: groupThread)
                await MainActor.run {
                    groupCall.updateMembershipProof(proof: proof)
                }
            } catch {
                if error.isNetworkFailureOrTimeout {
                    Logger.warn("Failed to fetch group call credentials \(error)")
                } else {
                    owsFailDebug("Failed to fetch group call credentials \(error)")
                }
            }
        }
    }

    func groupCallRequestGroupMembers(_ call: GroupThreadCall) {
        Logger.info("groupCallUpdateGroupMembers")

        updateGroupMembersForCurrentCallIfNecessary()
    }
}

extension SignalCall {
    func unpackGroupCall() -> GroupThreadCall? {
        switch mode {
        case .individual:
            return nil
        case .groupThread(let groupThreadCall):
            return groupThreadCall
        }
    }
}

private extension LocalDeviceState {
    var isJoined: Bool {
        switch joinState {
        case .joined: return true
        case .pending, .joining, .notJoined: return false
        }
    }
}

// MARK: - Group call participant updates

extension CallService: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard
            let thread = callServiceState.currentCall?.thread,
            thread.isGroupThread,
            databaseChanges.didUpdate(thread: thread)
        else {
            return
        }

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
     * Send a generic call message to the given remote recipient.
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

        let recipientAci = Aci(fromUUID: recipientUuid)

        // It's unlikely that this would ever have more than one call. But technically
        // we don't know which call this message is on behalf of. So we assume it's every
        // call with a participant with recipientUuid
        let relevantCalls = callServiceState.activeOrPendingCalls.filter { (call: SignalCall) -> Bool in
            call.participantAddresses.contains(where: { $0.serviceId == recipientAci })
        }

        databaseStorage.write(.promise) { transaction in
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(recipientAci),
                transaction: transaction
            )
        }.then(on: DispatchQueue.global()) { thread -> Promise<Void> in
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)

            return self.databaseStorage.write { transaction in
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: opaqueBuilder.buildInfallibly(),
                    overrideRecipients: nil,
                    transaction: transaction
                )
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: callMessage
                )

                return ThreadUtil.enqueueMessagePromise(
                    message: preparedMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: DispatchQueue.main) { _ in
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        }.catch(on: DispatchQueue.main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to send opaque message \(error)")
            } else if error is UntrustedIdentityError {
                relevantCalls.forEach {
                    switch $0.mode {
                    case .individual:
                        // TODO: Handle this case for 1:1 calls as well.
                        break
                    case .groupThread(let call):
                        call.publishSendFailureUntrustedParticipantIdentity()
                    }
                }
            } else {
                Logger.error("Failed to send opaque message \(error)")
            }
            // TODO: Tell RingRTC something went wrong. API TBD
        }
    }

    /**
     * Send a generic call message to a group. Send to all members of the group
     * or, if overrideRecipients is not empty, send to the given subset of members
     * using multi-recipient sealed sender. If the sealed sender request fails,
     * clients should provide a fallback mechanism.
     * Invoked on the main thread, asynchronously.
     * If there is any error, the UI can reset UI state and invoke the reset() API.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendCallMessageToGroup groupId: Data,
        message: Data,
        urgency: CallMessageUrgency,
        overrideRecipients: [UUID]
    ) {
        AssertIsOnMainThread()
        Logger.info("")

        databaseStorage.read(.promise) { transaction throws -> TSGroupThread in
            guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("tried to send call message to unknown group")
            }
            return thread
        }.then(on: DispatchQueue.global()) { thread -> Promise<Void> in
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)

            return self.databaseStorage.write { transaction in
                let overrideRecipients = overrideRecipients.map {
                    return AciObjC(Aci(fromUUID: $0))
                }
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: opaqueBuilder.buildInfallibly(),
                    overrideRecipients: overrideRecipients.isEmpty ? nil : overrideRecipients,
                    transaction: transaction
                )
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: callMessage
                )

                return ThreadUtil.enqueueMessagePromise(
                    message: preparedMessage,
                    limitToCurrentProcessLifetime: true,
                    isHighPriority: true,
                    transaction: transaction
                )
            }
        }.done(on: DispatchQueue.main) { _ in
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        }.catch(on: DispatchQueue.main) { error in
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

        guard callServiceState.currentCall == nil else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("a current call is already set"))
            return
        }

        owsAssertDebug(callServiceState.activeOrPendingCalls.contains(where: { $0 === call }), "unknown call: \(call)")

        switch call.mode {
        case .individual(let individualCall) where isOutgoing:
            individualCall.setOutgoingCallIdAndUpdateCallRecord(callId)
        case .individual:
            break
        case .groupThread:
            owsFail("Can't start a group call using this method.")
        }

        // We grab this before updating the currentCall since it will unset it by default as a precaution.
        let shouldEarlyRing = earlyRingNextIncomingCall.swap(false) && !isOutgoing

        // The call to be started is provided by the event.
        callServiceState.setCurrentCall(call)

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
        switch call.mode {
        case .individual(let individualCall):
            individualCall.networkRoute = networkRoute
            configureDataMode()
        case .groupThread:
            owsFail("Can't set the network route for a group call.")
        }
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
        onLowBandwidthForVideoFor call: SignalCall,
        recovered: Bool
    ) {
        // TODO: Implement handling of the "low outgoing bandwidth for video" notification.
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
        let senderAci = Aci(fromUUID: sender)

        /// Let our ``CallRecord`` delegate know we got a ring update.
        databaseStorage.asyncWrite { tx in
            self.groupCallRecordRingUpdateDelegate.didReceiveRingUpdate(
                groupId: groupId,
                ringId: ringId,
                ringUpdate: update,
                ringUpdateSender: senderAci,
                tx: tx.asV2Write
            )
        }

        guard update == .requested else {
            if
                let currentCall = self.callServiceState.currentCall,
                case .groupThread(let groupThreadCall) = currentCall.mode,
                case .incomingRing(_, ringId) = groupThreadCall.groupCallRingState
            {
                switch update {
                case .requested:
                    owsFail("checked above")
                case .expiredRing:
                    self.callUIAdapter.remoteDidHangupCall(currentCall)
                case .acceptedOnAnotherDevice:
                    self.callUIAdapter.didAnswerElsewhere(call: currentCall)
                case .declinedOnAnotherDevice:
                    self.callUIAdapter.didDeclineElsewhere(call: currentCall)
                case .busyLocally:
                    owsFailDebug("shouldn't get reported here")
                    fallthrough
                case .busyOnAnotherDevice:
                    self.callUIAdapter.wasBusyElsewhere(call: currentCall)
                case .cancelledByRinger:
                    self.callUIAdapter.remoteDidHangupCall(currentCall)
                }

                self.callServiceState.terminateCall(currentCall)
                groupThreadCall.groupCallRingState = .incomingRingCancelled
            }

            databaseStorage.asyncWrite { transaction in
                do {
                    try CancelledGroupRing(id: ringId).insert(transaction.unwrapGrdbWrite.database)
                    try CancelledGroupRing.deleteExpired(expiration: Date().addingTimeInterval(-30 * kMinuteInterval),
                                                         transaction: transaction)
                } catch {
                    owsFailDebug("failed to update cancellation table: \(error)")
                }
            }

            return
        }

        let caller = SignalServiceAddress(senderAci)

        enum RingAction {
            case cancel
            case ring(TSGroupThread)
        }

        let action: RingAction = databaseStorage.read { transaction in
            guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                owsFailDebug("discarding group ring \(ringId) from \(senderAci) for unknown group")
                return .cancel
            }

            guard GroupsV2MessageProcessor.discardMode(
                forMessageFrom: caller,
                groupId: groupId,
                tx: transaction
            ) == .doNotDiscard else {
                Logger.warn("discarding group ring \(ringId) from \(senderAci)")
                return .cancel
            }

            guard thread.groupMembership.fullMembers.count <= RemoteConfig.maxGroupCallRingSize else {
                Logger.warn("discarding group ring \(ringId) from \(senderAci) for too-large group")
                return .cancel
            }

            do {
                if try CancelledGroupRing.exists(transaction.unwrapGrdbRead.database, key: ringId) {
                    return .cancel
                }
            } catch {
                owsFailDebug("unable to check cancellation table: \(error)")
            }

            return .ring(thread)
        }

        switch action {
        case .cancel:
            do {
                try callManager.cancelGroupRing(groupId: groupId, ringId: ringId, reason: nil)
            } catch {
                owsFailDebug("RingRTC failed to cancel group ring \(ringId): \(error)")
            }
        case .ring(let thread):
            let currentCall = self.callServiceState.currentCall
            if currentCall?.thread.uniqueId == thread.uniqueId {
                // We're already ringing or connected, or at the very least already in the lobby.
                return
            }
            guard currentCall == nil else {
                do {
                    try callManager.cancelGroupRing(groupId: groupId, ringId: ringId, reason: .busy)
                } catch {
                    owsFailDebug("RingRTC failed to cancel group ring \(ringId): \(error)")
                }
                return
            }

            // Mute video by default unless the user has already approved it.
            // This keeps us from popping the "give permission to use your camera" alert before the user answers.
            let videoMuted = AVCaptureDevice.authorizationStatus(for: .video) != .authorized
            guard let (call, groupThreadCall) = buildAndConnectGroupCallIfPossible(
                thread: thread,
                videoMuted: videoMuted
            ) else {
                return owsFailDebug("Failed to build group call")
            }

            groupThreadCall.groupCallRingState = .incomingRing(caller: caller, ringId: ringId)

            self.callUIAdapter.reportIncomingCall(call)
        }
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
