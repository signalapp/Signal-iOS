//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
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
    // Even though we never use this, we need to retain it to ensure
    // `callManager` continues to work properly.
    private let callManagerHttpClient: AnyObject

    private var adHocCallRecordManager: any AdHocCallRecordManager { DependenciesBridge.shared.adHocCallRecordManager }
    private let appReadiness: AppReadiness
    private var audioSession: AudioSession { SUIEnvironment.shared.audioSessionRef }
    private var callLinkStore: any CallLinkRecordStore { DependenciesBridge.shared.callLinkStore }
    let authCredentialManager: any AuthCredentialManager
    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }
    private let db: any DB
    private var deviceSleepManager: DeviceSleepManager { DeviceSleepManager.shared }
    private var groupCallManager: GroupCallManager { SSKEnvironment.shared.groupCallManagerRef }
    private var messageSenderJobQueue: MessageSenderJobQueue { SSKEnvironment.shared.messageSenderJobQueueRef }
    private var reachabilityManager: SSKReachabilityManager { SSKEnvironment.shared.reachabilityManagerRef }

    public var callUIAdapter: CallUIAdapter

    let individualCallService: IndividualCallService
    let groupCallRemoteVideoManager: GroupCallRemoteVideoManager
    let callLinkManager: CallLinkManagerImpl
    let callLinkFetcher: CallLinkFetcherImpl
    let callLinkStateUpdater: CallLinkStateUpdater

    private var adHocCallStateObserver: AdHocCallStateObserver?

    /// Needs to be lazily initialized, because it uses singletons that are not
    /// available when this class is initialized.
    private lazy var groupCallAccessoryMessageDelegate: GroupCallAccessoryMessageDelegate = {
        return GroupCallAccessoryMessageHandler(
            databaseStorage: databaseStorage,
            groupCallRecordManager: DependenciesBridge.shared.groupCallRecordManager,
            messageSenderJobQueue: messageSenderJobQueue
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

    @MainActor
    private(set) lazy var audioService: CallAudioService = {
        let result = CallAudioService(audioSession: self.audioSession)
        callServiceState.addObserver(result, syncStateImmediately: true)
        return result
    }()

    public let earlyRingNextIncomingCall = AtomicBool(false, lock: .init())

    let callServiceState: CallServiceState
    var notificationObservers: [any NSObjectProtocol] = []

    @MainActor
    public init(
        appContext: any AppContext,
        appReadiness: AppReadiness,
        authCredentialManager: any AuthCredentialManager,
        callLinkPublicParams: GenericServerPublicParams,
        callLinkStore: any CallLinkRecordStore,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordStore: any CallRecordStore,
        db: any DB,
        mutableCurrentCall: AtomicValue<SignalCall?>,
        networkManager: NetworkManager,
        tsAccountManager: any TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.authCredentialManager = authCredentialManager
        let httpClient = CallHTTPClient()
        self.callManager = CallManager<SignalCall, CallService>(
            httpClient: httpClient.ringRtcHttpClient,
            fieldTrials: RingrtcFieldTrials.trials(with: appContext.appUserDefaults())
        )
        self.callManagerHttpClient = httpClient
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
        self.callLinkFetcher = CallLinkFetcherImpl()
        self.callLinkManager = CallLinkManagerImpl(
            networkManager: networkManager,
            serverParams: callLinkPublicParams,
            tsAccountManager: tsAccountManager
        )
        self.callLinkStateUpdater = CallLinkStateUpdater(
            authCredentialManager: authCredentialManager,
            callLinkFetcher: self.callLinkFetcher,
            callLinkManager: self.callLinkManager,
            callLinkStore: callLinkStore,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordStore: callRecordStore,
            db: db,
            tsAccountManager: tsAccountManager
        )
        self.db = db
        self.callManager.delegate = self
        SwiftSingletons.register(self)
        self.callServiceState.addObserver(self)

        notificationObservers.append(NotificationCenter.default.addObserver(forName: .OWSApplicationDidEnterBackground, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didBecomeActive() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: Self.callServicePreferencesDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureDataMode() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .registrationStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registrationChanged() }
        })

        // Note that we're not using the usual .owsReachabilityChanged
        // We want to update our data mode if the app has been backgrounded
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .reachabilityChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureDataMode() }
        })

        // We don't support a rotating call screen on phones,
        // but we do still want to rotate the various icons.
        if !UIDevice.current.isIPad {
            notificationObservers.append(NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.phoneOrientationDidChange() }
            })
        }

        appReadiness.runNowOrWhenAppWillBecomeReady {
            if let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
                self.callManager.setSelfUuid(localAci.rawUUID)
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

            self.callServiceState.addObserver(self.groupCallAccessoryMessageDelegate, syncStateImmediately: true)
            self.callServiceState.addObserver(self.groupCallRemoteVideoManager, syncStateImmediately: true)
        }
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    @MainActor
    public func rebuildCallUIAdapter() {
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
        case .callLink(let call):
            self.adHocCallStateObserver = nil
            call.removeObserver(self)
        }
        switch newValue?.mode {
        case nil:
            break
        case .individual(let call):
            call.addObserverAndSyncState(self)
        case .groupThread(let call):
            call.addObserver(self, syncStateImmediately: true)
        case .callLink(let call):
            self.adHocCallStateObserver = AdHocCallStateObserver(
                callLinkCall: call,
                adHocCallRecordManager: adHocCallRecordManager,
                callLinkStore: callLinkStore,
                messageSenderJobQueue: messageSenderJobQueue,
                db: db
            )
            call.addObserver(self, syncStateImmediately: true)
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
        case .groupThread, .callLink, nil:
            break
        }

        // To be safe, we reset the early ring on any call change so it's not left set from an unexpected state change.
        earlyRingNextIncomingCall.set(false)
    }

    func callServiceState(_ callServiceState: CallServiceState, didTerminateCall call: SignalCall) {
        if callServiceState.currentCall == nil {
            audioSession.isRTCAudioEnabled = false
        }
        audioSession.endAudioActivity(call.commonState.audioActivity)

        switch call.mode {
        case .individual:
            break
        case .groupThread(let call):
            // Kick off a peek now that we've disconnected to get an updated participant state.
            Task {
                await self.groupCallManager.peekGroupCallAndUpdateThread(
                    call.groupThread,
                    peekTrigger: .localEvent()
                )
            }
        case .callLink:
            break
        }
    }

    // MARK: -

    /**
     * Local user toggled to mute audio.
     */
    @MainActor
    func updateIsLocalAudioMuted(isLocalAudioMuted: Bool) {
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
        guard let frontmostViewController = AppEnvironment.shared.windowManagerRef.callViewWindow.findFrontmostViewController(ignoringAlerts: true) else {
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

    @MainActor
    private func updateIsLocalAudioMutedWithMicrophonePermission(call: SignalCall, isLocalAudioMuted: Bool) {
        owsPrecondition(call === callServiceState.currentCall)

        switch call.mode {
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.ringRtcCall.isOutgoingAudioMuted = isLocalAudioMuted
            call.groupCall(onLocalDeviceStateChanged: call.ringRtcCall)
        case .individual(let individualCall):
            individualCall.isMuted = isLocalAudioMuted
            individualCallService.ensureAudioState(call: call)
        }
    }

    /**
     * Local user toggled video.
     */
    @MainActor
    func updateIsLocalVideoMuted(isLocalVideoMuted: Bool) {
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
        let frontmostViewController = AppEnvironment.shared.windowManagerRef.callViewWindow.findFrontmostViewController(ignoringAlerts: true)
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

    @MainActor
    private func updateIsLocalVideoMutedWithCameraPermissions(call: SignalCall, isLocalVideoMuted: Bool) {
        owsPrecondition(call === callServiceState.currentCall)

        switch call.mode {
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.ringRtcCall.isOutgoingVideoMuted = isLocalVideoMuted
            call.groupCall(onLocalDeviceStateChanged: call.ringRtcCall)
        case .individual(let individualCall):
            individualCall.hasLocalVideo = !isLocalVideoMuted
        }

        updateIsVideoEnabled()
    }

    @MainActor
    func updateCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        call.videoCaptureController.switchCamera(isUsingFrontCamera: isUsingFrontCamera)
    }

    @MainActor
    private func configureDataMode() {
        guard appReadiness.isAppReady else { return }
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
    @MainActor
    public func handleFailedCall(failedCall: SignalCall, error: Error) {
        switch failedCall.mode {
        case .individual:
            individualCallService.handleFailedCall(
                failedCall: failedCall,
                error: error,
                shouldResetUI: false,
                shouldResetRingRTC: true
            )
        case .groupThread(let groupCall as GroupCall), .callLink(let groupCall as GroupCall):
            leaveAndTerminateGroupCall(failedCall, groupCall: groupCall)
        }
    }

    @MainActor
    func handleLocalHangupCall(_ call: SignalCall) {
        switch call.mode {
        case .individual:
            individualCallService.handleLocalHangupCall(call)
        case .groupThread(let groupThreadCall):
            if case .incomingRing(_, let ringId) = groupThreadCall.groupCallRingState {
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
            leaveAndTerminateGroupCall(call, groupCall: groupThreadCall)
        case .callLink(let callLinkCall):
            leaveAndTerminateGroupCall(call, groupCall: callLinkCall)
        }
    }

    // MARK: - Video

    @MainActor
    var shouldHaveLocalVideoTrack: Bool {
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
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return !call.ringRtcCall.isOutgoingVideoMuted
        }
    }

    @MainActor
    func updateIsVideoEnabled() {
        guard let call = self.callServiceState.currentCall else { return }

        switch call.mode {
        case .individual(let individualCall):
            if individualCall.state == .connected || individualCall.state == .reconnecting {
                callManager.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack, call: call)
            } else if individualCall.isViewLoaded, individualCall.hasLocalVideo, !Platform.isSimulator {
                // If we're not yet connected, just enable the camera but don't tell RingRTC
                // to start sending video. This allows us to show a "vanity" view while connecting.
                individualCall.videoCaptureController.startCapture()
            } else {
                individualCall.videoCaptureController.stopCapture()
            }
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            if shouldHaveLocalVideoTrack {
                call.videoCaptureController.startCapture()
            } else {
                call.videoCaptureController.stopCapture()
            }
        }
    }

    // MARK: -

    @MainActor
    func buildAndConnectGroupCall(for thread: TSGroupThread, isVideoMuted: Bool) -> (SignalCall, GroupThreadCall)? {
        owsAssertDebug(thread.groupModel.groupsVersion == .V2)

        return _buildAndConnectGroupCall(isOutgoingVideoMuted: isVideoMuted) { () -> (SignalCall, GroupThreadCall)? in
            let videoCaptureController = VideoCaptureController()
            let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
            let ringRtcCall = callManager.createGroupCall(
                groupId: thread.groupModel.groupId,
                sfuUrl: sfuUrl,
                hkdfExtraInfo: Data(),
                audioLevelsIntervalMillis: nil,
                videoCaptureController: videoCaptureController
            )
            guard let ringRtcCall else {
                return nil
            }
            let groupThreadCall = GroupThreadCall(
                delegate: self,
                ringRtcCall: ringRtcCall,
                groupThread: thread,
                videoCaptureController: videoCaptureController
            )
            return (SignalCall(groupThreadCall: groupThreadCall), groupThreadCall)
        }
    }

    /// Rather than always fetching the current `CallLinkState`,
    /// there may be times when we already have a reasonably
    /// up-to-date copy of the state and do not wish to have to,
    /// say, block UI waiting on a re-fetch. If in doubt, use
    /// `.fetch`. Because that is "so fetch."
    enum CallLinkStateRetrievalStrategy {
        case reuse(SignalServiceKit.CallLinkState)
        case fetch
    }

    @MainActor
    func buildAndConnectCallLinkCall(
        callLink: CallLink,
        callLinkStateRetrievalStrategy: CallLinkStateRetrievalStrategy
    ) async throws -> (SignalCall, CallLinkCall)? {
        let state: SignalServiceKit.CallLinkState
        switch callLinkStateRetrievalStrategy {
        case .reuse(let callLinkState):
            state = callLinkState
        case .fetch:
            state = try await callLinkStateUpdater.readCallLink(rootKey: callLink.rootKey).get()
        }
        let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let (adminPasskey, isDeleted) = try databaseStorage.read { tx -> (Data?, Bool) in
            let callLinkRecord = try callLinkStore.fetch(roomId: callLink.rootKey.deriveRoomId(), tx: tx.asV2Read)
            return (callLinkRecord?.adminPasskey, callLinkRecord?.isDeleted == true)
        }
        if isDeleted {
            throw OWSGenericError("Can't join a call link that you've deleted.")
        }
        return _buildAndConnectGroupCall(isOutgoingVideoMuted: false) { () -> (SignalCall, CallLinkCall)? in
            let videoCaptureController = VideoCaptureController()
            let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
            let secretParams = CallLinkSecretParams.deriveFromRootKey(callLink.rootKey.bytes)
            let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
            let ringRtcCall = callManager.createCallLinkCall(
                sfuUrl: sfuUrl,
                authCredentialPresentation: authCredentialPresentation.serialize(),
                linkRootKey: callLink.rootKey,
                adminPasskey: adminPasskey,
                hkdfExtraInfo: Data(),
                audioLevelsIntervalMillis: nil,
                videoCaptureController: videoCaptureController
            )
            guard let ringRtcCall else {
                return nil
            }
            let callLinkCall = CallLinkCall(
                callLink: callLink,
                adminPasskey: adminPasskey,
                callLinkState: state,
                ringRtcCall: ringRtcCall,
                videoCaptureController: videoCaptureController
            )
            return (SignalCall(callLinkCall: callLinkCall), callLinkCall)
        }
    }

    @MainActor
    private func _buildAndConnectGroupCall<T: GroupCall>(
        isOutgoingVideoMuted: Bool,
        createCall: () -> (SignalCall, T)?
    ) -> (SignalCall, T)? {
        guard callServiceState.currentCall == nil else {
            return nil
        }

        guard let (call, groupCall) = createCall() else {
            owsFailDebug("Failed to create call")
            return nil
        }

        // By default, group calls should start out with speakerphone enabled.
        self.audioService.requestSpeakerphone(isEnabled: true)

        groupCall.ringRtcCall.isOutgoingAudioMuted = false
        groupCall.ringRtcCall.isOutgoingVideoMuted = isOutgoingVideoMuted

        callServiceState.setCurrentCall(call)

        // Connect (but don't join) to subscribe to live updates.
        guard connectGroupCallIfNeeded(groupCall) else {
            callServiceState.terminateCall(call)
            return nil
        }

        return (call, groupCall)
    }

    @MainActor
    func joinGroupCallIfNecessary(_ call: SignalCall, groupCall: GroupCall) {
        guard call === self.callServiceState.currentCall else {
            owsFailDebug("Can't join a group call if it's not the current call")
            return
        }

        // If we're disconnected, it means we hit an error with the first
        // connection, so connect now. (Ex: You try to join a call that's full, and
        // then you try to join again.)
        guard connectGroupCallIfNeeded(groupCall) else {
            owsFailDebug("Can't join a group call if we can't connect()")
            return
        }

        // If we're not yet joined, join now. In general, it's unexpected that
        // this method would be called when you're already joined, but it is
        // safe to do so.
        let ringRtcCall = groupCall.ringRtcCall
        if ringRtcCall.localDeviceState.joinState == .notJoined {
            ringRtcCall.join()
            // Group calls can get disconnected, but we don't count that as ending the call.
            // So this call may have already been reported.
            if groupCall.commonState.systemState == .notReported {
                callUIAdapter.startOutgoingCall(call: call)
            }
        }
    }

    @MainActor
    private func connectGroupCallIfNeeded(_ groupCall: GroupCall) -> Bool {
        if groupCall.hasInvokedConnectMethod {
            return true
        }

        // If we haven't invoked the method, we shouldn't be connected. (Note: The
        // converse is NOT true, and that's why we need `hasInvokedConnectMethod`.)
        owsAssertDebug(groupCall.ringRtcCall.localDeviceState.connectionState == .notConnected)

        let result = groupCall.ringRtcCall.connect()
        if result {
            groupCall.hasInvokedConnectMethod = true
        }
        return result
    }

    /// Leaves the group call & schedules it for termination.
    ///
    /// If the call has already "ended" (RingRTC term), perhaps because we
    /// encountered an error, it will terminate the group call immediately.
    ///
    /// We wait for the call to end before terminating to ensure that observers
    /// have an opportunity to handle the "call ended" event.
    @MainActor
    private func leaveAndTerminateGroupCall(_ call: SignalCall, groupCall: GroupCall) {
        if groupCall.hasInvokedConnectMethod {
            groupCall.ringRtcCall.disconnect()
            groupCall.shouldTerminateOnEndEvent = true
        } else {
            callServiceState.terminateCall(call)
        }
    }

    func initiateCall(to callTarget: CallTarget, isVideo: Bool) {
        switch callTarget {
        case .individual(let contactThread):
            Task { await self.initiateIndividualCall(thread: contactThread, isVideo: isVideo) }
        case .groupThread(let groupThread):
            GroupCallViewController.presentLobby(thread: groupThread, videoMuted: !isVideo)
        case .callLink(let callLink):
            GroupCallViewController.presentLobby(for: callLink)
        }
    }

    @MainActor
    private func initiateIndividualCall(thread: TSContactThread, isVideo: Bool) async {
        let untrustedThreshold = Date(timeIntervalSinceNow: -OWSIdentityManagerImpl.Constants.defaultUntrustedInterval)

        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFail("Can't start a call if there's no view controller")
        }

        guard await CallStarter.prepareToStartCall(from: frontmostViewController, shouldAskForCameraPermission: isVideo) else {
            return
        }

        guard await SafetyNumberConfirmationSheet.presentRepeatedlyAsNecessary(
            for: { [thread.contactAddress] },
            from: frontmostViewController,
            confirmationText: CallStrings.confirmAndCallButtonTitle,
            untrustedThreshold: untrustedThreshold
        ) else {
            return
        }

        self.callUIAdapter.startAndShowOutgoingCall(thread: thread, hasLocalVideo: isVideo)
    }

    func buildOutgoingIndividualCallIfPossible(thread: TSContactThread, hasVideo: Bool) -> (SignalCall, IndividualCall)? {
        AssertIsOnMainThread()
        guard callServiceState.currentCall == nil else { return nil }

        let individualCall = IndividualCall.outgoingIndividualCall(
            thread: thread,
            offerMediaType: hasVideo ? .video : .audio
        )

        let call = SignalCall(individualCall: individualCall)

        return (call, individualCall)
    }

    // MARK: - Notifications

    @MainActor
    private func didEnterBackground() {
        self.updateIsVideoEnabled()
    }

    @MainActor
    private func didBecomeActive() {
        self.updateIsVideoEnabled()
    }

    @MainActor
    private func registrationChanged() {
        if let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
            callManager.setSelfUuid(localAci.rawUUID)
        }
    }

    /// The object is the rotation angle necessary to match the new orientation.
    static var phoneOrientationDidChange = Notification.Name("CallService.phoneOrientationDidChange")

    @MainActor
    private func phoneOrientationDidChange() {
        guard callServiceState.currentCall != nil else {
            return
        }
        sendPhoneOrientationNotification()
    }

    @MainActor
    private func shouldReorientUI(for call: SignalCall) -> Bool {
        owsAssertDebug(!UIDevice.current.isIPad, "iPad has full UIKit rotation support")

        switch call.mode {
        case .individual(let individualCall):
            // If we're in an audio-only 1:1 call, the user isn't going to be looking at the screen.
            // Don't distract them with rotating icons.
            return individualCall.hasLocalVideo || individualCall.isRemoteVideoEnabled
        case .groupThread, .callLink:
            // If we're in a group call, we don't want to use rotating icons because we
            // don't rotate user video at the same time, and that's very obvious for
            // grid view or any non-speaker tile in speaker view.
            return false
        }
    }

    @MainActor
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
    @MainActor
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

