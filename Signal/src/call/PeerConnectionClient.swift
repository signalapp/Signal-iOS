//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC
import SignalServiceKit
import SignalMessaging

// HACK - Seeing crazy SEGFAULTs on iOS9 when accessing these objc externs.
// iOS10 seems unaffected. Reproducible for ~1 in 3 calls.
// Binding them to a file constant seems to work around the problem.
let kAudioTrackType = kRTCMediaStreamTrackKindAudio
let kVideoTrackType = kRTCMediaStreamTrackKindVideo
let kMediaConstraintsMinWidth = kRTCMediaConstraintsMinWidth
let kMediaConstraintsMaxWidth = kRTCMediaConstraintsMaxWidth
let kMediaConstraintsMinHeight = kRTCMediaConstraintsMinHeight
let kMediaConstraintsMaxHeight = kRTCMediaConstraintsMaxHeight

/**
 * The PeerConnectionClient notifies it's delegate (the CallService) of key events in the call signaling life cycle
 *
 * The delegate's methods will always be called on the main thread.
 */
protocol PeerConnectionClientDelegate: class {

    /**
     * The connection has been established. The clients can now communicate.
     * This can be called multiple times throughout the call in the event of temporary network disconnects.
     */
    func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient)

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient)

    /**
     * After initially connecting, the connection disconnected.
     * It maybe be temporary, in which case `peerConnectionClientIceConnected` will be called again once we're reconnected.
     * Otherwise, `peerConnectionClientIceFailed` will eventually called.
     */
    func peerConnectionClientIceDisconnected(_ peerconnectionClient: PeerConnectionClient)

    /**
     * During the Signaling process each client generates IceCandidates locally, which contain information about how to 
     * reach the local client via the internet. The delegate must shuttle these IceCandates to the other (remote) client 
     * out of band, as part of establishing a connection over WebRTC.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, addedLocalIceCandidate iceCandidate: RTCIceCandidate)

    /**
     * Once the peerconnection is established, we can receive messages via the data channel, and notify the delegate.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: OWSWebRTCProtosData)

    /**
     * Fired whenever the local video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateLocal videoTrack: RTCVideoTrack?)

    /**
     * Fired whenever the remote video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateRemote videoTrack: RTCVideoTrack?)
}

/**
 * `PeerConnectionClient` is our interface to WebRTC.
 *
 * It is primarily a wrapper around `RTCPeerConnection`, which is responsible for sending and receiving our call data 
 * including audio, video, and some post-connected signaling (hangup, add video)
 */
class PeerConnectionClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {

    private class AtomicHandle<ValueType> : NSObject {
        var value: ValueType?

        func set(value: ValueType) {
            objc_sync_enter(self)
            self.value = value
            objc_sync_exit(self)
        }

        func get() -> ValueType? {
            objc_sync_enter(self)
            let result = value
            objc_sync_exit(self)
            return result
        }

        func clear() {
            Logger.info("\(logTag) \(#function)")

            objc_sync_enter(self)
            value = nil
            objc_sync_exit(self)
        }
    }

    enum Identifiers: String {
        case mediaStream = "ARDAMS",
             videoTrack = "ARDAMSv0",
             audioTrack = "ARDAMSa0",
             dataChannelSignaling = "signaling"
    }

    // A state in this class should only be accessed on this queue in order to
    // serialize access.
    //
    // This queue is also used to perform expensive calls to the WebRTC API.
    private static let signalingQueue = DispatchQueue(label: "CallServiceSignalingQueue")

    // Delegate is notified of key events in the call lifecycle.
    //
    // This property should only be accessed on the main thread.
    private weak var delegate: PeerConnectionClientDelegate?

    // Connection

    private var peerConnection: RTCPeerConnection?
    private let iceServers: [RTCIceServer]
    private let connectionConstraints: RTCMediaConstraints
    private let configuration: RTCConfiguration
    private let factory = RTCPeerConnectionFactory()

    // DataChannel

    private var dataChannel: RTCDataChannel?

    // Audio

    private var audioSender: RTCRtpSender?
    private var audioTrack: RTCAudioTrack?
    private var audioConstraints: RTCMediaConstraints

    // Video

    private var videoCaptureSession: AVCaptureSession?
    private var videoSender: RTCRtpSender?
    private var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCAVFoundationVideoSource?

    // RTCVideoTrack is fragile and prone to throwing exceptions and/or
    // causing deadlock in its destructor.  Therefore we take great care
    // with this property.
    private var remoteVideoTrack: RTCVideoTrack?
    private var cameraConstraints: RTCMediaConstraints

