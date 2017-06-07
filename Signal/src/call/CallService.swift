//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC

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

enum CallError: Error {
    case providerReset
    case assertionError(description: String)
    case disconnected
    case externalError(underlyingError: Error)
    case timeout(description: String)
    case obsoleteCall(description: String)
}

// Should be roughly synced with Android client for consistency
fileprivate let connectingTimeoutSeconds = 120

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
                              localVideoTrack: RTCVideoTrack?,
                              remoteVideoTrack: RTCVideoTrack?)
}

// This class' state should only be accessed on the main queue.
@objc class CallService: NSObject, CallObserver, PeerConnectionClientDelegate {

    // MARK: - Properties

    let TAG = "[CallService]"

    var observers = [Weak<CallServiceObserver>]()

    // MARK: Dependencies

    private let accountManager: AccountManager
    private let messageSender: MessageSender
    private let contactsManager: OWSContactsManager
    private let storageManager: TSStorageManager

    // Exposed by environment.m
    internal let notificationsAdapter: CallNotificationsAdapter
    internal var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    // MARK: Ivars

    var peerConnectionClient: PeerConnectionClient? {
        didSet {
            AssertIsOnMainThread()

            Logger.debug("\(self.TAG) .peerConnectionClient setter: \(oldValue != nil) -> \(peerConnectionClient != nil) \(String(describing: peerConnectionClient))")
        }
    }

    // TODO code cleanup: move thread into SignalCall? Or refactor messageSender to take SignalRecipient identifier.
    var thread: TSContactThread?
    var call: SignalCall? {
        didSet {
            AssertIsOnMainThread()

            oldValue?.removeObserver(self)
            call?.addObserverAndSyncState(observer: self)

            updateIsVideoEnabled()
            updateLockTimerEnabling()

            Logger.debug("\(self.TAG) .call setter: \(oldValue != nil) -> \(call != nil) \(String(describing: call))")

            for observer in observers {
                observer.value?.didUpdateCall(call:call)
            }
        }
    }

    /**
     * In the process of establishing a connection between the clients (ICE process) we must exchange ICE updates.
     * Because this happens via Signal Service it's possible the callee user has not accepted any change in the caller's 
     * identity. In which case *each* ICE update would cause an "identity change" warning on the callee's device. Since
     * this could be several messages, the caller stores all ICE updates until receiving positive confirmation that the 
     * callee has received a message from us. This positive confirmation comes in the form of the callees `CallAnswer` 
     * message.
     */
    var sendIceUpdatesImmediately = true
    var pendingIceUpdateMessages = [OWSCallIceUpdateMessage]()

    // ensure the incoming call promise isn't dealloc'd prematurely
    var incomingCallPromise: Promise<Void>?

    // Used to coordinate promises across delegate methods
    var fulfillCallConnectedPromise: (() -> Void)?