extension CallService: GroupCallObserver {
    @MainActor
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {

        let ringRtcCall = call.ringRtcCall

        Logger.info("")
        updateIsVideoEnabled()
        configureDataMode()

        switch call.concreteType {
        case .groupThread(let call):
            updateGroupMembersForCurrentCallIfNecessary()

            if
                ringRtcCall.localDeviceState.isJoined,
                case .shouldRing = call.groupCallRingState,
                call.ringRestrictions.isEmpty,
                ringRtcCall.remoteDeviceStates.isEmpty
            {
                // Don't start ringing until we join the call successfully.
                call.groupCallRingState = .ringing
                ringRtcCall.ringAll()
                audioService.playOutboundRing()
            }

            let groupThread = call.groupThread
            if ringRtcCall.localDeviceState.isJoined {
                if let eraId = ringRtcCall.peekInfo?.eraId {
                    groupCallAccessoryMessageDelegate.localDeviceMaybeJoinedGroupCall(
                        eraId: eraId,
                        groupThread: groupThread,
                        groupCallRingState: call.groupCallRingState
                    )
                }
            } else {
                groupCallAccessoryMessageDelegate.localDeviceMaybeLeftGroupCall(
                    groupThread: groupThread,
                    groupCall: ringRtcCall
                )
            }

        case .callLink:
            self.adHocCallStateObserver!.checkIfJoined()
        }
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()

        let ringRtcCall = call.ringRtcCall
        guard let peekInfo = ringRtcCall.peekInfo else {
            Logger.warn("No peek info for call: \(call)")
            return
        }

        switch call.concreteType {
        case .groupThread(let call):
            let groupThread = call.groupThread

            if
                ringRtcCall.localDeviceState.isJoined,
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
                    triggerEventTimestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                    tx: tx
                )
            }

