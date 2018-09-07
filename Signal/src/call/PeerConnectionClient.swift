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
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, received dataChannelMessage: WebRTCProtoData)

    /**
     * Fired whenever the local video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateLocalVideoCaptureSession captureSession: AVCaptureSession?)

    /**
     * Fired whenever the remote video track become active or inactive.
     */
    func peerConnectionClient(_ peerconnectionClient: PeerConnectionClient, didUpdateRemoteVideoTrack videoTrack: RTCVideoTrack?)
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
class PeerConnectionProxy: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {

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

    // MARK: - RTCPeerConnectionDelegate

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        self.get()?.peerConnection(peerConnection, didChange: stateChanged)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        self.get()?.peerConnection(peerConnection, didAdd: stream)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        self.get()?.peerConnection(peerConnection, didRemove: stream)
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        self.get()?.peerConnectionShouldNegotiate(peerConnection)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        self.get()?.peerConnection(peerConnection, didChange: newState)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        self.get()?.peerConnection(peerConnection, didChange: newState)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.get()?.peerConnection(peerConnection, didGenerate: candidate)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        self.get()?.peerConnection(peerConnection, didRemove: candidates)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.get()?.peerConnection(peerConnection, didOpen: dataChannel)
    }

    // MARK: - RTCDataChannelDelegate

    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        self.get()?.dataChannelDidChangeState(dataChannel)
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        self.get()?.dataChannel(dataChannel, didReceiveMessageWith: buffer)
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        self.get()?.dataChannel(dataChannel, didChangeBufferedAmount: amount)
    }
}

/**
 * `PeerConnectionClient` is our interface to WebRTC.
 *
 * It is primarily a wrapper around `RTCPeerConnection`, which is responsible for sending and receiving our call data
 * including audio, video, and some post-connected signaling (hangup, add video)
 */
class PeerConnectionClient: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, VideoCaptureSettingsDelegate {

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
    private let factory: RTCPeerConnectionFactory

    // DataChannel

    private var dataChannel: RTCDataChannel?

    // Audio

    private var audioSender: RTCRtpSender?
    private var audioTrack: RTCAudioTrack?
    private var audioConstraints: RTCMediaConstraints

    // Video

    private var videoCaptureController: VideoCaptureController?
    private var videoSender: RTCRtpSender?

    // RTCVideoTrack is fragile and prone to throwing exceptions and/or
    // causing deadlock in its destructor.  Therefore we take great care
    // with this property.
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var cameraConstraints: RTCMediaConstraints

    private let proxy = PeerConnectionProxy()
    // Note that we're deliberately leaking proxy instances using this
    // collection to avoid EXC_BAD_ACCESS.  Calls are rare and the proxy
    // is tiny (a single property), so it's better to leak and be safe.
    private static var expiredProxies = [PeerConnectionProxy]()

    init(iceServers: [RTCIceServer], delegate: PeerConnectionClientDelegate, callDirection: CallDirection, useTurnOnly: Bool) {
        AssertIsOnMainThread()

        self.iceServers = iceServers
        self.delegate = delegate

        // Ensure we enable SW decoders to enable VP8 support
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)

        self.factory = factory
        configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        if useTurnOnly {
            Logger.debug("using iceTransportPolicy: relay")
            configuration.iceTransportPolicy = .relay
        } else {
            Logger.debug("using iceTransportPolicy: default")
        }

