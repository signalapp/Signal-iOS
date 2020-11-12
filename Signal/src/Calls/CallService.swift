//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC
import PromiseKit

// All Observer methods will be invoked from the main thread.
protocol CallServiceObserver: class {
    /**
     * Fired whenever the call changes.
     */
    func didUpdateCall(call: SignalCall?)
}

@objc
public final class CallService: NSObject {
    public typealias CallManagerType = CallManager<SignalCall, CallService>

    public let callManager = CallManagerType()

    private var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    private var audioSession: OWSAudioSession {
        return Environment.shared.audioSession
    }

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private var databaseStorage: SDSDatabaseStorage { .shared }

    @objc
    public let individualCallService = IndividualCallService()

    lazy private(set) var audioService = CallAudioService()

    private var _currentCall: SignalCall?
    @objc
    public private(set) var currentCall: SignalCall? {
        set {
            AssertIsOnMainThread()

            let oldValue = _currentCall
            _currentCall = newValue

            oldValue?.removeObserver(self)
            newValue?.addObserverAndSyncState(observer: self)

            updateIsVideoEnabled()

            // Prevent device from sleeping while we have an active call.
            if oldValue != newValue {
                if let oldValue = oldValue {
                    oldValue.removeObserver(audioService)
                    DeviceSleepManager.shared.removeBlock(blockObject: oldValue)
                }

                if let newValue = newValue {
                    assert(calls.contains(newValue))
                    DeviceSleepManager.shared.addBlock(blockObject: newValue)
                    newValue.addObserverAndSyncState(observer: audioService)

                    if newValue.isIndividualCall { individualCallService.startCallTimer() }
                } else {
                    individualCallService.stopAnyCallTimer()
                }
            }

            Logger.debug("\(oldValue as Optional) -> \(newValue as Optional)")

            for observer in observers.elements {
                observer.didUpdateCall(call: newValue)
            }
        }
        get {
            AssertIsOnMainThread()

            return _currentCall
        }
    }

    /// True whenever CallService has any call in progress.
    /// The call may not yet be visible to the user if we are still in the middle of signaling.
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
    private var calls = Set<SignalCall>() {
        didSet {
            AssertIsOnMainThread()
        }
    }

    public override init() {
        super.init()

        SwiftSingletons.register(self)
        callManager.delegate = self

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

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            SDSDatabaseStorage.shared.appendUIDatabaseSnapshotDelegate(self)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Observers

    private var observers = WeakArray<CallServiceObserver>()

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        observer.didUpdateCall(call: currentCall)
    }

    // The observer-related methods should be invoked on the main thread.
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
            individualCallService.handleFailedCall(failedCall: failedCall, error: callError)
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

        if calls.remove(call) == nil {
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
        }

        // Apparently WebRTC will sometimes disable device orientation notifications.
        // After every call ends, we need to ensure they are enabled.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
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
        calls.insert(call)

        currentCall = call

        call.groupCall.isOutgoingAudioMuted = false
        call.groupCall.isOutgoingVideoMuted = false
        call.groupCall.connect()

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
        if call.groupCall.localDeviceState.connectionState == .notConnected { call.groupCall.connect() }

        // If we're not yet joined, join now. In general, it's unexpected that
        // this method would be called when you're already joined, but it is
        // safe to do so.
        if call.groupCall.localDeviceState.joinState == .notJoined { call.groupCall.join() }
    }

    func buildOutgoingIndividualCallIfPossible(address: SignalServiceAddress, hasVideo: Bool) -> SignalCall? {
        AssertIsOnMainThread()
        guard !hasCallInProgress else { return nil }

        let call = SignalCall.outgoingIndividualCall(localId: UUID(), remoteAddress: address)
        call.individualCall.offerMediaType = hasVideo ? .video : .audio

        calls.insert(call)

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
            localId: UUID(),
            remoteAddress: thread.contactAddress,
            sentAtTimestamp: sentAtTimestamp,
            offerMediaType: offerMediaType
        )

        calls.insert(newCall)

        return newCall
    }

    // MARK: - Notifications

    @objc func didEnterBackground() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()
        self.updateIsVideoEnabled()
    }

    // MARK: -

    private func updateGroupMembersForCurrentCallIfNecessary() {
        guard let call = currentCall, call.isGroupCall else { return }

        guard let groupThread = call.thread as? TSGroupThread,
              let groupModel = groupThread.groupModel as? TSGroupModelV2,
              let groupV2Params = try? groupModel.groupV2Params() else {
            return owsFailDebug("Unexpected group thread.")
        }

        call.groupCall.updateGroupMembers(members: groupThread.groupMembership.fullMembers.compactMap {
            guard let uuid = $0.uuid else {
                owsFailDebug("Skipping group member, missing uuid")
                return nil
            }

            guard let uuidCipherText = try? groupV2Params.userId(forUuid: uuid) else {
                owsFailDebug("Skipping group member, missing uuidCipherText")
                return nil
            }

            return GroupMemberInfo(userId: uuid, userIdCipherText: uuidCipherText)
        })
    }
}

extension CallService: CallObserver {
    public func individualCallStateDidChange(_ call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
    }