        case .callLink:
            self.adHocCallStateObserver!.checkIfActive()
            self.adHocCallStateObserver!.checkIfJoined()
        }
    }

    @MainActor
    func groupCallEnded(_ groupCall: GroupCall, reason: GroupCallEndReason) {
        groupCallAccessoryMessageDelegate.localDeviceGroupCallDidEnd()

        let call = callServiceState.currentCall
        switch call?.mode {
        case nil, .individual:
            owsFail("Can't receive callback without an active group call")
        case .groupThread(let currentCall as GroupCall), .callLink(let currentCall as GroupCall):
            owsPrecondition(currentCall === groupCall)
            if currentCall.shouldTerminateOnEndEvent {
                callServiceState.terminateCall(call!)
            }
        }
    }

    @MainActor
    public func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        switch call.concreteType {
        case .groupThread(let call):
            if
                case .ringing = call.groupCallRingState,
                !call.ringRtcCall.remoteDeviceStates.isEmpty
            {
                // The first time someone joins after a ring, we need to mark the call accepted.
                // (But if we didn't ring, the call will have already been marked accepted.)
                callUIAdapter.recipientAcceptedCall(.groupThread(call))
            }
        case .callLink:
            break
        }
    }
}

extension CallService: GroupThreadCallDelegate {
    func groupThreadCallRequestMembershipProof(_ call: GroupThreadCall) {
        Logger.info("")

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

    func groupThreadCallRequestGroupMembers(_ call: GroupThreadCall) {
        Logger.info("")

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
        case .callLink:
            return nil
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
        owsAssertDebug(appReadiness.isAppReady)

        switch callServiceState.currentCall?.mode {
        case nil, .individual, .callLink:
            break
        case .groupThread(let groupThreadCall):
            if databaseChanges.didUpdate(thread: groupThreadCall.groupThread) {
                updateGroupMembersForCurrentCallIfNecessary()
            }
        }
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(appReadiness.isAppReady)

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(appReadiness.isAppReady)

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
        Logger.info("")

        let callAtStart = self.callServiceState.currentCall
        Task {
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)
            await self.sendCallMessage(
                opaqueBuilder.buildInfallibly(),
                to: Aci(fromUUID: recipientUuid),
                callAtStart: callAtStart
            )
        }
    }

