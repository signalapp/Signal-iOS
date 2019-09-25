//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC
import SignalServiceKit
import SignalMessaging

/**
 * `CallService` is a global singleton that manages the state of WebRTC-backed Signal Calls
 * (as opposed to legacy "RedPhone Calls").
 *
 * It serves as a connection between the `CallUIAdapter` and the `PeerConnectionClient`.
 *
 * ## Signaling
 *
 * Signaling refers to the setup and tear down of the connection. Before the connection is established, this must happen
 * out of band (using Signal Service), but once the connection is established it's possible to publish updates 
 * (like hangup) via the established channel.
 *
 * Signaling state is synchronized on the main thread and only mutated in the handleXXX family of methods.
 *
 * Following is a high level process of the exchange of messages that takes place during call signaling.
 *
 * ### Key
 *
 * --[SOMETHING]--> represents a message of type "Something" sent from the caller to the callee
 * <--[SOMETHING]-- represents a message of type "Something" sent from the callee to the caller
 * SS: Message sent via Signal Service
 * DC: Message sent via WebRTC Data Channel
 *
 * ### Message Exchange / State Flow Overview
 *
 * |          Caller            |          Callee         |
 * +----------------------------+-------------------------+
 * Start outgoing call: `handleOutgoingCall`...
                        --[SS.CallOffer]-->
 * ...and start generating ICE updates.
 * As ICE candidates are generated, `handleLocalAddedIceCandidate` is called.
 * and we *store* the ICE updates for later.
 *
 *                                      Received call offer: `handleReceivedOffer`
 *                                         Send call answer
 *                     <--[SS.CallAnswer]--
 *                          Start generating ICE updates.
 *                          As they are generated `handleLocalAddedIceCandidate` is called
                            which immediately sends the ICE updates to the Caller.
 *                     <--[SS.ICEUpdate]-- (sent multiple times)
 *
 * Received CallAnswer: `handleReceivedAnswer`
 * So send any stored ice updates (and send future ones immediately)
 *                     --[SS.ICEUpdates]-->
 *
 *     Once compatible ICE updates have been exchanged...
 *                both parties: `handleIceConnected`
 *
 * Show remote ringing UI
 *                          Connect to offered Data Channel
 *                                    Show incoming call UI.
 *
 *                                   If callee answers Call
 *                                   send connected message
 *                   <--[DC.ConnectedMesage]--
 * Received connected message
 * Show Call is connected.
 *
 * Hang up (this could equally be sent by the Callee)
 *                      --[DC.Hangup]-->
 *                      --[SS.Hangup]-->
 */

public enum CallError: Error {
    case providerReset
    case assertionError(description: String)
    case disconnected
    case externalError(underlyingError: Error)
    case timeout(description: String)
    case obsoleteCall(description: String)
    case fatalError(description: String)
    case messageSendFailure(underlyingError: Error)
}

// Should be roughly synced with Android client for consistency
private let connectingTimeoutSeconds: TimeInterval = 120

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

protocol SignalCallDataDelegate: class {
    func outgoingIceUpdateDidFail(call: SignalCall, error: Error)
}

// Gather all per-call state in one place.
private class SignalCallData: NSObject {

    fileprivate weak var delegate: SignalCallDataDelegate?

    public let call: SignalCall

    // Used to coordinate promises across delegate methods
    let callConnectedPromise: Promise<Void>
    let callConnectedResolver: Resolver<Void>

    // Used to ensure any received ICE messages wait until the peer connection client is set up.
    let peerConnectionClientPromise: Promise<Void>
    let peerConnectionClientResolver: Resolver<Void>

    // Used to ensure CallOffer was sent before sending any ICE updates.
    let readyToSendIceUpdatesPromise: Promise<Void>
    let readyToSendIceUpdatesResolver: Resolver<Void>

    weak var localCaptureSession: AVCaptureSession? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    var isRemoteVideoEnabled = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteVideoEnabled)")
        }
    }

    var peerConnectionClient: PeerConnectionClient? {
        didSet {
            AssertIsOnMainThread()

            Logger.debug(".peerConnectionClient setter: \(oldValue != nil) -> \(peerConnectionClient != nil) \(String(describing: peerConnectionClient))")
        }
    }

    required init(call: SignalCall, delegate: SignalCallDataDelegate) {
        self.call = call
        self.delegate = delegate

        let (callConnectedPromise, callConnectedResolver) = Promise<Void>.pending()
        self.callConnectedPromise = callConnectedPromise
        self.callConnectedResolver = callConnectedResolver

        let (peerConnectionClientPromise, peerConnectionClientResolver) = Promise<Void>.pending()
        self.peerConnectionClientPromise = peerConnectionClientPromise
        self.peerConnectionClientResolver = peerConnectionClientResolver

        let (readyToSendIceUpdatesPromise, readyToSendIceUpdatesResolver) = Promise<Void>.pending()
        self.readyToSendIceUpdatesPromise = readyToSendIceUpdatesPromise
        self.readyToSendIceUpdatesResolver = readyToSendIceUpdatesResolver

        super.init()
    }

    deinit {
        Logger.debug("[SignalCallData] deinit")
    }

    // MARK: -

    public func terminate() {
        AssertIsOnMainThread()

        Logger.debug("")

        self.call.removeAllObservers()

        // In case we're still waiting on this promise somewhere, we need to reject it to avoid a memory leak.
        // There is no harm in rejecting a previously fulfilled promise.
        self.callConnectedResolver.reject(CallError.obsoleteCall(description: "Terminating call"))

        // In case we're still waiting on the peer connection setup somewhere, we need to reject it to avoid a memory leak.
        // There is no harm in rejecting a previously fulfilled promise.
        self.peerConnectionClientResolver.reject(CallError.obsoleteCall(description: "Terminating call"))

        // In case we're still waiting on this promise somewhere, we need to reject it to avoid a memory leak.
        // There is no harm in rejecting a previously fulfilled promise.
        self.readyToSendIceUpdatesResolver.reject(CallError.obsoleteCall(description: "Terminating call"))

        peerConnectionClient?.terminate()
        Logger.debug("setting peerConnectionClient")

        outgoingIceUpdateQueue.removeAll()
    }

    // MARK: - Dependencies

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    // MARK: - Outgoing ICE updates.

    // Setting up a call involves sending many (currently 20+) ICE updates.
    // We send messages serially in order to preserve outgoing message order.
    // There are so many ICE updates per call that the cost of sending all of
    // those messages becomes significant.  So we batch outgoing ICE updates,
    // making sure that we only have one outgoing ICE update message at a time.
    //
    // This variable should only be accessed on the main thread.
    private var outgoingIceUpdateQueue = [SSKProtoCallMessageIceUpdate]()
    private var outgoingIceUpdatesInFlight = false

    func sendOrEnqueue(outgoingIceUpdate iceUpdateProto: SSKProtoCallMessageIceUpdate) {
        AssertIsOnMainThread()

        outgoingIceUpdateQueue.append(iceUpdateProto)

        tryToSendIceUpdates()
    }

    private func tryToSendIceUpdates() {
        AssertIsOnMainThread()

        guard !outgoingIceUpdatesInFlight else {
            Logger.verbose("Enqueued outgoing ice update")
            return
        }

        let iceUpdateProtos = outgoingIceUpdateQueue
        guard iceUpdateProtos.count > 0 else {
            // Nothing in the queue.
            return
        }

        outgoingIceUpdateQueue.removeAll()
        outgoingIceUpdatesInFlight = true

        /**
         * Sent by both parties out of band of the RTC calling channels, as part of setting up those channels. The messages
         * include network accessibility information from the perspective of each client. Once compatible ICEUpdates have been
         * exchanged, the clients can connect.
         */
        let callMessage = OWSOutgoingCallMessage(thread: call.thread, iceUpdateMessages: iceUpdateProtos)
        let sendPromise = self.messageSender.sendMessage(.promise, callMessage.asPreparer)
            .done { [weak self] in
                AssertIsOnMainThread()

                guard let strongSelf = self else {
                    return
                }

                strongSelf.outgoingIceUpdatesInFlight = false
                strongSelf.tryToSendIceUpdates()
            }.catch { [weak self] (error) in
                AssertIsOnMainThread()

                guard let strongSelf = self else {
                    return
                }

                strongSelf.outgoingIceUpdatesInFlight = false
                strongSelf.delegate?.outgoingIceUpdateDidFail(call: strongSelf.call, error: error)
        }
        sendPromise.retainUntilComplete()
    }
}