    public func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        AssertIsOnMainThread()
        updateIsVideoEnabled()
    }

    public func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    public func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}
    public func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}

    public func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallLocalDeviceStateChanged")
        AssertIsOnMainThread()
        updateIsVideoEnabled()
        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {}
    public func groupCallJoinedMembersChanged(_ call: SignalCall) {}

    public func groupCallRequestMembershipProof(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallUpdateGroupMembershipProof")

        guard call === currentCall else { return cleanupStaleCall(call) }

        guard let groupThread = call.thread as? TSGroupThread,
              let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return owsFailDebug("unexpectedly missing thread")
        }

        do {
            try groupsV2.fetchGroupExternalCredentials(groupModel: groupModel).done(on: .main) { credential in
                guard let tokenData = credential.token?.data(using: .utf8) else {
                    throw OWSAssertionError("Invalid credential")
                }

                call.groupCall.updateMembershipProof(proof: tokenData)
            }.catch { error in
                owsFailDebug("Failed to fetch group call credential \(error)")
            }
        } catch {
            owsFailDebug("Failed to fetch group call credential \(error)")
        }
    }

    public func groupCallRequestGroupMembers(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallUpdateGroupMembers")

        guard call === currentCall else { return cleanupStaleCall(call) }

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        owsAssertDebug(call.isGroupCall)
        Logger.info("groupCallEnded \(reason)")
    }
}

extension CallService: UIDatabaseSnapshotDelegate {
    public func uiDatabaseSnapshotWillUpdate() {}

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard let thread = currentCall?.thread,
              thread.isGroupThread,
              databaseChanges.didUpdate(thread: thread) else { return }

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateGroupMembersForCurrentCallIfNecessary()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateGroupMembersForCurrentCallIfNecessary()
    }
}

extension CallService: CallManagerDelegate {
    public typealias CallManagerDelegateCallType = SignalCall

    /**
     * A call message should be sent to the given remote recipient.
     * Invoked on the main thread, asychronously.
     * If there is any error, the UI can reset UI state and invoke the reset() API.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendCallMessage recipientUuid: UUID,
        message: Data
    ) {
        AssertIsOnMainThread()
        Logger.info("shouldSendCallMessage")

        databaseStorage.write(.promise) { transaction in
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: recipientUuid),
                transaction: transaction
            )
        }.then { thread throws -> Promise<Void> in
            let opaqueBuilder = SSKProtoCallMessageOpaque.builder()
            opaqueBuilder.setData(message)

            let callMessage = OWSOutgoingCallMessage(
                thread: thread,
                opaqueMessage: try opaqueBuilder.build()
            )

            return self.messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done { _ in
            // TODO: Tell RingRTC we succeeded in sending the message. API TBD
        }.catch { error in
            owsFailDebug("Failed to send opaque message \(error)")
            // TODO: Tell RingRTC something went wrong. API TBD
        }
    }

    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendHttpRequest requestId: UInt32,
        url: String,
        method: CallManagerHttpMethod,
        headers: [String: String],
        body: Data?
    ) {
        AssertIsOnMainThread()
        Logger.info("shouldSendHttpRequest")

        let httpMethod: HTTPMethod
        switch method {
        case .get: httpMethod = .get
        case .post: httpMethod = .post
        case .put: httpMethod = .put
        }

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy(),
            configuration: OWSURLSession.defaultURLSessionConfiguration()
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { request in
            var request = request

            if let authHeader = headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                request.addValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }

            return request
        }

        firstly(on: .sharedUtility) {
            session.dataTaskPromise(url, method: httpMethod, headers: headers, body: body)
        }.done(on: .main) { response in
            self.callManager.receivedHttpResponse(
                requestId: requestId,
                statusCode: UInt16(response.statusCode),
                body: response.responseData
            )
        }.catch(on: .main) { error in
            owsFailDebug("Call manager http request failed \(error)")
            self.callManager.httpRequestFailed(requestId: requestId)
        }
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldCompareCalls call1: SignalCall,
        call2: SignalCall
    ) -> Bool {
        Logger.info("shouldCompareCalls")
        return call1.thread?.uniqueId == call2.thread?.uniqueId
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

        // The call to be started is provided by the event.
        currentCall = call

        individualCallService.callManager(
            callManager,
            shouldStartCall: call,
            callId: callId,
            isOutgoing: isOutgoing,
            callMediaType: callMediaType
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

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendOffer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data?,
        sdp: String?,
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
            sdp: sdp,
            callMediaType: callMediaType
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendAnswer callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        opaque: Data?,
        sdp: String?
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendAnswer: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            opaque: opaque,
            sdp: sdp
        )
    }

    public func callManager(
        _ callManager: CallManager<SignalCall, CallService>,
        shouldSendIceCandidates callId: UInt64,
        call: SignalCall,
        destinationDeviceId: UInt32?,
        candidates: [CallManagerIceCandidate]
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
        deviceId: UInt32,
        useLegacyHangupMessage: Bool
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isIndividualCall)

        individualCallService.callManager(
            callManager,
            shouldSendHangup: callId,
            call: call,
            destinationDeviceId: destinationDeviceId,
            hangupType: hangupType,
            deviceId: deviceId,
            useLegacyHangupMessage: useLegacyHangupMessage
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
}
