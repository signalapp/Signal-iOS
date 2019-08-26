//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalCoreKit
import SignalRingRTC
import WebRTC

/**
 * The PeerConnectionClient notifies it's delegate (the CallService) of key events in the call signaling life cycle
 *
 * The delegate's methods will always be called on the main thread.
 */
protocol PeerConnectionClientDelegate: class {

    /**
     * Fired for various asynchronous RingRTC events. See CallConnection.CallEvent for more information.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, onCallEvent event: CallEvent, callId: UInt64)

    /**
     * Fired whenever RingRTC encounters an error. Should always be considered fatal and end the session.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, onCallError error: String, callId: UInt64)

    /**
     * Fired whenever the remote video track becomes active or inactive.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, onAddRemoteVideoTrack track: RTCVideoTrack, callId: UInt64)

    /**
     * Fired whenever the local video track becomes active or inactive.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, onUpdateLocalVideoSession session: AVCaptureSession?, callId: UInt64)

    /**
     * Fired when an offer message should be sent over the signaling channel.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, shouldSendOffer sdp: String, callId: UInt64)

    /**
     * Fired when an answer message should be sent over the signaling channel.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, shouldSendAnswer sdp: String, callId: UInt64)

    /**
     * Fired when there are one or more local Ice Candidates to be sent over the signaling channel.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, shouldSendIceCandidates candidates: [RTCIceCandidate], callId: UInt64)

    /**
     * Fired when a hangup message should be sent over the signaling channel.
     */
    func peerConnectionClient(_ peerConnectionClient: PeerConnectionClient, shouldSendHangup callId: UInt64)
}

// In Swift (at least in Swift v3.3), weak variables aren't thread safe. It
// isn't safe to resolve/acquire/lock a weak reference into a strong reference
// while the instance might be being deallocated on another thread.
//
// PeerConnectionProxy provides thread-safe access to a strong reference.
// PeerConnectionClient has an PeerConnectionProxy to itself that its many async blocks
// (which run on more than one thread) can use to safely try to acquire a strong
// reference to the PeerConnectionClient. In ARC we'd normally, we'd avoid
// having an instance retain a strong reference to itself to avoid retain
// cycles, but it's safe in this case: PeerConnectionClient is owned (and only
// used by) a single entity CallService and CallService always calls
// [PeerConnectionClient terminate] when it is done with a PeerConnectionClient
// instance, so terminate is a reliable place where we can break the retain cycle.
//
// Note that we use the proxy in two ways:
//
// * As a delegate for the peer connection and the data channel,
//   safely forwarding delegate method invocations to the PCC.
// * To safely obtain references to the PCC within the PCC's
//   async blocks.
//
// This should be fixed in Swift 4, but it isn't.
//
// To test using the following scenarios:
//
// * Alice and Bob place simultaneous calls to each other. Both should get busy.
//   Repeat 10-20x.  Then verify that they can connect a call by having just one
//   call the other.
// * Alice or Bob (randomly alternating) calls the other. Recipient (randomly)
//   accepts call or hangs up.  If accepted, Alice or Bob (randomly) hangs up.
//   Repeat immediately, as fast as you can, 10-20x.
class PeerConnectionProxy: NSObject, CallConnectionDelegate {
    private var value: PeerConnectionClient?

    deinit {
        Logger.info("[PeerConnectionProxy] deinit")
    }

    func set(value: PeerConnectionClient) {
        objc_sync_enter(self)
        self.value = value
        objc_sync_exit(self)
    }

    func get() -> PeerConnectionClient? {
        objc_sync_enter(self)
        let result = value
        objc_sync_exit(self)

        if result == nil {
            // Every time this method returns nil is a
            // possible crash avoided.
            Logger.verbose("cleared get.")
        }

        return result
    }

    func clear() {
        Logger.info("")

        objc_sync_enter(self)
        value = nil
        objc_sync_exit(self)
    }

    // MARK: - CallConnectionDelegate