    private let handle: AtomicHandle<PeerConnectionClient>

    init(iceServers: [RTCIceServer], delegate: PeerConnectionClientDelegate, callDirection: CallDirection, useTurnOnly: Bool) {
        SwiftAssertIsOnMainThread(#function)

        self.iceServers = iceServers
        self.delegate = delegate

        configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        if useTurnOnly {
            Logger.debug("\(PeerConnectionClient.logTag) using iceTransportPolicy: relay")
            configuration.iceTransportPolicy = .relay
        } else {
            Logger.debug("\(PeerConnectionClient.logTag) using iceTransportPolicy: default")
        }

        let connectionConstraintsDict = ["DtlsSrtpKeyAgreement": "true"]
        connectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: connectionConstraintsDict)

        audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        handle = AtomicHandle<PeerConnectionClient>()

        super.init()

        handle.set(value: self)

        peerConnection = factory.peerConnection(with: configuration,
                                                constraints: connectionConstraints,
                                                delegate: self)
        createAudioSender()
        createVideoSender()

        if callDirection == .outgoing {
            // When placing an outgoing call, it's our responsibility to create the DataChannel. 
            // Recipient will not have to do this explicitly.
            createSignalingDataChannel()
        }
    }

    deinit {
        // TODO: We can demote this log level to debug once we're confident that
        // this class is always deallocated.
        Logger.info("[PeerConnectionClient] deinit")
    }

    // MARK: - Media Streams

    private func createSignalingDataChannel() {
        SwiftAssertIsOnMainThread(#function)
        guard let peerConnection = peerConnection else {
            Logger.debug("\(logTag) \(#function) Ignoring obsolete event in terminated client")
            return
        }

        let configuration = RTCDataChannelConfiguration()
        // Insist upon an "ordered" TCP data channel for delivery reliability.
        configuration.isOrdered = true
        let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                     configuration: configuration)
        dataChannel.delegate = self

        assert(self.dataChannel == nil)
        self.dataChannel = dataChannel
    }

    // MARK: Video

    fileprivate func createVideoSender() {
        SwiftAssertIsOnMainThread(#function)
        Logger.debug("\(logTag) in \(#function)")
        assert(self.videoSender == nil, "\(#function) should only be called once.")

        guard !Platform.isSimulator else {
            Logger.warn("\(logTag) Refusing to create local video track on simulator which has no capture device.")
            return
        }
        guard let peerConnection = peerConnection else {
            Logger.debug("\(logTag) \(#function) Ignoring obsolete event in terminated client")
            return
        }

        // TODO: We could cap the maximum video size.
        let cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                                    optionalConstraints: nil)

        // TODO: Revisit the cameraConstraints.
        let videoSource = factory.avFoundationVideoSource(with: cameraConstraints)
        self.localVideoSource = videoSource

        self.videoCaptureSession = videoSource.captureSession
        videoSource.useBackCamera = false

        let localVideoTrack = factory.videoTrack(with: videoSource, trackId: Identifiers.videoTrack.rawValue)
        self.localVideoTrack = localVideoTrack

        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        localVideoTrack.isEnabled = false

        let videoSender = peerConnection.sender(withKind: kVideoTrackType, streamId: Identifiers.mediaStream.rawValue)
        videoSender.track = localVideoTrack
        self.videoSender = videoSender
    }

    public func setCameraSource(useBackCamera: Bool) {
        SwiftAssertIsOnMainThread(#function)

        let handle = self.handle
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let localVideoSource = strongSelf.localVideoSource else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            // certain devices, e.g. 16GB iPod touch don't have a back camera
            guard localVideoSource.canUseBackCamera else {
                owsFail("\(strongSelf.logTag) in \(#function) canUseBackCamera was unexpectedly false")
                return
            }

            localVideoSource.useBackCamera = useBackCamera
        }
    }