    weak var localVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }
    var isRemoteVideoEnabled = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }

    required init(accountManager: AccountManager, contactsManager: OWSContactsManager, messageSender: MessageSender, notificationsAdapter: CallNotificationsAdapter) {
        self.accountManager = accountManager
        self.contactsManager = contactsManager
        self.messageSender = messageSender
        self.notificationsAdapter = notificationsAdapter
        self.storageManager = TSStorageManager.shared()

        super.init()

        self.createCallUIAdapter()

        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didEnterBackground),
                                               name:NSNotification.Name.UIApplicationDidEnterBackground,
                                               object:nil)
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didBecomeActive),
                                               name:NSNotification.Name.UIApplicationDidBecomeActive,
                                               object:nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func didEnterBackground() {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) \(#function)")

        self.updateIsVideoEnabled()
    }

    func didBecomeActive() {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) \(#function)")

        self.updateIsVideoEnabled()
    }

    /**
     * Choose whether to use CallKit or a Notification backed interface for calling.
     */
    public func createCallUIAdapter() {
        AssertIsOnMainThread()

        if self.call != nil {
            Logger.warn("\(TAG) ending current call in \(#function). Did user toggle callkit preference while in a call?")
            self.terminateCall()
        }
        self.callUIAdapter = CallUIAdapter(callService: self, contactsManager: self.contactsManager, notificationsAdapter: self.notificationsAdapter)
    }

    // MARK: - Class Methods

    // MARK: Notifications

    // Wrapping these class constants in a method to make it accessible to objc
    class func callServiceActiveCallNotificationName() -> String {
        return  "CallServiceActiveCallNotification"
    }

    // MARK: - Service Actions

    /**
     * Initiate an outgoing call.
     */
    public func handleOutgoingCall(_ call: SignalCall) -> Promise<Void> {
        AssertIsOnMainThread()

        guard self.call == nil else {
            let errorDescription = "\(TAG) call was unexpectedly already set."
            Logger.error(errorDescription)
            call.state = .localFailure
            return Promise(error: CallError.assertionError(description: errorDescription))
        }

        self.call = call

        let thread = TSContactThread.getOrCreateThread(contactId: call.remotePhoneNumber)
        self.thread = thread

        sendIceUpdatesImmediately = false
        pendingIceUpdateMessages = []

        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), withCallNumber: call.remotePhoneNumber, callType: RPRecentCallTypeOutgoingIncomplete, in: thread)
        callRecord.save()
        call.callRecord = callRecord

        return getIceServers().then { iceServers -> Promise<HardenedRTCSessionDescription> in
            Logger.debug("\(self.TAG) got ice servers:\(iceServers)")

            guard self.call == call else {
                throw CallError.obsoleteCall(description:"obsolete call in \(#function)")
            }

            guard self.peerConnectionClient == nil else {
                let errorDescription = "\(self.TAG) peerconnection was unexpectedly already set."
                Logger.error(errorDescription)
                throw CallError.assertionError(description: errorDescription)
            }

            let useTurnOnly = Environment.getCurrent().preferences.doCallsHideIPAddress()

            let peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self, callDirection: .outgoing, useTurnOnly: useTurnOnly)
            Logger.debug("\(self.TAG) setting peerConnectionClient in \(#function)")
            self.peerConnectionClient = peerConnectionClient

            return peerConnectionClient.createOffer()
        }.then { (sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> in
            guard self.call == call else {
                throw CallError.obsoleteCall(description:"obsolete call in \(#function)")
            }
            guard let peerConnectionClient = self.peerConnectionClient else {
                assertionFailure("Missing peerConnectionClient in \(#function)")
                throw CallError.obsoleteCall(description:"Missing peerConnectionClient in \(#function)")
            }

            return peerConnectionClient.setLocalSessionDescription(sessionDescription).then {
                let offerMessage = OWSCallOfferMessage(callId: call.signalingId, sessionDescription: sessionDescription.sdp)
                let callMessage = OWSOutgoingCallMessage(thread: thread, offerMessage: offerMessage)
                return self.messageSender.sendCallMessage(callMessage)
            }
        }.then {
            guard self.call == call else {
                throw CallError.obsoleteCall(description:"obsolete call in \(#function)")
            }

            let (callConnectedPromise, fulfill, _) = Promise<Void>.pending()
            self.fulfillCallConnectedPromise = fulfill

            // Don't let the outgoing call ring forever. We don't support inbound ringing forever anyway.
            let timeout: Promise<Void> = after(interval: TimeInterval(connectingTimeoutSeconds)).then { () -> Void in
                // rejecting a promise by throwing is safely a no-op if the promise has already been fulfilled
                throw CallError.timeout(description: "timed out waiting to receive call answer")
            }

            return race(timeout, callConnectedPromise)
        }.then {
            Logger.info(self.call == call
                ? "\(self.TAG) outgoing call connected."
                : "\(self.TAG) obsolete outgoing call connected.")
        }.catch { error in
            Logger.error("\(self.TAG) placing call failed with error: \(error)")

            if let callError = error as? CallError {
                self.handleFailedCall(failedCall: call, error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: call, error: externalError)
            }
        }
    }

    /**
     * Called by the call initiator after receiving a CallAnswer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sessionDescription: String) {
        Logger.info("\(TAG) received call answer for call: \(callId) thread: \(thread)")
        AssertIsOnMainThread()

        guard let call = self.call else {
            Logger.warn("\(self.TAG) ignoring obsolete call in \(#function)")
            return
        }

        guard call.signalingId == callId else {
            Logger.warn("\(self.TAG) ignoring obsolete call in \(#function)")
            return
        }

        // Now that we know the recipient trusts our identity, we no longer need to enqueue ICE updates.
        self.sendIceUpdatesImmediately = true

        if pendingIceUpdateMessages.count > 0 {
            Logger.error("\(self.TAG) Sending \(pendingIceUpdateMessages.count) pendingIceUpdateMessages")

            let callMessage = OWSOutgoingCallMessage(thread: thread, iceUpdateMessages: pendingIceUpdateMessages)
            let sendPromise = messageSender.sendCallMessage(callMessage).catch { error in
                Logger.error("\(self.TAG) failed to send ice updates in \(#function) with error: \(error)")
            }
            sendPromise.retainUntilComplete()
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(failedCall: call, error: CallError.assertionError(description: "peerConnectionClient was unexpectedly nil in \(#function)"))
            return
        }

        let sessionDescription = RTCSessionDescription(type: .answer, sdp: sessionDescription)
        let setDescriptionPromise = peerConnectionClient.setRemoteSessionDescription(sessionDescription).then {
            Logger.debug("\(self.TAG) successfully set remote description")
        }.catch { error in
            if let callError = error as? CallError {
                self.handleFailedCall(failedCall: call, error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: call, error: externalError)
            }
        }
        setDescriptionPromise.retainUntilComplete()
    }

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall, thread: TSContactThread) {
        AssertIsOnMainThread()

        // Insert missed call record
        if let callRecord = call.callRecord {
            if callRecord.callType == RPRecentCallTypeIncoming {
                callRecord.updateCallType(RPRecentCallTypeMissed)
            }
        } else {
            call.callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                     withCallNumber: thread.contactIdentifier(),
                                     callType: RPRecentCallTypeMissed,
                                     in: thread)
        }

        assert(call.callRecord != nil)
        call.callRecord?.save()

        self.callUIAdapter.reportMissedCall(call)
    }

    /**
     * Received a call while already in another call.
     */
    private func handleLocalBusyCall(_ call: SignalCall, thread: TSContactThread) {
        Logger.info("\(TAG) \(#function) for call: \(call) thread: \(thread)")
        AssertIsOnMainThread()

        let busyMessage = OWSCallBusyMessage(callId: call.signalingId)
        let callMessage = OWSOutgoingCallMessage(thread: thread, busyMessage: busyMessage)
        let sendPromise = messageSender.sendCallMessage(callMessage)
        sendPromise.retainUntilComplete()

        handleMissedCall(call, thread: thread)
    }

    /**
     * The callee was already in another call.
     */
    public func handleRemoteBusy(thread: TSContactThread) {
        Logger.info("\(TAG) \(#function) for thread: \(thread)")
        AssertIsOnMainThread()

        guard let call = self.call else {
            Logger.warn("\(self.TAG) ignoring obsolete call in \(#function)")
            return
        }

        guard thread.contactIdentifier() == call.remotePhoneNumber else {
            Logger.warn("\(self.TAG) ignoring obsolete call in \(#function)")
            return
        }

        call.state = .remoteBusy
        callUIAdapter.remoteBusy(call)
        terminateCall()
    }

    /**
     * Received an incoming call offer. We still have to complete setting up the Signaling channel before we notify
     * the user of an incoming call.
     */
    public func handleReceivedOffer(thread: TSContactThread, callId: UInt64, sessionDescription callerSessionDescription: String) {
        AssertIsOnMainThread()

        Logger.info("\(TAG) receivedCallOffer for thread:\(thread)")

        let newCall = SignalCall.incomingCall(localId: UUID(), remotePhoneNumber: thread.contactIdentifier(), signalingId: callId)

        let untrustedIdentity = OWSIdentityManager.shared().untrustedIdentityForSending(toRecipientId: thread.contactIdentifier())

        guard untrustedIdentity == nil else {
            let callerName = self.contactsManager.displayName(forPhoneIdentifier: thread.contactIdentifier())

            switch(untrustedIdentity!.verificationState) {
            case .verified:
                Logger.error("\(TAG) shouldn't have missed a call due to untrusted identity if the identity is verified")
                assertionFailure("shouldn't have missed a call due to untrusted identity if the identity is verified")
                self.notificationsAdapter.presentMissedCall(newCall, callerName: callerName)
            case .default:
                self.notificationsAdapter.presentMissedCallBecauseOfNewIdentity(call: newCall, callerName: callerName)
            case .noLongerVerified:
                self.notificationsAdapter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: newCall, callerName: callerName)
            }

            let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                    withCallNumber: thread.contactIdentifier(),
                                    callType: RPRecentCallTypeMissedBecauseOfChangedIdentity,
                                    in: thread)
            assert(newCall.callRecord == nil)
            newCall.callRecord = callRecord
            callRecord.save()

            return
        }

        guard self.call == nil else {
            // TODO on iOS10+ we can use CallKit to swap calls rather than just returning busy immediately.
            Logger.verbose("\(TAG) receivedCallOffer for thread: \(thread) but we're already in call: \(call!)")

            handleLocalBusyCall(newCall, thread: thread)
            return
        }

        self.thread = thread
        call = newCall

        let backgroundTask = UIApplication.shared.beginBackgroundTask {
            let timeout = CallError.timeout(description: "background task time ran out before call connected.")
            DispatchQueue.main.async {
                guard self.call == newCall else {
                    Logger.warn("\(self.TAG) ignoring obsolete call in \(#function)")
                    return
                }
                self.handleFailedCall(failedCall: newCall, error: timeout)
            }
        }

        incomingCallPromise = firstly {
            return getIceServers()
        }.then { (iceServers: [RTCIceServer]) -> Promise<HardenedRTCSessionDescription> in
            // FIXME for first time call recipients I think we'll see mic/camera permission requests here,
            // even though, from the users perspective, no incoming call is yet visible.
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "getIceServers() response for obsolete call")
            }
            assert(self.peerConnectionClient == nil, "Unexpected PeerConnectionClient instance")

            // For contacts not stored in our system contacts, we assume they are an unknown caller, and we force
            // a TURN connection, so as not to reveal any connectivity information (IP/port) to the caller.
            let unknownCaller = self.contactsManager.signalAccount(forRecipientId: thread.contactIdentifier()) == nil

            let useTurnOnly = unknownCaller || Environment.getCurrent().preferences.doCallsHideIPAddress()

            Logger.debug("\(self.self.TAG) setting peerConnectionClient in \(#function)")
            let peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self, callDirection: .incoming, useTurnOnly: useTurnOnly)
            self.peerConnectionClient = peerConnectionClient

            let offerSessionDescription = RTCSessionDescription(type: .offer, sdp: callerSessionDescription)
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

            // Find a sessionDescription compatible with my constraints and the remote sessionDescription
            return peerConnectionClient.negotiateSessionDescription(remoteDescription: offerSessionDescription, constraints: constraints)
        }.then { (negotiatedSessionDescription: HardenedRTCSessionDescription) in
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "negotiateSessionDescription() response for obsolete call")
            }
            Logger.debug("\(self.TAG) set the remote description")

            let answerMessage = OWSCallAnswerMessage(callId: newCall.signalingId, sessionDescription: negotiatedSessionDescription.sdp)
            let callAnswerMessage = OWSOutgoingCallMessage(thread: thread, answerMessage: answerMessage)

            return self.messageSender.sendCallMessage(callAnswerMessage)
        }.then {
            guard self.call == newCall else {
                throw CallError.obsoleteCall(description: "sendCallMessage() response for obsolete call")
            }
            Logger.debug("\(self.TAG) successfully sent callAnswerMessage")

            let (promise, fulfill, _) = Promise<Void>.pending()

            let timeout: Promise<Void> = after(interval: TimeInterval(connectingTimeoutSeconds)).then { () -> Void in
                // rejecting a promise by throwing is safely a no-op if the promise has already been fulfilled
                throw CallError.timeout(description: "timed out waiting for call to connect")
            }

            // This will be fulfilled (potentially) by the RTCDataChannel delegate method
            self.fulfillCallConnectedPromise = fulfill

            return race(promise, timeout)
        }.then {
            Logger.info(self.call == newCall
                ? "\(self.TAG) incoming call connected."
                : "\(self.TAG) obsolete incoming call connected.")
        }.catch { error in
            guard self.call == newCall else {
                Logger.debug("\(self.TAG) error for obsolete call: \(error)")
                return
            }
            if let callError = error as? CallError {
                self.handleFailedCall(failedCall: newCall, error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(failedCall: newCall, error: externalError)
            }
        }.always {
            Logger.debug("\(self.TAG) ending background task awaiting inbound call connection")
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    /**
     * Remote client (could be caller or callee) sent us a connectivity update
     */
    public func handleRemoteAddedIceCandidate(thread: TSContactThread, callId: UInt64, sdp: String, lineIndex: Int32, mid: String) {
        AssertIsOnMainThread()
        Logger.info("\(TAG) called \(#function)")

        guard let currentThread = self.thread else {
            Logger.warn("ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?")
            return
        }

        guard thread.contactIdentifier() == currentThread.contactIdentifier() else {
            Logger.warn("ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?")
            return
        }

        guard let call = self.call else {
            Logger.warn("ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?")
            return
        }

        guard call.signalingId == callId else {
            Logger.warn("ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?")
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            Logger.warn("ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?")
            return
        }

        peerConnectionClient.addIceCandidate(RTCIceCandidate(sdp: sdp, sdpMLineIndex: lineIndex, sdpMid: mid))
    }

    /**
     * Local client (could be caller or callee) generated some connectivity information that we should send to the 
     * remote client.
     */
    private func handleLocalAddedIceCandidate(_ iceCandidate: RTCIceCandidate) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            handleFailedCurrentCall(error: .assertionError(description: "ignoring local ice candidate, since there is no current call."))
            return
        }

        guard call.state != .idle else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            handleFailedCurrentCall(error: .assertionError(description: "ignoring local ice candidate, since call is now idle."))
            return
        }

        guard let thread = self.thread else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            handleFailedCurrentCall(error: .assertionError(description: "ignoring local ice candidate, because there was no current TSContactThread."))
            return
        }

        let iceUpdateMessage = OWSCallIceUpdateMessage(callId: call.signalingId, sdp: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMLineIndex, sdpMid: iceCandidate.sdpMid)

        if self.sendIceUpdatesImmediately {
            Logger.info("\(TAG) in \(#function). Sending immediately.")
            let callMessage = OWSOutgoingCallMessage(thread: thread, iceUpdateMessage: iceUpdateMessage)
            let sendPromise = self.messageSender.sendCallMessage(callMessage)
            sendPromise.retainUntilComplete()
        } else {
            // For outgoing messages, we wait to send ice updates until we're sure client received our call message.
            // e.g. if the client has blocked our message due to an identity change, we'd otherwise
            // bombard them with a bunch *more* undecipherable messages.
            Logger.info("\(TAG) in \(#function). Enqueing for later.")
            self.pendingIceUpdateMessages.append(iceUpdateMessage)
            return
        }
    }

    /**
     * The clients can now communicate via WebRTC.
     *
     * Called by both caller and callee. Compatible ICE messages have been exchanged between the local and remote 
     * client.
     */
    private func handleIceConnected() {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function)")

        guard let call = self.call else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call."))
            return
        }

        guard let thread = self.thread else {
            // This will only be called for the current peerConnectionClient, so
            // fail the current call.
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current thread."))
            return
        }

        switch call.state {
        case .dialing:
            call.state = .remoteRinging
        case .answering:
            call.state = .localRinging
            self.callUIAdapter.reportIncomingCall(call, thread: thread)
        case .remoteRinging:
            Logger.info("\(TAG) call alreading ringing. Ignoring \(#function)")
        case .connected:
            Logger.info("\(TAG) Call reconnected \(#function)")
        default:
            Logger.debug("\(TAG) unexpected call state for \(#function): \(call.state)")
        }
    }

    /**
     * The remote client (caller or callee) ended the call.
     */
    public func handleRemoteHangup(thread: TSContactThread) {
        Logger.debug("\(TAG) in \(#function)")
        AssertIsOnMainThread()

        guard thread.contactIdentifier() == self.thread?.contactIdentifier() else {
            // This can safely be ignored.
            // We don't want to fail the current call because an old call was slow to send us the hangup message.
            Logger.warn("\(TAG) ignoring hangup for thread:\(thread) which is not the current thread: \(String(describing: self.thread))")
            return
        }

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) call was unexpectedly nil in \(#function)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
            return
        }

        switch call.state {
        case .idle, .dialing, .answering, .localRinging, .localFailure, .remoteBusy, .remoteRinging:
            handleMissedCall(call, thread: thread)
        case .connected, .localHangup, .remoteHangup:
            Logger.info("\(TAG) call is finished.")
        }

        call.state = .remoteHangup
        // Notify UI
        callUIAdapter.remoteDidHangupCall(call)

        // self.call is nil'd in `terminateCall`, so it's important we update it's state *before* calling `terminateCall`
        terminateCall()
    }

    /**
     * User chose to answer call referrred to by call `localId`. Used by the Callee only.
     *
     * Used by notification actions which can't serialize a call object.
     */
    public func handleAnswerCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) call was unexpectedly nil in \(#function)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
            return
        }

        guard call.localId == localId else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        self.handleAnswerCall(call)
    }

    /**
     * User chose to answer call referrred to by call `localId`. Used by the Callee only.
     */
    public func handleAnswerCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function)")

        guard let currentCall = self.call else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call"))
            return
        }

        guard call == currentCall else {
            // This could conceivably happen if the other party of an old call was slow to send us their answer
            // and we've subsequently engaged in another call. Don't kill the current call, but just ignore it.
            Logger.warn("\(TAG) ignoring \(#function) for call other than current call")
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) ignoring \(#function) for call other than current call"))
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) missing peerconnection client in \(#function)"))
            return
        }

        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), withCallNumber: call.remotePhoneNumber, callType: RPRecentCallTypeIncomingIncomplete, in: thread)
        callRecord.save()
        call.callRecord = callRecord

        let message = DataChannelMessage.forConnected(callId: call.signalingId)
        peerConnectionClient.sendDataChannelMessage(data: message.asData())

        handleConnectedCall(call)
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    func handleConnectedCall(_ call: SignalCall) {
        Logger.debug("\(TAG) in \(#function)")
        AssertIsOnMainThread()

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) peerConnectionClient unexpectedly nil in \(#function)"))
            return
        }

        assert(self.fulfillCallConnectedPromise != nil)
        // cancel connection timeout
        self.fulfillCallConnectedPromise?()

        call.state = .connected

        // We don't risk transmitting any media until the remote client has admitted to being connected.
        peerConnectionClient.setAudioEnabled(enabled: !call.isMuted)
        peerConnectionClient.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
    }

    /**
     * Local user chose to decline the call vs. answering it.
     *
     * The call is referred to by call `localId`, which is included in Notification actions.
     *
     * Incoming call only.
     */
    public func handleDeclineCall(localId: UUID) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) call was unexpectedly nil in \(#function)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
            return
        }

        guard call.localId == localId else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        self.handleDeclineCall(call)
    }

    /**
     * Local user chose to decline the call vs. answering it.
     *
     * Incoming call only.
     */
    public func handleDeclineCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        Logger.info("\(TAG) in \(#function)")

        // Currently we just handle this as a hangup. But we could offer more descriptive action. e.g. DataChannel message
        handleLocalHungupCall(call)
    }

    /**
     * Local user chose to end the call.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func handleLocalHungupCall(_ call: SignalCall) {
        AssertIsOnMainThread()

        guard let currentCall = self.call else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call"))
            return
        }

        guard call == currentCall else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) ignoring \(#function) for call other than current call"))
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) missing peerconnection client in \(#function)"))
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(failedCall: call, error: .assertionError(description:"\(TAG) missing thread in \(#function)"))
            return
        }

        call.state = .localHangup

        // TODO something like this lifted from Signal-Android.
        //        this.accountManager.cancelInFlightRequests();
        //        this.messageSender.cancelInFlightRequests();

        // If the call is connected, we can send the hangup via the data channel.
        let message = DataChannelMessage.forHangup(callId: call.signalingId)
        peerConnectionClient.sendDataChannelMessage(data: message.asData())

        // If the call hasn't started yet, we don't have a data channel to communicate the hang up. Use Signal Service Message.
        let hangupMessage = OWSCallHangupMessage(callId: call.signalingId)
        let callMessage = OWSOutgoingCallMessage(thread: thread, hangupMessage: hangupMessage)
        let sendPromise = self.messageSender.sendCallMessage(callMessage).then {
            Logger.debug("\(self.TAG) successfully sent hangup call message to \(thread)")
        }.catch { error in
            Logger.error("\(self.TAG) failed to send hangup call message to \(thread) with error: \(error)")
        }
        sendPromise.retainUntilComplete()

        terminateCall()
    }

    /**
     * Local user toggled to mute audio.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setIsMuted(isMuted: Bool) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) call was unexpectedly nil in \(#function)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) call unexpectedly nil in \(#function)"))
            return
        }

        call.isMuted = isMuted

        guard let peerConnectionClient = self.peerConnectionClient else {
            // The peer connection might not be created yet.
            return
        }

        if call.state == .connected {
            peerConnectionClient.setAudioEnabled(enabled: !isMuted)
        }
    }

    /**
     * Local user toggled video.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setHasLocalVideo(hasLocalVideo: Bool) {
        AssertIsOnMainThread()

        let authStatus = AVCaptureDevice.authorizationStatus(forMediaType:AVMediaTypeVideo)
        switch authStatus {
        case .notDetermined:
            Logger.debug("\(TAG) authStatus: AVAuthorizationStatusNotDetermined")
            break
        case .restricted:
            Logger.debug("\(TAG) authStatus: AVAuthorizationStatusRestricted")
            break
        case .denied:
            Logger.debug("\(TAG) authStatus: AVAuthorizationStatusDenied")
            break
        case .authorized:
            Logger.debug("\(TAG) authStatus: AVAuthorizationStatusAuthorized")
            break
        }

        // We don't need to worry about the user granting or remoting this permission
        // during a call while the app is in the background, because changing this
        // permission kills the app.
        if authStatus != .authorized {

            OWSAlerts.showAlert(withTitle:NSLocalizedString("MISSING_CAMERA_PERMISSION_TITLE", comment: "Alert title when camera is not authorized"),
                                message:NSLocalizedString("MISSING_CAMERA_PERMISSION_MESSAGE", comment: "Alert body when camera is not authorized"))

            return
        }

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) call was unexpectedly nil in \(#function)")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) call unexpectedly nil in \(#function)"))
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

    func handleCallKitStartVideo() {
        AssertIsOnMainThread()

        self.setHasLocalVideo(hasLocalVideo:true)
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
    private func handleDataChannelMessage(_ message: OWSWebRTCProtosData) {
        AssertIsOnMainThread()

        guard let call = self.call else {
            // This should never happen; return to a known good state.
            assertionFailure("\(TAG) received data message, but there is no current call. Ignoring.")
            handleFailedCurrentCall(error: .assertionError(description:"\(TAG) received data message, but there is no current call. Ignoring."))
            return
        }

        if message.hasConnected() {
            Logger.debug("\(TAG) remote participant sent Connected via data channel")

            let connected = message.connected!

            guard connected.id == call.signalingId else {
                // This should never happen; return to a known good state.
                assertionFailure("\(TAG) received connected message for call with id:\(connected.id) but current call has id:\(call.signalingId)")
                handleFailedCurrentCall(error: .assertionError(description:"\(TAG) received connected message for call with id:\(connected.id) but current call has id:\(call.signalingId)"))
                return
            }

            self.callUIAdapter.recipientAcceptedCall(call)
            handleConnectedCall(call)

        } else if message.hasHangup() {
            Logger.debug("\(TAG) remote participant sent Hangup via data channel")

            let hangup = message.hangup!

            guard hangup.id == call.signalingId else {
                // This should never happen; return to a known good state.
                assertionFailure("\(TAG) received hangup message for call with id:\(hangup.id) but current call has id:\(call.signalingId)")
                handleFailedCurrentCall(error: .assertionError(description:"\(TAG) received hangup message for call with id:\(hangup.id) but current call has id:\(call.signalingId)"))
                return
            }

            guard let thread = self.thread else {
                // This should never happen; return to a known good state.
                assertionFailure("\(TAG) current contact thread is unexpectedly nil when receiving hangup DataChannelMessage")
                handleFailedCurrentCall(error: .assertionError(description:"\(TAG) current contact thread is unexpectedly nil when receiving hangup DataChannelMessage"))
                return
            }

            handleRemoteHangup(thread: thread)
        } else if message.hasVideoStreamingStatus() {
            Logger.debug("\(TAG) remote participant sent VideoStreamingStatus via data channel")

            self.isRemoteVideoEnabled = message.videoStreamingStatus.enabled()
        } else {
            Logger.info("\(TAG) received unknown or empty DataChannelMessage")
        }
    }

    // MARK: - PeerConnectionClientDelegate

    /**
     * The connection has been established. The clients can now communicate.
     */
    internal func peerConnectionClientIceConnected(_ peerConnectionClient: PeerConnectionClient) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleIceConnected()
    }

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    internal func peerConnectionClientIceFailed(_ peerConnectionClient: PeerConnectionClient) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
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
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleLocalAddedIceCandidate(iceCandidate)
    }

    /**
     * Once the peerconnection is established, we can receive messages via the data channel, and notify the delegate.
     */
    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, received dataChannelMessage: OWSWebRTCProtosData) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.handleDataChannelMessage(dataChannelMessage)
    }

    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, didUpdateLocal videoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.localVideoTrack = videoTrack
    }

    internal func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, didUpdateRemote videoTrack: RTCVideoTrack?) {
        AssertIsOnMainThread()

        guard peerConnectionClient == self.peerConnectionClient else {
            Logger.debug("\(self.TAG) \(#function) Ignoring event from obsolete peerConnectionClient")
            return
        }

        self.remoteVideoTrack = videoTrack
    }

    // MARK: Helpers

    /**
     * RTCIceServers are used when attempting to establish an optimal connection to the other party. SignalService supplies
     * a list of servers, plus we have fallback servers hardcoded in the app.
     */
    private func getIceServers() -> Promise<[RTCIceServer]> {
        AssertIsOnMainThread()

        return firstly {
            return accountManager.getTurnServerInfo()
        }.then { turnServerInfo -> [RTCIceServer] in
            Logger.debug("\(self.TAG) got turn server urls: \(turnServerInfo.urls)")

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
        }.recover { error -> [RTCIceServer] in
            Logger.error("\(self.TAG) fetching ICE servers failed with error: \(error)")
            Logger.warn("\(self.TAG) using fallback ICE Servers")

            return [CallService.fallbackIceServer]
        }
    }

    // This method should be called when either: a) we know or assume that
    // the error is related to the current call. b) the error is so serious
    // that we want to terminate the current call (if any) in order to
    // return to a known good state.
    public func handleFailedCurrentCall(error: CallError) {
        handleFailedCall(failedCall: self.call, error: error, forceTerminate:true)
    }

    // This method should be called when a fatal error occurred for a call.
    //
    // * If we know which call it was, we should update that call's state
    //   to reflect the error.
    // * IFF that call is the current call, we want to terminate it.
    public func handleFailedCall(failedCall: SignalCall?, error: CallError, forceTerminate: Bool = false) {
        AssertIsOnMainThread()
        Logger.error("\(TAG) call failed with error: \(error)")

        guard let failedCall = failedCall else {
            Logger.debug("\(TAG) in \(#function) ignoring obsolete call.")
            return
        }

        // It's essential to set call.state before terminateCall, because terminateCall nils self.call
        failedCall.error = error
        failedCall.state = .localFailure
        self.callUIAdapter.failCall(failedCall, error: error)

        // Only terminate the current call if the error pertains to the current call,
        // or if we're trying to return to a known good state.
        let shouldTerminate = forceTerminate || failedCall == self.call
        guard shouldTerminate else {
            Logger.debug("\(TAG) in \(#function) ignoring obsolete call.")
            return
        }

        // Only terminate the call if it is the current call.
        terminateCall()
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    private func terminateCall() {
        AssertIsOnMainThread()

        Logger.debug("\(TAG) in \(#function)")

        localVideoTrack = nil
        remoteVideoTrack = nil
        isRemoteVideoEnabled = false

        PeerConnectionClient.stopAudioSession()
        peerConnectionClient?.terminate()
        Logger.debug("\(TAG) setting peerConnectionClient in \(#function)")
        peerConnectionClient = nil

        call?.removeAllObservers()
        call = nil
        thread = nil
        incomingCallPromise = nil
        sendIceUpdatesImmediately = true
        Logger.info("\(TAG) clearing pendingIceUpdateMessages")
        pendingIceUpdateMessages = []
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) \(#function): \(state)")
        updateIsVideoEnabled()
    }

    internal func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool) {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) \(#function): \(hasLocalVideo)")
        self.updateIsVideoEnabled()
    }

    internal func muteDidChange(call: SignalCall, isMuted: Bool) {
        AssertIsOnMainThread()
        // Do nothing
    }

    internal func speakerphoneDidChange(call: SignalCall, isEnabled: Bool) {
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

        Logger.info("\(self.TAG) \(#function): \(shouldHaveLocalVideoTrack)")

        self.peerConnectionClient?.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack)

        let message = DataChannelMessage.forVideoStreamingStatus(callId: call.signalingId, enabled:shouldHaveLocalVideoTrack)
        peerConnectionClient.sendDataChannelMessage(data: message.asData())
    }

    // MARK: - Observers

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(Weak(value: observer))

        // Synchronize observer with current call state
        let call = self.call
        let localVideoTrack = self.localVideoTrack
        let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil
        observer.didUpdateVideoTracks(call:call,
                                      localVideoTrack:localVideoTrack,
                                      remoteVideoTrack:remoteVideoTrack)
    }

    // The observer-related methods should be invoked on the main thread.
    func removeObserver(_ observer: CallServiceObserver) {
        AssertIsOnMainThread()

        while let index = observers.index(where: { $0.value === observer }) {
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

        let call = self.call
        let localVideoTrack = self.localVideoTrack
        let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil

        for observer in observers {
            observer.value?.didUpdateVideoTracks(call:call,
                                                 localVideoTrack:localVideoTrack,
                                                 remoteVideoTrack:remoteVideoTrack)
        }
    }

    private func updateLockTimerEnabling() {
        AssertIsOnMainThread()

        // Prevent screen from dimming during call.
        //
        // Note that this state has no effect if app is in the background.
        let hasCall = call != nil
        UIApplication.shared.isIdleTimerDisabled = hasCall
    }
}

fileprivate extension MessageSender {
    /**
     * Wrap message sending in a Promise for easier callback chaining.
     */
    fileprivate func sendCallMessage(_ message: OWSOutgoingCallMessage) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.send(message, success: fulfill, failure: reject)
        }
    }
}