// This class' state should only be accessed on the main queue.
@objc public class CallService: NSObject, CallObserver, PeerConnectionClientDelegate, SignalCallDataDelegate {

    // MARK: - Properties

    var observers = [Weak<CallServiceObserver>]()

    // Exposed by environment.m

    @objc public var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    // MARK: Ivars

    fileprivate var callData: SignalCallData? {
        didSet {
            AssertIsOnMainThread()

            oldValue?.delegate = nil
            oldValue?.call.removeObserver(self)
            callData?.call.addObserverAndSyncState(observer: self)

            updateIsVideoEnabled()

            // Prevent device from sleeping while we have an active call.
            if oldValue != callData {
                if let oldValue = oldValue {
                    DeviceSleepManager.sharedInstance.removeBlock(blockObject: oldValue)
                }
                if let callData = callData {
                    DeviceSleepManager.sharedInstance.addBlock(blockObject: callData)
                    self.startCallTimer()
                } else {
                    stopAnyCallTimer()
                }
            }

            Logger.debug(".callData setter: \(oldValue?.call.identifiersForLogs as Optional) -> \(callData?.call.identifiersForLogs as Optional)")

            for observer in observers {
                observer.value?.didUpdateCall(call: callData?.call)
            }
        }
    }

    @objc
    var call: SignalCall? {
        get {
            AssertIsOnMainThread()

            return callData?.call
        }
    }
    var peerConnectionClient: PeerConnectionClient? {
        get {
            AssertIsOnMainThread()

            return callData?.peerConnectionClient
        }
    }

    var localCaptureSession: AVCaptureSession? {
        get {
            AssertIsOnMainThread()

            return callData?.localCaptureSession
        }
    }

    var remoteVideoTrack: RTCVideoTrack? {
        get {
            AssertIsOnMainThread()

            return callData?.remoteVideoTrack
        }
    }

    var isRemoteVideoEnabled: Bool {
        get {
            AssertIsOnMainThread()

            guard let callData = callData else {
                return false
            }
            return callData.isRemoteVideoEnabled
        }
    }

    @objc public override init() {

        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: NSNotification.Name.OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
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

    private var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    var databaseStorage: SDSDatabaseStorage {
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

        if self.call != nil {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            self.terminateCall()
        }
        self.callUIAdapter = CallUIAdapter(callService: self, contactsManager: self.contactsManager, notificationPresenter: self.notificationPresenter)
    }

    // MARK: - Service Actions

    /**
     * Initiate an outgoing call.
     */
    func handleOutgoingCall(_ call: SignalCall) -> Promise<Void> {
        AssertIsOnMainThread()

        let callId = call.signalingId
        BenchEventStart(title: "Outgoing Call Connection", eventId: "call-\(callId)")

        guard self.call == nil else {
            let errorDescription = "call was unexpectedly already set."
            Logger.error(errorDescription)
            call.state = .localFailure
            OWSProdError(OWSAnalyticsEvents.callServiceCallAlreadySet(), file: #file, function: #function, line: #line)
            return Promise(error: CallError.assertionError(description: errorDescription))
        }

        let callData = SignalCallData(call: call, delegate: self)
        self.callData = callData

        // MJK TODO remove this timestamp param
        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), callType: .outgoingIncomplete, in: call.thread)
        databaseStorage.write { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.callRecord = callRecord

        let promise = getIceServers()
            .then { iceServers -> Promise<HardenedRTCSessionDescription> in
            Logger.debug("got ice servers:\(iceServers) for call: \(call.identifiersForLogs)")

            guard self.call == call else {
                throw CallError.obsoleteCall(description: "obsolete call")
            }

            guard callData.peerConnectionClient == nil else {
                let errorDescription = "peerConnectionClient was unexpectedly already set."
                Logger.error(errorDescription)
                OWSProdError(OWSAnalyticsEvents.callServicePeerConnectionAlreadySet(), file: #file, function: #function, line: #line)
                throw CallError.assertionError(description: errorDescription)
            }

            let useTurnOnly = Environment.shared.preferences.doCallsHideIPAddress()

            let peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self, callDirection: .outgoing, useTurnOnly: useTurnOnly)
            Logger.debug("setting peerConnectionClient for call: \(call.identifiersForLogs)")
            callData.peerConnectionClient = peerConnectionClient
            callData.peerConnectionClientResolver.fulfill(())

            return peerConnectionClient.createOffer()
        }.then { (sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> in
            guard self.call == call else {
                throw CallError.obsoleteCall(description: "obsolete call")
            }
            guard let peerConnectionClient = self.peerConnectionClient else {
                owsFailDebug("Missing peerConnectionClient")
                throw CallError.obsoleteCall(description: "Missing peerConnectionClient")
            }

            Logger.info("session description for outgoing call: \(call.identifiersForLogs), sdp: \(sessionDescription.logSafeDescription).")

            return
                peerConnectionClient.setLocalSessionDescription(sessionDescription)
            .then { _ -> Promise<Void> in
                do {
                    let offerBuilder = SSKProtoCallMessageOffer.builder(id: call.signalingId,
                                                                        sessionDescription: sessionDescription.sdp)
                    let callMessage = OWSOutgoingCallMessage(thread: call.thread, offerMessage: try offerBuilder.build())
                    return self.messageSender.sendMessage(.promise, callMessage.asPreparer)
                } catch {
                    owsFailDebug("Couldn't build proto")
                    throw CallError.fatalError(description: "Couldn't build proto")
                }
            }
        }.then { () -> Promise<Void> in
            guard self.call == call else {
                throw CallError.obsoleteCall(description: "obsolete call")
            }

            // For outgoing calls, wait until call offer is sent before we send any ICE updates, to ensure message ordering for
            // clients that don't support receiving ICE updates before receiving the call offer.
            self.readyToSendIceUpdates(call: call)

            // Don't let the outgoing call ring forever. We don't support inbound ringing forever anyway.
            let timeout: Promise<Void> = after(seconds: connectingTimeoutSeconds).done {
                // This code will always be called, whether or not the call has timed out.
                // However, if the call has already connected, the `race` promise will have already been
                // fulfilled. Rejecting an already fulfilled promise is a no-op.
                throw CallError.timeout(description: "timed out waiting to receive call answer")
            }

            return race(timeout, callData.callConnectedPromise)
        }.done {
            Logger.info(self.call == call
                ? "outgoing call connected: \(call.identifiersForLogs)."
                : "obsolete outgoing call connected: \(call.identifiersForLogs).")
        }

        promise.catch { error in
            Logger.error("placing call \(call.identifiersForLogs) failed with error: \(error)")

            if let callError = error as? CallError {
                if case .timeout = callError {
                    OWSProdInfo(OWSAnalyticsEvents.callServiceErrorTimeoutWhileConnectingOutgoing(), file: #file, function: #function, line: #line)
                }
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorOutgoingConnectionFailedInternal(), file: #file, function: #function, line: #line)
                self.handleFailedCall(failedCall: call, error: callError)
            } else {
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorOutgoingConnectionFailedExternal(), file: #file, function: #function, line: #line)
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: call, error: externalError)
            }
        }.retainUntilComplete()

        return promise
    }

    func readyToSendIceUpdates(call: SignalCall) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            self.handleFailedCall(failedCall: call, error: .obsoleteCall(description:"obsolete call"))
            return
        }
        guard callData.call == call else {
            Logger.warn("ignoring \(#function) for call other than current call")
            return
        }

        callData.readyToSendIceUpdatesResolver.fulfill(())
    }

