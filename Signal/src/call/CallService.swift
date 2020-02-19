//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalRingRTC
import WebRTC
import SignalServiceKit
import SignalMessaging

/**
 * `CallService` is a global singleton that manages the state of RingRTC-backed Signal
 * Calls (as opposed to legacy "RedPhone Calls" and "WebRTC Calls").
 *
 * It serves as a connection between the `CallUIAdapter` and the `CallConnection`
 * provided by RingRTC.
 *
 * ## Signaling
 *
 * Signaling refers to the setup and tear down of the connection. Before the connection
 * is established, this must happen out of band (using the Signal Service), but once the
 * connection is established it's possible to publish updates (like hangup) via the
 * established channel.
 *
 * Signaling state is synchronized on the main thread and only mutated in the handleXXX
 * family of methods.
 *
 * Following is a high level process of the exchange of messages that takes place during
 * call signaling.
 *
 * ### Key
 *
 * --[SOMETHING]--> represents a message from the caller to the callee
 * <--[SOMETHING]-- represents a message from the callee to the caller
 * SS: Message sent via Signal Service
 * DC: Message sent via RingRTC (using a WebRTC Data Channel)
 *
 * ### Message Exchange / State Flow Overview
 *
 * |          Caller        |                 Callee                 |
 * +------------------------+----------------------------------------+
 * Start outgoing call: `handleOutgoingCall`...
 *                  --[SS.CallOffer]-->
 * ...and start generating ICE updates.
 *
 * As ICE candidates are generated, `handleLocalAddedIceCandidate`
 * is called and we *store* the ICE updates for later.
 *
 *                           Received call offer: `handleReceivedOffer`
 *                                                   Send call answer
 *                 <--[SS.CallAnswer]--
 *                           ... and start generating ICE updates.
 *
 *                           As ICE candidates are generated, `handleLocalAddedIceCandidate`
 *                           is called which immediately sends the ICE updates to the Caller.
 *                 <--[SS.ICEUpdate]-- (sent multiple times)
 *
 * Received CallAnswer: `handleReceivedAnswer`
 * So send any stored ice updates (and send future ones immediately)
 *                 --[SS.ICEUpdates]-->
 *
 * Once compatible ICE updates have been exchanged both parties: `handleRinging`:
 *
 * Show remote ringing UI...
 *                           Show incoming call UI...
 *
 *                           If callee answers Call send `connected` message by invoking
 *                           the `accept` CallConnection API.
 *
 *               <--[DC.ConnectedMesage]--
 * Received connected message via remoteConnected call event...
 * Show Call is connected.
 *
 * Hang up (this could equally be sent by the Callee)
 *                   --[DC.Hangup]--> (via CallConnection API)
 *                   --[SS.Hangup]-->
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

    public var isTerminated: Bool

    public var backgroundTask: OWSBackgroundTask?

    // Used to ensure any received ICE messages wait until the callConnection is set up.
    let callConnectionPromise: Promise<Void>
    let callConnectionResolver: Resolver<Void>

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

    var callConnectionFactory: CallConnectionFactory? {
        didSet {
            AssertIsOnMainThread()

            Logger.debug(".callConnectionFactory setter: \(oldValue != nil) -> \(callConnectionFactory != nil) \(String(describing: callConnectionFactory))")
        }
    }

    var callConnection: CallConnection? {
        didSet {
            AssertIsOnMainThread()

            Logger.debug(".callConnection setter: \(oldValue != nil) -> \(callConnection != nil) \(String(describing: callConnection))")
        }
    }

    var shouldSendHangup = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    required init(call: SignalCall, delegate: SignalCallDataDelegate) {
        self.call = call
        self.delegate = delegate
        self.isTerminated = false

        let (callConnectionPromise, callConnectionResolver) = Promise<Void>.pending()
        self.callConnectionPromise = callConnectionPromise
        self.callConnectionResolver = callConnectionResolver

        let (readyToSendIceUpdatesPromise, readyToSendIceUpdatesResolver) = Promise<Void>.pending()
        self.readyToSendIceUpdatesPromise = readyToSendIceUpdatesPromise
        self.readyToSendIceUpdatesResolver = readyToSendIceUpdatesResolver

        self.callConnectionFactory = CallConnectionFactory()

        super.init()
    }

    deinit {
        Logger.debug("[SignalCallData] deinit")
    }

    // MARK: -

    public func terminate() {
        AssertIsOnMainThread()

        Logger.debug("")

        if (self.isTerminated) {
            owsFailDebug("Already terminated!")
            return
        }

        self.isTerminated = true

        self.call.removeAllObservers()

        // In case we're still waiting on the callConnection setup somewhere, we need to reject it to avoid a memory leak.
        // There is no harm in rejecting a previously fulfilled promise.
        self.callConnectionResolver.reject(CallError.obsoleteCall(description: "Terminating call"))

        // In case we're still waiting on this promise somewhere, we need to reject it to avoid a memory leak.
        // There is no harm in rejecting a previously fulfilled promise.
        self.readyToSendIceUpdatesResolver.reject(CallError.obsoleteCall(description: "Terminating call"))

        DispatchQueue.global().async {
            if let callConnection = self.callConnection {
                Logger.debug("Calling callConnection.close()")
                callConnection.close()
            }

            if let callConnectionFactory = self.callConnectionFactory {
                Logger.debug("Calling callConnectionFactory.close()")
                callConnectionFactory.close()
            }

            self.outgoingIceUpdateQueue.removeAll()

            Logger.debug("done")
        }
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
        Logger.info("")

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
                Logger.info("sent ice update call message")

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

// MARK: - CallService

// This class' state should only be accessed on the main queue.
@objc public class CallService: NSObject, CallObserver, CallConnectionDelegate, SignalCallDataDelegate {

    // MARK: - Properties

    var observers = [Weak<CallServiceObserver>]()

    // Exposed by environment.m

    @objc public var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    // MARK: Ivars

    fileprivate var deferredHangupList: [UInt64: SignalCallData] = [:]

    private var _callData: SignalCallData?
    fileprivate var callData: SignalCallData? {
        set {
            AssertIsOnMainThread()

            let oldValue = _callData
            _callData = newValue

            oldValue?.delegate = nil
            oldValue?.call.removeObserver(self)
            newValue?.call.addObserverAndSyncState(observer: self)

            updateIsVideoEnabled()

            // Prevent device from sleeping while we have an active call.
            if oldValue != newValue {
                if let oldValue = oldValue {
                    DeviceSleepManager.sharedInstance.removeBlock(blockObject: oldValue)
                }
                if let newValue = newValue {
                    DeviceSleepManager.sharedInstance.addBlock(blockObject: newValue)
                    self.startCallTimer()
                } else {
                    stopAnyCallTimer()
                }
            }

            Logger.debug(".callData setter: \(oldValue?.call.identifiersForLogs as Optional) -> \(newValue?.call.identifiersForLogs as Optional)")

            for observer in observers {
                observer.value?.didUpdateCall(call: newValue?.call)
            }
        }
        get {
            AssertIsOnMainThread()

            return _callData
        }
    }

    // NOTE: This accessor should only be used outside this class.
    //       Within this class use callData to ensure coherency.
    @objc
    var currentCall: SignalCall? {
        get {
            AssertIsOnMainThread()

            return callData?.call
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

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
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

        // TODO MULTIRING
        guard FeatureFlags.calling else {
            // The CallUIAdapter creates the callkit adaptee which in turn adds calling buttons
            // to the contacts app. They don't do anything, but it seems like they shouldn't be
            // there.
            Logger.info("not creating call UI adapter for device that doesn't support calling")
            return
        }

        if self.callData != nil {
            Logger.warn("ending current call in. Did user toggle callkit preference while in a call?")
            self.terminate(callData: self.callData)
        }

        self.callUIAdapter = CallUIAdapter(callService: self, contactsManager: self.contactsManager)
    }

    // MARK: - Service Actions

    /**
     * Initiate an outgoing call.
     */
    func handleOutgoingCall(_ call: SignalCall) -> Promise<Void> {
        AssertIsOnMainThread()
        Logger.info("")

        let callId = call.signalingId
        BenchEventStart(title: "Outgoing Call Connection", eventId: "call-\(callId)")

        guard self.callData == nil else {
            let errorDescription = "call was unexpectedly already set."
            Logger.error(errorDescription)
            call.state = .localFailure
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

        let promise = getIceServers().done { iceServers in
            guard !call.isTerminated else {
                Logger.debug("terminated call")
                return
            }

            guard self.callData === callData else {
                throw CallError.obsoleteCall(description: "obsolete call")
            }

            guard callData.callConnection == nil else {
                let errorDescription = "callConnection was unexpectedly already set."
                Logger.error(errorDescription)
                throw CallError.assertionError(description: errorDescription)
            }

            Logger.debug("got ice servers: \(iceServers) for call: \(call.identifiersForLogs)")

            let useTurnOnly = Environment.shared.preferences.doCallsHideIPAddress()

            // Create a CallConnection to handle the call media.
            let callConnection = try callData.callConnectionFactory?.createCallConnection(delegate: self, iceServers: iceServers, callId: callId, isOutgoing: true, hideIp: useTurnOnly)
            Logger.debug("setting callConnection for call: \(call.identifiersForLogs)")

            callData.callConnection = callConnection
            callData.callConnectionResolver.fulfill(())

            try callConnection?.sendOffer()
        }

        promise.catch { error in
            Logger.error("outgoing call \(call.identifiersForLogs) failed with error: \(error)")

            guard self.callData === callData else {
                Logger.debug("ignoring error for obsolete call")
                return
            }

            self.handleFailedCall(failedCall: call, error: error)
        }.retainUntilComplete()

        return promise
    }

    func readyToSendIceUpdates(call: SignalCall) {
        AssertIsOnMainThread()
        Logger.debug("")

        guard let callData = self.callData else {
            self.handleFailedCall(failedCall: call, error: CallError.obsoleteCall(description: "obsolete call"))
            return
        }
        guard callData.call === call else {
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
        Logger.info("for call: \(callId) thread: \(thread.contactAddress)")

        guard let callData = self.callData else {
            Logger.warn("ignoring obsolete call: \(callId)")
            return
        }
        let call = callData.call

        guard call.signalingId == callId else {
            Logger.warn("ignoring mismatched call: \(callId) currentCall: \(call.signalingId)")
            return
        }

        guard let callConnection = callData.callConnection else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "callConnection was unexpectedly nil"))
            return
        }

        do {
            try callConnection.receivedAnswer(sdp: sessionDescription)
        } catch {
            Logger.debug("receivedAnswer failed with \(error)")

            self.handleFailedCall(failedCall: call, error: error)
        }
    }

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        if call.callRecord == nil {
            // MJK TODO remove this timestamp param
            call.callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                     callType: .incomingMissed,
                                     in: call.thread)
        }

        guard let callRecord = call.callRecord else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "callRecord was unexpectedly nil"))
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

        guard let callData = self.callData else {
            Logger.warn("ignoring obsolete call: \(callId)")
            return
        }
        let call = callData.call

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
        terminate(callData: self.callData)
    }

    /**
     * Received an incoming call offer. We still have to complete setting up the Signaling channel before we notify
     * the user of an incoming call.
     */
    public func handleReceivedOffer(thread: TSContactThread, callId: UInt64, sessionDescription callerSessionDescription: String) {
        AssertIsOnMainThread()
        Logger.info("")

        BenchEventStart(title: "Incoming Call Connection", eventId: "call-\(callId)")

        let newCall = SignalCall.incomingCall(localId: UUID(), remoteAddress: thread.contactAddress, signalingId: callId)

        Logger.info("receivedCallOffer: \(newCall.identifiersForLogs)")

        let untrustedIdentity = OWSIdentityManager.shared().untrustedIdentityForSending(to: thread.contactAddress)

        guard tsAccountManager.isOnboarded() else {
            Logger.warn("user is not onboarded, skipping call.")
            let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                    callType: .incomingMissed,
                                    in: thread)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            databaseStorage.write { transaction in
                callRecord.anyInsert(transaction: transaction)
            }

            terminate(callData: nil)

            return
        }

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

            terminate(callData: nil)

            return
        }

        if let existingCallData = self.callData {
            let existingCall = existingCallData.call

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
                    terminate(callData: nil)
                }
            }

            return
        }

        Logger.info("starting new call: \(newCall.identifiersForLogs)")

        let callData = SignalCallData(call: newCall, delegate: self)
        self.callData = callData

        callData.shouldSendHangup = true

        Logger.debug("Enable backgroundTask")
        let backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }

            let timeout = CallError.timeout(description: "background task time ran out before call connected.")

            guard self.callData?.call === newCall else {
                Logger.warn("ignoring obsolete call")
                return
            }
            self.handleFailedCall(failedCall: newCall, error: timeout)
        })

        callData.backgroundTask = backgroundTask

        getIceServers().done { iceServers in
            // FIXME for first time call recipients I think we'll see mic/camera permission requests here,
            // even though, from the users perspective, no incoming call is yet visible.
            Logger.debug("got ice servers: \(iceServers) for call: \(newCall.identifiersForLogs)")

            guard let currentCallData = self.callData, currentCallData.call === newCall else {
                throw CallError.obsoleteCall(description: "getIceServers() response for obsolete call")
            }

            assert(currentCallData.callConnection == nil, "Unexpected CallConnection instance")

            // For contacts not stored in our system contacts, we assume they are an unknown caller, and we force
            // a TURN connection, so as not to reveal any connectivity information (IP/port) to the caller.
            let isUnknownCaller = !self.contactsManager.hasSignalAccount(for: thread.contactAddress)

            let useTurnOnly = isUnknownCaller || Environment.shared.preferences.doCallsHideIPAddress()

            // Create a CallConnection to handle the call media.
            let callConnection = try currentCallData.callConnectionFactory?.createCallConnection(delegate: self, iceServers: iceServers, callId: callId, isOutgoing: false, hideIp: useTurnOnly)
            Logger.debug("setting callConnection for call: \(newCall.identifiersForLogs)")

            callData.callConnection = callConnection
            callData.callConnectionResolver.fulfill(())

            try callConnection?.receivedOffer(sdp: callerSessionDescription)
        }.recover { error in
            Logger.error("incoming call \(newCall.identifiersForLogs) failed with error: \(error)")

            guard self.callData?.call === newCall else {
                Logger.debug("ignoring error for obsolete call")
                return
            }

            self.handleFailedCall(failedCall: newCall, error: error)
        }.retainUntilComplete()
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update
     */
    public func handleRemoteAddedIceCandidate(thread: TSContactThread, callId: UInt64, sdp: String, lineIndex: Int32, mid: String) {
        AssertIsOnMainThread()
        Logger.info("for callId: \(callId)")

        guard let callData = self.callData,
         callData.call.signalingId == callId else {
            Logger.warn("ignoring ICE candidate for obsolete call: \(callId)")
            return
        }

        callData.callConnectionPromise.done {
            AssertIsOnMainThread()
            Logger.debug("handling callId: \(callId)")

            guard callData === self.callData else {
                Logger.warn("ignoring ICE candidate for obsolete call: \(callId)")
                return
            }
            let call = callData.call

            guard thread.contactAddress == call.thread.contactAddress else {
                Logger.warn("ignoring remote ice update for thread: \(String(describing: thread.uniqueId)) due to thread mismatch. Call already ended?")
                return
            }

            guard let callConnection = callData.callConnection else {
                Logger.warn("ignoring remote ice update for thread: \(String(describing: thread.uniqueId)) since there is no current callConnection. Call already ended?")
                return
            }

            try callConnection.receivedIceCandidate(sdp: sdp, lineIndex: lineIndex, sdpMid: mid)
         }.catch { error in
            Logger.error("handleRemoteAddedIceCandidate failed with error: \(error)")

            // @note We will move on and try to connect the call.
        }.retainUntilComplete()
    }

    /**
     * Local client (could be caller or callee) generated some connectivity information that we should send to the 
     * remote client.
     */
    private func handleLocalAddedIceCandidate(_ iceCandidate: RTCIceCandidate, callData: SignalCallData) {
        AssertIsOnMainThread()

        guard self.callData === callData else {
            Logger.warn("Receive local ICE candidate for obsolete call.")
            return
        }

        // Wait until we've sent the CallOffer before sending any ice updates for the call to ensure
        // intuitive message ordering for other clients.
        callData.readyToSendIceUpdatesPromise.done {
            guard callData === self.callData else {
                self.handleFailedCurrentCall(error: .obsoleteCall(description: "current call changed since we became ready to send ice updates"))
                return
            }
            let call = callData.call

            guard call.state != .idle else {
                // This will only be called for the current callConnection, so
                // fail the current call.
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
            Logger.error("waitUntilReadyToSendIceUpdates failed with error: \(error)")
        }.retainUntilComplete()
    }

    /**
     * The clients can now communicate via WebRTC, so we can let the UI know.
     *
     * Called by both caller and callee. Compatible ICE messages have been exchanged between the local and remote
     * client.
     */
    private func handleRinging() {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData else {
            // This will only be called for the current callConnection, so
            // fail the current call.
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

    private func handleReconnecting() {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This will only be called for the current callConnection, so
            // fail the current call.
            handleFailedCurrentCall(error: CallError.assertionError(description: "ignoring \(#function) since there is no current call."))
            return
        }
        let call = callData.call

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
        Logger.info("")

        guard let callData = self.callData else {
            // This may happen if we hang up slightly before they hang up.
            handleFailedCurrentCall(error: .obsoleteCall(description:"call was unexpectedly nil"))
            return
        }
        let call = callData.call

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
        terminate(callData: self.callData)
    }

    /**
     * User chose to answer call referred to by call `localId`. Used by the Callee only.
     *
     * Used by notification actions which can't serialize a call object.
     */
    @objc public func handleAnswerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This should never happen; return to a known good state.
            owsFailDebug("call was unexpectedly nil")
            handleFailedCurrentCall(error: CallError.assertionError(description: "call was unexpectedly nil"))
            return
        }
            let call = callData.call

        guard call.localId == localId else {
            // This should never happen; return to a known good state.
            owsFailDebug("callLocalId: \(localId) doesn't match current calls: \(call.localId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "callLocalId: \(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        self.handleAnswerCall(call)
    }

    /**
     * User chose to answer call referred to by call `localId`. Used by the Callee only.
     */
    public func handleAnswerCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "callData unexpectedly nil"))
            return
        }

        guard call == callData.call else {
            // This could conceivably happen if the other party of an old call was slow to send us their answer
            // and we've subsequently engaged in another call. Don't kill the current call, but just ignore it.
            Logger.warn("ignoring \(#function) for call other than current call")
            return
        }

        guard let callConnection = callData.callConnection else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "missing callConnection"))
            return
        }

        Logger.info("\(call.identifiersForLogs).")

        // MJK TODO remove this timestamp param
        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), callType: .incomingIncomplete, in: call.thread)
        databaseStorage.write { transaction in
            callRecord.anyInsert(transaction: transaction)
        }
        call.callRecord = callRecord

        do {
            try callConnection.accept()
        } catch {
            self.handleFailedCall(failedCall: call, error: error)
            return
        }

        handleConnectedCall(callData)
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    private func handleConnectedCall(_ callData: SignalCallData) {
        AssertIsOnMainThread()
        Logger.info("")

        guard callData === self.callData else {
            Logger.debug("Ignoring connected for obsolete call.")
            return
        }
        let call = callData.call
        guard let callConnection = callData.callConnection else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "callConnection unexpectedly nil"))
            return
        }

        Logger.info("handleConnectedCall: \(callData.call.identifiersForLogs).")

        // End the background task.
        callData.backgroundTask = nil

        callData.call.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        ensureAudioState(call: callData.call, callConnection: callConnection)

        do {
            try callConnection.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
        } catch {
            owsFailDebug("callConnection.setLocalVideoEnabled failed \(error)")
        }
    }

    /**
     * Local user chose to end the call.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func handleLocalHungupCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData else {
            owsFailDebug("no valid callData found, nothing to hangup")
            return
        }

        guard callData.call === call else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "ignoring \(#function) for call other than current call"))
            return
        }

        Logger.info("\(call.identifiersForLogs)")

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

        let originalState = call.state
        call.state = .localHangup

        if let callConnection = callData.callConnection {
            // Stop audio capture ASAP
            ensureAudioState(call: call, callConnection: callConnection)

            switch originalState {
            case .dialing, .remoteRinging, .localRinging, .connected, .reconnecting:
                // Only in these states would we expect the CallConnection to
                // be negotiated and need to do a formal hangup (again).
                Logger.debug("hanging up via CallConnection")

                do {
                    // Hangup a call, should send 'hangup' message via data channel. Will
                    // also call shouldSendHangup which will send a 'hangup' message via
                    // signaling and actually terminate the call.

                    // Add the call to the deferredHangupList
                    deferredHangupList[call.signalingId] = callData
                    self.callData = nil

                    Logger.debug("deferredHangupList.count: \(deferredHangupList.count)")

                    try callConnection.hangup()
                } catch {
                    // In case of error, clear the item from the list.
                    deferredHangupList.removeValue(forKey: call.signalingId)

                    owsFailDebug("\(error)")
                    terminate(callData: callData)
                }
            default:
                Logger.debug("")

                terminate(callData: callData)
            }
        } else {
            Logger.info("ending call before callConnection created (device offline or quick hangup)")

            guard callData.shouldSendHangup else {
                terminate(callData: callData)
                return
            }

            do {
                let hangupBuilder = SSKProtoCallMessageHangup.builder(id: call.signalingId)
                let callMessage = OWSOutgoingCallMessage(thread: call.thread, hangupMessage: try hangupBuilder.build())
                let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
                    .done {
                        Logger.info("sent hangup call message to \(call.thread.contactAddress)")
                    }.ensure {
                        self.terminate(callData: callData)
                    }.catch { error in
                        owsFailDebug("failed to send hangup call message to \(call.thread.contactAddress) with error: \(error)")
                    }

                sendPromise.retainUntilComplete()
            } catch {
                owsFailDebug("couldn't build hangup proto")
                terminate(callData: callData)
            }
        }
    }

    /**
     * Local user toggled to mute audio.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setIsMuted(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This can happen after a call has ended. Reproducible on iOS11, when the other party ends the call.
            Logger.info("ignoring mute request for obsolete call")
            return
        }
        let call = callData.call

        call.isMuted = isMuted

        guard let callConnection = callData.callConnection else {
            // The callConnection might not be created yet.
            return
        }

        ensureAudioState(call: call, callConnection: callConnection)
    }

    /**
     * Local user toggled to hold call. Currently only possible via CallKit screen,
     * e.g. when another Call comes in.
     */
    func setIsOnHold(call: SignalCall, isOnHold: Bool) {
        AssertIsOnMainThread()

        guard let callData = self.callData, call == callData.call else {
            Logger.info("ignoring hold request for obsolete call")
            return
        }

        call.isOnHold = isOnHold

        guard let callConnection = callData.callConnection else {
            // The callConnection might not be created yet.
            return
        }

        ensureAudioState(call: call, callConnection: callConnection)
    }

    func ensureAudioState(call: SignalCall, callConnection: CallConnection) {
        guard call.state == .connected else {
            do {
                try callConnection.setLocalAudioEnabled(enabled: false)
            } catch {
                owsFailDebug("callConnection.setLocalAudioEnabled failed")
            }
            return
        }
        guard !call.isMuted else {
            do {
                try callConnection.setLocalAudioEnabled(enabled: false)
            } catch {
                owsFailDebug("callConnection.setLocalAudioEnabled failed")
            }
            return
        }
        guard !call.isOnHold else {
            do {
                try callConnection.setLocalAudioEnabled(enabled: false)
            } catch {
                owsFailDebug("callConnection.setLocalAudioEnabled failed")
            }
            return
        }

        do {
            try callConnection.setLocalAudioEnabled(enabled: true)
        } catch {
            owsFailDebug("callConnection.setLocalAudioEnabled failed")
        }
    }

    /**
     * Local user toggled video.
     *
     * Can be used for Incoming and Outgoing calls.
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
        guard let callData = self.callData else {
            owsFailDebug("Missing callData")
            return
        }

        frontmostViewController.ows_askForCameraPermissions { granted in
            guard self.callData === callData else {
                owsFailDebug("Ignoring camera permissions for obsolete call.")
                return
            }

            if granted {
                // Success callback; camera permissions are granted.
                self.setHasLocalVideoWithCameraPermissions(hasLocalVideo: hasLocalVideo)
            }
        }
    }

    private func setHasLocalVideoWithCameraPermissions(hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        guard let callData = self.callData else {
            // This can happen if you toggle local video right after
            // the other user ends the call.
            Logger.debug("Ignoring event from obsolete call.")
            return
        }
        let call = callData.call

        call.hasLocalVideo = hasLocalVideo

        guard let callConnection = callData.callConnection else {
            // The callConnection might not be created yet.
            return
        }

        if call.state == .connected {
            do {
                try callConnection.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
            } catch {
                owsFailDebug("callConnection.setLocalVideoEnabled failed \(error)")
            }
        }
    }

    @objc
    func handleCallKitStartVideo() {
        AssertIsOnMainThread()

        self.setHasLocalVideo(hasLocalVideo: true)
    }

    func setCameraSource(call: SignalCall, isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        guard let callData = self.callData,
            let callConnection = callData.callConnection else {
            return
        }

        do {
            try callConnection.setCameraSource(isUsingFrontCamera: isUsingFrontCamera)
        } catch {
            owsFailDebug("callConnection.setCameraSource failed")
        }
    }

    // MARK: - CallConnectionDelegate

    public func callConnection(_ callConnectionParam: CallConnection, onCallEvent event: CallEvent, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard FeatureFlags.calling else {
            Logger.info("Ignoring call event on unsupported device.")
            return
        }

        guard let callData = self.callData,
            callConnectionParam == callData.callConnection else {
            Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("received call event for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "received call event for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        switch event {
        case .ringing:
            Logger.debug("Got ringing.")

            // The underlying connection is established, notify the user.
            handleRinging()

        case .remoteConnected:
            Logger.debug("Got remoteConnected, the peer (callee) accepted the call: \(call.identifiersForLogs)")

            callUIAdapter.recipientAcceptedCall(call)
            handleConnectedCall(callData)

        case .remoteVideoEnable:
            Logger.debug("remote participant sent VideoStreamingStatus via data channel: \(call.identifiersForLogs).")

            callData.isRemoteVideoEnabled = true
            fireDidUpdateVideoTracks()

        case .remoteVideoDisable:
            Logger.debug("remote participant sent VideoStreamingStatus via data channel: \(call.identifiersForLogs).")

            callData.isRemoteVideoEnabled = false
            fireDidUpdateVideoTracks()

        case .remoteHangup:
            Logger.debug("Got remoteHangup: \(call.identifiersForLogs)")

            handleRemoteHangup(thread: call.thread, callId: callId)

        case .connectionFailed:
            Logger.debug("Got connectionFailed.")

            // Return to a known good state.
            self.handleFailedCurrentCall(error: CallError.disconnected)

        case .callTimeout:
            Logger.debug("Got callTimeout.")

            let description: String

            if call.direction == .outgoing {
                description = "timeout for outgoing call"
            } else {
                description = "timeout for incoming call"
            }

            handleFailedCall(failedCall: call, error: CallError.timeout(description: description))

        case .callReconnecting:
            Logger.debug("Got callReconnecting.")

            self.handleReconnecting()
        }
    }

    public func callConnection(_ callConnectionParam: CallConnection, onCallError error: String, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("Got an error from RingRTC: \(error)")

        guard let callData = self.callData,
            callConnectionParam == callData.callConnection else {
                Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("received call error for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "received call error for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        // We will try to send a hangup over signaling to let the
        // remote peer know we are ending the call.
        do {
            let hangupBuilder = SSKProtoCallMessageHangup.builder(id: call.signalingId)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, hangupMessage: try hangupBuilder.build())
            let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
                .done {
                    Logger.info("sent hangup call message to \(call.thread.contactAddress)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring hangup send success for obsolete call.")
                        return
                    }

                    // We fail the call rather than terminate it.
                    self.handleFailedCall(failedCall: call, error: CallError.assertionError(description: error))
                }.catch { error in
                    Logger.error("failed to send hangup call message to \(call.thread.contactAddress) with error: \(error)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring hangup send failure for obsolete call.")
                        return
                    }

                    self.handleFailedCall(failedCall: call, error: CallError.assertionError(description: "failed to send hangup call message"))
            }

            sendPromise.retainUntilComplete()
        } catch {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build hangup proto"))
        }
    }

    public func callConnection(_ callConnectionParam: CallConnection, onAddRemoteVideoTrack track: RTCVideoTrack, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData,
            callConnectionParam == callData.callConnection else {
                Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("received remote video track for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "received remote video track for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        callData.remoteVideoTrack = track
        fireDidUpdateVideoTracks()
    }

    public func callConnection(_ callConnectionParam: CallConnection, onUpdateLocalVideoSession session: AVCaptureSession?, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData,
            callConnectionParam == callData.callConnection else {
                Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("received local video session for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "received local video session for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        callData.localCaptureSession = session
        fireDidUpdateVideoTracks()
    }

    public func callConnection(_ callConnectionParam: CallConnection, shouldSendOffer sdp: String, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData,
            callConnectionParam == callData.callConnection else {
                Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard !call.isTerminated else {
            Logger.debug("terminated call")
            return
        }

        guard callId == call.signalingId else {
            owsFailDebug("should send offer for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "should send offer for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        callData.shouldSendHangup = true

        do {
            let offerBuilder = SSKProtoCallMessageOffer.builder(id: call.signalingId, sessionDescription: sdp)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, offerMessage: try offerBuilder.build())
            let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
                .done {
                    Logger.info("sent offer call message to \(call.thread.contactAddress)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring call offer send success for obsolete call.")
                        return
                    }

                    guard !call.isTerminated else {
                        Logger.debug("terminated call")
                        return
                    }

                    // Ultimately, RingRTC will start sending Ice Candidates at the proper
                    // time, so we open the gate here right after sending the offer.
                    self.readyToSendIceUpdates(call: call)
                }.catch { error in
                    Logger.error("failed to send offer call message to \(call.thread.contactAddress) with error: \(error)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring call offer send failure for obsolete call.")
                        return
                    }

                    self.handleFailedCall(failedCall: call, error: CallError.assertionError(description: "failed to send offer call message"))
                }

            sendPromise.retainUntilComplete()
        } catch {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build offer proto"))
        }
    }

    public func callConnection(_ callConnectionParam: CallConnection, shouldSendAnswer sdp: String, callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData, callConnectionParam == callData.callConnection else {
            Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("should send answer for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "should send answer for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        do {
            let answerBuilder = SSKProtoCallMessageAnswer.builder(id: call.signalingId, sessionDescription: sdp)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, answerMessage: try answerBuilder.build())
            let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
                .done {
                    Logger.info("sent answer call message to \(call.thread.contactAddress)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring call answer send success for obsolete call.")
                        return
                    }

                    guard !call.isTerminated else {
                        Logger.debug("terminated call")
                        return
                    }

                    // Ultimately, RingRTC will start sending Ice Candidates at the proper
                    // time, so we open the gate here right after sending the answer.
                    self.readyToSendIceUpdates(call: call)
                }.catch { error in
                    Logger.error("failed to send answer call message to \(call.thread.contactAddress) with error: \(error)")

                    guard self.callData === callData else {
                        Logger.debug("Ignoring call answer send failure for obsolete call.")
                        return
                    }

                    self.handleFailedCall(failedCall: call, error: CallError.assertionError(description: "failed to send answer call message"))
                }

            sendPromise.retainUntilComplete()
        } catch {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "couldn't build answer proto"))
        }
    }

    public func callConnection(_ callConnectionParam: CallConnection, shouldSendIceCandidates candidates: [RTCIceCandidate], callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = self.callData, callConnectionParam == callData.callConnection else {
            Logger.debug("Ignoring event from obsolete call.")
            return
        }

        let call = callData.call

        guard callId == call.signalingId else {
            owsFailDebug("should send ice candidate for call with id: \(callId) but current call has id: \(call.signalingId)")
            handleFailedCurrentCall(error: CallError.assertionError(description: "should send ice candidate for call with id: \(callId) but current call has id: \(call.signalingId)"))
            return
        }

        // We keep the Ice Candidate queue here in the app so that
        // it can batch candidates together as fast as it takes to
        // actually send the messages.
        for iceCandidate in candidates {
            self.handleLocalAddedIceCandidate(iceCandidate, callData: callData)
        }
    }

    public func callConnection(_ callConnectionParam: CallConnection, shouldSendHangup callId: UInt64) {
        AssertIsOnMainThread()
        Logger.info("")

        guard let callData = deferredHangupList.removeValue(forKey: callId) else {
            owsFailDebug("obsolete call: \(callId)")
            return
        }

        Logger.debug("deferredHangupList.count: \(deferredHangupList.count)")

        guard callConnectionParam == callData.callConnection else {
            Logger.debug("obsolete client: \(callId)")
            return
        }

        guard !callData.isTerminated else {
            owsFailDebug("Call was already terminated!")
            return
        }

        let call = callData.call

        do {
            let hangupBuilder = SSKProtoCallMessageHangup.builder(id: call.signalingId)
            let callMessage = OWSOutgoingCallMessage(thread: call.thread, hangupMessage: try hangupBuilder.build())
            let sendPromise = messageSender.sendMessage(.promise, callMessage.asPreparer)
                .done {
                    Logger.info("sent hangup call message to \(call.thread.contactAddress)")
                }.ensure {
                    self.terminate(callData: callData)
                }.catch { error in
                    owsFailDebug("failed to send hangup call message to \(call.thread.contactAddress) with error: \(error)")
                }

            sendPromise.retainUntilComplete()
        } catch {
            owsFailDebug("couldn't build hangup proto")
            terminate(callData: callData)
        }
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
        handleFailedCall(failedCall: self.callData?.call, error: error)
    }

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall?, error: Error) {
        AssertIsOnMainThread()

        let callError: CallError = {
            switch error {
            case let callError as CallError:
                return callError
            default:
                return CallError.externalError(underlyingError: error)
            }
        }()

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
            failedCall.error = callError
            failedCall.state = .localFailure
            self.callUIAdapter.failCall(failedCall, error: callError)

            // Only terminate the current call if the error pertains to the current call.
            guard failedCall === self.callData?.call else {
                Logger.debug("ignoring obsolete call: \(failedCall.identifiersForLogs).")
                return
            }

            Logger.error("call: \(failedCall.identifiersForLogs) failed with error: \(error)")
        } else {
            Logger.error("unknown call failed with error: \(error)")
        }

        // Only terminate the call if it is the current call.
        terminate(callData: self.callData)
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    private func terminate(callData: SignalCallData?) {
        AssertIsOnMainThread()
        Logger.info("")

        // If callData is for the current call, clear it out first.
        if self.callData === callData {
            Logger.debug("")

            // Terminating the current call.
            fireDidUpdateVideoTracks()

            // nil self.callData when terminating the current call.
            self.callData = nil
        }

        callData?.terminate()

        callUIAdapter.didTerminateCall(callData?.call)

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

        guard let callData = self.callData else {
            return false
        }
            let call = callData.call

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

        guard let callData = self.callData else {
            return
        }

        guard let callConnection = callData.callConnection else {
            return
        }

        let shouldHaveLocalVideoTrack = self.shouldHaveLocalVideoTrack()

        Logger.info("shouldHaveLocalVideoTrack: \(shouldHaveLocalVideoTrack)")

        do {
            try callConnection.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack)
            if callData.call.state == .connected {
                try callConnection.sendLocalVideoStatus(enabled: shouldHaveLocalVideoTrack)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: - Observers

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(Weak(value: observer))

        // Synchronize observer with current call state
        fireDidUpdateVideoTracks(forObserver: observer)
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

        for weakObserver in observers {
            if let observer = weakObserver.value {
                fireDidUpdateVideoTracks(forObserver: observer)
            }
        }
    }

    private func fireDidUpdateVideoTracks(forObserver observer: CallServiceObserver) {
        AssertIsOnMainThread()

        let isRemoteVideoEnabled = callData?.isRemoteVideoEnabled ?? false
        let remoteVideoTrack = isRemoteVideoEnabled ? callData?.remoteVideoTrack : nil
        observer.didUpdateVideoTracks(call: callData?.call,
                                      localCaptureSession: callData?.localCaptureSession,
                                      remoteVideoTrack: remoteVideoTrack)
    }

    // MARK: CallViewController Timer

    var activeCallTimer: Timer?
    func startCallTimer() {
        AssertIsOnMainThread()

        stopAnyCallTimer()
        assert(self.activeCallTimer == nil)

        guard let callData = self.callData else {
            owsFailDebug("Missing callData.")
            return
        }

        self.activeCallTimer = WeakTimer.scheduledTimer(timeInterval: 1, target: self, userInfo: nil, repeats: true) { timer in
            guard callData === self.callData else {
                owsFailDebug("call has since ended. Timer should have been invalidated.")
                timer.invalidate()
                return
            }
            let call = callData.call

            self.ensureCallScreenPresented(call: call)
        }
    }

    func ensureCallScreenPresented(call: SignalCall) {
        guard self.callData?.call === call else {
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

        if !OWSWindowManager.shared.hasCall {
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

        guard self.callData?.call === call else {
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