        let connectionConstraintsDict = ["DtlsSrtpKeyAgreement": "true"]
        connectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: connectionConstraintsDict)

        audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        super.init()

        proxy.set(value: self)

        peerConnection = factory.peerConnection(with: configuration,
                                                constraints: connectionConstraints,
                                                delegate: proxy)
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
        AssertIsOnMainThread()
        guard let peerConnection = peerConnection else {
            Logger.debug("Ignoring obsolete event in terminated client")
            return
        }

        let configuration = RTCDataChannelConfiguration()
        // Insist upon an "ordered" TCP data channel for delivery reliability.
        configuration.isOrdered = true

        guard let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                           configuration: configuration) else {

                                                            // TODO fail outgoing call?
                                                            owsFailDebug("dataChannel was unexpectedly nil")
                                                            return
        }
        dataChannel.delegate = proxy

        assert(self.dataChannel == nil)
        self.dataChannel = dataChannel
    }

    // MARK: - Video

    fileprivate func createVideoSender() {
        AssertIsOnMainThread()
        Logger.debug("")
        assert(self.videoSender == nil, "\(#function) should only be called once.")

        guard !Platform.isSimulator else {
            Logger.warn("Refusing to create local video track on simulator which has no capture device.")
            return
        }
        guard let peerConnection = peerConnection else {
            Logger.debug("Ignoring obsolete event in terminated client")
            return
        }

        let videoSource = factory.videoSource()

        let localVideoTrack = factory.videoTrack(with: videoSource, trackId: Identifiers.videoTrack.rawValue)
        self.localVideoTrack = localVideoTrack
        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        localVideoTrack.isEnabled = false

        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        self.videoCaptureController = VideoCaptureController(capturer: capturer, settingsDelegate: self)

        let videoSender = peerConnection.sender(withKind: kVideoTrackType, streamId: Identifiers.mediaStream.rawValue)
        videoSender.track = localVideoTrack
        self.videoSender = videoSender
    }

    public func setCameraSource(isUsingFrontCamera: Bool) {
        AssertIsOnMainThread()

        let proxyCopy = self.proxy
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }

            guard let captureController = strongSelf.videoCaptureController else {
                owsFailDebug("captureController was unexpectedly nil")
                return
            }

            captureController.switchCamera(isUsingFrontCamera: isUsingFrontCamera)
        }
    }

    public func setLocalVideoEnabled(enabled: Bool) {
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        let completion = {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            let captureSession: AVCaptureSession? = {
                guard enabled else {
                    return nil
                }

                guard let captureController = strongSelf.videoCaptureController else {
                    owsFailDebug("videoCaptureController was unexpectedly nil")
                    return nil
                }

                return captureController.captureSession
            }()

            strongDelegate.peerConnectionClient(strongSelf, didUpdateLocalVideoCaptureSession: captureSession)
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard let videoCaptureController = strongSelf.videoCaptureController else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }

            guard let localVideoTrack = strongSelf.localVideoTrack else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            localVideoTrack.isEnabled = enabled

            if enabled {
                Logger.debug("starting video capture")
                videoCaptureController.startCapture()
            } else {
                Logger.debug("stopping video capture")
                videoCaptureController.stopCapture()
            }

            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: VideoCaptureSettingsDelegate

    var videoWidth: Int32 {
        return 400
    }

    var videoHeight: Int32 {
        return 400
    }

    // MARK: - Audio

    fileprivate func createAudioSender() {
        AssertIsOnMainThread()
        Logger.debug("")
        assert(self.audioSender == nil, "\(#function) should only be called once.")

        guard let peerConnection = peerConnection else {
            Logger.debug("Ignoring obsolete event in terminated client")
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
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            guard let audioTrack = strongSelf.audioTrack else {
                Logger.debug("Ignoring obsolete event in terminated client")
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
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        let (promise, fulfill, reject) = Promise<HardenedRTCSessionDescription>.pending()
        let completion: ((RTCSessionDescription?, Error?) -> Void) = { (sdp, error) in
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()
            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            if let error = error {
                reject(error)
                return
            }

            guard let sessionDescription = sdp else {
                Logger.error("No session description was obtained, even though there was no error reported.")
                let error = OWSErrorMakeUnableToProcessServerResponseError()
                reject(error)
                return
            }

            fulfill(HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription))
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            peerConnection.offer(for: strongSelf.defaultOfferConstraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async {
                    completion(sdp, error)
                }
            })
        }

        return promise
    }

    public func setLocalSessionDescriptionInternal(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        let proxyCopy = self.proxy
        let (promise, fulfill, reject) = Promise<Void>.pending()
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()

            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            Logger.verbose("setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription, completionHandler: { (error) in
                if let error = error {
                    reject(error)
                } else {
                    fulfill(())
                }
            })
        }
        return promise
    }

    public func setLocalSessionDescription(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        let (promise, fulfill, reject) = Promise<Void>.pending()
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            Logger.verbose("setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription,
                                               completionHandler: { error in
                                                if let error = error {
                                                    reject(error)
                                                    return
                                                }
                                                fulfill(())
            })
        }

        return promise
    }

    public func negotiateSessionDescription(remoteDescription: RTCSessionDescription, constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        return setRemoteSessionDescription(remoteDescription)
            .then(on: PeerConnectionClient.signalingQueue) {
                guard let strongSelf = proxyCopy.get() else {
                    return Promise(error: NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                }
                    return strongSelf.negotiateAnswerSessionDescription(constraints: constraints)
        }
    }

    public func setRemoteSessionDescription(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        let (promise, fulfill, reject) = Promise<Void>.pending()
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            Logger.verbose("setting remote description: \(sessionDescription)")
            peerConnection.setRemoteDescription(sessionDescription,
                                                completionHandler: { error in
                                                    if let error = error {
                                                        reject(error)
                                                        return
                                                    }
                                                    fulfill(())
            })
        }
        return promise
    }

    private func negotiateAnswerSessionDescription(constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        assertOnSignalingQueue()
        let proxyCopy = self.proxy
        let (promise, fulfill, reject) = Promise<HardenedRTCSessionDescription>.pending()
        let completion: ((RTCSessionDescription?, Error?) -> Void) = { (sdp, error) in
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()
            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            if let error = error {
                reject(error)
                return
            }

            guard let sessionDescription = sdp else {
                Logger.error("unexpected empty session description, even though no error was reported.")
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

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else {
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }
            strongSelf.assertOnSignalingQueue()

            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                reject(NSError(domain: "Obsolete client", code: 0, userInfo: nil))
                return
            }

            Logger.debug("negotiating answer session.")

            peerConnection.answer(for: constraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async {
                    completion(sdp, error)
                }
            })
        }
        return promise
    }

    public func addRemoteIceCandidate(_ candidate: RTCIceCandidate) {
        let proxyCopy = self.proxy
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            Logger.info("adding remote ICE candidate: \(candidate.sdp)")
            peerConnection.add(candidate)
        }
    }

    public func terminate() {
        AssertIsOnMainThread()
        Logger.debug("")

        // Clear the delegate immediately so that we can guarantee that
        // no delegate methods are called after terminate() returns.
        delegate = nil

        // Clear the proxy immediately so that enqueued work is aborted
        // going forward.
        PeerConnectionClient.expiredProxies.append(proxy)
        proxy.clear()

        // Don't use [weak self]; we always want to perform terminateInternal().
        PeerConnectionClient.signalingQueue.async {
            self.terminateInternal()
        }
    }

    private func terminateInternal() {
        assertOnSignalingQueue()
        Logger.debug("")

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
        localVideoTrack = nil
        remoteVideoTrack = nil
        videoCaptureController = nil

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
        AssertIsOnMainThread()
        let proxyCopy = self.proxy
        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }

            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client: \(description)")
                return
            }

            guard let dataChannel = strongSelf.dataChannel else {
                if isCritical {
                    Logger.info("enqueuing critical data channel message for after we have a dataChannel: \(description)")
                    strongSelf.pendingDataChannelMessages.append(PendingDataChannelMessage(data: data, description: description, isCritical: isCritical))
                } else {
                    Logger.error("ignoring sending \(data) for nil dataChannel: \(description)")
                }
                return
            }

            Logger.debug("sendDataChannelMessage trying: \(description)")

            let buffer = RTCDataBuffer(data: data, isBinary: false)
            let result = dataChannel.sendData(buffer)

            if result {
                Logger.debug("sendDataChannelMessage succeeded: \(description)")
            } else {
                Logger.warn("sendDataChannelMessage failed: \(description)")
                if isCritical {
                    OWSProdError(OWSAnalyticsEvents.peerConnectionClientErrorSendDataChannelMessageFailed(), file: #file, function: #function, line: #line)
                }
            }
        }
    }

    // MARK: RTCDataChannelDelegate

    /** The data channel state changed. */
    internal func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("dataChannelDidChangeState: \(dataChannel)")
    }

    /** The data channel successfully received a data buffer. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let proxyCopy = self.proxy
        let completion: (WebRTCProtoData) -> Void = { (dataChannelMessage) in
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClient(strongSelf, received: dataChannelMessage)
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard strongSelf.peerConnection != nil else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            Logger.debug("dataChannel didReceiveMessageWith buffer:\(buffer)")

            var dataChannelMessage: WebRTCProtoData
            do {
                dataChannelMessage = try WebRTCProtoData.parseData(buffer.data)
            } catch {
                Logger.error("failed to parse dataProto")
                return
            }

            DispatchQueue.main.async {
                completion(dataChannelMessage)
            }
        }
    }

    /** The data channel's |bufferedAmount| changed. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        Logger.debug("didChangeBufferedAmount: \(amount)")
    }

    // MARK: - RTCPeerConnectionDelegate

    /** Called when the SignalingState changed. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("didChange signalingState:\(stateChanged.debugDescription)")
    }

    /** Called when media is received on a new stream from remote peer. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let proxyCopy = self.proxy
        let completion: (RTCVideoTrack) -> Void = { (remoteVideoTrack) in
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }

            // TODO: Consider checking for termination here.

            strongDelegate.peerConnectionClient(strongSelf, didUpdateRemoteVideoTrack: remoteVideoTrack)
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFailDebug("mismatched peerConnection callback.")
                return
            }
            guard stream.videoTracks.count > 0 else {
                owsFailDebug("didAdd stream missing stream.")
                return
            }
            let remoteVideoTrack = stream.videoTracks[0]
            Logger.debug("didAdd stream:\(stream) video tracks: \(stream.videoTracks.count) audio tracks: \(stream.audioTracks.count)")

            strongSelf.remoteVideoTrack = remoteVideoTrack

            DispatchQueue.main.async {
                completion(remoteVideoTrack)
            }
        }
    }

    /** Called when a remote peer closes a stream. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.debug("didRemove Stream:\(stream)")
    }

    /** Called when negotiation is needed, for example ICE has restarted. */
    internal func peerConnectionShouldNegotiate(_ peerConnectionParam: RTCPeerConnection) {
        Logger.debug("shouldNegotiate")
    }

    /** Called any time the IceConnectionState changes. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let proxyCopy = self.proxy
        let connectedCompletion : () -> Void = {
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceConnected(strongSelf)
        }
        let failedCompletion : () -> Void = {
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceFailed(strongSelf)
        }
        let disconnectedCompletion : () -> Void = {
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClientIceDisconnected(strongSelf)
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFailDebug("mismatched peerConnection callback.")
                return
            }

            Logger.info("didChange IceConnectionState:\(newState.debugDescription)")
            switch newState {
            case .connected, .completed:
                DispatchQueue.main.async(execute: connectedCompletion)
            case .failed:
                Logger.warn("RTCIceConnection failed.")
                DispatchQueue.main.async(execute: failedCompletion)
            case .disconnected:
                Logger.warn("RTCIceConnection disconnected.")
                DispatchQueue.main.async(execute: disconnectedCompletion)
            default:
                Logger.debug("ignoring change IceConnectionState:\(newState.debugDescription)")
            }
        }
    }

    /** Called any time the IceGatheringState changes. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.info("didChange IceGatheringState:\(newState.debugDescription)")
    }

    /** New ice candidate has been found. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let proxyCopy = self.proxy
        let completion: (RTCIceCandidate) -> Void = { (candidate) in
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            guard let strongDelegate = strongSelf.delegate else { return }
            strongDelegate.peerConnectionClient(strongSelf, addedLocalIceCandidate: candidate)
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFailDebug("mismatched peerConnection callback.")
                return
            }
            Logger.info("adding local ICE candidate:\(candidate.sdp)")
            DispatchQueue.main.async {
                completion(candidate)
            }
        }
    }

    /** Called when a group of local Ice candidates have been removed. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("didRemove IceCandidates:\(candidates)")
    }

    /** New data channel has been opened. */
    internal func peerConnection(_ peerConnectionParam: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        let proxyCopy = self.proxy
        let completion: ([PendingDataChannelMessage]) -> Void = { (pendingMessages) in
            AssertIsOnMainThread()
            guard let strongSelf = proxyCopy.get() else { return }
            pendingMessages.forEach { message in
                strongSelf.sendDataChannelMessage(data: message.data, description: message.description, isCritical: message.isCritical)
            }
        }

        PeerConnectionClient.signalingQueue.async {
            guard let strongSelf = proxyCopy.get() else { return }
            guard let peerConnection = strongSelf.peerConnection else {
                Logger.debug("Ignoring obsolete event in terminated client")
                return
            }
            guard peerConnection == peerConnectionParam else {
                owsFailDebug("mismatched peerConnection callback.")
                return
            }
            Logger.info("didOpen dataChannel:\(dataChannel)")
            if strongSelf.dataChannel != nil {
                owsFailDebug("dataChannel unexpectedly set twice.")
            }
            strongSelf.dataChannel = dataChannel
            dataChannel.delegate = strongSelf.proxy

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
        AssertIsOnMainThread()

        var result: RTCPeerConnection?
        PeerConnectionClient.signalingQueue.sync {
            result = peerConnection
            Logger.info("")
        }
        return result!
    }

    internal func dataChannelForTests() -> RTCDataChannel {
        AssertIsOnMainThread()

        var result: RTCDataChannel?
        PeerConnectionClient.signalingQueue.sync {
            result = dataChannel
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

    var logSafeDescription: String {
        #if DEBUG
        return sdp
        #else
        return redactIPV6(sdp: redactIcePwd(sdp: sdp))
        #endif
    }

    private func redactIcePwd(sdp: String) -> String {
        #if DEBUG
        return sdp
        #else
        var text = sdp
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\n\n", with: "\n")
        let lines = text.components(separatedBy: "\n")
        let filteredLines: [String] = lines.map { line in
            guard !line.contains("ice-pwd") else {
                return "[ REDACTED ice-pwd ]"
            }
            return line
        }
        let filteredText = filteredLines.joined(separator: "\n")
        return filteredText
        #endif
    }

    private func redactIPV6(sdp: String) -> String {
        #if DEBUG
        return sdp
        #else

        // Example values to match:
        //
        // * 2001:0db8:85a3:0000:0000:8a2e:0370:7334
        // * 2001:db8:85a3::8a2e:370:7334
        // * ::1
        // * ::
        // * ::ffff:192.0.2.128
        //
        // See: https://en.wikipedia.org/wiki/IPv6_addresshttps://en.wikipedia.org/wiki/IPv6_address
        do {
            let regex = try NSRegularExpression(pattern: "[\\da-f]*:[\\da-f]*:[\\da-f:\\.]*",
                options: .caseInsensitive)
            return regex.stringByReplacingMatches(in: sdp, options: [], range: NSRange(location: 0, length: sdp.count), withTemplate: "[ REDACTED_IPV6_ADDRESS ]")
        } catch {
            owsFail("Could not redact IPv6 addresses.")
            return "[Could not redact IPv6 addresses.]"
        }
        #endif
    }
}

protocol VideoCaptureSettingsDelegate: class {
    var videoWidth: Int32 { get }
    var videoHeight: Int32 { get }
}

class VideoCaptureController {

    private let capturer: RTCCameraVideoCapturer
    private weak var settingsDelegate: VideoCaptureSettingsDelegate?
    private let serialQueue = DispatchQueue(label: "org.signal.videoCaptureController")
    private var isUsingFrontCamera: Bool = true

    public var captureSession: AVCaptureSession {
        return capturer.captureSession
    }

    public init(capturer: RTCCameraVideoCapturer, settingsDelegate: VideoCaptureSettingsDelegate) {
        self.capturer = capturer
        self.settingsDelegate = settingsDelegate
    }

    public func startCapture() {
        serialQueue.sync { [weak self] in
            guard let strongSelf = self else {
                return
            }

            strongSelf.startCaptureSync()
        }
    }

    public func stopCapture() {
        serialQueue.sync { [weak self] in
            guard let strongSelf = self else {
                return
            }

            strongSelf.capturer.stopCapture()
        }
    }

    public func switchCamera(isUsingFrontCamera: Bool) {
        serialQueue.sync { [weak self] in
            guard let strongSelf = self else {
                return
            }

            strongSelf.isUsingFrontCamera = isUsingFrontCamera
            strongSelf.startCaptureSync()
        }
    }

    private func assertIsOnSerialQueue() {
        if _isDebugAssertConfiguration(), #available(iOS 10.0, *) {
            assertOnQueue(serialQueue)
        }
    }

    private func startCaptureSync() {
        assertIsOnSerialQueue()

        let position: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        guard let device: AVCaptureDevice = self.device(position: position) else {
            owsFailDebug("unable to find captureDevice")
            return
        }

        guard let format: AVCaptureDevice.Format = self.format(device: device) else {
            owsFailDebug("unable to find captureDevice")
            return
        }

        let fps = self.framesPerSecond(format: format)
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    private func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        guard let device = (captureDevices.first { $0.position == position }) else {
            Logger.debug("unable to find desired position: \(position)")
            return captureDevices.first
        }

        return device
    }

    private func format(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let targetWidth = settingsDelegate?.videoWidth ?? 0
        let targetHeight = settingsDelegate?.videoHeight ?? 0

        var selectedFormat: AVCaptureDevice.Format?
        var currentDiff: Int32 = Int32.max

        for format in formats {
            let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height)
            if diff < currentDiff {
                selectedFormat = format
                currentDiff = diff
            }
        }

        if _isDebugAssertConfiguration(), let selectedFormat = selectedFormat {
            let dimension = CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription)
            Logger.debug("selected format width: \(dimension.width) height: \(dimension.height)")
        }

        assert(selectedFormat != nil)

        return selectedFormat
    }

    private func framesPerSecond(format: AVCaptureDevice.Format) -> Int {
        var maxFrameRate: Float64 = 0
        for range in format.videoSupportedFrameRateRanges {
            maxFrameRate = max(maxFrameRate, range.maxFrameRate)
        }

        return Int(maxFrameRate)
    }
}

// MARK: Pretty Print Objc enums.

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