    /**
     * Called by the call initiator after receiving a CallAnswer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sessionDescription: String) {
        AssertIsOnMainThread()
        Logger.info("received call answer for call: \(callId) thread: \(thread.contactAddress)")

        guard let call = self.call else {
            Logger.warn("ignoring obsolete call: \(callId)")
            return
        }

        guard call.signalingId == callId else {
            Logger.warn("ignoring mismatched call: \(callId) currentCall: \(call.signalingId)")
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            OWSProdError(OWSAnalyticsEvents.callServicePeerConnectionMissing(), file: #file, function: #function, line: #line)
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "peerConnectionClient was unexpectedly nil"))
            return
        }

        let sessionDescription = RTCSessionDescription(type: .answer, sdp: sessionDescription)

        peerConnectionClient.setRemoteSessionDescription(sessionDescription)
        .done {
            Logger.debug("successfully set remote description")
        }.catch { error in
            if let callError = error as? CallError {
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorHandleReceivedErrorInternal(), file: #file, function: #function, line: #line)
                self.handleFailedCall(failedCall: call, error: callError)
            } else {
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorHandleReceivedErrorExternal(), file: #file, function: #function, line: #line)
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: call, error: externalError)
            }
        }.retainUntilComplete()
    }

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        if call.callRecord == nil {
            // MJK TODO remove this timestamp param
            call.callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                     callType: .incomingMissed,
                                     in: call.thread)
        }

        guard let callRecord = call.callRecord else {
            handleFailedCall(failedCall: call, error: .assertionError(description: "callRecord was unexpectedly nil"))
            return
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
        case .incomingMissedBecauseOfChangedIdentity, .incomingDeclined, .outgoingMissed, .outgoing:
            owsFailDebug("unexpected RPRecentCallType: \(callRecord.callType)")
            databaseStorage.write { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
        default:
            databaseStorage.write { transaction in
                callRecord.anyUpsert(transaction: transaction)
            }
            owsFailDebug("unknown RPRecentCallType: \(callRecord.callType)")
        }
    }

    /**
     * Received a call while already in another call.
     */
    private func handleLocalBusyCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("for call: \(call.identifiersForLogs) thread: \(call.thread.contactAddress)")

        do {
            let busyBuilder = SSKProtoCallMessageBusy.builder(id: call.signalingId)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, busyMessage: try busyBuilder.build())
            let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
            sendPromise.retainUntilComplete()

