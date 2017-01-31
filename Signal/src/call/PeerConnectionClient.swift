//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC

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
 */
protocol PeerConnectionClientDelegate: class {

    /**
     * The connection has been established. The clients can now communicate.
     */
    func peerConnectionClientIceConnected(_ peerconnectionClient: PeerConnectionClient)

    /**
     * The connection failed to establish. The clients will not be able to communicate.
     */
    func peerConnectionClientIceFailed(_ peerconnectionClient: PeerConnectionClient)

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

    let TAG = "[PeerConnectionClient]"
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
    private weak var delegate: PeerConnectionClientDelegate!

    func setDelegate(delegate: PeerConnectionClientDelegate?) {
        PeerConnectionClient.signalingQueue.sync {
            self.delegate = delegate
        }
    }

    // Connection

    private var peerConnection: RTCPeerConnection!
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
    static private let sharedAudioSession = CallAudioSession()

    // Video

    private var videoSender: RTCRtpSender?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var cameraConstraints: RTCMediaConstraints

    init(iceServers: [RTCIceServer], delegate: PeerConnectionClientDelegate) {
        self.iceServers = iceServers
        self.delegate = delegate

        configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require

        let connectionConstraintsDict = ["DtlsSrtpKeyAgreement": "true"]
        connectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: connectionConstraintsDict)

        audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints:nil)
        cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        super.init()

        // Configure audio session so we don't prompt user with Record permission until call is connected.
        type(of: self).configureAudioSession()
        peerConnection = factory.peerConnection(with: configuration,
                                                constraints: connectionConstraints,
                                                delegate: self)
        createAudioSender()
        createVideoSender()
    }

    // MARK: - Media Streams

    public func createSignalingDataChannel() {
        PeerConnectionClient.signalingQueue.sync {
            let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                         configuration: RTCDataChannelConfiguration())
            dataChannel.delegate = self

            assert(self.dataChannel == nil)
            self.dataChannel = dataChannel
        }
    }

    // MARK: Video

    fileprivate func createVideoSender() {
        AssertIsOnMainThread()

        Logger.debug("\(self.TAG) in \(#function)")
        assert(self.videoSender == nil, "\(#function) should only be called once.")

        guard !Platform.isSimulator else {
            Logger.warn("\(self.TAG) Refusing to create local video track on simulator which has no capture device.")
            return
        }

        // TODO: We could cap the maximum video size.
        let cameraConstraints = RTCMediaConstraints(mandatoryConstraints:nil,
                                                    optionalConstraints:nil)

        // TODO: Revisit the cameraConstraints.
        let videoSource = factory.avFoundationVideoSource(with: cameraConstraints)
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

    public func setLocalVideoEnabled(enabled: Bool) {
        AssertIsOnMainThread()

        PeerConnectionClient.signalingQueue.async {
            guard let localVideoTrack = self.localVideoTrack else {
                let action = enabled ? "enable" : "disable"
                Logger.error("\(self.TAG)) trying to \(action) videoTrack which doesn't exist")
                return
            }

            localVideoTrack.isEnabled = enabled

            if let delegate = self.delegate {
                DispatchQueue.main.async {
                    delegate.peerConnectionClient(self, didUpdateLocal: enabled ? localVideoTrack : nil)
                }
            }
        }
    }

    // MARK: Audio

    fileprivate func createAudioSender() {
        AssertIsOnMainThread()

        Logger.debug("\(self.TAG) in \(#function)")
        assert(self.audioSender == nil, "\(#function) should only be called once.")

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

        PeerConnectionClient.signalingQueue.async {
            guard let audioTrack = self.audioTrack else {
                let action = enabled ? "enable" : "disable"
                Logger.error("\(self.TAG) trying to \(action) audioTrack which doesn't exist.")
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
        return RTCMediaConstraints(mandatoryConstraints:mandatoryConstraints, optionalConstraints:nil)
    }

    public func createOffer() -> Promise<HardenedRTCSessionDescription> {
        var result: Promise<HardenedRTCSessionDescription>? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = Promise { fulfill, reject in
                peerConnection.offer(for: self.defaultOfferConstraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                    PeerConnectionClient.signalingQueue.async {
                        guard error == nil else {
                            reject(error!)
                            return
                        }

                        guard let sessionDescription = sdp else {
                            Logger.error("\(self.TAG) No session description was obtained, even though there was no error reported.")
                            let error = OWSErrorMakeUnableToProcessServerResponseError()
                            reject(error)
                            return
                        }

                        fulfill(HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription))
                    }
                })
            }
        }
        // TODO: Propagate exception
        return result!
    }

    public func setLocalSessionDescriptionInternal(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        assertOnSignalingQueue()

        return PromiseKit.wrap {
            Logger.verbose("\(self.TAG) setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription, completionHandler: $0)
        }
    }

    public func setLocalSessionDescription(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        var result: Promise<Void>? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = setLocalSessionDescriptionInternal(sessionDescription)
        }
        // TODO: Propagate exception
        return result!
    }

    public func negotiateSessionDescription(remoteDescription: RTCSessionDescription, constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        var result: Promise<HardenedRTCSessionDescription>? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = firstly {
                return self.setRemoteSessionDescriptionInternal(remoteDescription)
                }.then(on: PeerConnectionClient.signalingQueue) {
                    return self.negotiateAnswerSessionDescription(constraints: constraints)
            }
        }
        // TODO: Propagate exception
        return result!
    }

    private func setRemoteSessionDescriptionInternal(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        assertOnSignalingQueue()

        return PromiseKit.wrap {
            Logger.verbose("\(self.TAG) setting remote description: \(sessionDescription)")
            peerConnection.setRemoteDescription(sessionDescription, completionHandler: $0)
        }
    }

    public func setRemoteSessionDescription(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        var result: Promise<Void>? = nil
        PeerConnectionClient.signalingQueue.sync {
            result = setRemoteSessionDescriptionInternal(sessionDescription)
        }
        // TODO: Propagate exception
        return result!
    }

    private func negotiateAnswerSessionDescription(constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        assertOnSignalingQueue()

        return Promise { fulfill, reject in
            Logger.debug("\(self.TAG) negotiating answer session.")

            peerConnection.answer(for: constraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
                PeerConnectionClient.signalingQueue.async {
                    guard error == nil else {
                        reject(error!)
                        return
                    }

                    guard let sessionDescription = sdp else {
                        Logger.error("\(self.TAG) unexpected empty session description, even though no error was reported.")
                        let error = OWSErrorMakeUnableToProcessServerResponseError()
                        reject(error)
                        return
                    }

                    let hardenedSessionDescription = HardenedRTCSessionDescription(rtcSessionDescription: sessionDescription)

                    self.setLocalSessionDescriptionInternal(hardenedSessionDescription)
                        .then(on: PeerConnectionClient.signalingQueue) {
                            fulfill(hardenedSessionDescription)
                        }.catch { error in
                            reject(error)
                    }
                }
            })
        }
    }

    public func addIceCandidate(_ candidate: RTCIceCandidate) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) adding candidate")
            self.peerConnection.add(candidate)
        }
    }

    public func terminate() {
        PeerConnectionClient.signalingQueue.async {
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
            Logger.debug("\(self.TAG) in \(#function)")
            self.audioTrack = nil
            self.localVideoTrack = nil
            self.remoteVideoTrack = nil
            self.dataChannel = nil
            self.audioSender = nil
            self.videoSender = nil

            self.peerConnection.delegate = nil
            self.peerConnection.close()
        }
    }

    // MARK: - Data Channel

    public func sendDataChannelMessage(data: Data) -> Bool {
        var result = false
        PeerConnectionClient.signalingQueue.sync {
            guard let dataChannel = self.dataChannel else {
                Logger.error("\(self.TAG) in \(#function) ignoring sending \(data) for nil dataChannel")
                result = false
                return
            }

            let buffer = RTCDataBuffer(data: data, isBinary: false)
            result = dataChannel.sendData(buffer)
        }
        return result
    }

    // MARK: RTCDataChannelDelegate

    /** The data channel state changed. */
    internal func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("\(self.TAG) dataChannelDidChangeState: \(dataChannel)")
    }

    /** The data channel successfully received a data buffer. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) dataChannel didReceiveMessageWith buffer:\(buffer)")

            guard let dataChannelMessage = OWSWebRTCProtosData.parse(from:buffer.data) else {
                // TODO can't proto parsings throw an exception? Is it just being lost in the Objc->Swift?
                Logger.error("\(self.TAG) failed to parse dataProto")
                return
            }

            if let delegate = self.delegate {
                DispatchQueue.main.async {
                    delegate.peerConnectionClient(self, received: dataChannelMessage)
                }
            }
        }
    }

    /** The data channel's |bufferedAmount| changed. */
    internal func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        Logger.debug("\(self.TAG) didChangeBufferedAmount: \(amount)")
    }

    // MARK: - RTCPeerConnectionDelegate

    /** Called when the SignalingState changed. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("\(self.TAG) didChange signalingState:\(stateChanged.debugDescription)")
    }

    /** Called when media is received on a new stream from remote peer. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) didAdd stream:\(stream) video tracks: \(stream.videoTracks.count) audio tracks: \(stream.audioTracks.count)")

            if stream.videoTracks.count > 0 {
                self.remoteVideoTrack = stream.videoTracks[0]
                if let delegate = self.delegate {
                    let remoteVideoTrack = self.remoteVideoTrack
                    DispatchQueue.main.async {
                        delegate.peerConnectionClient(self, didUpdateRemote: remoteVideoTrack)
                    }
                }
            }
        }
    }

    /** Called when a remote peer closes a stream. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.debug("\(self.TAG) didRemove Stream:\(stream)")
    }

    /** Called when negotiation is needed, for example ICE has restarted. */
    internal func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.debug("\(self.TAG) shouldNegotiate")
    }

    /** Called any time the IceConnectionState changes. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) didChange IceConnectionState:\(newState.debugDescription)")
            switch newState {
            case .connected, .completed:
                if let delegate = self.delegate {
                    DispatchQueue.main.async {
                        delegate.peerConnectionClientIceConnected(self)
                    }
                }
            case .failed:
                Logger.warn("\(self.TAG) RTCIceConnection failed.")
                if let delegate = self.delegate {
                    DispatchQueue.main.async {
                        delegate.peerConnectionClientIceFailed(self)
                    }
                }
            case .disconnected:
                Logger.warn("\(self.TAG) RTCIceConnection disconnected.")
            default:
                Logger.debug("\(self.TAG) ignoring change IceConnectionState:\(newState.debugDescription)")
            }
        }
    }

    /** Called any time the IceGatheringState changes. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.debug("\(self.TAG) didChange IceGatheringState:\(newState.debugDescription)")
    }

    /** New ice candidate has been found. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) didGenerate IceCandidate:\(candidate.sdp)")
            if let delegate = self.delegate {
                DispatchQueue.main.async {
                    delegate.peerConnectionClient(self, addedLocalIceCandidate: candidate)
                }
            }
        }
    }

    /** Called when a group of local Ice candidates have been removed. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("\(self.TAG) didRemove IceCandidates:\(candidates)")
    }

    /** New data channel has been opened. */
    internal func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        PeerConnectionClient.signalingQueue.async {
            Logger.debug("\(self.TAG) didOpen dataChannel:\(dataChannel)")
            assert(self.dataChannel == nil)
            self.dataChannel = dataChannel
            dataChannel.delegate = self
        }
    }

    // Mark: Audio Session

    class func configureAudioSession() {
        sharedAudioSession.configure()
    }

    class func startAudioSession() {
        sharedAudioSession.start()
    }

    class func stopAudioSession() {
        sharedAudioSession.stop()
    }

    // MARK: Helpers

    /**
     * We synchronize access to state in this class using this queue.
     */
    private func assertOnSignalingQueue() {
        if #available(iOS 10.0, *) {
            dispatchPrecondition(condition: .onQueue(type(of: self).signalingQueue))
        } else {
            // Skipping check on <iOS10, since syntax is different and it's just a development convenience.
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
        description = description.replacingOccurrences(of: "(a=fmtp:111 ((?!cbr=).)*)\r?\n", with: "$1;cbr=1\r\n")

        // Strip plaintext audio-level details
        // https://tools.ietf.org/html/rfc6464
        description = description.replacingOccurrences(of: ".+urn:ietf:params:rtp-hdrext:ssrc-audio-level.*\r?\n", with: "")

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