    public func setLocalVideoEnabled(enabled: Bool) {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        let completion = { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let localVideoTrack = strongSelf.localVideoTrack else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClient(strongSelf, didUpdateLocal: enabled ? localVideoTrack : nil)
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard let localVideoTrack = strongSelf.localVideoTrack else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard let videoCaptureSession = strongSelf.videoCaptureSession else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            localVideoTrack.isEnabled = enabled

            if enabled {
                Logger.debug("\(strongSelf.logTag) in \(#function) starting videoCaptureSession")
                videoCaptureSession.startRunning()
            } else {
                Logger.debug("\(strongSelf.logTag) in \(#function) stopping videoCaptureSession")
                videoCaptureSession.stopRunning()
            }

            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: Audio

    fileprivate func createAudioSender() {
        SwiftAssertIsOnMainThread(#function)
        Logger.debug("\(logTag) in \(#function)")
        assert(self.audioSender == nil, "\(#function) should only be called once.")

        guard let peerConnection = peerConnection else {
            Logger.debug("\(logTag) \(#function) Ignoring obsolete event in terminated client")
            return
        }

        let audioSource = factory.audioSource(with: self.audioConstraints)

        let audioTrack = factory.audioTrack(with: audioSource, trackId: Identifiers.audioTrack.rawValue)
        self.audioTrack = audioTrack

        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        audioTrack.isEnabled = false

        let audioSender = peerConnection.sender(withKind: kAudioTrackType, streamId: Identifiers.mediaStream.rawValue)
        audioSender.track = audioTrack
        self.audioSender = audioSender
    }

    public func setAudioEnabled(enabled: Bool) {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard let audioTrack = strongSelf.audioTrack else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            audioTrack.isEnabled = enabled
        }
    }

    // MARK: - Session negotiation

    private var defaultOfferConstraints: RTCMediaConstraints {
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ]
        return RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
    }

    public func createOffer() -> Promise<HardenedRTCSessionDescription> {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        let (promise, fulfill, reject) = Promise<HardenedRTCSessionDescription>.pending()
        let completion: ((RTCSessionDescription?, Error?) -> Void) = { [weak self] (sdp, error) in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()
            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            if let error = error {
                reject(error)
                return
            }

            guard let sessionDescription = sdp else {
                Logger.error("\(strongSelf.logTag) No session description was obtained, even though there was no error reported.")
                let error = OWSErrorMakeUnableToProcessServerResponseError()
                reject(error)
                return
            }

            fulfill(HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription))
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            peerConnection.offer(for: strongSelf.defaultOfferConstraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async { [weak self] in
                    completion(sdp, error)
                }
            })
        }