            handleMissedCall(call)
        } catch {
            owsFailDebug("Couldn't build proto")
        }
    }

    /**
     * The callee was already in another call.
     */
    public func handleRemoteBusy(thread: TSContactThread, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("for thread: \(thread.contactAddress)")

        guard let call = self.call else {
            Logger.warn("ignoring obsolete call: \(callId)")
            return
        }

        guard call.signalingId == callId else {
            Logger.warn("ignoring mismatched call: \(callId) currentCall: \(call.signalingId)")
            return
        }

        guard thread.contactAddress == call.remoteAddress else {
            Logger.warn("ignoring obsolete call")
            return
        }

        call.state = .remoteBusy
        assert(call.callRecord != nil)
        call.callRecord?.updateCallType(.outgoingMissed)

        callUIAdapter.remoteBusy(call)
        terminateCall()
    }

    /**
     * Received an incoming call offer. We still have to complete setting up the Signaling channel before we notify
     * the user of an incoming call.
     */
    public func handleReceivedOffer(thread: TSContactThread, callId: UInt64, sessionDescription callerSessionDescription: String) {
        AssertIsOnMainThread()

        BenchEventStart(title: "Incoming Call Connection", eventId: "call-\(callId)")

        let newCall = SignalCall.incomingCall(localId: UUID(), remoteAddress: thread.contactAddress, signalingId: callId)

        Logger.info("receivedCallOffer: \(newCall.identifiersForLogs)")

        let untrustedIdentity = OWSIdentityManager.shared().untrustedIdentityForSending(to: thread.contactAddress)

        guard untrustedIdentity == nil else {
            Logger.warn("missed a call due to untrusted identity: \(newCall.identifiersForLogs)")

            let callerName = self.contactsManager.displayName(for: thread.contactAddress)

            switch untrustedIdentity!.verificationState {
            case .verified:
                owsFailDebug("shouldn't have missed a call due to untrusted identity if the identity is verified")
                self.notificationPresenter.presentMissedCall(newCall, callerName: callerName)
            case .default:
                self.notificationPresenter.presentMissedCallBecauseOfNewIdentity(call: newCall, callerName: callerName)
            case .noLongerVerified:
                self.notificationPresenter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: newCall, callerName: callerName)
            }

            // MJK TODO remove this timestamp param
            let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                    callType: .incomingMissedBecauseOfChangedIdentity,
                                    in: thread)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            terminateCall()

            return
        }

        guard self.call == nil else {
            let existingCall = self.call!

            // TODO on iOS10+ we can use CallKit to swap calls rather than just returning busy immediately.
            Logger.info("receivedCallOffer: \(newCall.identifiersForLogs) but we're already in call: \(existingCall.identifiersForLogs)")

            handleLocalBusyCall(newCall)

            if existingCall.remoteAddress == newCall.remoteAddress {
                Logger.info("handling call from current call user as remote busy.: \(newCall.identifiersForLogs) but we're already in call: \(existingCall.identifiersForLogs)")

                // If we're receiving a new call offer from the user we already think we have a call with,
                // terminate our current call to get back to a known good state.  If they call back, we'll 
                // be ready.
                // 
                // TODO: Auto-accept this incoming call if our current call was either a) outgoing or 
                // b) never connected.  There will be a bit of complexity around making sure that two
                // parties that call each other at the same time end up connected.
                switch existingCall.state {
                case .idle, .dialing, .remoteRinging:
                    // If both users are trying to call each other at the same time,
                    // both should see busy.
                    handleRemoteBusy(thread: existingCall.thread, callId: existingCall.signalingId)
                case .answering, .localRinging, .connected, .localFailure, .localHangup, .remoteHangup, .remoteBusy, .reconnecting:
                    // If one user calls another while the other has a "vestigial" call with
                    // that same user, fail the old call.
                    terminateCall()
                }
            }

            return
        }

        Logger.info("starting new call: \(newCall.identifiersForLogs)")

        let callData = SignalCallData(call: newCall, delegate: self)
        self.callData = callData

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            guard let strongSelf = self else {
                return
            }
            let timeout = CallError.timeout(description: "background task time ran out before call connected.")

            guard strongSelf.call == newCall else {
                Logger.warn("ignoring obsolete call")
                return
            }
            strongSelf.handleFailedCall(failedCall: newCall, error: timeout)
        })

        getIceServers()
            .then { (iceServers: [RTCIceServer]) -> Promise<HardenedRTCSessionDescription> in
            // FIXME for first time call recipients I think we'll see mic/camera permission requests here,
            // even though, from the users perspective, no incoming call is yet visible.
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "getIceServers() response for obsolete call")
            }
            assert(self.peerConnectionClient == nil, "Unexpected PeerConnectionClient instance")

            // For contacts not stored in our system contacts, we assume they are an unknown caller, and we force
            // a TURN connection, so as not to reveal any connectivity information (IP/port) to the caller.
            let isUnknownCaller = !self.contactsManager.hasSignalAccount(for: thread.contactAddress)

            let useTurnOnly = isUnknownCaller || Environment.shared.preferences.doCallsHideIPAddress()

            Logger.debug("setting peerConnectionClient for: \(newCall.identifiersForLogs)")
            let peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self, callDirection: .incoming, useTurnOnly: useTurnOnly)
            callData.peerConnectionClient = peerConnectionClient
            callData.peerConnectionClientResolver.fulfill(())

            let offerSessionDescription = RTCSessionDescription(type: .offer, sdp: callerSessionDescription)
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

            // Find a sessionDescription compatible with my constraints and the remote sessionDescription
            return peerConnectionClient.negotiateSessionDescription(remoteDescription: offerSessionDescription, constraints: constraints)
        }.then { (negotiatedSessionDescription: HardenedRTCSessionDescription) -> Promise<Void> in
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "negotiateSessionDescription() response for obsolete call")
            }

            Logger.info("session description for incoming call: \(newCall.identifiersForLogs), sdp: \(negotiatedSessionDescription.logSafeDescription).")

            do {
                let answerBuilder = SSKProtoCallMessageAnswer.builder(id: newCall.signalingId,
                                                                                               sessionDescription: negotiatedSessionDescription.sdp)
                let callAnswerMessage = OWSOutgoingCallMessage(thread: thread, answerMessage: try answerBuilder.build())

                return self.messageSender.sendMessage(.promise, callAnswerMessage.asPreparer)
            } catch {
                owsFailDebug("Couldn't build proto")
                throw CallError.fatalError(description: "Couldn't build proto")
            }
        }.then { () -> Promise<Void> in
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "sendMessage response for obsolete call")
            }
            Logger.debug("successfully sent callAnswerMessage for: \(newCall.identifiersForLogs)")

            // There's nothing technically forbidding receiving ICE updates before receiving the CallAnswer, but this
            // a more intuitive ordering.
            self.readyToSendIceUpdates(call: newCall)

            let timeout: Promise<Void> = after(seconds: connectingTimeoutSeconds).done {
                // rejecting a promise by throwing is safely a no-op if the promise has already been fulfilled
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorTimeoutWhileConnectingIncoming(), file: #file, function: #function, line: #line)
                throw CallError.timeout(description: "timed out waiting for call to connect")
            }

            // This will be fulfilled (potentially) by the RTCDataChannel delegate method
            return race(callData.callConnectedPromise, timeout)
        }.done {
            Logger.info(self.call == newCall
                ? "incoming call connected: \(newCall.identifiersForLogs)."
                : "obsolete incoming call connected: \(newCall.identifiersForLogs).")
        }.recover { error in
            guard self.call == newCall else {
                Logger.debug("ignoring error: \(error)  for obsolete call: \(newCall.identifiersForLogs).")
                return
            }
            if let callError = error as? CallError {
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorIncomingConnectionFailedInternal(), file: #file, function: #function, line: #line)
                self.handleFailedCall(failedCall: newCall, error: callError)
            } else {
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorIncomingConnectionFailedExternal(), file: #file, function: #function, line: #line)
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: newCall, error: externalError)
            }
        }.ensure {
            Logger.debug("ending background task awaiting inbound call connection")

            assert(backgroundTask != nil)
            backgroundTask = nil
        }.retainUntilComplete()
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update
     */
    public func handleRemoteAddedIceCandidate(thread: TSContactThread, callId: UInt64, sdp: String, lineIndex: Int32, mid: String) {
        AssertIsOnMainThread()
        Logger.verbose("callId: \(callId)")

        guard let callData = self.callData else {
            Logger.info("ignoring remote ice update, since there is no current call.")
            return
        }

        callData.peerConnectionClientPromise.done {
            AssertIsOnMainThread()

            guard let call = self.call else {
                Logger.warn("ignoring remote ice update for thread: \(String(describing: thread.uniqueId)) since there is no current call. Call already ended?")
                return
            }

            guard call.signalingId == callId else {
                Logger.warn("ignoring mismatched call: \(callId) currentCall: \(call.signalingId)")
                return
            }

            guard thread.contactAddress == call.thread.contactAddress else {
                Logger.warn("ignoring remote ice update for thread: \(String(describing: thread.uniqueId)) due to thread mismatch. Call already ended?")
                return
            }

            guard let peerConnectionClient = self.peerConnectionClient else {
                Logger.warn("ignoring remote ice update for thread: \(String(describing: thread.uniqueId)) since there is no current peerConnectionClient. Call already ended?")
                return
            }

            Logger.verbose("addRemoteIceCandidate")
            peerConnectionClient.addRemoteIceCandidate(RTCIceCandidate(sdp: sdp, sdpMLineIndex: lineIndex, sdpMid: mid))
        }.catch { error in
            OWSProdInfo(OWSAnalyticsEvents.callServiceErrorHandleRemoteAddedIceCandidate(), file: #file, function: #function, line: #line)
            Logger.error("peerConnectionClientPromise failed with error: \(error)")
        }.retainUntilComplete()
    }

    /**
     * Local client (could be caller or callee) generated some connectivity information that we should send to the 
     * remote client.
     */
    private func handleLocalAddedIceCandidate(_ iceCandidate: RTCIceCandidate) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            OWSProdError(OWSAnalyticsEvents.callServiceCallMissing(), file: #file, function: #function, line: #line)
            self.handleFailedCurrentCall(error: CallError.assertionError(description: "ignoring local ice candidate, since there is no current call."))
            return
        }
        let call = callData.call

        // Wait until we've sent the CallOffer before sending any ice updates for the call to ensure
        // intuitive message ordering for other clients.
        callData.readyToSendIceUpdatesPromise.done {
            guard call == self.call else {
                self.handleFailedCurrentCall(error: .obsoleteCall(description: "current call changed since we became ready to send ice updates"))
                return
            }

            guard call.state != .idle else {
                // This will only be called for the current peerConnectionClient, so
                // fail the current call.
                OWSProdError(OWSAnalyticsEvents.callServiceCallUnexpectedlyIdle(), file: #file, function: #function, line: #line)
                self.handleFailedCurrentCall(error: CallError.assertionError(description: "ignoring local ice candidate, since call is now idle."))
                return
            }

            guard let sdpMid = iceCandidate.sdpMid else {
                owsFailDebug("Missing sdpMid")
                throw CallError.fatalError(description: "Missing sdpMid")
            }

            guard iceCandidate.sdpMLineIndex < UINT32_MAX else {
                owsFailDebug("Invalid sdpMLineIndex")
                throw CallError.fatalError(description: "Invalid sdpMLineIndex")
            }

            Logger.info("sending ICE Candidate \(call.identifiersForLogs).")

            let iceUpdateProto: SSKProtoCallMessageIceUpdate
            do {
                let iceUpdateBuilder = SSKProtoCallMessageIceUpdate.builder(id: call.signalingId,
                                                                            sdpMid: sdpMid,
                                                                            sdpMlineIndex: UInt32(iceCandidate.sdpMLineIndex),
                                                                            sdp: iceCandidate.sdp)
                iceUpdateProto = try iceUpdateBuilder.build()
            } catch {
                owsFailDebug("Couldn't build proto")
                throw CallError.fatalError(description: "Couldn't build proto")
            }

            /**
             * Sent by both parties out of band of the RTC calling channels, as part of setting up those channels. The messages
             * include network accessibility information from the perspective of each client. Once compatible ICEUpdates have been
             * exchanged, the clients can connect.
             */
            callData.sendOrEnqueue(outgoingIceUpdate: iceUpdateProto)
        }.catch { error in
            OWSProdInfo(OWSAnalyticsEvents.callServiceErrorHandleLocalAddedIceCandidate(), file: #file, function: #function, line: #line)
            Logger.error("waitUntilReadyToSendIceUpdates failed with error: \(error)")
        }.retainUntilComplete()
    }

    /**
     * The clients can now communicate via WebRTC.
     *
     * Called by both caller and callee. Compatible ICE messages have been exchanged between the local and remote
     * client.
     */
    private func handleIceConnected() {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            OWSProdError(OWSAnalyticsEvents.callServiceCallMissing(), file: #file, function: #function, line: #line)
            handleFailedCurrentCall(error: CallError.assertionError(description: "ignoring \(#function) since there is no current call."))
            return
        }
        let call = callData.call
        let callId = call.signalingId

        Logger.info("\(call.identifiersForLogs)")

        switch call.state {
        case .dialing:
            if call.state != .remoteRinging {
                BenchEventComplete(eventId: "call-\(callId)")
            }
            call.state = .remoteRinging
        case .answering:
            if call.state != .localRinging {
                BenchEventComplete(eventId: "call-\(callId)")
            }
            call.state = .localRinging
            self.callUIAdapter.reportIncomingCall(call, thread: call.thread)
        case .remoteRinging:
            Logger.info("call already ringing. Ignoring \(#function): \(call.identifiersForLogs).")
        case .connected:
            Logger.info("Call reconnected \(#function): \(call.identifiersForLogs).")
        case .reconnecting:
            call.state = .connected
        case .idle, .localRinging, .localFailure, .localHangup, .remoteHangup, .remoteBusy:
            owsFailDebug("unexpected call state: \(call.state): \(call.identifiersForLogs).")
        }
    }

    private func handleIceDisconnected() {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            OWSProdError(OWSAnalyticsEvents.callServiceCallMissing(), file: #file, function: #function, line: #line)
            handleFailedCurrentCall(error: CallError.assertionError(description: "ignoring \(#function) since there is no current call."))
            return
        }

        Logger.info("\(call.identifiersForLogs).")

        switch call.state {
        case .remoteRinging, .localRinging:
            Logger.debug("disconnect while ringing... we'll keep ringing")
        case .connected:
            call.state = .reconnecting
        default:
            owsFailDebug("unexpected call state: \(call.state): \(call.identifiersForLogs).")
        }
    }

    /**
     * The remote client (caller or callee) ended the call.
     */
    public func handleRemoteHangup(thread: TSContactThread, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.debug("")

        guard let call = self.call else {
            // This may happen if we hang up slightly before they hang up.
            handleFailedCurrentCall(error: .obsoleteCall(description:"call was unexpectedly nil"))
            return
        }

        guard call.signalingId == callId else {
            Logger.warn("ignoring mismatched call: \(callId) currentCall: \(call.signalingId)")
            return
        }

        guard thread.contactAddress == call.thread.contactAddress else {
            // This can safely be ignored.
            // We don't want to fail the current call because an old call was slow to send us the hangup message.
            Logger.warn("ignoring hangup for thread: \(thread.contactAddress) which is not the current call: \(call.identifiersForLogs)")
            return
        }

        Logger.info("\(call.identifiersForLogs).")

        switch call.state {
        case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
            handleMissedCall(call)
        case .connected, .reconnecting, .localHangup, .remoteHangup:
            Logger.info("call is finished.")
        }

        call.state = .remoteHangup
        // Notify UI
        callUIAdapter.remoteDidHangupCall(call)

        // self.call is nil'd in `terminateCall`, so it's important we update it's state *before* calling `terminateCall`
        terminateCall()
    }

    /**
     * User chose to answer call referred to by call `localId`. Used by the Callee only.
     *
     * Used by notification actions which can't serialize a call object.
     */
    @objc public func handleAnswerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            owsFailDebug("call was unexpectedly nil")
            OWSProdError(OWSAnalyticsEvents.callServiceCallMissing(), file: #file, function: #function, line: #line)
            handleFailedCurrentCall(error: CallError.assertionError(description: "call was unexpectedly nil"))
            return
        }

        guard call.localId == localId else {
            // This should never happen; return to a known good state.
            owsFailDebug("callLocalId:\(localId) doesn't match current calls: \(call.localId)")
            OWSProdError(OWSAnalyticsEvents.callServiceCallIdMismatch(), file: #file, function: #function, line: #line)
            handleFailedCurrentCall(error: CallError.assertionError(description: "callLocalId:\(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        self.handleAnswerCall(call)
    }

    /**
     * User chose to answer call referred to by call `localId`. Used by the Callee only.
     */
    public func handleAnswerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("")

        guard let currentCallData = self.callData else {
            OWSProdError(OWSAnalyticsEvents.callServiceCallDataMissing(), file: #file, function: #function, line: #line)
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "callData unexpectedly nil"))
            return
        }

        guard call == currentCallData.call else {
            // This could conceivably happen if the other party of an old call was slow to send us their answer
            // and we've subsequently engaged in another call. Don't kill the current call, but just ignore it.
            Logger.warn("ignoring \(#function) for call other than current call")
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            OWSProdError(OWSAnalyticsEvents.callServicePeerConnectionMissing(), file: #file, function: #function, line: #line)
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "missing peerConnection client"))
            return
        }

        Logger.info("\(call.identifiersForLogs).")

        // MJK TODO remove this timestamp param
        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), callType: .incomingIncomplete, in: call.thread)
        databaseStorage.write { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.callRecord = callRecord

        var messageData: Data
        do {
            let connectedBuilder = WebRTCProtoConnected.builder(id: call.signalingId)
            let dataBuilder = WebRTCProtoData.builder()
            dataBuilder.setConnected(try connectedBuilder.build())
            messageData = try dataBuilder.buildSerializedData()
        } catch {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build proto"))
            return
        }

        peerConnectionClient.sendDataChannelMessage(data: messageData, description: "connected", isCritical: true)

        handleConnectedCall(currentCallData)
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    private func handleConnectedCall(_ callData: SignalCallData) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let peerConnectionClient = callData.peerConnectionClient else {
            OWSProdError(OWSAnalyticsEvents.callServicePeerConnectionMissing(), file: #file, function: #function, line: #line)
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "peerConnectionClient unexpectedly nil"))
            return
        }

        Logger.info("handleConnectedCall: \(callData.call.identifiersForLogs).")

        // cancel connection timeout
        callData.callConnectedResolver.fulfill(())

        callData.call.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        ensureAudioState(call: callData.call, peerConnectionClient: peerConnectionClient)
        peerConnectionClient.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
    }

    /**
     * Local user chose to end the call.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func handleLocalHungupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard let currentCall = self.call else {
            Logger.info("No current call. Other party hung up just before us.")

            // terminating the call might be redundant, but it shouldn't hurt.
            terminateCall()
            return
        }

        guard call == currentCall else {
            OWSProdError(OWSAnalyticsEvents.callServiceCallMismatch(), file: #file, function: #function, line: #line)
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "ignoring \(#function) for call other than current call"))
            return
        }

        Logger.info("\(call.identifiersForLogs).")

        if let callRecord = call.callRecord {
            if callRecord.callType == .outgoingIncomplete {
                callRecord.updateCallType(.outgoingMissed)
            }
        } else if call.state == .localRinging {
            // MJK TODO remove this timestamp param
            let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                    callType: .incomingDeclined,
                                    in: call.thread)
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }
            call.callRecord = callRecord
        } else {
            owsFailDebug("missing call record")
        }

        call.state = .localHangup

        // TODO something like this lifted from Signal-Android.
        //        this.accountManager.cancelInFlightRequests();
        //        this.messageSender.cancelInFlightRequests();

        if let peerConnectionClient = self.peerConnectionClient {
            // Stop audio capture ASAP
            ensureAudioState(call: call, peerConnectionClient: peerConnectionClient)

            // If the call is connected, we can send the hangup via the data channel for faster hangup.

            var messageData: Data
            do {
                let hangupBuilder = WebRTCProtoHangup.builder(id: call.signalingId)
                let dataBuilder = WebRTCProtoData.builder()
                dataBuilder.setHangup(try hangupBuilder.build())
                messageData = try dataBuilder.buildSerializedData()
            } catch {
                handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build proto"))
                return
            }

            peerConnectionClient.sendDataChannelMessage(data: messageData, description: "hangup", isCritical: true)
        } else {
            Logger.info("ending call before peer connection created. Device offline or quick hangup.")
        }

        // If the call hasn't started yet, we don't have a data channel to communicate the hang up. Use Signal Service Message.
        do {
            let hangupBuilder = SSKProtoCallMessageHangup.builder(id: call.signalingId)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, hangupMessage: try hangupBuilder.build())

            self.messageSender.sendMessage(.promise, callMessage.asPreparer)
            .done {
                Logger.debug("successfully sent hangup call message to \(call.thread.contactAddress)")
            }.catch { error in
                OWSProdInfo(OWSAnalyticsEvents.callServiceErrorHandleLocalHungupCall(), file: #file, function: #function, line: #line)
                Logger.error("failed to send hangup call message to \(call.thread.contactAddress) with error: \(error)")
            }.retainUntilComplete()

            terminateCall()
        } catch {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build proto"))
        }
    }

    /**
     * Local user toggled to mute audio.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        guard call == self.call else {
            // This can happen after a call has ended. Reproducible on iOS11, when the other party ends the call.
            Logger.info("ignoring mute request for obsolete call")
            return
        }

        call.isMuted = isMuted

        guard let peerConnectionClient = self.peerConnectionClient else {
            // The peer connection might not be created yet.
            return
        }

        ensureAudioState(call: call, peerConnectionClient: peerConnectionClient)
    }

    /**
     * Local user toggled to hold call. Currently only possible via CallKit screen,
     * e.g. when another Call comes in.
     */
    func setIsOnHold(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()

        guard call == self.call else {
            Logger.info("ignoring held request for obsolete call")
            return
        }

        call.isOnHold = isOnHold

        guard let peerConnectionClient = self.peerConnectionClient else {
            // The peer connection might not be created yet.
            return
        }

        ensureAudioState(call: call, peerConnectionClient: peerConnectionClient)
    }

    func ensureAudioState(call: SignalCall, peerConnectionClient: PeerConnectionClient) {
        guard call.state == .connected else {
            peerConnectionClient.setAudioEnabled(enabled: false)
            return
        }
        guard !call.isMuted else {
            peerConnectionClient.setAudioEnabled(enabled: false)
            return
        }
        guard !call.isOnHold else {
            peerConnectionClient.setAudioEnabled(enabled: false)
            return
        }

        peerConnectionClient.setAudioEnabled(enabled: true)
    }

    /**
     * Local user toggled video.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setHasLocalVideo(hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return
        }

        frontmostViewController.ows_askForCameraPermissions { [weak self] granted in
            guard let strongSelf = self else {
                return
            }

            if (granted) {
                // Success callback; camera permissions are granted.
                strongSelf.setHasLocalVideoWithCameraPermissions(hasLocalVideo: hasLocalVideo)
            } else {
                // Failed callback; camera permissions are _NOT_ granted.

                // We don't need to worry about the user granting or remoting this permission
                // during a call while the app is in the background, because changing this
                // permission kills the app.
                OWSAlerts.showAlert(title: NSLocalizedString("MISSING_CAMERA_PERMISSION_TITLE", comment: "Alert title when camera is not authorized"),
                                    message: NSLocalizedString("MISSING_CAMERA_PERMISSION_MESSAGE", comment: "Alert body when camera is not authorized"))
            }
        }
    }

    private func setHasLocalVideoWithCameraPermissions(hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This can happen if you toggle local video right after
            // the other user ends the call.
            Logger.debug("Ignoring event from obsolete call")
            return
        }

        call.hasLocalVideo = hasLocalVideo

        guard let peerConnectionClient = self.peerConnectionClient else {
            // The peer connection might not be created yet.
            return
        }

        if call.state == .connected {
            peerConnectionClient.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
        }
    }

    @objc
    func handleCallKitStartVideo() {
        AssertIsOnMainThread()

        self.setHasLocalVideo(hasLocalVideo: true)
    }

    func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        guard let peerConnectionClient = self.peerConnectionClient else {
            return
        }

        peerConnectionClient.setCameraSource(isUsingFrontCamera: isUsingFrontCamera)
    }

    /**
     * Local client received a message on the WebRTC data channel. 
     *
     * The WebRTC data channel is a faster signaling channel than out of band Signal Service messages. Once it's 
     * established we use it to communicate further signaling information. The one sort-of exception is that with 
     * hangup messages we redundantly send a Signal Service hangup message, which is more reliable, and since the hangup 
     * action is idemptotent, there's no harm done.
     *
     * Used by both Incoming and Outgoing calls.
     */
    private func handleDataChannelMessage(_ message: WebRTCProtoData) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This should never happen; return to a known good state.
            owsFailDebug("received data message, but there is no current call. Ignoring.")
            OWSProdError(OWSAnalyticsEvents.callServiceCallMissing(), file: #file, function: #function, line: #line)
            handleFailedCurrentCall(error: CallError.assertionError(description: "received data message, but there is no current call. Ignoring."))
            return
        }
        let call = callData.call

        if let connected = message.connected {
            Logger.debug("remote participant sent Connected via data channel: \(call.identifiersForLogs).")

            guard connected.id == call.signalingId else {
                // This should never happen; return to a known good state.
                owsFailDebug("received connected message for call with id:\(connected.id) but current call has id:\(call.signalingId)")
                OWSProdError(OWSAnalyticsEvents.callServiceCallIdMismatch(), file: #file, function: #function, line: #line)
                handleFailedCurrentCall(error: CallError.assertionError(description: "received connected message for call with id:\(connected.id) but current call has id:\(call.signalingId)"))
                return
            }

            self.callUIAdapter.recipientAcceptedCall(call)
            handleConnectedCall(callData)

        } else if let hangup = message.hangup {
            Logger.debug("remote participant sent Hangup via data channel: \(call.identifiersForLogs).")

            guard hangup.id == call.signalingId else {
                // This should never happen; return to a known good state.
                owsFailDebug("received hangup message for call with id:\(hangup.id) but current call has id:\(call.signalingId)")
                OWSProdError(OWSAnalyticsEvents.callServiceCallIdMismatch(), file: #file, function: #function, line: #line)
                handleFailedCurrentCall(error: CallError.assertionError(description: "received hangup message for call with id:\(hangup.id) but current call has id:\(call.signalingId)"))
                return
            }

            handleRemoteHangup(thread: call.thread, callId: hangup.id)
        } else if let videoStreamingStatus = message.videoStreamingStatus {
            Logger.debug("remote participant sent VideoStreamingStatus via data channel: \(call.identifiersForLogs).")

            callData.isRemoteVideoEnabled = videoStreamingStatus.enabled
            self.fireDidUpdateVideoTracks()
        } else {
            Logger.info("received unknown or empty DataChannelMessage: \(call.identifiersForLogs).")
        }
    }

    // MARK: - PeerConnectionClientDelegate

    /**
     * The connection has been established. The clients can now communicate.
     */
    internal func peerConnectionClientIceConnected(_ peerConnectionClient: PeerConnectionClient) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleIceConnected()
    }

    func peerConnectionClientIceDisconnected(_ peerConnectionClient: PeerConnectionClient) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleIceDisconnected()
    }

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    internal func peerConnectionClientIceFailed(_ peerConnectionClient: PeerConnectionClient) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        // Return to a known good state.
        self.handleFailedCurrentCall(error: CallError.disconnected)
    }

    /**
     * During the Signaling process each client generates IceCandidates locally, which contain information about how to
     * reach the local client via the internet. The delegate must shuttle these IceCandates to the other (remote) client
     * out of band, as part of establishing a connection over WebRTC.
     */
    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleLocalAddedIceCandidate(iceCandidate)
    }

    /**
     * Once the peerConnection is established, we can receive messages via the data channel, and notify the delegate.
     */
    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, received dataChannelMessage: WebRTCProtoData) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleDataChannelMessage(dataChannelMessage)
    }

    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, didUpdateLocalVideoCaptureSession captureSession: AVCaptureSession?) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }
        guard let callData = callData else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        callData.localCaptureSession = captureSession
        fireDidUpdateVideoTracks()
    }

    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, didUpdateRemoteVideoTrack videoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }
        guard let callData = callData else {
            Logger.debug("Ignoring event from obsolete peerConnectionClient")
            return
        }

        callData.remoteVideoTrack = videoTrack
        fireDidUpdateVideoTracks()
    }

    // MARK: -

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
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Guarantee<[RTCIceServer]> in
            Logger.error("fetching ICE servers failed with error: \(error)")
            Logger.warn("using fallback ICE Servers")

            return Guarantee.value([CallService.fallbackIceServer])
        }
    }

    // This method should be called when either: a) we know or assume that
    // the error is related to the current call. b) the error is so serious
    // that we want to terminate the current call (if any) in order to
    // return to a known good state.
    public func handleFailedCurrentCall(error: CallError) {
        Logger.debug("")

        // Return to a known good state by ending the current call, if any.
        handleFailedCall(failedCall: self.call, error: error)
    }

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall?, error: CallError) {
        AssertIsOnMainThread()

        if case CallError.assertionError(description: let description) = error {
            owsFailDebug(description)
        }

        if let failedCall = failedCall {

            switch failedCall.state {
            case .answering, .localRinging:
                assert(failedCall.callRecord == nil)
                // call failed before any call record could be created, make one now.
                handleMissedCall(failedCall)
            default:
                assert(failedCall.callRecord != nil)
            }

            // It's essential to set call.state before terminateCall, because terminateCall nils self.call
            failedCall.error = error
            failedCall.state = .localFailure
            self.callUIAdapter.failCall(failedCall, error: error)

            // Only terminate the current call if the error pertains to the current call.
            guard failedCall == self.call else {
                Logger.debug("ignoring obsolete call: \(failedCall.identifiersForLogs).")
                return
            }

            Logger.error("call: \(failedCall.identifiersForLogs) failed with error: \(error)")
        } else {
            Logger.error("unknown call failed with error: \(error)")
        }

        // Only terminate the call if it is the current call.
        terminateCall()
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    private func terminateCall() {
        AssertIsOnMainThread()

        Logger.debug("")

        let currentCallData = self.callData
        self.callData = nil

        currentCallData?.terminate()

        self.callUIAdapter.didTerminateCall(currentCallData?.call)

        fireDidUpdateVideoTracks()

        // Apparently WebRTC will sometimes disable device orientation notifications.
        // After every call ends, we need to ensure they are enabled.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("\(state)")

        updateIsVideoEnabled()
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.info("\(hasLocalVideo)")

        self.updateIsVideoEnabled()
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        // Do nothing
    }

    internal func holdDidChange(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()
        // Do nothing
    }

    internal func audioSourceDidChange(call: SignalCall, audioSource: AudioSource?) {
        AssertIsOnMainThread()
        // Do nothing
    }

    // MARK: - Video

    private func shouldHaveLocalVideoTrack() -> Bool {
        AssertIsOnMainThread()

        guard let call = self.call else {
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

    //TODO only fire this when it's changed? as of right now it gets called whenever you e.g. lock the phone while it's incoming ringing.
    private func updateIsVideoEnabled() {
        AssertIsOnMainThread()

        guard let call = self.call else {
            return
        }
        guard let peerConnectionClient = self.peerConnectionClient else {
            return
        }

        let shouldHaveLocalVideoTrack = self.shouldHaveLocalVideoTrack()

        Logger.info("\(shouldHaveLocalVideoTrack)")

        self.peerConnectionClient?.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack)

        var messageData: Data
        do {
            let videoStreamingStatusBuilder = WebRTCProtoVideoStreamingStatus.builder(id: call.signalingId)
            videoStreamingStatusBuilder.setEnabled(shouldHaveLocalVideoTrack)
            let dataBuilder = WebRTCProtoData.builder()
            dataBuilder.setVideoStreamingStatus(try videoStreamingStatusBuilder.build())
            messageData = try dataBuilder.buildSerializedData()
        } catch {
            Logger.error("couldn't build proto")
            return
        }

        peerConnectionClient.sendDataChannelMessage(data: messageData, description: "videoStreamingStatus", isCritical: false)
    }

    // MARK: - Observers

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(Weak(value: observer))

        // Synchronize observer with current call state
        let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil
        observer.didUpdateVideoTracks(call: self.call,
                                      localCaptureSession: self.localCaptureSession,
                                      remoteVideoTrack: remoteVideoTrack)
    }

    // The observer-related methods should be invoked on the main thread.
    func removeObserver(_ observer: CallServiceObserver) {
        AssertIsOnMainThread()

        while let index = observers.firstIndex(where: { $0.value === observer }) {
            observers.remove(at: index)
        }
    }

    // The observer-related methods should be invoked on the main thread.
    func removeAllObservers() {
        AssertIsOnMainThread()

        observers = []
    }

    private func fireDidUpdateVideoTracks() {
        AssertIsOnMainThread()

        let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil
        for observer in observers {
            observer.value?.didUpdateVideoTracks(call: self.call,
                                                 localCaptureSession: self.localCaptureSession,
                                                 remoteVideoTrack: remoteVideoTrack)
        }
    }

    // MARK: CallViewController Timer

    var activeCallTimer: Timer?
    func startCallTimer() {
        AssertIsOnMainThread()

        stopAnyCallTimer()
        assert(self.activeCallTimer == nil)

        self.activeCallTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { [weak self] timer in
            guard let strongSelf = self else {
                return
            }

            guard let call = strongSelf.call else {
                owsFailDebug("call has since ended. Timer should have been invalidated.")
                timer.invalidate()
                return
            }

            strongSelf.ensureCallScreenPresented(call: call)
        }
    }

    func ensureCallScreenPresented(call: SignalCall) {
        guard let currentCall = self.call else {
            owsFailDebug("obsolete call: \(call.identifiersForLogs)")
            return
        }
        guard currentCall == call else {
            owsFailDebug("obsolete call: \(call.identifiersForLogs)")
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

        guard !call.isTerminated else {
            // There's a brief window between when the callViewController is removed
            // and when this timer is terminated.
            //
            // We don't want to fail a call that's already terminated.
            Logger.debug("ignoring screen protection check for already terminated call.")
            return
        }

        if !OWSWindowManager.shared().hasCall() {
            OWSProdError(OWSAnalyticsEvents.callServiceCallViewCouldNotPresent(), file: #file, function: #function, line: #line)
            owsFailDebug("Call terminated due to missing call view.")
            self.handleFailedCall(failedCall: call, error: CallError.assertionError(description: "Call view didn't present after \(kMaxViewPresentationDelay) seconds"))
            return
        }
    }

    func stopAnyCallTimer() {
        AssertIsOnMainThread()

        self.activeCallTimer?.invalidate()
        self.activeCallTimer = nil
    }

    // MARK: - SignalCallDataDelegate

    func outgoingIceUpdateDidFail(call: SignalCall, error: Error) {
        AssertIsOnMainThread()

        guard self.call == call else {
            Logger.warn("obsolete call")
            return
        }

        handleFailedCall(failedCall: call, error: CallError.messageSendFailure(underlyingError: error))
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
