//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import WebRTC

let kAudioTrackType = kRTCMediaStreamTrackKindAudio
let kVideoTrackType = kRTCMediaStreamTrackKindVideo

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

    // Delegate is notified of key events in the call lifecycle.
    public weak var delegate: PeerConnectionClientDelegate!

    // Connection

    internal var peerConnection: RTCPeerConnection!
    private let iceServers: [RTCIceServer]
    private let connectionConstraints: RTCMediaConstraints
    private let configuration: RTCConfiguration
    private let factory = RTCPeerConnectionFactory()

    // DataChannel

    // `dataChannel` is public because on incoming calls, we don't explicitly create the channel, rather `CallService`
    // assigns it when the channel is discovered due to the caller having created it.
    public var dataChannel: RTCDataChannel?

    // Audio

    private var audioSender: RTCRtpSender?
    private var audioTrack: RTCAudioTrack?
    private var audioConstraints: RTCMediaConstraints
    static private let sharedAudioSession = CallAudioSession()

    // Video

    private var videoSender: RTCRtpSender?
    private var videoTrack: RTCVideoTrack?
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
        let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                     configuration: RTCDataChannelConfiguration())
        dataChannel.delegate = self

        self.dataChannel = dataChannel
    }

    // MARK: Video

    fileprivate func createVideoSender() {
        Logger.debug("\(TAG) in \(#function)")
        assert(self.videoSender == nil, "\(#function) should only be called once.")

        guard !Platform.isSimulator else {
            Logger.warn("\(TAG) Refusing to create local video track on simulator which has no capture device.")
            return
        }

        let videoSource = factory.avFoundationVideoSource(with: cameraConstraints)
        let videoTrack = factory.videoTrack(with: videoSource, trackId: Identifiers.videoTrack.rawValue)
        self.videoTrack = videoTrack

        // Disable by default until call is connected.
        // FIXME - do we require mic permissions at this point?
        // if so maybe it would be better to not even add the track until the call is connected
        // instead of creating it and disabling it.
        videoTrack.isEnabled = false

        // Occasionally seeing this crash on the next line, after a *second* call:
//         -[__NSCFNumber length]: unrecognized selector sent to instance 0x1562c610
        // Seems like either videoKind or videoStreamId (both of which are Strings) is being GC'd prematurely. 
        // Not sure why, but assigned the value to local vars above in hopes of avoiding it.
//        let videoKind = kRTCMediaStreamTrackKindVideo

        let videoSender = peerConnection.sender(withKind: kVideoTrackType, streamId: Identifiers.mediaStream.rawValue)
        videoSender.track = videoTrack
        self.videoSender = videoSender
    }

    public func setVideoEnabled(enabled: Bool) {
        guard let videoTrack = self.videoTrack else {
            let action = enabled ? "enable" : "disable"
            Logger.error("\(TAG)) trying to \(action) videoTrack which doesn't exist")
            return
        }

        videoTrack.isEnabled = enabled
    }

    // MARK: Audio

    fileprivate func createAudioSender() {
        Logger.debug("\(TAG) in \(#function)")
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
        guard let audioTrack = self.audioTrack else {
            let action = enabled ? "enable" : "disable"
            Logger.error("\(TAG) trying to \(action) audioTrack which doesn't exist.")
            return
        }

        audioTrack.isEnabled = enabled
    }

    // MARK: - Session negotiation

    var defaultOfferConstraints: RTCMediaConstraints {
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ]
        return RTCMediaConstraints(mandatoryConstraints:mandatoryConstraints, optionalConstraints:nil)
    }

    func createOffer() -> Promise<HardenedRTCSessionDescription> {
        return Promise { fulfill, reject in
            peerConnection.offer(for: self.defaultOfferConstraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
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
            })
        }
    }

    func setLocalSessionDescription(_ sessionDescription: HardenedRTCSessionDescription) -> Promise<Void> {
        return PromiseKit.wrap {
            Logger.verbose("\(self.TAG) setting local session description: \(sessionDescription)")
            peerConnection.setLocalDescription(sessionDescription.rtcSessionDescription, completionHandler: $0)
        }
    }

    func negotiateSessionDescription(remoteDescription: RTCSessionDescription, constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        return firstly {
            return self.setRemoteSessionDescription(remoteDescription)
        }.then {
            return self.negotiateAnswerSessionDescription(constraints: constraints)
        }
    }

    func setRemoteSessionDescription(_ sessionDescription: RTCSessionDescription) -> Promise<Void> {
        return PromiseKit.wrap {
            Logger.verbose("\(self.TAG) setting remote description: \(sessionDescription)")
            peerConnection.setRemoteDescription(sessionDescription, completionHandler: $0)
        }
    }

    func negotiateAnswerSessionDescription(constraints: RTCMediaConstraints) -> Promise<HardenedRTCSessionDescription> {
        return Promise { fulfill, reject in
            Logger.debug("\(self.TAG) negotiating answer session.")

            peerConnection.answer(for: constraints, completionHandler: { (sdp: RTCSessionDescription?, error: Error?) in
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

                self.setLocalSessionDescription(hardenedSessionDescription).then {
                    fulfill(hardenedSessionDescription)
                }.catch { error in
                    reject(error)
                }
            })
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        Logger.debug("\(TAG) adding candidate")
        self.peerConnection.add(candidate)
    }

    func terminate() {
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
        Logger.debug("\(TAG) in \(#function)")
        audioTrack = nil
        videoTrack = nil
        dataChannel = nil
        audioSender = nil
        videoSender = nil

        peerConnection.delegate = nil
        peerConnection.close()
    }

    // MARK: - Data Channel

    func sendDataChannelMessage(data: Data) -> Bool {
        guard let dataChannel = self.dataChannel else {
            Logger.error("\(TAG) in \(#function) ignoring sending \(data) for nil dataChannel")
            return false
        }

        let buffer = RTCDataBuffer(data: data, isBinary: false)
        return dataChannel.sendData(buffer)
    }

    // MARK: RTCDataChannelDelegate

    /** The data channel state changed. */
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("\(TAG) dataChannelDidChangeState: \(dataChannel)")
    }

    /** The data channel successfully received a data buffer. */
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        Logger.debug("\(TAG) dataChannel didReceiveMessageWith buffer:\(buffer)")

        guard let dataChannelMessage = OWSWebRTCProtosData.parse(from:buffer.data) else {
            // TODO can't proto parsings throw an exception? Is it just being lost in the Objc->Swift?
            Logger.error("\(TAG) failed to parse dataProto")
            return
        }

        delegate.peerConnectionClient(self, received: dataChannelMessage)
    }

    /** The data channel's |bufferedAmount| changed. */
    public func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
        Logger.debug("\(TAG) didChangeBufferedAmount: \(amount)")
    }

    // MARK: - RTCPeerConnectionDelegate

    /** Called when the SignalingState changed. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("\(TAG) didChange signalingState:\(stateChanged.debugDescription)")
    }

    /** Called when media is received on a new stream from remote peer. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Logger.debug("\(TAG) didAdd stream:\(stream)")
    }

    /** Called when a remote peer closes a stream. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Logger.debug("\(TAG) didRemove Stream:\(stream)")
    }

    /** Called when negotiation is needed, for example ICE has restarted. */
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.debug("\(TAG) shouldNegotiate")
    }

    /** Called any time the IceConnectionState changes. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Logger.debug("\(TAG) didChange IceConnectionState:\(newState.debugDescription)")
        switch newState {
        case .connected, .completed:
            self.delegate.peerConnectionClientIceConnected(self)
        case .failed:
            Logger.warn("\(self.TAG) RTCIceConnection failed.")
            self.delegate.peerConnectionClientIceFailed(self)
        default:
            Logger.debug("\(self.TAG) ignoring change IceConnectionState:\(newState.debugDescription)")
        }
    }

    /** Called any time the IceGatheringState changes. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.debug("\(TAG) didChange IceGatheringState:\(newState.debugDescription)")
    }

    /** New ice candidate has been found. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Logger.debug("\(TAG) didGenerate IceCandidate:\(candidate.sdp)")
        self.delegate.peerConnectionClient(self, addedLocalIceCandidate: candidate)
    }

    /** Called when a group of local Ice candidates have been removed. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("\(TAG) didRemove IceCandidates:\(candidates)")
    }

    /** New data channel has been opened. */
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Logger.debug("\(TAG) didOpen dataChannel:\(dataChannel)")
        CallService.signalingQueue.async {
            Logger.debug("\(self.TAG) set dataChannel")
            self.dataChannel = dataChannel
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