    @MainActor
    private func sendCallMessage(
        _ opaqueMessage: SSKProtoCallMessageOpaque,
        to recipientAci: Aci,
        callAtStart: SignalCall?
    ) async {
        do {
            let sendPromise = await databaseStorage.awaitableWrite { transaction in
                let thread = TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(recipientAci),
                    transaction: transaction
                )
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: opaqueMessage,
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
            try await sendPromise.awaitable()
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        } catch {
            self.publishUntrustedIdentityErrorIfNeeded(error, callAtStart: callAtStart)
            Logger.warn("Failed to send opaque message \(error)")
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
        Logger.info("")
        let callAtStart = self.callServiceState.currentCall
        Task {
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)
            opaqueBuilder.setUrgency(urgency.protobufValue)
            await self.sendCallMessageToGroup(
                opaqueBuilder.buildInfallibly(),
                groupId: groupId,
                overrideRecipients: overrideRecipients,
                callAtStart: callAtStart
            )
        }
    }

    @MainActor
    private func sendCallMessageToGroup(
        _ opaqueMessage: SSKProtoCallMessageOpaque,
        groupId: Data,
        overrideRecipients: [UUID],
        callAtStart: SignalCall?
    ) async {
        do {
            let sendPromise = try await self.databaseStorage.awaitableWrite { transaction in
                guard let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    throw OWSAssertionError("tried to send call message to unknown group")
                }
                let overrideRecipients = overrideRecipients.map {
                    return AciObjC(Aci(fromUUID: $0))
                }
                let callMessage = OWSOutgoingCallMessage(
                    thread: thread,
                    opaqueMessage: opaqueMessage,
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
            try await sendPromise.awaitable()
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        } catch {
            self.publishUntrustedIdentityErrorIfNeeded(error, callAtStart: callAtStart)
            Logger.warn("Failed to send opaque message \(error)")
            // TODO: Tell RingRTC something went wrong. API TBD
        }
    }

    @MainActor
    private func publishUntrustedIdentityErrorIfNeeded(_ error: any Error, callAtStart: SignalCall?) {
        guard error is UntrustedIdentityError else {
            return
        }
        switch callAtStart?.mode {
        case nil:
            Logger.warn("The relevant call has already ended.")
        case .individual:
            owsFailDebug("This method isn't implemented for 1:1 calls.")
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            call.handleUntrustedIdentityError()
        }
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldCompareCalls call1: SignalCall,
        call2: SignalCall
    ) -> Bool {
        Logger.info("")
        guard case .individual(let call1) = call1.mode else {
            owsFailDebug("Can't compare multi-participant calls.")
            return false
        }
        guard case .individual(let call2) = call2.mode else {
            owsFailDebug("Can't compare multi-participant calls.")
            return false
        }
        return call1.thread.uniqueId == call2.thread.uniqueId
    }

    // MARK: - 1:1 Call Delegates

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldStartCall call: SignalCall,
        callId: UInt64,
        isOutgoing: Bool,
        callMediaType: CallMediaType
    ) {
        guard callServiceState.currentCall == nil else {
            handleFailedCall(failedCall: call, error: OWSGenericError("a current call is already set"))
            return
        }

        switch call.mode {
        case .individual(let individualCall) where isOutgoing:
            individualCall.setOutgoingCallIdAndUpdateCallRecord(callId)
        case .individual:
            break
        case .groupThread, .callLink:
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

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onEvent call: SignalCall,
        event: CallManagerEvent
    ) {
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
    @MainActor
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
        case .groupThread, .callLink:
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

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendOffer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data,
        callMediaType: CallMediaType
    ) {
        individualCallService.callManager(
            callManager,
            shouldSendOffer: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            opaque: opaque,
            callMediaType: callMediaType
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendAnswer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data
    ) {
        individualCallService.callManager(
            callManager,
            shouldSendAnswer: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            opaque: opaque
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendIceCandidates callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        candidates: [Data]
    ) {
        individualCallService.callManager(
            callManager,
            shouldSendIceCandidates: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            candidates: candidates
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendHangup callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        hangupType: HangupType,
        deviceId: UInt32
    ) {
        individualCallService.callManager(
            callManager,
            shouldSendHangup: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            hangupType: hangupType,
            deviceId: deviceId
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendBusy callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?
    ) {
        individualCallService.callManager(
            callManager,
            shouldSendBusy: callId,
            call: call,
            destinationDeviceId: destinationDeviceId
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onUpdateLocalVideoSession call: SignalCall,
        session: AVCaptureSession?
    ) {
        individualCallService.callManager(
            callManager,
            onUpdateLocalVideoSession: call,
            session: session
        )
    }

    @MainActor
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        onAddRemoteVideoTrack call: SignalCall,
        track: RTCVideoTrack
    ) {
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
    @MainActor
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

                self.leaveAndTerminateGroupCall(currentCall, groupCall: groupThreadCall)
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
                forMessageFrom: senderAci,
                groupId: groupId,
                tx: transaction
            ) == .doNotDiscard else {
                Logger.warn("discarding group ring \(ringId) from \(senderAci)")
                return .cancel
            }

            guard thread.groupMembership.fullMembers.count <= RemoteConfig.current.maxGroupCallRingSize else {
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
            if case .groupThread(let call) = currentCall?.mode, call.groupThread.uniqueId == thread.uniqueId {
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
            guard let (call, groupThreadCall) = buildAndConnectGroupCall(
                for: thread,
                isVideoMuted: videoMuted
            ) else {
                return owsFailDebug("Failed to build group call")
            }

            groupThreadCall.groupCallRingState = .incomingRing(caller: SignalServiceAddress(senderAci), ringId: ringId)

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