        return promise
    }

    public func setLocalSessionDescriptionInternal(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        let handle = self.handle
        return PromiseKit.wrap { [weak self] resolve in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()

            guard let peerConnection = peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            Logger.verbose("\(strongSelf.logTag) setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription, completionHandler: resolve)
        }
    }

    public func setLocalSessionDescription(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        let (promise, fulfill, reject) = Promise<Void>.pending()
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            Logger.verbose("\(strongSelf.logTag) setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription,
                                               completionHandler: { error in
                                                if let error = error {
                                                    reject(error)
                                                    return
                                                }
                                                fulfill()
            })
        }

        return promise
    }

    public func negotiateSessionDescription(remoteDescription: RTCSessionDescription, constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        return setRemoteSessionDescription(remoteDescription)
            .then(on: PeerConnectionClient.signalingQueue) { [weak self] in
                guard let strongSelf = handle.get() else {
                    return Promise { _, reject in
                        reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                    }
                }
                    return strongSelf.negotiateAnswerSessionDescription(constraints: constraints)
        }
    }

    public func setRemoteSessionDescription(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        let (promise, fulfill, reject) = Promise<Void>.pending()
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            Logger.verbose("\(strongSelf.logTag) setting remote description: \(sessionDescription)")
            peerConnection.setRemoteDescription(sessionDescription,
                                                completionHandler: { error in
                                                    if let error = error {
                                                        reject(error)
                                                        return
                                                    }
                                                    fulfill()
            })
        }
        return promise
    }

    private func negotiateAnswerSessionDescription(constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        assertOnSignalingQueue()
        let handle = self.handle
        let (promise, fulfill, reject) = Promise<HardenedRTCSessionDescription>.pending()
        let completion: ((RTCSessionDescription?, Error?) -> Void) = { [weak self] (sdp, error) in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()
            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            if let error = error {
                reject(error)
                return
            }

            guard let sessionDescription = sdp else {
                Logger.error("\(strongSelf.logTag) unexpected empty session description, even though no error was reported.")
                let error = OWSErrorMakeUnableToProcessServerResponseError()
                reject(error)
                return
            }

            let hardenedSessionDescription = HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription)

            strongSelf.setLocalSessionDescriptionInternal(hardenedSessionDescription)
                .then(on: PeerConnectionClient.signalingQueue) { _ in
                    fulfill(hardenedSessionDescription)
                }.catch { error in
                    reject(error)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            strongSelf.assertOnSignalingQueue()

            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }

            Logger.debug("\(strongSelf.logTag) negotiating answer session.")

            peerConnection.answer(for: constraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async { [weak self] in
                    completion(sdp, error)
                }
            })
        }
        return promise
    }

    public func addRemoteIceCandidate(_ candidate: RTCIceCandidate) {
        let handle = self.handle
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            Logger.info("\(strongSelf.logTag) adding remote ICE candidate: \(candidate.sdp)")
            peerConnection.add(candidate)
        }
    }

    public func terminate() {
        SwiftAssertIsOnMainThread(#function)
        Logger.debug("\(logTag) in \(#function)")

        // Clear the delegate immediately so that we can guarantee that
        // no delegate methods are called after terminate() returns.
        delegate = nil

        // Clear the handle immediately so that enqueued work is aborted
        // going forward.
        handle.clear()

        // Don't use [weak self]; we always want to perform terminateInternal().
        PeerConnectionClient.signalingQueue.async {
            self.terminateInternal()
        }
    }

    private func terminateInternal() {
        assertOnSignalingQueue()
        Logger.debug("\(logTag) in \(#function)")

        //        Some notes on preventing crashes while disposing of peerConnection for video calls
        //        from: https://groups.google.com/forum/#!searchin/discuss-webrtc/objc$20crash$20dealloc%7Csort:relevance/discuss-webrtc/7D-vk5yLjn8/rBW2D6EW4GYJ
        //        The sequence to make it work appears to be
        //
        //        [capturer stop]; // I had to add this as a method to RTCVideoCapturer
        //        [localRenderer stop];
        //        [remoteRenderer stop];
        //        [peerConnection close];

        // audioTrack is a strong property because we need access to it to mute/unmute, but I was seeing it
        // become nil when it was only a weak property. So we retain it and manually nil the reference here, because
        // we are likely to crash if we retain any peer connection properties when the peerconnection is released

        localVideoTrack?.isEnabled = false
        remoteVideoTrack?.isEnabled = false

        if let dataChannel = self.dataChannel {
            dataChannel.delegate = nil
        }

        dataChannel = nil
        audioSender = nil
        audioTrack = nil
        videoSender = nil
        localVideoSource = nil
        localVideoTrack = nil
        remoteVideoTrack = nil

        if let peerConnection = peerConnection {
            peerConnection.delegate = nil
            peerConnection.close()
        }
        peerConnection = nil
    }

    // MARK: - Data Channel

    // should only be accessed on PeerConnectionClient.signalingQueue
    var pendingDataChannelMessages: [PendingDataChannelMessage] = []
    struct PendingDataChannelMessage {
        let data: Data
        let description: String
        let isCritical: Bool
    }

    public func sendDataChannelMessage(data: Data, description: String, isCritical: Bool) {
        SwiftAssertIsOnMainThread(#function)
        let handle = self.handle
        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client: \(description)")
                return
            }

            guard let dataChannel = strongSelf.dataChannel else {
                if isCritical {
                    Logger.info("\(strongSelf.logTag) in \(#function) enqueuing critical data channel message for after we have a dataChannel: \(description)")
                    strongSelf.pendingDataChannelMessages.append(PendingDataChannelMessage(data: data, description: description, isCritical: isCritical))
                } else {
                    Logger.error("\(strongSelf.logTag) in \(#function) ignoring sending \(data) for nil dataChannel: \(description)")
                }
                return
            }

            Logger.debug("\(strongSelf.logTag) sendDataChannelMessage trying: \(description)")

            let buffer = RTCDataBuffer(data: data, isBinary: false)
            let result = dataChannel.sendData(buffer)

            if result {
                Logger.debug("\(strongSelf.logTag) sendDataChannelMessage succeeded: \(description)")
            } else {
                Logger.warn("\(strongSelf.logTag) sendDataChannelMessage failed: \(description)")
                if isCritical {
                    OWSProdError(OWSAnalyticsEvents.peerConnectionClientErrorSendDataChannelMessageFailed(), file: #file, function: #function, line: #line)
                }
            }
        }
    }

    // MARK: RTCDataChannelDelegate

    /** The data channel state changed. */
    internal func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("\(logTag) dataChannelDidChangeState: \(dataChannel)")
    }

    /** The data channel successfully received a data buffer. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let handle = self.handle
        let completion: (OWSWebRTCProtosData) -> Void = { [weak self] (dataChannelMessage) in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClient(strongSelf, received: dataChannelMessage)
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            Logger.debug("\(strongSelf.logTag) dataChannel didReceiveMessageWith buffer:\(buffer)")

            guard let dataChannelMessage = OWSWebRTCProtosData.parse(from: buffer.data) else {
                // TODO can't proto parsings throw an exception? Is it just being lost in the Objc->Swift?
                Logger.error("\(strongSelf.logTag) failed to parse dataProto")
                return
            }

            DispatchQueue.main.async {
                completion(dataChannelMessage)
            }
        }
    }

    /** The data channel's |bufferedAmount| changed. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        Logger.debug("\(logTag) didChangeBufferedAmount: \(amount)")
    }

    // MARK: - RTCPeerConnectionDelegate

    /** Called when the SignalingState changed. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("\(logTag) didChange signalingState:\(stateChanged.debugDescription)")
    }

    /** Called when media is received on a new stream from remote peer. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let handle = self.handle
        let completion: (RTCVideoTrack) -> Void = { [weak self] (remoteVideoTrack) in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            // TODO: Consider checking for termination here.

            strongDelegate.peerConnectionClient(strongSelf, didUpdateRemote: remoteVideoTrack)
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFail("\(strongSelf.logTag) in \(#function) mismatched peerConnection callback.")
                return
            }
            guard stream.videoTracks.count > 0 else {
                owsFail("\(strongSelf.logTag) in \(#function) didAdd stream missing stream.")
                return
            }
            let remoteVideoTrack = stream.videoTracks[0]
            Logger.debug("\(strongSelf.logTag) didAdd stream:\(stream) video tracks: \(stream.videoTracks.count) audio tracks: \(stream.audioTracks.count)")

            strongSelf.remoteVideoTrack = remoteVideoTrack

            DispatchQueue.main.async {
                completion(remoteVideoTrack)
            }
        }
    }

    /** Called when a remote peer closes a stream. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.debug("\(logTag) didRemove Stream:\(stream)")
    }

    /** Called when negotiation is needed, for example ICE has restarted. */
    internal func peerConnectionShouldNegotiate(_ peerConnectionParam: RTCPeerConnection) {
        Logger.debug("\(logTag) shouldNegotiate")
    }

    /** Called any time the IceConnectionState changes. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let handle = self.handle
        let connectedCompletion : () -> Void = { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceConnected(strongSelf)
        }
        let failedCompletion : () -> Void = { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceFailed(strongSelf)
        }
        let disconnectedCompletion : () -> Void = { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceDisconnected(strongSelf)
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFail("\(strongSelf.logTag) in \(#function) mismatched peerConnection callback.")
                return
            }

            Logger.info("\(strongSelf.logTag) didChange IceConnectionState:\(newState.debugDescription)")
            switch newState {
            case .connected, .completed:
                DispatchQueue.main.async(execute: connectedCompletion)
            case .failed:
                Logger.warn("\(strongSelf.logTag) RTCIceConnection failed.")
                DispatchQueue.main.async(execute: failedCompletion)
            case .disconnected:
                Logger.warn("\(strongSelf.logTag) RTCIceConnection disconnected.")
                DispatchQueue.main.async(execute: disconnectedCompletion)
            default:
                Logger.debug("\(strongSelf.logTag) ignoring change IceConnectionState:\(newState.debugDescription)")
            }
        }
    }

    /** Called any time the IceGatheringState changes. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.info("\(logTag) didChange IceGatheringState:\(newState.debugDescription)")
    }

    /** New ice candidate has been found. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let handle = self.handle
        let completion: (RTCIceCandidate) -> Void = { [weak self] (candidate) in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClient(strongSelf, addedLocalIceCandidate: candidate)
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFail("\(strongSelf.logTag) in \(#function) mismatched peerConnection callback.")
                return
            }
            Logger.info("\(strongSelf.logTag) adding local ICE candidate:\(candidate.sdp)")
            DispatchQueue.main.async {
                completion(candidate)
            }
        }
    }

    /** Called when a group of local Ice candidates have been removed. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("\(logTag) didRemove IceCandidates:\(candidates)")
    }

    /** New data channel has been opened. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        let handle = self.handle
        let completion: ([PendingDataChannelMessage]) -> Void = { [weak self] (pendingMessages) in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = handle.get() else { return }
            pendingMessages.forEach { message in
                strongSelf.sendDataChannelMessage(data: message.data, description: message.description, isCritical: message.isCritical)
            }
        }

        PeerConnectionClient.signalingQueue.async { [weak self] in
            guard let strongSelf = handle.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("\(strongSelf.logTag) \(#function) Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFail("\(strongSelf.logTag) in \(#function) mismatched peerConnection callback.")
                return
            }
            Logger.info("\(strongSelf.logTag) didOpen dataChannel:\(dataChannel)")
            if strongSelf.dataChannel != nil {
                owsFail("\(strongSelf.logTag) in \(#function) dataChannel unexpectedly set twice.")
            }
            strongSelf.dataChannel = dataChannel
            dataChannel.delegate = strongSelf

            let pendingMessages = strongSelf.pendingDataChannelMessages
            strongSelf.pendingDataChannelMessages = []
            DispatchQueue.main.async {
                completion(pendingMessages)
            }
        }
    }

    // MARK: Helpers

    /**
     * We synchronize access to state in this class using this queue.
     */
    private func assertOnSignalingQueue() {
        assertOnQueue(type(of: self).signalingQueue)
    }

    // MARK: Test-only accessors

    internal func peerConnectionForTests() -> RTCPeerConnection {
        SwiftAssertIsOnMainThread(#function)

        var result: RTCPeerConnection? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = peerConnection
            Logger.info("\(self.logTag) called \(#function)")
        }
        return result!
    }

    internal func dataChannelForTests() -> RTCDataChannel {
        SwiftAssertIsOnMainThread(#function)

        var result: RTCDataChannel? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = dataChannel
            Logger.info("\(self.logTag) called \(#function)")
        }
        return result!
    }

    internal func flushSignalingQueueForTests() {
        SwiftAssertIsOnMainThread(#function)

        PeerConnectionClient.signalingQueue.sync {
            // Noop.
        }
    }
}

