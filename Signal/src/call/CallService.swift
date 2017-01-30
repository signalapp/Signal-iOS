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
 * Signaling state is synchronized on the `signalingQueue` and only mutated in the handleXXX family of methods.
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
}

// FIXME TODO do we need to timeout?
fileprivate let timeoutSeconds = 60

// All Observer methods will be invoked from the main thread.
protocol CallServiceObserver: class {
    /**
     * Fired whenever the local or remote video track become active or inactive.
     */
    func didUpdateVideoTracks(localVideoTrack: RTCVideoTrack?,
                              remoteVideoTrack: RTCVideoTrack?)
}

// This class' state should only be accessed on the signaling queue, _except_
// the observer-related state which only be accessed on the main thread.
@objc class CallService: NSObject, CallObserver, PeerConnectionClientDelegate {

    // MARK: - Properties

    let TAG = "[CallService]"

    var observers = [Weak<CallServiceObserver>]()

    // MARK: Dependencies

    let accountManager: AccountManager
    let messageSender: MessageSender
    var callUIAdapter: CallUIAdapter!

    // MARK: Class

    static let fallbackIceServer = RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])

    // Synchronize call signaling on the callSignalingQueue to make sure any appropriate requisite state is set.
    static let signalingQueue = DispatchQueue(label: "CallServiceSignalingQueue")

    // MARK: Ivars

    var peerConnectionClient: PeerConnectionClient?
    // TODO code cleanup: move thread into SignalCall? Or refactor messageSender to take SignalRecipient identifier.
    var thread: TSContactThread?
    var call: SignalCall? {
        didSet {
            assertOnSignalingQueue()

            oldValue?.removeObserver(self)
            call?.addObserverAndSyncState(observer: self)

            DispatchQueue.main.async { [weak self] in
                self?.updateIsVideoEnabled()
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
            assertOnSignalingQueue()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            assertOnSignalingQueue()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }
    var isRemoteVideoEnabled = false {
        didSet {
            assertOnSignalingQueue()

            Logger.info("\(self.TAG) \(#function)")

            fireDidUpdateVideoTracks()
        }
    }

    required init(accountManager: AccountManager, contactsManager: OWSContactsManager, messageSender: MessageSender, notificationsAdapter: CallNotificationsAdapter) {
        self.accountManager = accountManager
        self.messageSender = messageSender

        super.init()

        self.callUIAdapter = CallUIAdapter(callService: self, contactsManager: contactsManager, notificationsAdapter: notificationsAdapter)
    }

    // MARK: - Class Methods

    // MARK: Notifications

    // Wrapping these class constants in a method to make it accessible to objc
    class func callServiceActiveCallNotificationName() -> String {
        return  "CallServiceActiveCallNotification"
    }

    // MARK: - Service Actions

    // Unless otherwise documented, these `handleXXX` methods expect to be called on the SignalingQueue to coordinate 
    // state across calls.

    /**
     * Initiate an outgoing call.
     */
    public func handleOutgoingCall(_ call: SignalCall) -> Promise<Void> {
        assertOnSignalingQueue()

        self.call = call

        let thread = TSContactThread.getOrCreateThread(contactId: call.remotePhoneNumber)
        self.thread = thread

        sendIceUpdatesImmediately = false
        pendingIceUpdateMessages = []

        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), withCallNumber: call.remotePhoneNumber, callType: RPRecentCallTypeOutgoing, in: thread)
        callRecord.save()

        guard self.peerConnectionClient == nil else {
            let errorDescription = "\(TAG) peerconnection was unexpectedly already set."
            Logger.error(errorDescription)
            call.state = .localFailure
            return Promise(error: CallError.assertionError(description: errorDescription))
        }

        return getIceServers().then(on: CallService.signalingQueue) { iceServers -> Promise<HardenedRTCSessionDescription> in
            Logger.debug("\(self.TAG) got ice servers:\(iceServers)")
            let peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self)

            // When placing an outgoing call, it's our responsibility to create the DataChannel. Recipient will not have
            // to do this explicitly.
            peerConnectionClient.createSignalingDataChannel()

            self.peerConnectionClient = peerConnectionClient

            return self.peerConnectionClient!.createOffer()
        }.then(on: CallService.signalingQueue) { (sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> in
            return self.peerConnectionClient!.setLocalSessionDescription(sessionDescription).then(on: CallService.signalingQueue) {
                let offerMessage = OWSCallOfferMessage(callId: call.signalingId, sessionDescription: sessionDescription.sdp)
                let callMessage = OWSOutgoingCallMessage(thread: thread, offerMessage: offerMessage)
                return self.messageSender.sendCallMessage(callMessage)
            }
        }.catch(on: CallService.signalingQueue) { error in
            Logger.error("\(self.TAG) placing call failed with error: \(error)")

            if let callError = error as? CallError {
                self.handleFailedCall(error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(error: externalError)
            }
        }
    }

    /**
     * Called by the call initiator after receiving a CallAnswer from the callee.
     */
    public func handleReceivedAnswer(thread: TSContactThread, callId: UInt64, sessionDescription: String) {
        Logger.debug("\(TAG) received call answer for call: \(callId) thread: \(thread)")
        assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"call was unexpectedly nil in \(#function)"))
            return
        }

        guard call.signalingId == callId else {
            let description: String = "received answer for call: \(callId) but current call has id: \(call.signalingId)"
            handleFailedCall(error: .assertionError(description: description))
            return
        }

        // Now that we know the recipient trusts our identity, we no longer need to enqueue ICE updates.
        self.sendIceUpdatesImmediately = true

        if pendingIceUpdateMessages.count > 0 {
            let callMessage = OWSOutgoingCallMessage(thread: thread, iceUpdateMessages: pendingIceUpdateMessages)
            _ = messageSender.sendCallMessage(callMessage).catch { error in
                Logger.error("\(self.TAG) failed to send ice updates in \(#function) with error: \(error)")
            }
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: CallError.assertionError(description: "peerConnectionClient was unexpectedly nil in \(#function)"))
            return
        }

        let sessionDescription = RTCSessionDescription(type: .answer, sdp: sessionDescription)
        _ = peerConnectionClient.setRemoteSessionDescription(sessionDescription).then {
            Logger.debug("\(self.TAG) successfully set remote description")
        }.catch(on: CallService.signalingQueue) { error in
            if let callError = error as? CallError {
                self.handleFailedCall(error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(error: externalError)
            }
        }
    }

    /**
     * User didn't answer incoming call
     */
    public func handleMissedCall(_ call: SignalCall, thread: TSContactThread) {
        // Insert missed call record
        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(),
                                withCallNumber: thread.contactIdentifier(),
                                callType: RPRecentCallTypeMissed,
                                in: thread)
        callRecord.save()

        DispatchQueue.main.async {
            self.callUIAdapter.reportMissedCall(call)
        }
    }

    /**
     * Received a call while already in another call.
     */
    private func handleLocalBusyCall(_ call: SignalCall, thread: TSContactThread) {
        Logger.debug("\(TAG) \(#function) for call: \(call) thread: \(thread)")
        assertOnSignalingQueue()

        let busyMessage = OWSCallBusyMessage(callId: call.signalingId)
        let callMessage = OWSOutgoingCallMessage(thread: thread, busyMessage: busyMessage)
        _ = messageSender.sendCallMessage(callMessage)

        handleMissedCall(call, thread: thread)
    }

    /**
     * The callee was already in another call.
     */
    public func handleRemoteBusy(thread: TSContactThread) {
        Logger.debug("\(TAG) \(#function) for thread: \(thread)")
        assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description: "call unexpectedly nil in \(#function)"))
            return
        }

        call.state = .remoteBusy
        terminateCall()
    }

    /**
     * Received an incoming call offer. We still have to complete setting up the Signaling channel before we notify
     * the user of an incoming call.
     */
    public func handleReceivedOffer(thread: TSContactThread, callId: UInt64, sessionDescription callerSessionDescription: String) {
        assertOnSignalingQueue()

        Logger.verbose("\(TAG) receivedCallOffer for thread:\(thread)")
        let newCall = SignalCall.incomingCall(localId: UUID(), remotePhoneNumber: thread.contactIdentifier(), signalingId: callId)

        guard call == nil else {
            // TODO on iOS10+ we can use CallKit to swap calls rather than just returning busy immediately.
            Logger.verbose("\(TAG) receivedCallOffer for thread: \(thread) but we're already in call: \(call)")

            handleLocalBusyCall(newCall, thread: thread)
            return
        }

        self.thread = thread
        call = newCall

        let backgroundTask = UIApplication.shared.beginBackgroundTask {
            let timeout = CallError.timeout(description: "background task time ran out before call connected.")
            CallService.signalingQueue.async {
                self.handleFailedCall(error: timeout)
            }
        }

        incomingCallPromise = firstly {
            return getIceServers()
        }.then(on: CallService.signalingQueue) { (iceServers: [RTCIceServer]) -> Promise<HardenedRTCSessionDescription> in
            // FIXME for first time call recipients I think we'll see mic/camera permission requests here,
            // even though, from the users perspective, no incoming call is yet visible.
            self.peerConnectionClient = PeerConnectionClient(iceServers: iceServers, delegate: self)

            let offerSessionDescription = RTCSessionDescription(type: .offer, sdp: callerSessionDescription)
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

            // Find a sessionDescription compatible with my constraints and the remote sessionDescription
            return self.peerConnectionClient!.negotiateSessionDescription(remoteDescription: offerSessionDescription, constraints: constraints)
        }.then(on: CallService.signalingQueue) { (negotiatedSessionDescription: HardenedRTCSessionDescription) in
            Logger.debug("\(self.TAG) set the remote description")

            let answerMessage = OWSCallAnswerMessage(callId: newCall.signalingId, sessionDescription: negotiatedSessionDescription.sdp)
            let callAnswerMessage = OWSOutgoingCallMessage(thread: thread, answerMessage: answerMessage)

            return self.messageSender.sendCallMessage(callAnswerMessage)
        }.then(on: CallService.signalingQueue) {
            Logger.debug("\(self.TAG) successfully sent callAnswerMessage")

            let (promise, fulfill, _) = Promise<Void>.pending()

            let timeout: Promise<Void> = after(interval: TimeInterval(timeoutSeconds)).then { () -> Void in
                // rejecting a promise by throwing is safely a no-op if the promise has already been fulfilled
                throw CallError.timeout(description: "timed out waiting for call to connect")
            }

            // This will be fulfilled (potentially) by the RTCDataChannel delegate method
            self.fulfillCallConnectedPromise = fulfill

            return race(promise, timeout)
        }.catch(on: CallService.signalingQueue) { error in
            if let callError = error as? CallError {
                self.handleFailedCall(error: callError)
            } else {
                let externalError = CallError.externalError(underlyingError: error)
                self.handleFailedCall(error: externalError)
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
        assertOnSignalingQueue()
        Logger.debug("\(TAG) called \(#function)")

        guard self.thread != nil else {
            handleFailedCall(error: .assertionError(description: "ignoring remote ice update for thread: \(thread.uniqueId) since there is no current thread. Call already ended?"))
            return
        }

        guard thread.contactIdentifier() == self.thread!.contactIdentifier() else {
            handleFailedCall(error: .assertionError(description: "ignoring remote ice update for thread: \(thread.uniqueId) since the current call is for thread: \(self.thread!.uniqueId)"))
            return
        }

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description: "ignoring remote ice update for callId: \(callId), since there is no current call."))
            return
        }

        guard call.signalingId == callId else {
            handleFailedCall(error: .assertionError(description: "ignoring remote ice update for call: \(callId) since the current call is: \(call.signalingId)"))
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description: "ignoring remote ice update for thread: \(thread) since the current call hasn't initialized it's peerConnectionClient"))
            return
        }

        peerConnectionClient.addIceCandidate(RTCIceCandidate(sdp: sdp, sdpMLineIndex: lineIndex, sdpMid: mid))
    }

    /**
     * Local client (could be caller or callee) generated some connectivity information that we should send to the 
     * remote client.
     */
    private func handleLocalAddedIceCandidate(_ iceCandidate: RTCIceCandidate) {
        assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description: "ignoring local ice candidate, since there is no current call."))
            return
        }

        guard call.state != .idle else {
            handleFailedCall(error: .assertionError(description: "ignoring local ice candidate, since call is now idle."))
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(error: .assertionError(description: "ignoring local ice candidate, because there was no current TSContactThread."))
            return
        }

        let iceUpdateMessage = OWSCallIceUpdateMessage(callId: call.signalingId, sdp: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMLineIndex, sdpMid: iceCandidate.sdpMid)

        if self.sendIceUpdatesImmediately {
            let callMessage = OWSOutgoingCallMessage(thread: thread, iceUpdateMessage: iceUpdateMessage)
            _ = self.messageSender.sendCallMessage(callMessage)
        } else {
            // For outgoing messages, we wait to send ice updates until we're sure client received our call message.
            // e.g. if the client has blocked our message due to an identity change, we'd otherwise
            // bombard them with a bunch *more* undecipherable messages.
            Logger.debug("\(TAG) enqueuing iceUpdate until we receive call answer")
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
        assertOnSignalingQueue()

        Logger.debug("\(TAG) in \(#function)")

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call."))
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current thread."))
            return
        }

        switch call.state {
        case .dialing:
            call.state = .remoteRinging
        case .answering:
            call.state = .localRinging
            DispatchQueue.main.async {
                self.callUIAdapter.reportIncomingCall(call, thread: thread)
            }
            // cancel connection timeout
            self.fulfillCallConnectedPromise?()
        case .remoteRinging:
            Logger.info("\(TAG) call alreading ringing. Ignoring \(#function)")
        default:
            Logger.debug("\(TAG) unexpected call state for \(#function): \(call.state)")
        }
    }

    /**
     * The remote client (caller or callee) ended the call.
     */
    public func handleRemoteHangup(thread: TSContactThread) {
        Logger.debug("\(TAG) in \(#function)")
        assertOnSignalingQueue()

        guard thread.contactIdentifier() == self.thread?.contactIdentifier() else {
            // This can safely be ignored. 
            // We don't want to fail the current call because an old call was slow to send us the hangup message.
            Logger.warn("\(TAG) ignoring hangup for thread:\(thread) which is not the current thread: \(self.thread)")
            return
        }

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
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
        DispatchQueue.main.async {
            self.callUIAdapter.remoteDidHangupCall(call)
        }

        // self.call is nil'd in `terminateCall`, so it's important we update it's state *before* calling `terminateCall`
        terminateCall()
    }

    /**
     * User chose to answer call referrred to by call `localId`. Used by the Callee only.
     *
     * Used by notification actions which can't serialize a call object.
     */
    public func handleAnswerCall(localId: UUID) {
        // TODO #function is called from objc, how to access swift defiend dispatch queue (OS_dispatch_queue)
        //assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
            return
        }

        guard call.localId == localId else {
            handleFailedCall(error: .assertionError(description:"\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        // Because we may not be on signalingQueue (because this method is called from Objc which doesn't have 
        // access to signalingQueue (that I can find). FIXME?
        type(of: self).signalingQueue.async {
            self.handleAnswerCall(call)
        }
    }

    /**
     * User chose to answer call referrred to by call `localId`. Used by the Callee only.
     */
    public func handleAnswerCall(_ call: SignalCall) {
        assertOnSignalingQueue()

        Logger.debug("\(TAG) in \(#function)")

        guard self.call != nil else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call"))
            return
        }

        guard call == self.call! else {
            // This could conceivably happen if the other party of an old call was slow to send us their answer
            // and we've subsequently engaged in another call. Don't kill the current call, but just ignore it.
            Logger.warn("\(TAG) ignoring \(#function) for call other than current call")
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) for call other than current call"))
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description:"\(TAG) missing peerconnection client in \(#function)"))
            return
        }

        let callRecord = TSCall(timestamp: NSDate.ows_millisecondTimeStamp(), withCallNumber: call.remotePhoneNumber, callType: RPRecentCallTypeIncoming, in: thread)
        callRecord.save()

        let message = DataChannelMessage.forConnected(callId: call.signalingId)
        if peerConnectionClient.sendDataChannelMessage(data: message.asData()) {
            Logger.debug("\(TAG) sendDataChannelMessage returned true")
        } else {
            Logger.warn("\(TAG) sendDataChannelMessage returned false")
        }

        handleConnectedCall(call)
    }

    /**
     * For outgoing call, when the callee has chosen to accept the call.
     * For incoming call, when the local user has chosen to accept the call.
     */
    func handleConnectedCall(_ call: SignalCall) {
        Logger.debug("\(TAG) in \(#function)")
        assertOnSignalingQueue()

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description:"\(TAG) peerConnectionClient unexpectedly nil in \(#function)"))
            return
        }

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
        // #function is called from objc, how to access swift defiend dispatch queue (OS_dispatch_queue)
        //assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) call was unexpectedly nil in \(#function)"))
            return
        }

        guard call.localId == localId else {
            handleFailedCall(error: .assertionError(description:"\(TAG) callLocalId:\(localId) doesn't match current calls: \(call.localId)"))
            return
        }

        // Because we may not be on signalingQueue (because this method is called from Objc which doesn't have
        // access to signalingQueue (that I can find). FIXME?
        type(of: self).signalingQueue.async {
            self.handleDeclineCall(call)
        }
    }

    /**
     * Local user chose to decline the call vs. answering it.
     *
     * Incoming call only.
     */
    public func handleDeclineCall(_ call: SignalCall) {
        assertOnSignalingQueue()

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
        assertOnSignalingQueue()

        guard self.call != nil else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) since there is no current call"))
            return
        }

        guard call == self.call! else {
            handleFailedCall(error: .assertionError(description:"\(TAG) ignoring \(#function) for call other than current call"))
            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description:"\(TAG) missing peerconnection client in \(#function)"))
            return
        }

        guard let thread = self.thread else {
            handleFailedCall(error: .assertionError(description:"\(TAG) missing thread in \(#function)"))
            return
        }

        call.state = .localHangup

        // TODO something like this lifted from Signal-Android.
        //        this.accountManager.cancelInFlightRequests();
        //        this.messageSender.cancelInFlightRequests();

        // If the call is connected, we can send the hangup via the data channel.
        let message = DataChannelMessage.forHangup(callId: call.signalingId)
        if peerConnectionClient.sendDataChannelMessage(data: message.asData()) {
            Logger.debug("\(TAG) sendDataChannelMessage returned true")
        } else {
            Logger.warn("\(TAG) sendDataChannelMessage returned false")
        }

        // If the call hasn't started yet, we don't have a data channel to communicate the hang up. Use Signal Service Message.
        let hangupMessage = OWSCallHangupMessage(callId: call.signalingId)
        let callMessage = OWSOutgoingCallMessage(thread: thread, hangupMessage: hangupMessage)
        _  = self.messageSender.sendCallMessage(callMessage).then(on: CallService.signalingQueue) {
            Logger.debug("\(self.TAG) successfully sent hangup call message to \(thread)")
        }.catch(on: CallService.signalingQueue) { error in
            Logger.error("\(self.TAG) failed to send hangup call message to \(thread) with error: \(error)")
        }

        terminateCall()
    }

    /**
     * Local user toggled to mute audio.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setIsMuted(isMuted: Bool) {
        assertOnSignalingQueue()

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description:"\(TAG) peerConnectionClient unexpectedly nil in \(#function)"))
            return
        }

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) call unexpectedly nil in \(#function)"))
            return
        }

        call.isMuted = isMuted
        peerConnectionClient.setAudioEnabled(enabled: !isMuted)
    }

    /**
     * Local user toggled video.
     *
     * Can be used for Incoming and Outgoing calls.
     */
    func setHasLocalVideo(hasLocalVideo: Bool) {
        assertOnSignalingQueue()

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

        // We don't need to worry about the user granting or remotinv this permission
        // during a call while the app is in the background, because changing this
        // permission kills the app.
        if authStatus != .authorized {
            DispatchQueue.main.async {
                let title = NSLocalizedString("CAMERA_PERMISSION_MISSING_TITLE", comment: "Alert title when camera is not authorized")
                let message = NSLocalizedString("CAMERA_PERMISSION_MISSING_BODY", comment: "Alert body when camera is not authorized")
                let okButton = NSLocalizedString("OK", comment:"")

                let alert = UIAlertView(title:title, message:message, delegate:nil, cancelButtonTitle:okButton)
                alert.show()
            }

            return
        }

        guard let peerConnectionClient = self.peerConnectionClient else {
            handleFailedCall(error: .assertionError(description:"\(TAG) peerConnectionClient unexpectedly nil in \(#function)"))
            return
        }

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) call unexpectedly nil in \(#function)"))
            return
        }

        call.hasLocalVideo = hasLocalVideo
        peerConnectionClient.setLocalVideoEnabled(enabled: shouldHaveLocalVideoTrack())
    }

    func handleCallKitStartVideo() {
        CallService.signalingQueue.async {
            self.setHasLocalVideo(hasLocalVideo:true)
        }
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
        assertOnSignalingQueue()

        guard let call = self.call else {
            handleFailedCall(error: .assertionError(description:"\(TAG) received data message, but there is no current call. Ignoring."))
            return
        }

        if message.hasConnected() {
            Logger.debug("\(TAG) remote participant sent Connected via data channel")

            let connected = message.connected!

            guard connected.id == call.signalingId else {
                handleFailedCall(error: .assertionError(description:"\(TAG) received connected message for call with id:\(connected.id) but current call has id:\(call.signalingId)"))
                return
            }

            DispatchQueue.main.async {
                self.callUIAdapter.recipientAcceptedCall(call)
            }
            handleConnectedCall(call)

        } else if message.hasHangup() {
            Logger.debug("\(TAG) remote participant sent Hangup via data channel")

            let hangup = message.hangup!

            guard hangup.id == call.signalingId else {
                handleFailedCall(error: .assertionError(description:"\(TAG) received hangup message for call with id:\(hangup.id) but current call has id:\(call.signalingId)"))
                return
            }

            guard let thread = self.thread else {
                handleFailedCall(error: .assertionError(description:"\(TAG) current contact thread is unexpectedly nil when receiving hangup DataChannelMessage"))
                return
            }

            handleRemoteHangup(thread: thread)
        } else if message.hasVideoStreamingStatus() {
            Logger.debug("\(TAG) remote participant sent VideoStreamingStatus via data channel")

            self.isRemoteVideoEnabled = message.videoStreamingStatus.enabled()
        }
    }

    // MARK: - PeerConnectionClientDelegate

    /**
     * The connection has been established. The clients can now communicate.
     */
    internal func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient) {
        CallService.signalingQueue.async {
            self.handleIceConnected()
        }
    }

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    internal func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient) {
        CallService.signalingQueue.async {
            self.handleFailedCall(error: CallError.disconnected)
        }
    }

    /**
     * During the Signaling process each client generates IceCandidates locally, which contain information about how to
     * reach the local client via the internet. The delegate must shuttle these IceCandates to the other (remote) client
     * out of band, as part of establishing a connection over WebRTC.
     */
    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate) {
        CallService.signalingQueue.async {
            self.handleLocalAddedIceCandidate(iceCandidate)
        }
    }

    /**
     * Once the peerconnection is established, we can receive messages via the data channel, and notify the delegate.
     */
    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: OWSWebRTCProtosData) {
        CallService.signalingQueue.async {
            self.handleDataChannelMessage(dataChannelMessage)
        }
    }

    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateLocal videoTrack: RTCVideoTrack?) {
        CallService.signalingQueue.async { [weak self] in
            if let strongSelf = self {
                strongSelf.localVideoTrack = videoTrack
                strongSelf.fireDidUpdateVideoTracks()
            }
        }
    }

    internal func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateRemote videoTrack: RTCVideoTrack?) {
        CallService.signalingQueue.async { [weak self] in
            if let strongSelf = self {
                strongSelf.remoteVideoTrack = videoTrack
                strongSelf.fireDidUpdateVideoTracks()
            }
        }
    }

    // MARK: Helpers

    /**
     * Ensure that all `SignalCall` and `CallService` state is synchronized by only mutating signaling state in 
     * handleXXX methods, and putting those methods on the signaling queue.
     *
     * TODO: We might want to move this queue and method to OWSDispatch so that we can assert this in
     *       other classes like SignalCall as well.
     */
    private func assertOnSignalingQueue() {
        if #available(iOS 10.0, *) {
            dispatchPrecondition(condition: .onQueue(type(of: self).signalingQueue))
        } else {
            // Skipping check on <iOS10, since syntax is different and it's just a development convenience.
        }
    }

    /**
     * RTCIceServers are used when attempting to establish an optimal connection to the other party. SignalService supplies
     * a list of servers, plus we have fallback servers hardcoded in the app.
     */
    private func getIceServers() -> Promise<[RTCIceServer]> {
        return firstly {
            return accountManager.getTurnServerInfo()
        }.then(on: CallService.signalingQueue) { turnServerInfo -> [RTCIceServer] in
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

    public func handleFailedCall(error: CallError) {
        assertOnSignalingQueue()
        Logger.error("\(TAG) call failed with error: \(error)")

        if let call = self.call {
            // It's essential to set call.state before terminateCall, because terminateCall nils self.call
            call.error = error
            call.state = .localFailure
            DispatchQueue.main.async {
                self.callUIAdapter.failCall(call, error: error)
            }
        } else {
            // This can happen when we receive an out of band signaling message (e.g. IceUpdate)
            // after the call has ended
            Logger.debug("\(TAG) in \(#function) but there was no call to fail.")
        }

        terminateCall()
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    private func terminateCall() {
        assertOnSignalingQueue()

        Logger.debug("\(TAG) in \(#function)")

        PeerConnectionClient.stopAudioSession()
        peerConnectionClient?.delegate = nil
        peerConnectionClient?.terminate()

        peerConnectionClient = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        isRemoteVideoEnabled = false
        call?.removeAllObservers()
        call = nil
        thread = nil
        incomingCallPromise = nil
        sendIceUpdatesImmediately = true
        pendingIceUpdateMessages = []

        fireDidUpdateVideoTracks()
    }

    // MARK: - CallObserver

    internal func stateDidChange(call: SignalCall, state: CallState) {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) \(#function): \(state)")
        self.updateIsVideoEnabled()
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
        assertOnSignalingQueue()

        // The iOS simulator doesn't provide any sort of camera capture
        // support or emulation (http://goo.gl/rHAnC1) so don't bother
        // trying to open a local stream.
        return (!Platform.isSimulator &&
            call != nil &&
            call!.state == .connected &&
            call!.hasLocalVideo)
    }

    private func updateIsVideoEnabled() {
        AssertIsOnMainThread()

        // It's only safe to access the class properties on the signaling queue, so
        // we dispatch there...
        CallService.signalingQueue.async {
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
            if peerConnectionClient.sendDataChannelMessage(data: message.asData()) {
                Logger.debug("\(self.TAG) sendDataChannelMessage returned true")
            } else {
                Logger.warn("\(self.TAG) sendDataChannelMessage returned false")
            }

        }
    }

    // MARK: - Observers

    // The observer-related methods should be invoked on the main thread.
    func addObserverAndSyncState(observer: CallServiceObserver) {
        AssertIsOnMainThread()

        observers.append(Weak(value: observer))

        // Synchronize observer with current call state

        // It's only safe to access the video track properties on the signaling queue, so
        // we dispatch there...
        CallService.signalingQueue.async {
            let localVideoTrack = self.localVideoTrack
            let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil
            // Then dispatch back to the main thread.
            DispatchQueue.main.async {
                observer.didUpdateVideoTracks(localVideoTrack:localVideoTrack,
                                              remoteVideoTrack:remoteVideoTrack)
            }
        }
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

    func fireDidUpdateVideoTracks() {
        assertOnSignalingQueue()

        let localVideoTrack = self.localVideoTrack
        let remoteVideoTrack = self.isRemoteVideoEnabled ? self.remoteVideoTrack : nil

        DispatchQueue.main.async { [weak self] in
            if let strongSelf = self {
                for observer in strongSelf.observers {
                    observer.value?.didUpdateVideoTracks(localVideoTrack:localVideoTrack,
                                                         remoteVideoTrack:remoteVideoTrack)
                }
            }
        }

        // Prevent screen from dimming during video call.
        let hasLocalOrRemoteVideo = localVideoTrack != nil || remoteVideoTrack != nil
        UIApplication.shared.isIdleTimerDisabled = hasLocalOrRemoteVideo
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
