//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalRingRTC
import WebRTC
import SignalServiceKit
import SignalMessaging

// All Observer methods will be invoked from the main thread.
protocol CallServiceObserver: class {
    /**
     * Fired whenever the call changes.
     */
    func didUpdateCall(call: SignalCall?)

    /**
     * Fired whenever the local or remote video track become active or inactive.
     */
    func didUpdateVideoTracks(call: SignalCall?,
                              localCaptureSession: AVCaptureSession?,
                              remoteVideoTrack: RTCVideoTrack?)
}

// MARK: - CallService

extension SignalCall: CallManagerCallReference { }

// This class' state should only be accessed on the main queue.
@objc final public class CallService: NSObject, CallObserver, CallManagerDelegate {

    public typealias CallManagerDelegateCallType = SignalCall

    // MARK: - Properties

    var observers: WeakArray<CallServiceObserver> = []

    let callManager: CallManager<SignalCall, CallService>

    // Exposed by environment.m

    @objc public var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    // MARK: Ivars

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
                    DeviceSleepManager.sharedInstance.removeBlock(blockObject: oldValue)
                }
                if let newValue = newValue {
                    assert(calls.contains(newValue))
                    DeviceSleepManager.sharedInstance.addBlock(blockObject: newValue)
                    self.startCallTimer()
                } else {
                    stopAnyCallTimer()
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
    private var calls: Set<SignalCall> = [] {
        didSet {
            AssertIsOnMainThread()
        }
    }

    @objc public override init() {
        self.callManager = CallManager<SignalCall, CallService>()

        super.init()

        SwiftSingletons.register(self)

        callManager.delegate = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
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

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    @objc public func createCallUIAdapter() {
        AssertIsOnMainThread()

        guard FeatureFlags.calling else {
            // The CallUIAdapter creates the callkit adaptee which in turn adds calling buttons
            // to the contacts app. They don't do anything, but it seems like they shouldn't be
            // there.
            Logger.info("not creating call UI adapter for device that doesn't support calling")
            return
        }

        if let call = self.currentCall {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            self.terminate(call: call)
        }

        self.callUIAdapter = CallUIAdapter(callService: self, contactsManager: self.contactsManager)
    }

    // MARK: - Call Control Actions

    /**
     * Initiate an outgoing call.
     */
    func handleOutgoingCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        BenchEventStart(title: "Outgoing Call Connection", eventId: "call-\(call.localId)")

        guard self.currentCall == nil else {
            owsFailDebug("call already exists: \(String(describing: self.currentCall))")
            return
        }

        // Create a callRecord for outgoing calls immediately.
        let callRecord = TSCall(callType: .outgoingIncomplete, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
        databaseStorage.write { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.callRecord = callRecord

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = TSAccountManager.sharedInstance().storedDeviceId()

        do {
            // TODO - once the "call as type" feature lands, set the type appropriately
            try callManager.placeCall(call: call, callMediaType: .audioCall, localDevice: localDeviceId)
        } catch {
            self.handleFailedCall(failedCall: call, error: error)
        }
    }

    /**
     * User chose to answer the call. Used by the Callee only.
     */
    public func handleAcceptCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("\(call)")

        guard self.currentCall === call else {
            let error = OWSAssertionError("accepting call: \(call) which is different from currentCall: \(self.currentCall as Optional)")
            handleFailedCall(failedCall: call, error: error)
            return
        }

        guard let callId = call.callId else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("no callId for call: \(call)"))
            return
        }

        let callRecord = TSCall(callType: .incomingIncomplete, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
        databaseStorage.write { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.callRecord = callRecord

        do {
            try callManager.accept(callId: callId)

            // It's key that we configure the AVAudioSession for a call *before* we fulfill the
            // CXAnswerCallAction.
            //
            // Otherwise CallKit has been seen not to activate the audio session.
            // That is, `provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession)`
            // was sometimes not called.`
            //
            // That is why we connect here, rather than waiting for a racy async response from CallManager,
            // confirming that the call has connected.
            handleConnected(call: call)
        } catch {
            self.handleFailedCall(failedCall: call, error: error)
        }
    }

    func buildOutgoingCallIfAvailable(address: SignalServiceAddress) -> SignalCall? {
        AssertIsOnMainThread()
        guard !hasCallInProgress else {
            return nil
        }

        let call = SignalCall.outgoingCall(localId: UUID(), remoteAddress: address)
        calls.insert(call)

        return call
    }

    /**
     * Local user chose to end the call.
     */
    func handleLocalHangupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("\(call)")

        guard call === self.currentCall else {
            Logger.info("ignoring hangup for obsolete call: \(call)")
            return
        }

        if let callRecord = call.callRecord {
            if callRecord.callType == .outgoingIncomplete {
                callRecord.updateCallType(.outgoingMissed)
            }
        } else if call.state == .localRinging {
            let callRecord = TSCall(callType: .incomingDeclined, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }
            call.callRecord = callRecord
        } else {
            owsFailDebug("missing call record")
        }

        call.state = .localHangup

        ensureAudioState(call: call)

        terminate(call: call)

        do {
            try callManager.hangup()
        } catch {
            // no point in "failing" the call if the user expressed their intent to hang up
            // and we've already called: `terminate(call: cal)`
            owsFailDebug("error: \(error)")
        }
    }

    /**
     * Local user toggled to mute audio.
     */
    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        call.isMuted = isMuted

        ensureAudioState(call: call)
    }

    /**
     * Local user toggled video.
     */
    func setHasLocalVideo(hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        // This method can be initiated either from the CallViewController.videoButton or via CallKit
        // in either case we want to show the alert on the callViewWindow.
        guard let frontmostViewController =
                UIApplication.shared.findFrontmostViewController(ignoringAlerts: true,
                                                                 window: OWSWindowManager.shared.callViewWindow) else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        // Keep a reference to the call before permissions were requested...
        guard let call = self.currentCall else {
            owsFailDebug("missing currentCall")
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
                self.setHasLocalVideoWithCameraPermissions(call: call, hasLocalVideo: hasLocalVideo)
            }
        }
    }

    func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        callManager.setCameraSource(isUsingFrontCamera: isUsingFrontCamera)
    }

    // MARK: - Signaling Functions

    /**
     * Received an incoming call Offer from call initiator.
     */
    public func handleReceivedOffer(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, sdp: String?, opaque: Data?, sentAtTimestamp: UInt64, callType: SSKProtoCallMessageOfferType, supportsMultiRing: Bool) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let newCall = SignalCall.incomingCall(localId: UUID(), remoteAddress: thread.contactAddress, sentAtTimestamp: sentAtTimestamp)
        calls.insert(newCall)
        BenchEventStart(title: "Incoming Call Connection", eventId: "call-\(newCall.localId)")

        guard tsAccountManager.isOnboarded() else {
            Logger.warn("user is not onboarded, skipping call.")
            let callRecord = TSCall(callType: .incomingMissed, thread: thread, sentAtTimestamp: sentAtTimestamp)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.state = .localFailure
            terminate(call: newCall)

            return
        }

        if let untrustedIdentity = OWSIdentityManager.shared().untrustedIdentityForSending(to: thread.contactAddress) {
            Logger.warn("missed a call due to untrusted identity: \(newCall)")

            let callerName = self.contactsManager.displayName(for: thread.contactAddress)

            switch untrustedIdentity.verificationState {
            case .verified:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                self.notificationPresenter.presentMissedCall(newCall, callerName: callerName)
            case .default:
                self.notificationPresenter.presentMissedCallBecauseOfNewIdentity(call: newCall, callerName: callerName)
            case .noLongerVerified:
                self.notificationPresenter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: newCall, callerName: callerName)
            }

            let callRecord = TSCall(callType: .incomingMissedBecauseOfChangedIdentity, thread: thread, sentAtTimestamp: sentAtTimestamp)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.state = .localFailure
            terminate(call: newCall)

            return
        }

        guard allowsInboundCallsInThread(thread) else {
            Logger.info("Ignoring call offer from \(thread.contactAddress) due to insufficient permissions.")

            // Send the need permission message to the caller, so they know why we rejected their call.
            callManager(
                callManager,
                shouldSendHangup: callId,
                call: newCall,
                destinationDeviceId: sourceDevice,
                hangupType: .needPermission,
                deviceId: tsAccountManager.storedDeviceId(),
                useLegacyHangupMessage: true
            )

            // Store the call as a missed call for the local user. They will see it in the conversation
            // along with the message request dialog. When they accept the dialog, they can call back
            // or the caller can try again.
            let callRecord = TSCall(callType: .incomingMissed, thread: thread, sentAtTimestamp: sentAtTimestamp)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            newCall.state = .localFailure
            terminate(call: newCall)

            return
        }

        Logger.debug("Enable backgroundTask")
        let backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            // See if the newCall actually became the currentCall.
            guard self.currentCall === newCall else {
                Logger.warn("ignoring obsolete call")
                return
            }

            self.handleFailedCall(failedCall: newCall, error: CallError.timeout(description: "background task time ran out before call connected"))
        })

        newCall.backgroundTask = backgroundTask

        // TODO - Need to calculate the "message age" when ready
        let messageAgeSec: UInt64 = 0

        let callMediaType: CallMediaType
        switch callType {
        case .offerAudioCall: callMediaType = .audioCall
        case .offerVideoCall: callMediaType = .videoCall
        }

        // Get the current local device Id, must be valid for lifetime of the call.
        let localDeviceId = TSAccountManager.sharedInstance().storedDeviceId()
        let isPrimaryDevice = TSAccountManager.sharedInstance().isPrimaryDevice

        do {
            try callManager.receivedOffer(call: newCall, sourceDevice: sourceDevice, callId: callId, opaque: opaque, sdp: sdp, messageAgeSec: messageAgeSec, callMediaType: callMediaType, localDevice: localDeviceId, remoteSupportsMultiRing: supportsMultiRing, isLocalDevicePrimary: isPrimaryDevice)
        } catch {
            handleFailedCall(failedCall: newCall, error: error)
        }
    }

    private func allowsInboundCallsInThread(_ thread: TSContactThread) -> Bool {
        return databaseStorage.read { transaction in
            // IFF one of the following things is true, we can handle inbound call offers
            // * The thread is in our profile whitelist
            // * The thread belongs to someone in our system contacts
            // * The thread existed before messages requests
            return SSKEnvironment.shared.profileManager.isThread(inProfileWhitelist: thread, transaction: transaction)
                || self.contactsManager.isSystemContact(address: thread.contactAddress)
                || GRDBThreadFinder.isPreMessageRequestsThread(thread, transaction: transaction.unwrapGrdbRead)
        }
    }

    /**
     * Called by the call initiator after receiving an Answer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, sdp: String?, opaque: Data?, supportsMultiRing: Bool) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        do {
            try callManager.receivedAnswer(sourceDevice: sourceDevice, callId: callId, opaque: opaque, sdp: sdp, remoteSupportsMultiRing: supportsMultiRing)
        } catch {
            owsFailDebug("error: \(error)")
            if let currentCall = currentCall, currentCall.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error)
            }
        }
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update.
     */
    public func handleReceivedIceCandidates(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, candidates: [SSKProtoCallMessageIceUpdate]) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let iceCandidates = candidates.filter { $0.id == callId }.map { candidate in
            CallManagerIceCandidate(opaque: candidate.opaque, sdp: candidate.sdp)
        }

        do {
            try callManager.receivedIceCandidates(sourceDevice: sourceDevice, callId: callId, candidates: iceCandidates)
        } catch {
            owsFailDebug("error: \(error)")
            // we don't necessarily want to fail the call just because CallManager errored on an
            // ICE candidate
        }
    }

    /**
     * The remote client (caller or callee) ended the call.
     */
    public func handleReceivedHangup(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32, type: SSKProtoCallMessageHangupType, deviceId: UInt32) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        let hangupType: HangupType
        switch type {
        case .hangupNormal: hangupType = .normal
        case .hangupAccepted: hangupType = .accepted
        case .hangupDeclined: hangupType = .declined
        case .hangupBusy: hangupType = .busy
        case .hangupNeedPermission: hangupType = .needPermission
        }

        do {
            try callManager.receivedHangup(sourceDevice: sourceDevice, callId: callId, hangupType: hangupType, deviceId: deviceId)
        } catch {
            owsFailDebug("\(error)")
            if let currentCall = currentCall, currentCall.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error)
            }
        }
    }

    /**
     * The callee was already in another call.
     */
    public func handleReceivedBusy(thread: TSContactThread, callId: UInt64, sourceDevice: UInt32) {
        AssertIsOnMainThread()
        Logger.info("callId: \(callId), thread: \(thread.contactAddress)")

        do {
            try callManager.receivedBusy(sourceDevice: sourceDevice, callId: callId)
        } catch {
            owsFailDebug("\(error)")
            if let currentCall = currentCall, currentCall.callId == callId {
                handleFailedCall(failedCall: currentCall, error: error)
            }
        }
    }

    // MARK: - Call Manager Events

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldStartCall call: SignalCall, callId: UInt64, isOutgoing: Bool, callMediaType: CallMediaType) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard FeatureFlags.calling else {
            owsFailDebug("ignoring call event on unsupported device")
            return
        }

        guard self.currentCall == nil else {
            handleFailedCall(failedCall: call, error: OWSAssertionError("a current call is already set"))
            return
        }

        if !calls.contains(call) {
            owsFailDebug("unknown call: \(call)")
        }

        call.callId = callId

        // The call to be started is provided by the event.
        self.currentCall = call

        // Start the call, asynchronously.
        getIceServers().done { iceServers in
            guard self.currentCall === call else {
                Logger.debug("call has since ended")
                return
            }

            var isUnknownCaller = false
            if call.direction == .incoming {
                isUnknownCaller = !self.contactsManager.hasSignalAccount(for: call.thread.contactAddress)
            }

            let useTurnOnly = isUnknownCaller || Environment.shared.preferences.doCallsHideIPAddress()

            // Tell the Call Manager to proceed with its active call.
            try self.callManager.proceed(callId: callId, iceServers: iceServers, hideIp: useTurnOnly)
        }.catch { error in
            owsFailDebug("\(error)")
            guard call === self.currentCall else {
                Logger.debug("")
                return
            }

            callManager.drop(callId: callId)
            self.handleFailedCall(failedCall: call, error: error)
        }

        Logger.debug("")
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, onEvent call: SignalCall, event: CallManagerEvent) {
        AssertIsOnMainThread()
        Logger.info("call: \(call), onEvent: \(event)")

        guard FeatureFlags.calling else {
            owsFailDebug("ignoring call event on unsupported device")
            return
        }

        switch event {
        case .ringingLocal:
            handleRinging(call: call)

        case .ringingRemote:
            handleRinging(call: call)

        case .connectedLocal:
            Logger.debug("")
            // nothing further to do - already handled in handleAcceptCall().

        case .connectedRemote:
            callUIAdapter.recipientAcceptedCall(call)
            handleConnected(call: call)

        case .endedLocalHangup:
            Logger.debug("")
            // nothing further to do - already handled in handleLocalHangupCall().

        case .endedRemoteHangup:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            switch call.state {
            case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
                handleMissedCall(call)
            case .connected, .reconnecting, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
                Logger.info("call is finished")
            }

            call.state = .remoteHangup

            // Notify UI
            callUIAdapter.remoteDidHangupCall(call)

            terminate(call: call)

        case .endedRemoteHangupNeedPermission:
            guard call === currentCall else {
                cleanupStaleCall(call)
                return
            }

            switch call.state {
            case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
                handleMissedCall(call)
            case .connected, .reconnecting, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
                Logger.info("call is finished")
            }

            call.state = .remoteHangupNeedPermission

            // Notify UI
            callUIAdapter.remoteDidHangupCall(call)

            terminate(call: call)

        case .endedRemoteHangupAccepted:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            switch call.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupAccepted: \(call.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but answered somewhere else first. state: \(call.state)")
                handleAnsweredElsewhere(call: call)
            case .localRinging, .reconnecting:
                handleAnsweredElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupAccepted' since call is already finished")
            }

        case .endedRemoteHangupDeclined:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            switch call.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupDeclined: \(call.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but declined somewhere else first. state: \(call.state)")
                handleDeclinedElsewhere(call: call)
            case .localRinging, .reconnecting:
                handleDeclinedElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupDeclined' since call is already finished")
            }

        case .endedRemoteHangupBusy:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            switch call.state {
            case .idle, .dialing, .remoteBusy, .remoteRinging, .answeredElsewhere, .declinedElsewhere, .busyElsewhere, .remoteHangup, .remoteHangupNeedPermission:
                handleFailedCall(failedCall: call, error: OWSAssertionError("unexpected state for endedRemoteHangupBusy: \(call.state)"))
                return
            case .answering, .connected:
                Logger.info("tried answering locally, but already in a call somewhere else first. state: \(call.state)")
                handleBusyElsewhere(call: call)
            case .localRinging, .reconnecting:
                handleBusyElsewhere(call: call)
            case  .localFailure, .localHangup:
                Logger.info("ignoring 'endedRemoteHangupBusy' since call is already finished")
            }

        case .endedRemoteBusy:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            assert(call.direction == .outgoing)
            if let callRecord = call.callRecord {
                callRecord.updateCallType(.outgoingMissed)
            } else {
                owsFailDebug("outgoing call should have call record")
            }

            call.state = .remoteBusy

            // Notify UI
            callUIAdapter.remoteBusy(call)

            terminate(call: call)

        case .endedRemoteGlare:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            if let callRecord = call.callRecord {
                switch callRecord.callType {
                case .outgoingMissed, .incomingDeclined, .incomingMissed, .incomingMissedBecauseOfChangedIdentity, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere:
                    // already handled and ended, don't update the call record.
                    break
                case .incomingIncomplete, .incoming:
                    callRecord.updateCallType(.incomingMissed)
                    callUIAdapter.reportMissedCall(call)
                case .outgoingIncomplete:
                    callRecord.updateCallType(.outgoingMissed)
                    callUIAdapter.remoteBusy(call)
                case .outgoing:
                    callRecord.updateCallType(.outgoingMissed)
                    callUIAdapter.reportMissedCall(call)
                @unknown default:
                    owsFailDebug("unknown RPRecentCallType: \(callRecord.callType)")
                }
            } else {
                assert(call.direction == .incoming)
                let callRecord = TSCall(callType: .incomingMissed, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
                databaseStorage.write { callRecord.anyInsert(transaction: $0) }
                call.callRecord = callRecord
                callUIAdapter.reportMissedCall(call)
            }
            call.state = .localFailure
            terminate(call: call)

        case .endedTimeout:
            let description: String

            if call.direction == .outgoing {
                description = "timeout for outgoing call"
            } else {
                description = "timeout for incoming call"
            }

            handleFailedCall(failedCall: call, error: CallError.timeout(description: description))

        case .endedSignalingFailure:
            handleFailedCall(failedCall: call, error: CallError.timeout(description: "signaling failure for call"))

        case .endedInternalFailure:
            handleFailedCall(failedCall: call, error: OWSAssertionError("call manager internal error"))

        case .endedConnectionFailure:
            handleFailedCall(failedCall: call, error: CallError.disconnected)

        case .endedDropped:
            Logger.debug("")

            // An incoming call was dropped, ignoring because we have already
            // failed the call on the screen.

        case .remoteVideoEnable:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            call.isRemoteVideoEnabled = true
            fireDidUpdateVideoTracks()

        case .remoteVideoDisable:
            guard call === self.currentCall else {
                cleanupStaleCall(call)
                return
            }

            call.isRemoteVideoEnabled = false
            fireDidUpdateVideoTracks()

        case .reconnecting:
            self.handleReconnecting(call: call)

        case .reconnected:
            self.handleReconnected(call: call)

        case .endedReceivedOfferExpired:
            // TODO - This is the case where an incoming offer's timestamp is
            // not within the range +/- 120 seconds of the current system time.
            // At the moment, this is not an issue since we are currently setting
            // the timestamp separately when we receive the offer (above).
            handleMissedCall(call)
            call.state = .localFailure
            terminate(call: call)

        case .endedReceivedOfferWhileActive:
            handleMissedCall(call)
            call.state = .localFailure
            terminate(call: call)

        case .endedIgnoreCallsFromNonMultiringCallers:
            handleMissedCall(call)
            call.state = .localFailure
            terminate(call: call)
        }
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, onUpdateLocalVideoSession call: SignalCall, session: AVCaptureSession?) {
        AssertIsOnMainThread()
        Logger.info("onUpdateLocalVideoSession")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        call.localCaptureSession = session
        fireDidUpdateVideoTracks()
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, onAddRemoteVideoTrack call: SignalCall, track: RTCVideoTrack) {
        AssertIsOnMainThread()
        Logger.info("onAddRemoteVideoTrack")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        call.remoteVideoTrack = track
        fireDidUpdateVideoTracks()
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldCompareCalls call1: SignalCall, call2: SignalCall) -> Bool {
        // May not be on the main thread.
        Logger.info("shouldCompareCalls")
        return call1.remoteAddress == call2.remoteAddress
    }

    // MARK: - Call Manager Signaling

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldSendOffer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data?, sdp: String?, callMediaType: CallMediaType) {
        AssertIsOnMainThread()
        Logger.info("shouldSendOffer")

        firstly { () throws -> Promise<Void> in
            let offerBuilder = SSKProtoCallMessageOffer.builder(id: callId)
            if let opaque = opaque { offerBuilder.setOpaque(opaque) }
            if let sdp = sdp { offerBuilder.setSdp(sdp) }
            switch callMediaType {
            case .audioCall: offerBuilder.setType(.offerAudioCall)
            case .videoCall: offerBuilder.setType(.offerVideoCall)
            }
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, offerMessage: try offerBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.info("sent offer message to \(call.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send offer message to \(call.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldSendAnswer callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, opaque: Data?, sdp: String?) {
        AssertIsOnMainThread()
        Logger.info("shouldSendAnswer")

        firstly { () throws -> Promise<Void> in
            let answerBuilder = SSKProtoCallMessageAnswer.builder(id: callId)
            if let opaque = opaque { answerBuilder.setOpaque(opaque) }
            if let sdp = sdp { answerBuilder.setSdp(sdp) }
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, answerMessage: try answerBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent answer message to \(call.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send answer message to \(call.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldSendIceCandidates callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, candidates: [CallManagerIceCandidate]) {
        AssertIsOnMainThread()
        Logger.info("shouldSendIceCandidates")

        firstly { () throws -> Promise<Void> in
            var iceUpdateProtos = [SSKProtoCallMessageIceUpdate]()

            for iceCandidate in candidates {
                let iceUpdateProto: SSKProtoCallMessageIceUpdate
                let iceUpdateBuilder = SSKProtoCallMessageIceUpdate.builder(id: callId)
                if let opaque = iceCandidate.opaque { iceUpdateBuilder.setOpaque(opaque) }
                if let sdp = iceCandidate.sdp { iceUpdateBuilder.setSdp(sdp) }

                // Hardcode fields for older clients; remove after appropriate time period.
                iceUpdateBuilder.setLine(0)
                iceUpdateBuilder.setMid("audio")

                iceUpdateProto = try iceUpdateBuilder.build()
                iceUpdateProtos.append(iceUpdateProto)
            }

            guard !iceUpdateProtos.isEmpty else {
                throw OWSAssertionError("no ice updates to send")
            }

            let callMessage = OWSOutgoingCallMessage(thread: call.thread, iceUpdateMessages: iceUpdateProtos, destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent ice update message to \(call.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send ice update message to \(call.thread.contactAddress) with error: \(error)")
            callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldSendHangup callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?, hangupType: HangupType, deviceId: UInt32, useLegacyHangupMessage: Bool) {
        AssertIsOnMainThread()
        Logger.info("shouldSendHangup")

        firstly { () throws -> Promise<Void> in
            let hangupBuilder = SSKProtoCallMessageHangup.builder(id: callId)

            switch hangupType {
            case .normal: hangupBuilder.setType(.hangupNormal)
            case .accepted: hangupBuilder.setType(.hangupAccepted)
            case .declined: hangupBuilder.setType(.hangupDeclined)
            case .busy: hangupBuilder.setType(.hangupBusy)
            case .needPermission: hangupBuilder.setType(.hangupNeedPermission)
            }

            if hangupType != .normal {
                // deviceId is optional and only used when indicated by a hangup due to
                // a call being accepted elsewhere.
                hangupBuilder.setDeviceID(deviceId)
            }

            let callMessage: OWSOutgoingCallMessage
            if useLegacyHangupMessage {
                callMessage = OWSOutgoingCallMessage(thread: call.thread, legacyHangupMessage: try hangupBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            } else {
                callMessage = OWSOutgoingCallMessage(thread: call.thread, hangupMessage: try hangupBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            }
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent hangup message to \(call.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send hangup message to \(call.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    public func callManager(_ callManager: CallManager<SignalCall, CallService>, shouldSendBusy callId: UInt64, call: SignalCall, destinationDeviceId: UInt32?) {
        AssertIsOnMainThread()
        Logger.info("shouldSendBusy")

        firstly { () throws -> Promise<Void> in
            let busyBuilder = SSKProtoCallMessageBusy.builder(id: callId)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, busyMessage: try busyBuilder.build(), destinationDeviceId: NSNumber(value: destinationDeviceId))
            return messageSender.sendMessage(.promise, callMessage.asPreparer)
        }.done {
            Logger.debug("sent busy message to \(call.thread.contactAddress) device: \((destinationDeviceId != nil) ? String(destinationDeviceId!) : "nil")")
            try self.callManager.signalingMessageDidSend(callId: callId)
        }.catch { error in
            Logger.error("failed to send busy message to \(call.thread.contactAddress) with error: \(error)")
            self.callManager.signalingMessageDidFail(callId: callId)
        }
    }

    // MARK: - Support Functions

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        let callRecord: TSCall
        if let existingCallRecord = call.callRecord {
            callRecord = existingCallRecord
        } else {
            callRecord = TSCall(callType: .incomingMissed, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
            call.callRecord = callRecord
        }

        switch callRecord.callType {
        case .incomingMissed:
            databaseStorage.write { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
            callUIAdapter.reportMissedCall(call)
        case .incomingIncomplete, .incoming:
            callRecord.updateCallType(.incomingMissed)
            callUIAdapter.reportMissedCall(call)
        case .outgoingIncomplete:
            callRecord.updateCallType(.outgoingMissed)
        case .incomingMissedBecauseOfChangedIdentity, .incomingDeclined, .outgoingMissed, .outgoing, .incomingAnsweredElsewhere, .incomingDeclinedElsewhere, .incomingBusyElsewhere:
            owsFailDebug("unexpected RPRecentCallType: \(callRecord.callType)")
            databaseStorage.write { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
        @unknown default:
            databaseStorage.write { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
            owsFailDebug("unknown RPRecentCallType: \(callRecord.callType)")
        }
    }

    func handleAnsweredElsewhere(call: SignalCall) {
        if let existingCallRecord = call.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingAnsweredElsewhere)
        } else {
            let callRecord = TSCall(callType: .incomingAnsweredElsewhere, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
            call.callRecord = callRecord
            databaseStorage.write { callRecord.anyInsert(transaction: $0) }
        }

        call.state = .answeredElsewhere

        // Notify UI
        callUIAdapter.didAnswerElsewhere(call: call)

        terminate(call: call)
    }

    func handleDeclinedElsewhere(call: SignalCall) {
        if let existingCallRecord = call.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingDeclinedElsewhere)
        } else {
            let callRecord = TSCall(callType: .incomingDeclinedElsewhere, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
            call.callRecord = callRecord
            databaseStorage.write { callRecord.anyInsert(transaction: $0) }
        }

        call.state = .declinedElsewhere

        // Notify UI
        callUIAdapter.didDeclineElsewhere(call: call)

        terminate(call: call)
    }

    func handleBusyElsewhere(call: SignalCall) {
        if let existingCallRecord = call.callRecord {
            // There should only be an existing call record due to a race where the call is answered
            // simultaneously on multiple devices, and the caller is proceeding with the *other*
            // devices call.
            existingCallRecord.updateCallType(.incomingBusyElsewhere)
        } else {
            let callRecord = TSCall(callType: .incomingBusyElsewhere, thread: call.thread, sentAtTimestamp: call.sentAtTimestamp)
            call.callRecord = callRecord
            databaseStorage.write { callRecord.anyInsert(transaction: $0) }
        }

        call.state = .busyElsewhere

        // Notify UI
        callUIAdapter.reportMissedCall(call)

        terminate(call: call)
    }

    /**
     * The clients can now communicate via WebRTC, so we can let the UI know.
     *
     * Called by both caller and callee. Compatible ICE messages have been exchanged between the local and remote
     * client.
     */
    private func handleRinging(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        switch call.state {
        case .dialing:
            if call.state != .remoteRinging {
                BenchEventComplete(eventId: "call-\(call.localId)")
            }
            call.state = .remoteRinging
        case .answering:
            if call.state != .localRinging {
                BenchEventComplete(eventId: "call-\(call.localId)")
            }
            call.state = .localRinging
            self.callUIAdapter.reportIncomingCall(call, thread: call.thread)
        case .remoteRinging:
            Logger.info("call already ringing. Ignoring \(#function): \(call).")
        case .idle, .localRinging, .connected, .reconnecting, .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            owsFailDebug("unexpected call state: \(call.state): \(call).")
        }
    }

    private func handleReconnecting(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        switch call.state {
        case .remoteRinging, .localRinging:
            Logger.debug("disconnect while ringing... we'll keep ringing")
        case .connected:
            call.state = .reconnecting
        default:
            owsFailDebug("unexpected call state: \(call.state): \(call).")
        }
    }

    private func handleReconnected(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        switch call.state {
        case .reconnecting:
            call.state = .connected
        default:
            owsFailDebug("unexpected call state: \(call.state): \(call).")
        }
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    private func handleConnected(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        // End the background task.
        call.backgroundTask = nil

        call.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        ensureAudioState(call: call)
        callManager.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack(), call: call)
    }

    /**
     * Local user toggled to hold call. Currently only possible via CallKit screen,
     * e.g. when another Call comes in.
     */
    func setIsOnHold(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        Logger.info("call: \(call)")

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        call.isOnHold = isOnHold

        ensureAudioState(call: call)
    }

    func ensureAudioState(call: SignalCall) {
        guard call.state == .connected else {
            self.callManager.setLocalAudioEnabled(enabled: false)
            return
        }
        guard !call.isMuted else {
            self.callManager.setLocalAudioEnabled(enabled: false)
            return
        }
        guard !call.isOnHold else {
            self.callManager.setLocalAudioEnabled(enabled: false)
            return
        }

        self.callManager.setLocalAudioEnabled(enabled: true)
    }

    private func setHasLocalVideoWithCameraPermissions(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard call === self.currentCall else {
            cleanupStaleCall(call)
            return
        }

        call.hasLocalVideo = hasLocalVideo
        if call.state == .connected {
            callManager.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack(), call: call)
        }
    }

    @objc
    func handleCallKitStartVideo() {
        AssertIsOnMainThread()

        self.setHasLocalVideo(hasLocalVideo: true)
    }

    /**
     * RTCIceServers are used when attempting to establish an optimal connection to the other party. SignalService supplies
     * a list of servers, plus we have fallback servers hardcoded in the app.
     */
    private func getIceServers() -> Promise<[RTCIceServer]> {

        return self.accountManager.getTurnServerInfo()
        .map(on: DispatchQueue.global()) { turnServerInfo -> [RTCIceServer] in
            Logger.debug("got turn server urls: \(turnServerInfo.urls)")

            return turnServerInfo.urls.map { url in
                if url.hasPrefix("turn") {
                    // Only "turn:" servers require authentication. Don't include the credentials to other ICE servers
                    // as 1.) they aren't used, and 2.) the non-turn servers might not be under our control.
                    // e.g. we use a public fallback STUN server.
                    return RTCIceServer(urlStrings: [url], username: turnServerInfo.username, credential: turnServerInfo.password)
                } else {
                    return RTCIceServer(urlStrings: [url])
                }
            } + [CallService.fallbackIceServer]
        }.recover(on: .global()) { (error: Error) -> Guarantee<[RTCIceServer]> in
            Logger.error("fetching ICE servers failed with error: \(error)")
            Logger.warn("using fallback ICE Servers")

            return Guarantee.value([CallService.fallbackIceServer])
        }
    }

    public func handleCallKitProviderReset() {
        AssertIsOnMainThread()
        Logger.debug("")

        // Return to a known good state by ending the current call, if any.
        if let call = self.currentCall {
            handleFailedCall(failedCall: call, error: CallError.providerReset)
        }
        callManager.reset()
    }

    func cleanupStaleCall(_ staleCall: SignalCall, function: StaticString = #function, line: UInt = #line) {
        assert(staleCall != self.currentCall)
        if let currentCall = self.currentCall {
            let error = OWSAssertionError("trying \(function):\(line) for call: \(staleCall) which is not currentCall: \(currentCall as Optional)")
            handleFailedCall(failedCall: staleCall, error: error)
        } else {
            Logger.info("ignoring \(function):\(line) for call: \(staleCall) since currentCall has ended.")
            assert(staleCall.isEnded)
        }
    }

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall, error: Error) {
        AssertIsOnMainThread()
        Logger.debug("")

        let callError: CallError = {
            switch error {
            case let callError as CallError:
                return callError
            default:
                return CallError.externalError(underlyingError: error)
            }
        }()

        switch failedCall.state {
        case .answering, .localRinging:
            assert(failedCall.callRecord == nil)
            // call failed before any call record could be created, make one now.
            handleMissedCall(failedCall)
        default:
            assert(failedCall.callRecord != nil)
        }

        guard !failedCall.isEnded else {
            Logger.debug("ignoring error: \(error) for already terminated call: \(failedCall)")
            return
        }

        failedCall.error = callError
        failedCall.state = .localFailure
        self.callUIAdapter.failCall(failedCall, error: callError)

        Logger.error("call: \(failedCall) failed with error: \(error)")
        terminate(call: failedCall)
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    private func terminate(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call as Optional)")
        assert(call.isEnded)

        // If call is for the current call, clear it out first.
        if self.currentCall === call {
            fireDidUpdateVideoTracks()
            self.currentCall = nil
        }

        if calls.remove(call) == nil {
            owsFailDebug("unknown call: \(call)")
        }

        call.terminate()
        callUIAdapter.didTerminateCall(call, hasCallInProgress: self.hasCallInProgress)

        // Apparently WebRTC will sometimes disable device orientation notifications.
        // After every call ends, we need to ensure they are enabled.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    // MARK: - CallObserver

    public func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("\(state)")

        updateIsVideoEnabled()
    }

    public func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.info("\(hasLocalVideo)")

        self.updateIsVideoEnabled()
    }

    public func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        // Do nothing
    }

    public func holdDidChange(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        // Do nothing
    }

    public func audioSourceDidChange(call: SignalCall, audioSource: AudioSource?) {
        AssertIsOnMainThread()
        // Do nothing
    }

    // MARK: - Video

    private func shouldHaveLocalVideoTrack() -> Bool {
        AssertIsOnMainThread()

        guard let call = self.currentCall else {
            return false
        }

        // The iOS simulator doesn't provide any sort of camera capture
        // support or emulation (http://goo.gl/rHAnC1) so don't bother
        // trying to open a local stream.
        return (!Platform.isSimulator &&
            UIApplication.shared.applicationState != .background &&
            call.state == .connected &&
            call.hasLocalVideo)
    }

    private func updateIsVideoEnabled() {
        AssertIsOnMainThread()

        guard let call = self.currentCall else {
            return
        }

        if call.state == .connected || call.state == .reconnecting {
            callManager.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack(), call: call)
        }
    }

    // MARK: - Observers

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        fireDidUpdateVideoTracks(forObserver: observer)
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

    private func fireDidUpdateVideoTracks() {
        AssertIsOnMainThread()

        for observer in observers.elements {
            fireDidUpdateVideoTracks(forObserver: observer)
        }
    }

    private func fireDidUpdateVideoTracks(forObserver observer: CallServiceObserver) {
        AssertIsOnMainThread()

        let isRemoteVideoEnabled = currentCall?.isRemoteVideoEnabled ?? false
        let remoteVideoTrack = isRemoteVideoEnabled ? currentCall?.remoteVideoTrack : nil
        observer.didUpdateVideoTracks(call: currentCall,
                                      localCaptureSession: currentCall?.localCaptureSession,
                                      remoteVideoTrack: remoteVideoTrack)
    }

    // MARK: CallViewController Timer

    var activeCallTimer: Timer?
    func startCallTimer() {
        AssertIsOnMainThread()

        stopAnyCallTimer()
        assert(self.activeCallTimer == nil)

        guard let call = self.currentCall else {
            owsFailDebug("Missing call.")
            return
        }

        var hasUsedUpTimerSlop: Bool = false

        self.activeCallTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { timer in
            guard call === self.currentCall else {
                owsFailDebug("call has since ended. Timer should have been invalidated.")
                timer.invalidate()
                return
            }
            self.ensureCallScreenPresented(call: call, hasUsedUpTimerSlop: &hasUsedUpTimerSlop)
        }
    }

    func ensureCallScreenPresented(call: SignalCall, hasUsedUpTimerSlop: inout Bool) {
        guard self.currentCall === call else {
            owsFailDebug("obsolete call: \(call)")
            return
        }

        guard let connectedDate = call.connectedDate else {
            // Ignore; call hasn't connected yet.
            return
        }

        let kMaxViewPresentationDelay: Double = 5
        guard fabs(connectedDate.timeIntervalSinceNow) > kMaxViewPresentationDelay else {
            // Ignore; call connected recently.
            return
        }

        guard !OWSWindowManager.shared.hasCall else {
            // call screen is visible
            return
        }

        guard hasUsedUpTimerSlop else {
            // We hide the call screen synchronously, as soon as the user hangs up the call
            // But it takes a while to communicate the hangup from the UI -> CallKit -> CallService
            // However it's possible the timer fired the *instant* after the user hit the hangup
            // button, so we allow one tick of the timer cycle as slop.
            Logger.verbose("using up timer slop")
            hasUsedUpTimerSlop = true
            return
        }

        owsFailDebug("Call terminated due to missing call view.")
        self.handleFailedCall(failedCall: call, error: OWSAssertionError("Call view didn't present after \(kMaxViewPresentationDelay) seconds"))
    }

    func stopAnyCallTimer() {
        AssertIsOnMainThread()

        self.activeCallTimer?.invalidate()
        self.activeCallTimer = nil
    }
}

extension RPRecentCallType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .incoming:
            return ".incoming"
        case .outgoing:
            return ".outgoing"
        case .incomingMissed:
            return ".incomingMissed"
        case .outgoingIncomplete:
            return ".outgoingIncomplete"
        case .incomingIncomplete:
            return ".incomingIncomplete"
        case .incomingMissedBecauseOfChangedIdentity:
            return ".incomingMissedBecauseOfChangedIdentity"
        case .incomingDeclined:
            return ".incomingDeclined"
        case .outgoingMissed:
            return ".outgoingMissed"
        default:
            owsFailDebug("unexpected RPRecentCallType: \(self)")
            return "RPRecentCallTypeUnknown"
        }
    }
}

extension NSNumber {
    convenience init?(value: UInt32?) {
        guard let value = value else { return nil }
        self.init(value: value)
    }
}