    func callConnection(_ callConnection: CallConnection, onCallEvent event: CallEvent, callId: UInt64) {
        self.get()?.callConnection(callConnection, onCallEvent: event, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, onCallError error: String, callId: UInt64) {
        self.get()?.callConnection(callConnection, onCallError: error, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, onAddRemoteVideoTrack track: RTCVideoTrack, callId: UInt64) {
        self.get()?.callConnection(callConnection, onAddRemoteVideoTrack: track, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, onUpdateLocalVideoSession session: AVCaptureSession?, callId: UInt64) {
        self.get()?.callConnection(callConnection, onUpdateLocalVideoSession: session, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, shouldSendOffer sdp: String, callId: UInt64) {
        self.get()?.callConnection(callConnection, shouldSendOffer: sdp, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, shouldSendAnswer sdp: String, callId: UInt64) {
        self.get()?.callConnection(callConnection, shouldSendAnswer: sdp, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, shouldSendIceCandidates candidates: [RTCIceCandidate], callId: UInt64) {
        self.get()?.callConnection(callConnection, shouldSendIceCandidates: candidates, callId: callId)
    }

    func callConnection(_ callConnection: CallConnection, shouldSendHangup callId: UInt64) {
        self.get()?.callConnection(callConnection, shouldSendHangup: callId)
    }

    func callConnection(_ callConnection: CallConnection, shouldSendBusy callId: UInt64) {
        self.get()?.callConnection(callConnection, shouldSendBusy: callId)
    }
}

/**
 * `PeerConnectionClient` is our interface to WebRTC.
 *
 * It is primarily a wrapper around `RTCPeerConnection`, which is responsible for sending and receiving our call data
 * including audio, video, and some post-connected signaling (hangup, add video)
 */
class PeerConnectionClient: NSObject, CallConnectionDelegate {

    private static let signalingQueue = DispatchQueue(label: "CallServiceSignalingQueue")

    // Delegate is notified of key events in the call lifecycle.
    //
    // This property should only be accessed on the main thread.
    private weak var delegate: PeerConnectionClientDelegate?

    // Connection

    private var callConnectionfactory: CallConnectionFactory?
    private var callConnection: CallConnection?

    private let proxy = PeerConnectionProxy()

    // Note that we're deliberately leaking proxy instances using this
    // collection to avoid EXC_BAD_ACCESS.  Calls are rare and the proxy
    // is tiny (a single property), so it's better to leak and be safe.
    private static var expiredProxies = [PeerConnectionProxy]()

    init(delegate: PeerConnectionClientDelegate) {
        AssertIsOnMainThread()

        self.delegate = delegate

        callConnectionfactory = CallConnectionFactory()

        super.init()

        proxy.set(value: self)

        Logger.debug("object! PeerConnectionClient created \(ObjectIdentifier(self))")
    }

    deinit {
        Logger.debug("object! PeerConnectionClient destroyed \(ObjectIdentifier(self))")
    }

    public func close() {
        AssertIsOnMainThread()

        Logger.debug("close")

        // Clear the delegate immediately so that we can guarantee that
        // no delegate methods are called after terminate() returns.
        delegate = nil

        // Clear the proxy immediately so that enqueued work is aborted
        // going forward.
        PeerConnectionClient.expiredProxies.append(proxy)
        proxy.clear()

        // Don't use [weak self]; we always want to perform terminateInternal().
        PeerConnectionClient.signalingQueue.async {
            //        Some notes on preventing crashes while disposing of peerConnection for video calls
            //        from: https://groups.google.com/forum/#!searchin/discuss-webrtc/objc$20crash$20dealloc%7Csort:relevance/discuss-webrtc/7D-vk5yLjn8/rBW2D6EW4GYJ
            //        The sequence to make it work appears to be
            //
            //        [capturer stop]; // I had to add this as a method to RTCVideoCapturer
            //        [localRenderer stop];
            //        [remoteRenderer stop];
            //        [peerConnection close];

            if let callConnection = self.callConnection {
                Logger.debug("Calling callConnection.close()")
                callConnection.close()
            }
            self.callConnection = nil
            Logger.debug("callConnection is nil")

            if let callConnectionfactory = self.callConnectionfactory {
                Logger.debug("Calling callConnectionfactory.close()")
                callConnectionfactory.close()
            }
            self.callConnectionfactory = nil
            Logger.debug("callConnectionfactory is nil")
        }
    }

    // MARK: - Session negotiation

    public func sendOffer(iceServers: [RTCIceServer], useTurnOnly: Bool, callId: UInt64) throws {
        AssertIsOnMainThread()

        Logger.debug("sendOffer")

        guard let callConnectionfactory = self.callConnectionfactory else {
            throw CallError.fatalError(description: "Missing factory")
        }

        let callConnection = try callConnectionfactory.createCallConnection(delegate: proxy, iceServers: iceServers, callId: callId, isOutgoing: true, hideIp: useTurnOnly)
        self.callConnection = callConnection

        try callConnection.sendOffer()
    }

    public func receivedOffer(iceServers: [RTCIceServer], useTurnOnly: Bool, callId: UInt64, sdp: String) throws {
        AssertIsOnMainThread()

        Logger.debug("receivedOffer")

        guard let callConnectionfactory = self.callConnectionfactory else {
            throw CallError.fatalError(description: "Missing factory")
        }

        let callConnection = try callConnectionfactory.createCallConnection(delegate: proxy, iceServers: iceServers, callId: callId, isOutgoing: false, hideIp: useTurnOnly)
        self.callConnection = callConnection

        try callConnection.receivedOffer(sdp: sdp)
    }

    public func receivedAnswer(sdp: String) throws {
        AssertIsOnMainThread()

        Logger.debug("receivedAnswer")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.receivedAnswer(sdp: sdp)
    }

    public func receivedIceCandidate(sdp: String, lineIndex: Int32, sdpMid: String) throws {
        AssertIsOnMainThread()

        Logger.debug("receivedIceCandidate")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.receivedIceCandidate(sdp: sdp, lineIndex: lineIndex, sdpMid: sdpMid)
    }

    // MARK: - Session Control

    public func acceptCall() throws {
        AssertIsOnMainThread()

        Logger.debug("acceptCall")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.accept()
    }

    public func hangup() throws {
        AssertIsOnMainThread()

        Logger.debug("hangup")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.hangup()
    }

    public func setLocalAudioEnabled(enabled: Bool) throws {
        AssertIsOnMainThread()

        Logger.debug("setLocalAudioEnabled \(enabled)")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.setLocalAudioEnabled(enabled: enabled)
    }

    public func setLocalVideoEnabled(enabled: Bool) throws {
        AssertIsOnMainThread()

        Logger.debug("setLocalVideoEnabled \(enabled)")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.setLocalVideoEnabled(enabled: enabled)
    }

    public func sendLocalVideoStatus(enabled: Bool) throws {
        AssertIsOnMainThread()

        Logger.debug("sendLocalVideoStatus \(enabled)")

        guard let callConnection = self.callConnection else {
            throw CallError.obsoleteCall(description: "Invalid callConnection")
        }

        try callConnection.sendLocalVideoStatus(enabled: enabled)
    }

    public func setCameraSource(isUsingFrontCamera: Bool) throws {
        AssertIsOnMainThread()

        Logger.debug("setCameraSource \(isUsingFrontCamera)")

        let proxyCopy = self.proxy

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            do {
                try callConnection.switchCamera(isUsingFrontCamera: isUsingFrontCamera)
            } catch {
                Logger.debug("callConnection.switchCamera failed with \(error)")
            }
        }
    }

    // MARK: - CallConnectionDelegate

    internal func callConnection(_ callConnectionParam: CallConnection, onCallEvent event: CallEvent, callId: UInt64) {
        Logger.debug("onCallEvent")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("onCallEvent - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, onCallEvent: event, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, onCallError error: String, callId: UInt64) {
        Logger.debug("onCallError")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("onCallError - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, onCallError: error, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, onAddRemoteVideoTrack track: RTCVideoTrack, callId: UInt64) {
        Logger.debug("onAddRemoteVideoTrack")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("onAddRemoteVideoTrack - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, onAddRemoteVideoTrack: track, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, onUpdateLocalVideoSession session: AVCaptureSession?, callId: UInt64) {
        Logger.debug("onUpdateLocalVideoSession")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("onUpdateLocalVideoSession - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, onUpdateLocalVideoSession: session, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, shouldSendOffer sdp: String, callId: UInt64) {
        Logger.debug("shouldSendOffer")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("shouldSendOffer - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, shouldSendOffer: sdp, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, shouldSendAnswer sdp: String, callId: UInt64) {
        Logger.debug("shouldSendAnswer")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("shouldSendAnswer - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, shouldSendAnswer: sdp, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, shouldSendIceCandidates candidates: [RTCIceCandidate], callId: UInt64) {
        Logger.debug("shouldSendIceCandidates")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("shouldSendIceCandidates - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, shouldSendIceCandidates: candidates, callId: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, shouldSendHangup callId: UInt64) {
        Logger.debug("shouldSendHangup")

        let proxyCopy = self.proxy

        DispatchQueue.main.async {
            Logger.debug("shouldSendHangup - main thread")

            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            guard let callConnection = strongSelf.callConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard callConnection == callConnectionParam else {
                owsFailDebug("Mismatched callConnection callback")
                return
            }

            strongDelegate.peerConnectionClient(strongSelf, shouldSendHangup: callId)
        }
    }

    internal func callConnection(_ callConnectionParam: CallConnection, shouldSendBusy callId: UInt64) {
        // Not supported on iOS. CallService maintains the state necessary
        // to send Busy messages when appropriate.
    }

    // MARK: Test-only accessors

    internal func peerConnectionForTests() -> CallConnection {
        AssertIsOnMainThread()

        var result: CallConnection?
        PeerConnectionClient.signalingQueue.sync {
            result = callConnection
            Logger.info("")
        }
        return result!
    }

    internal func flushSignalingQueueForTests() {
        AssertIsOnMainThread()

        PeerConnectionClient.signalingQueue.sync {
            // Noop.
        }
    }
}
