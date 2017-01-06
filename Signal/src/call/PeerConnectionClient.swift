//  Created by Michael Kirk on 11/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import PromiseKit
import WebRTC

let kAudioTrackType = kRTCMediaStreamTrackKindAudio
let kVideoTrackType = kRTCMediaStreamTrackKindVideo

/**
 * `PeerConnectionClient` is our interface to WebRTC.
 *
 * It is primarily a wrapper around `RTCPeerConnection`, which is responsible for sending and receiving our call data 
 * including audio, video, and some signaling - though the bulk of the signaling is *establishing* the connection, 
 * meaning we can't use the connection to transmit yet.
 */
class PeerConnectionClient: NSObject {

    let TAG = "[PeerConnectionClient]"
    enum Identifiers: String {
        case mediaStream = "ARDAMS",
             videoTrack = "ARDAMSv0",
             audioTrack = "ARDAMSa0",
             dataChannelSignaling = "signaling"
    }

    // Connection

    private let peerConnection: RTCPeerConnection
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

    // Video

    private var videoSender: RTCRtpSender?
    private var videoTrack: RTCVideoTrack?
    private var cameraConstraints: RTCMediaConstraints

    init(iceServers: [RTCIceServer], peerConnectionDelegate: RTCPeerConnectionDelegate) {
        self.iceServers = iceServers

        configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require

        let connectionConstraintsDict = ["DtlsSrtpKeyAgreement": "true"]
        connectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: connectionConstraintsDict)
        peerConnection = factory.peerConnection(with: configuration,
                                                constraints: connectionConstraints,
                                                delegate: peerConnectionDelegate)

        audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints:nil)
        cameraConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        super.init()

        createAudioSender()
        createVideoSender()
    }

    // MARK: - Media Streams

    public func createSignalingDataChannel(delegate: RTCDataChannelDelegate) {
        let dataChannel = peerConnection.dataChannel(forLabel: Identifiers.dataChannelSignaling.rawValue,
                                                     configuration: RTCDataChannelConfiguration())
        dataChannel.delegate = delegate

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
            Logger.error("\(TAG)) trying to \(action) videoTack which doesn't exist")
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
            "OfferToReceiveVideo" : "true"
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
        audioTrack = nil
        videoTrack = nil
        dataChannel = nil
        audioSender = nil
        videoSender = nil

        peerConnection.close()
    }

    // MARK: Data Channel

    func sendDataChannelMessage(data: Data) -> Bool {
        guard let dataChannel = self.dataChannel else {
            Logger.error("\(TAG) in \(#function) ignoring sending \(data) for nil dataChannel")
            return false
        }

        let buffer = RTCDataBuffer(data: data, isBinary: false)
        return dataChannel.sendData(buffer)
    }

    // MARK: CallAudioManager

    internal func configureAudioSession() {
        Logger.warn("TODO: \(#function)")
    }

    internal func stopAudio() {
        Logger.warn("TODO: \(#function)")
    }

    internal func startAudio() {
        guard let audioSender = self.audioSender else {
            Logger.error("\(TAG) ignoring \(#function) because audioSender was nil")
            return
        }

        Logger.warn("TODO: \(#function)")
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