/**
 * Restrict an RTCSessionDescription to more secure parameters
 */
class HardenedRTCSessionDescription {
    let rtcSessionDescription: RTCSessionDescription
    var sdp: String { return rtcSessionDescription.sdp }

    init(rtcSessionDescription: RTCSessionDescription) {
        self.rtcSessionDescription = HardenedRTCSessionDescription.harden(rtcSessionDescription: rtcSessionDescription)
    }

    /**
     * Set some more secure parameters for the session description
     */
    class func harden(rtcSessionDescription: RTCSessionDescription) -> RTCSessionDescription {
        var description = rtcSessionDescription.sdp

        // Enforce Constant bit rate.
        let cbrRegex = try! NSRegularExpression(pattern: "(a=fmtp:111 ((?!cbr=).)*)\r?\n", options: .caseInsensitive)
        description = cbrRegex.stringByReplacingMatches(in: description, options: [], range: NSRange(location: 0, length: description.count), withTemplate: "$1;cbr=1\r\n")

        // Strip plaintext audio-level details
        // https://tools.ietf.org/html/rfc6464
        let audioLevelRegex = try! NSRegularExpression(pattern: ".+urn:ietf:params:rtp-hdrext:ssrc-audio-level.*\r?\n", options: .caseInsensitive)
        description = audioLevelRegex.stringByReplacingMatches(in: description, options: [], range: NSRange(location: 0, length: description.count), withTemplate: "")

        return RTCSessionDescription.init(type: rtcSessionDescription.type, sdp: description)
    }
}

// Mark: Pretty Print Objc enums.

fileprivate extension RTCSignalingState {
    var debugDescription: String {
        switch self {
        case .stable:
            return "stable"
        case .haveLocalOffer:
            return "haveLocalOffer"
        case .haveLocalPrAnswer:
            return "haveLocalPrAnswer"
        case .haveRemoteOffer:
            return "haveRemoteOffer"
        case .haveRemotePrAnswer:
            return "haveRemotePrAnswer"
        case .closed:
            return "closed"
        }
    }
}

fileprivate extension RTCIceGatheringState {
    var debugDescription: String {
        switch self {
        case .new:
            return "new"
        case .gathering:
            return "gathering"
        case .complete:
            return "complete"
        }
    }
}

fileprivate extension RTCIceConnectionState {
    var debugDescription: String {
        switch self {
        case .new:
            return "new"
        case .checking:
            return "checking"
        case .connected:
            return "connected"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .disconnected:
            return "disconnected"
        case .closed:
            return "closed"
        case .count:
            return "count"
        }
    }
}
